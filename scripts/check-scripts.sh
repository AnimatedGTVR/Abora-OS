#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

version_value="$(tr -d '\n' < VERSION | tr -cd '[:alnum:]._-')"
case "$version_value" in
  [Vv]*) release_tag="$version_value" ;;
  *) release_tag="v$version_value" ;;
esac

bash_scripts=(
  "scripts/abora-app-catalog.sh"
  "scripts/abora-apps.sh"
  "scripts/abora-custom-packages.sh"
  "scripts/abora.sh"
  "scripts/abora-adopt-nixos.sh"
  "scripts/abora-adopt-bootstrap.sh"
  "scripts/abora-boot.sh"
  "scripts/abora-build.sh"
  "scripts/abora-check-full.sh"
  "scripts/abora-config.sh"
  "scripts/abora-desktop.sh"
  "scripts/abora-desktop-profiles.sh"
  "scripts/abora-dotfiles-import.sh"
  "scripts/abora-doctor.sh"
  "scripts/abora-gaming.sh"
  "scripts/abora-hardware-test.sh"
  "scripts/abora-installer.sh"
  "scripts/abora-repair-flake-purity.sh"
  "scripts/abora-recovery.sh"
  "scripts/abora-session-setup.sh"
  "scripts/abora-setup-launcher.sh"
  "scripts/abora-support-report.sh"
  "scripts/abora-ui.sh"
  "scripts/abora-welcome.sh"
  "scripts/anix.sh"
  "scripts/check-desktops.sh"
  "scripts/abora-theme-sync.sh"
  "scripts/abora-update.sh"
  "scripts/build-iso.sh"
  "scripts/package-anix.sh"
  "scripts/build-tinypm-image.sh"
  "scripts/package-tinypm.sh"
  "scripts/preflight.sh"
  "scripts/rebuild-vm.sh"
  "scripts/check-release-files.sh"
  "scripts/release-metadata.sh"
  "scripts/run-qemu.sh"
  "scripts/check-scripts.sh"
  "scripts/dev-doctor.sh"
  "scripts/abora-desktop-preview.sh"
)

nix_files=(
  "flake.nix"
  "nix/modules/abora-options.nix"
  "nix/modules/anix.nix"
  "nix/modules/branding.nix"
  "nix/modules/installed-base.nix"
  "nix/profiles/live.nix"
  "nix/pkgs/desktop-preview.nix"
  "nix/pkgs/hardware-test.nix"
)

python_scripts=(
  "scripts/abora-config-gui.py"
  "scripts/abora-welcome-gui.py"
  "scripts/abora-gaming-welcome-gui.py"
)

required_files=(
  "scripts/abora-check-full.sh"
  "scripts/abora-setup.desktop"
  "docs/wiki/ANIX-V1.md"
  "docs/wiki/ANIX-V2-Languages.md"
  "docs/wiki/TinyPM.md"
  "docs/wiki/Abora-Tools.md"
  "docs/wiki/Abora-Gaming.md"
  "docs/wiki/Recovery.md"
  "docs/wiki/Updating-Abora.md"
  "docs/bug-report-template.md"
  "vendor/tinypm/Cargo.toml"
  "vendor/tinypm/src/main.rs"
  "vendor/tinypm/src/bin/grab.rs"
)

failed=0

pass() {
  printf '[ok]   %s\n' "$1"
}

fail() {
  printf '[fail] %s\n' "$1"
  failed=1
}

# ── abora-update-resolver (C# decision logic for abora-update.sh) ──────────────
# The runtime tests further down that exercise resolve_update_ref/
# guard_against_accidental_downgrade need a real built binary -- there's no
# bash implementation to fall back to anymore (see scripts/abora-update.sh's
# resolver_bin). A plain `dotnet build` (not the slower AOT publish used for
# the real Nix package) is enough for behavioral testing.
resolver_bin=""
if command -v dotnet >/dev/null 2>&1; then
  if MSBuildEnableWorkloadResolver=false dotnet build \
      "$repo_dir/tools/abora-update-resolver/AboraUpdateResolver.csproj" \
      -c Debug >/dev/null 2>&1; then
    # scripts/abora-update.sh calls $resolver_bin as a single executable
    # (matching how it's found on a real system, via PATH) -- this wrapper
    # gives the "dotnet <dll>" invocation that single-executable shape.
    resolver_wrapper="$(mktemp)"
    printf '#!/usr/bin/env bash\nexec dotnet %q "$@"\n' \
      "$repo_dir/tools/abora-update-resolver/bin/Debug/net10.0/abora-update-resolver.dll" \
      > "$resolver_wrapper"
    chmod +x "$resolver_wrapper"
    resolver_bin="$resolver_wrapper"
    pass "abora-update-resolver: built for runtime tests"
  else
    fail "abora-update-resolver: dotnet build failed"
  fi
else
  pass "dotnet unavailable (abora-update-resolver runtime tests skipped)"
fi

# ── abora-plan-tool (C# Plan JSON structural validation for anix.sh) ───────────
plan_tool_bin=""
if command -v dotnet >/dev/null 2>&1; then
  if MSBuildEnableWorkloadResolver=false dotnet build \
      "$repo_dir/tools/abora-plan-tool/AboraPlanTool.csproj" \
      -c Debug >/dev/null 2>&1; then
    plan_tool_wrapper="$(mktemp)"
    printf '#!/usr/bin/env bash\nexec dotnet %q "$@"\n' \
      "$repo_dir/tools/abora-plan-tool/bin/Debug/net10.0/abora-plan-tool.dll" \
      > "$plan_tool_wrapper"
    chmod +x "$plan_tool_wrapper"
    plan_tool_bin="$plan_tool_wrapper"
    pass "abora-plan-tool: built for runtime tests"
  else
    fail "abora-plan-tool: dotnet build failed"
  fi
else
  pass "dotnet unavailable (abora-plan-tool runtime tests skipped)"
fi

# ── MINT (vendored Go installer front-end) ──────────────────────────────────
# vendor/mint had no automated verification anywhere in this repo before --
# only the manual `make test-installer*` targets, which a human has to
# remember to run. That's a real contributing factor to regressions only
# being caught after they ship. `go vet` and `go test` here are intentionally
# separate from a full lint pass (golangci-lint isn't assumed to be
# installed) -- this is the same baseline safety net every other language in
# this repo already gets from check-scripts.sh/check-all-files.sh.
if command -v go >/dev/null 2>&1; then
  if (cd "$repo_dir/vendor/mint" && go build ./... >/dev/null 2>&1); then
    pass "vendor/mint: go build"
  else
    fail "vendor/mint: go build"
  fi
  if (cd "$repo_dir/vendor/mint" && go vet ./... >/dev/null 2>&1); then
    pass "vendor/mint: go vet"
  else
    fail "vendor/mint: go vet"
  fi
  if (cd "$repo_dir/vendor/mint" && go test ./... >/dev/null 2>&1); then
    pass "vendor/mint: go test"
  else
    fail "vendor/mint: go test"
  fi
else
  pass "go unavailable (vendor/mint build/vet/test skipped)"
fi

for file in "${bash_scripts[@]}"; do
  if [[ ! -f "$file" ]]; then
    fail "Missing file: $file"
    continue
  fi

  if bash -n "$file"; then
    pass "syntax (bash): $file"
  else
    fail "syntax (bash): $file"
  fi

  if [[ -x "$file" ]]; then
    pass "executable: $file"
  else
    fail "not executable: $file"
  fi
done

tmp_gnome_wallpaper_test="$(mktemp -d)"
tmp_gnome_home="$tmp_gnome_wallpaper_test/home"
tmp_gnome_state="$tmp_gnome_wallpaper_test/state"
tmp_gnome_log="$tmp_gnome_wallpaper_test/gsettings.log"
tmp_gnome_wallpaper="$tmp_gnome_wallpaper_test/titlis-alps.jpg"
tmp_gnome_gsettings="$tmp_gnome_wallpaper_test/gsettings"
mkdir -p "$tmp_gnome_home" "$tmp_gnome_state/abora"
printf 'jpg\n' > "$tmp_gnome_wallpaper"
printf 'titlis-alps.jpg|titlis-alps.jpg\n' > "$tmp_gnome_state/abora/wallpaper-seed"
cat > "$tmp_gnome_gsettings" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "get" ]]; then
  case "\${2:-}:\${3:-}" in
    org.gnome.desktop.interface:color-scheme) printf "'prefer-light'\\n" ;;
    org.gnome.desktop.background:picture-uri) printf "'file:///missing/abora-gaming-orange.jpg'\\n" ;;
    org.gnome.desktop.background:picture-uri-dark) printf "'file:///missing/abora-gaming-orange.jpg'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri) printf "'file:///missing/abora-gaming-orange.jpg'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri-dark) printf "'file:///missing/abora-gaming-orange.jpg'\\n" ;;
    *) printf "''\\n" ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "set" ]]; then
  printf '%s\\n' "\$*" >> "$tmp_gnome_log"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp_gnome_gsettings"
HOME="$tmp_gnome_home" \
XDG_STATE_HOME="$tmp_gnome_state" \
XDG_CURRENT_DESKTOP="GNOME" \
WAYLAND_DISPLAY="wayland-1" \
ABORA_DEFAULT_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_DEFAULT_DARK_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_GSETTINGS_BIN="$tmp_gnome_gsettings" \
ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
  bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
if grep -q "org.gnome.desktop.background picture-uri 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null \
  && grep -q "org.gnome.desktop.background picture-uri-dark 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null; then
  pass "runtime: GNOME wallpaper repair replaces missing image URIs"
else
  fail "runtime: GNOME wallpaper repair replaces missing image URIs"
fi

: > "$tmp_gnome_log"
cat > "$tmp_gnome_gsettings" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "get" ]]; then
  case "\${2:-}:\${3:-}" in
    org.gnome.desktop.interface:color-scheme) printf "'prefer-light'\\n" ;;
    org.gnome.desktop.background:picture-uri) printf "''\\n" ;;
    org.gnome.desktop.background:picture-uri-dark) printf "'file://${tmp_gnome_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri) printf "''\\n" ;;
    org.gnome.desktop.screensaver:picture-uri-dark) printf "'file://${tmp_gnome_wallpaper}'\\n" ;;
    *) printf "''\\n" ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "set" ]]; then
  printf '%s\\n' "\$*" >> "$tmp_gnome_log"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp_gnome_gsettings"
HOME="$tmp_gnome_home" \
XDG_STATE_HOME="$tmp_gnome_state" \
XDG_CURRENT_DESKTOP="GNOME" \
WAYLAND_DISPLAY="wayland-1" \
ABORA_DEFAULT_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_DEFAULT_DARK_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_GSETTINGS_BIN="$tmp_gnome_gsettings" \
ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
  bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
if grep -q "org.gnome.desktop.background picture-uri 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null; then
  pass "runtime: GNOME wallpaper repair replaces empty active image URI"
else
  fail "runtime: GNOME wallpaper repair replaces empty active image URI"
fi

: > "$tmp_gnome_log"
cat > "$tmp_gnome_gsettings" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "get" ]]; then
  case "\${2:-}:\${3:-}" in
    org.gnome.desktop.interface:color-scheme) printf "'prefer-light'\\n" ;;
    org.gnome.desktop.background:picture-uri) printf "'file://${tmp_gnome_wallpaper}'\\n" ;;
    org.gnome.desktop.background:picture-uri-dark) printf "'file://${tmp_gnome_wallpaper}'\\n" ;;
    org.gnome.desktop.background:picture-options) printf "'none'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri) printf "'file://${tmp_gnome_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri-dark) printf "'file://${tmp_gnome_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-options) printf "'none'\\n" ;;
    *) printf "''\\n" ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "set" ]]; then
  printf '%s\\n' "\$*" >> "$tmp_gnome_log"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp_gnome_gsettings"
HOME="$tmp_gnome_home" \
XDG_STATE_HOME="$tmp_gnome_state" \
XDG_CURRENT_DESKTOP="GNOME" \
WAYLAND_DISPLAY="wayland-1" \
ABORA_DEFAULT_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_DEFAULT_DARK_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_GSETTINGS_BIN="$tmp_gnome_gsettings" \
ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
  bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
if grep -q "org.gnome.desktop.background picture-options 'zoom'" "$tmp_gnome_log" 2>/dev/null \
  && grep -q "org.gnome.desktop.screensaver picture-options 'zoom'" "$tmp_gnome_log" 2>/dev/null; then
  pass "runtime: GNOME wallpaper repair replaces solid-color image mode"
else
  fail "runtime: GNOME wallpaper repair replaces solid-color image mode"
fi

: > "$tmp_gnome_log"
tmp_gnome_empty_wallpaper="$tmp_gnome_wallpaper_test/empty-wallpaper.jpg"
: > "$tmp_gnome_empty_wallpaper"
cat > "$tmp_gnome_gsettings" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "get" ]]; then
  case "\${2:-}:\${3:-}" in
    org.gnome.desktop.interface:color-scheme) printf "'prefer-light'\\n" ;;
    org.gnome.desktop.background:picture-uri) printf "'file://${tmp_gnome_empty_wallpaper}'\\n" ;;
    org.gnome.desktop.background:picture-uri-dark) printf "'file://${tmp_gnome_empty_wallpaper}'\\n" ;;
    org.gnome.desktop.background:picture-options) printf "'zoom'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri) printf "'file://${tmp_gnome_empty_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri-dark) printf "'file://${tmp_gnome_empty_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-options) printf "'zoom'\\n" ;;
    *) printf "''\\n" ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "set" ]]; then
  printf '%s\\n' "\$*" >> "$tmp_gnome_log"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp_gnome_gsettings"
HOME="$tmp_gnome_home" \
XDG_STATE_HOME="$tmp_gnome_state" \
XDG_CURRENT_DESKTOP="GNOME" \
WAYLAND_DISPLAY="wayland-1" \
ABORA_DEFAULT_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_DEFAULT_DARK_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_GSETTINGS_BIN="$tmp_gnome_gsettings" \
ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
  bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
if grep -q "org.gnome.desktop.background picture-uri 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null \
  && grep -q "org.gnome.desktop.screensaver picture-uri 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null; then
  pass "runtime: GNOME wallpaper repair replaces empty image files"
else
  fail "runtime: GNOME wallpaper repair replaces empty image files"
fi

: > "$tmp_gnome_log"
tmp_gnome_old_abora_dir="$tmp_gnome_wallpaper_test/run/current-system/sw/share/backgrounds/abora"
tmp_gnome_old_abora_wallpaper="$tmp_gnome_old_abora_dir/abora-gaming-orange.jpg"
mkdir -p "$tmp_gnome_old_abora_dir"
printf 'old image\n' > "$tmp_gnome_old_abora_wallpaper"
cat > "$tmp_gnome_gsettings" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "get" ]]; then
  case "\${2:-}:\${3:-}" in
    org.gnome.desktop.interface:color-scheme) printf "'prefer-light'\\n" ;;
    org.gnome.desktop.background:picture-uri) printf "'file://${tmp_gnome_old_abora_wallpaper}'\\n" ;;
    org.gnome.desktop.background:picture-uri-dark) printf "'file://${tmp_gnome_old_abora_wallpaper}'\\n" ;;
    org.gnome.desktop.background:picture-options) printf "'zoom'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri) printf "'file://${tmp_gnome_old_abora_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-uri-dark) printf "'file://${tmp_gnome_old_abora_wallpaper}'\\n" ;;
    org.gnome.desktop.screensaver:picture-options) printf "'zoom'\\n" ;;
    *) printf "''\\n" ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "set" ]]; then
  printf '%s\\n' "\$*" >> "$tmp_gnome_log"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp_gnome_gsettings"
HOME="$tmp_gnome_home" \
XDG_STATE_HOME="$tmp_gnome_state" \
XDG_CURRENT_DESKTOP="GNOME" \
WAYLAND_DISPLAY="wayland-1" \
ABORA_DEFAULT_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_DEFAULT_DARK_WALLPAPER="$tmp_gnome_wallpaper" \
ABORA_GSETTINGS_BIN="$tmp_gnome_gsettings" \
ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
  bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
if grep -q "org.gnome.desktop.background picture-uri 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null \
  && grep -q "org.gnome.desktop.screensaver picture-uri 'file://${tmp_gnome_wallpaper}'" "$tmp_gnome_log" 2>/dev/null; then
  pass "runtime: GNOME wallpaper repair replaces stale Abora wallpaper URIs"
else
  fail "runtime: GNOME wallpaper repair replaces stale Abora wallpaper URIs"
fi
rm -rf "$tmp_gnome_wallpaper_test"

tmp_desktop_wallpaper_test="$(mktemp -d)"
tmp_desktop_home="$tmp_desktop_wallpaper_test/home"
tmp_desktop_state="$tmp_desktop_wallpaper_test/state"
tmp_desktop_bin="$tmp_desktop_wallpaper_test/bin"
tmp_desktop_log="$tmp_desktop_wallpaper_test/tools.log"
tmp_desktop_wallpaper="$tmp_desktop_wallpaper_test/titlis-alps.jpg"
mkdir -p "$tmp_desktop_home" "$tmp_desktop_state" "$tmp_desktop_bin"
printf 'jpg\n' > "$tmp_desktop_wallpaper"
cat > "$tmp_desktop_bin/plasma-apply-wallpaperimage" <<EOF
#!/usr/bin/env bash
printf 'plasma %s\\n' "\$*" >> "$tmp_desktop_log"
EOF
cat > "$tmp_desktop_bin/pcmanfm-qt" <<EOF
#!/usr/bin/env bash
printf 'pcmanfm-qt %s\\n' "\$*" >> "$tmp_desktop_log"
EOF
cat > "$tmp_desktop_bin/feh" <<EOF
#!/usr/bin/env bash
printf 'feh %s\\n' "\$*" >> "$tmp_desktop_log"
EOF
cat > "$tmp_desktop_bin/swaybg" <<EOF
#!/usr/bin/env bash
printf 'swaybg %s\\n' "\$*" >> "$tmp_desktop_log"
sleep 0.1
EOF
cat > "$tmp_desktop_bin/xfconf-query" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-c" && "\${3:-}" == "-l" ]]; then
  printf '/backdrop/screen0/monitor0/workspace0/last-image\\n'
  exit 0
fi
printf 'xfconf %s\\n' "\$*" >> "$tmp_desktop_log"
EOF
chmod +x "$tmp_desktop_bin"/*
run_desktop_wallpaper_seed() {
  local current="$1"
  local session="$2"
  HOME="$tmp_desktop_home" \
  XDG_STATE_HOME="$tmp_desktop_state/$current-$session" \
  XDG_RUNTIME_DIR="$tmp_desktop_wallpaper_test/runtime-$current-$session" \
  XDG_CURRENT_DESKTOP="$current" \
  DESKTOP_SESSION="$session" \
  DISPLAY=":99" \
  WAYLAND_DISPLAY="wayland-test" \
  PATH="$tmp_desktop_bin:/usr/bin:/bin" \
  ABORA_DEFAULT_WALLPAPER="$tmp_desktop_wallpaper" \
  ABORA_DEFAULT_DARK_WALLPAPER="$tmp_desktop_wallpaper" \
  ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
    bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
}
run_desktop_wallpaper_seed "KDE" "plasma"
run_desktop_wallpaper_seed "XFCE" "xfce"
run_desktop_wallpaper_seed "LXQt" "lxqt"
run_desktop_wallpaper_seed "sway" "sway"
run_desktop_wallpaper_seed "i3" "i3"
if grep -q "plasma ${tmp_desktop_wallpaper}" "$tmp_desktop_log" \
	  && grep -q "xfconf .*${tmp_desktop_wallpaper}" "$tmp_desktop_log" \
	  && grep -q "pcmanfm-qt --set-wallpaper=${tmp_desktop_wallpaper}" "$tmp_desktop_log" \
	  && grep -q "swaybg -i ${tmp_desktop_wallpaper} -m fill" "$tmp_desktop_log" \
	  && grep -q "feh --no-fehbg --bg-fill ${tmp_desktop_wallpaper}" "$tmp_desktop_log" \
	  && [[ -f "$tmp_desktop_state/sway-sway/abora/wallpaper-seed" ]] \
	  && [[ -f "$tmp_desktop_state/i3-i3/abora/wallpaper-seed" ]]; then
	  pass "runtime: non-GNOME desktop wallpaper seeders call the right tools"
	else
	  fail "runtime: non-GNOME desktop wallpaper seeders call the right tools"
fi
rm -rf "$tmp_desktop_wallpaper_test"

if grep -q 'systemd.user.services.abora-session-setup' nix/modules/installed-base.nix \
  && grep -q 'systemd.user.services.abora-session-setup' nix/profiles/live.nix \
  && grep -q 'graphical-session.target' nix/modules/installed-base.nix \
  && grep -q 'graphical-session.target' nix/profiles/live.nix \
  && grep -q 'ABORA_SESSION_SETUP_WAIT' scripts/abora-session-setup.sh; then
  pass "runtime: desktop session setup has a systemd fallback for non-XDG-autostart sessions"
else
  fail "runtime: desktop session setup has a systemd fallback for non-XDG-autostart sessions"
fi

if grep -q 'feh' nix/modules/installed-base.nix \
  && grep -q 'swaybg' nix/modules/installed-base.nix \
  && grep -q 'libsForQt5.qt5ct' nix/modules/installed-base.nix \
  && grep -q 'qt6Packages.qt6ct' nix/modules/installed-base.nix \
  && grep -q 'feh' nix/profiles/live.nix \
  && grep -q 'swaybg' nix/profiles/live.nix \
  && grep -q 'libsForQt5.qt5ct' nix/profiles/live.nix \
  && grep -q 'qt6Packages.qt6ct' nix/profiles/live.nix; then
  pass "static: live and installed systems ship wallpaper/theme helper tools"
else
  fail "static: live and installed systems ship wallpaper/theme helper tools"
fi

tmp_missing_wallpaper_session="$(mktemp -d)"
tmp_missing_wallpaper_home="$tmp_missing_wallpaper_session/home"
tmp_missing_wallpaper_state="$tmp_missing_wallpaper_session/state"
tmp_missing_wallpaper_log="$tmp_missing_wallpaper_session/gsettings.log"
tmp_missing_wallpaper_gsettings="$tmp_missing_wallpaper_session/gsettings"
mkdir -p "$tmp_missing_wallpaper_home" "$tmp_missing_wallpaper_state"
cat > "$tmp_missing_wallpaper_gsettings" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "get" ]]; then
  case "\${2:-}:\${3:-}" in
    org.gnome.desktop.interface:color-scheme) printf "'default'\\n" ;;
    *) printf "''\\n" ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "set" ]]; then
  printf '%s\\n' "\$*" >> "$tmp_missing_wallpaper_log"
  exit 0
fi
exit 1
EOF
chmod +x "$tmp_missing_wallpaper_gsettings"
HOME="$tmp_missing_wallpaper_home" \
XDG_STATE_HOME="$tmp_missing_wallpaper_state" \
XDG_CURRENT_DESKTOP="GNOME" \
WAYLAND_DISPLAY="wayland-1" \
ABORA_DEFAULT_WALLPAPER="$tmp_missing_wallpaper_session/missing-wallpaper.jpg" \
ABORA_DEFAULT_DARK_WALLPAPER="$tmp_missing_wallpaper_session/missing-wallpaper.jpg" \
ABORA_GSETTINGS_BIN="$tmp_missing_wallpaper_gsettings" \
ABORA_THEME_SYNC_SCRIPT="/no/theme-sync" \
  bash scripts/abora-session-setup.sh >/dev/null 2>&1 || true
if [[ -f "$tmp_missing_wallpaper_home/.zshrc" ]] \
  && grep -q "org.gnome.desktop.interface color-scheme 'prefer-light'" "$tmp_missing_wallpaper_log" 2>/dev/null \
  && ! grep -q "org.gnome.desktop.background picture-uri" "$tmp_missing_wallpaper_log" 2>/dev/null; then
  pass "runtime: session setup keeps non-wallpaper first-login work when wallpaper is missing"
else
  fail "runtime: session setup keeps non-wallpaper first-login work when wallpaper is missing"
fi
rm -rf "$tmp_missing_wallpaper_session"

if command -v python3 >/dev/null 2>&1; then
  for file in "${python_scripts[@]}"; do
    if [[ ! -f "$file" ]]; then
      fail "Missing file: $file"
      continue
    fi
    if python3 -m py_compile "$file"; then
      pass "syntax (python): $file"
    else
      fail "syntax (python): $file"
    fi
  done
else
  pass "python3 unavailable (GUI syntax checks skipped)"
fi

# Regression test: abora-installer-gui.py can't source the bash desktop
# library, so it keeps its own DESKTOPS list -- which silently drifted by
# one entry (missing "pantheon" entirely, so the graphical installer could
# never offer it even though it's a fully supported profile everywhere
# else: abora_supported_desktop_profiles, anix.sh's valid_desktops, and
# abora-options.nix's desktop enum all include it) before this check was
# added. Compares the real bash function's output against the GUI's real
# Python list, not a copy of either.
if command -v python3 >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  _desktop_bash_list="$(source scripts/abora-desktop-profiles.sh; abora_supported_desktop_profiles | sort)"
  _desktop_gui_list="$(python3 -c "
import re
text = open('scripts/abora-installer-gui.py').read()
m = re.search(r'DESKTOPS = \[(.*?)\]', text, re.S)
ids = re.findall(r\"\('(\w+)'\", m.group(1))
print('\n'.join(sorted(ids)))
")"
  if [[ "$_desktop_bash_list" == "$_desktop_gui_list" ]]; then
    pass "runtime: abora-installer-gui.py's DESKTOPS matches abora_supported_desktop_profiles"
  else
    fail "runtime: abora-installer-gui.py's DESKTOPS matches abora_supported_desktop_profiles"
    diff <(printf '%s\n' "$_desktop_bash_list") <(printf '%s\n' "$_desktop_gui_list") | sed 's/^/              /'
  fi
fi

# Regression test: abora-installer-gui.py's get_disks() re-implements
# abora-installer.sh's collect_disks() disk-name filtering in Python (can't
# source the bash awk filter), and it silently drifted -- missing "ram" and
# "zram" from its excluded-prefix list, so the GUI installer offered
# /dev/zram0 (RAM-backed, never real storage) as a selectable, pre-checked
# "Available Disk" whenever no other disk was excludable, while the TUI
# installer correctly filters it via `^(fd|loop|ram|sr|zram)`. Compares the
# GUI's real exclusion tuple against the TUI's real awk regex, not a copy of
# either.
if command -v python3 >/dev/null 2>&1; then
  _disk_filter_tui="$(grep -oE '\^\(fd\|loop\|ram\|sr\|zram\)' scripts/abora-installer.sh | head -1)"
  _disk_filter_gui="$(python3 -c "
import re
text = open('scripts/abora-installer-gui.py').read()
m = re.search(r\"name\.startswith\(\((.*?)\)\)\", text)
prefixes = sorted(re.findall(r\"'(\w+)'\", m.group(1)))
print(','.join(prefixes))
")"
  if [[ -n "$_disk_filter_tui" ]] \
    && [[ "$_disk_filter_gui" == "fd,loop,ram,sr,zram" ]]; then
    pass "runtime: abora-installer-gui.py's disk filter excludes ram/zram like abora-installer.sh"
  else
    fail "runtime: abora-installer-gui.py's disk filter excludes ram/zram like abora-installer.sh"
  fi
fi

# Regression test: get_disks()'s hotplug filter compared `d.get('hotplug')`
# against the string '1', but `lsblk -J` emits HOTPLUG as a real JSON
# boolean (true/false) -- a bool never equals a str in Python, so this
# comparison was always False and the filter never excluded a single
# device, despite its own docstring claiming it excludes
# "hotplug-flagged devices". A hotpluggable disk (e.g. a second USB drive
# inserted alongside the boot media) would be offered as an install
# target in the graphical installer. Imports the real module (skipped if
# PyGObject/Gtk4 aren't importable) and calls the real get_disks() with
# subprocess.run mocked to return fabricated lsblk JSON -- one disk with
# hotplug:true, one with hotplug:false -- checking the hotplug one is
# excluded and the other isn't.
if command -v python3 >/dev/null 2>&1 && python3 -c "import gi; gi.require_version('Gtk','4.0')" >/dev/null 2>&1; then
  set +e
  _hotplug_test_out="$(python3 -c "
import sys, json, importlib.util
from unittest import mock

spec = importlib.util.spec_from_file_location('abora_installer_gui', 'scripts/abora-installer-gui.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

fake_lsblk_json = json.dumps({
    'blockdevices': [
        {'name': 'sda', 'size': '32G', 'type': 'disk', 'model': 'USB Drive', 'hotplug': True},
        {'name': 'nvme0n1', 'size': '1T', 'type': 'disk', 'model': 'NVMe SSD', 'hotplug': False},
    ]
})

class FakeResult:
    def __init__(self, stdout):
        self.stdout = stdout
        self.returncode = 0

def fake_run(cmd, **kwargs):
    if cmd[0] == 'lsblk' and '-J' in cmd:
        return FakeResult(fake_lsblk_json)
    return FakeResult('')

with mock.patch.object(mod.subprocess, 'run', side_effect=fake_run):
    disks = mod.get_disks()

names = [d[0] for d in disks]
if '/dev/sda' in names or '/dev/nvme0n1' not in names:
    print('FAIL: %s' % (disks,))
    sys.exit(1)
print('PASS')
" 2>&1)"
  set -e
  if [[ "$_hotplug_test_out" == "PASS" ]]; then
    pass "runtime: abora-installer-gui.py's get_disks() excludes hotplug-flagged disks"
  else
    fail "runtime: abora-installer-gui.py's get_disks() excludes hotplug-flagged disks"
    printf '              %s\n' "$_hotplug_test_out"
  fi
else
  pass "PyGObject/Gtk4 unavailable (get_disks hotplug test skipped)"
fi

# Regression test for the "use an existing partition" install mode
# (list_disk_partitions/find_existing_esp/_partitions_with_children):
# extracts the real functions from abora-installer.sh (it can't be
# sourced wholesale -- it unconditionally runs `main "$@"` at the bottom)
# and exercises them against a fake `lsblk` on PATH, no root or real
# block devices required. Covers two real bug classes this code went
# through several rounds of real fixes for:
#   1. lsblk's default columnar output is space-padded/aligned, not a
#      fixed delimiter, so any value containing a space (a Windows
#      "System Reserved" LABEL being the most common real example)
#      silently shifted every field after it out of position under
#      naive `awk` field splitting -- switched to `lsblk -P`
#      (KEY="value" pairs) parsed with a portable match() loop instead.
#   2. list_disk_partitions() tagged ESP-typed partitions with "[ESP]"
#      but didn't exclude them from the candidate *root* list -- an
#      operator could select the very ESP find_existing_esp() found to
#      reuse unformatted as their new root partition instead, and
#      partition_disk_existing() would then mkfs.ext4 over it. sda5
#      below is an unmounted, unused ESP (plausible real state: left
#      over after a previous install was wiped) that must never appear
#      in list_disk_partitions()'s output even though it would pass
#      every other filter (not mounted, no busy children).
tmp_partfuncs="$(mktemp)"
tmp_lsblk_bin="$(mktemp -d)"
sed -n '/^readonly ESP_PARTTYPE_GUID=/,/^check_install_environment()/p' scripts/abora-installer.sh \
  | sed '$d' > "$tmp_partfuncs"
if [[ -s "$tmp_partfuncs" ]] && bash -n "$tmp_partfuncs" 2>/dev/null; then
  cat > "$tmp_lsblk_bin/lsblk" <<'LSBLK_SHIM'
#!/usr/bin/env bash
if [[ "$*" == *"NAME,PKNAME"* ]]; then
  printf 'NAME="sda" PKNAME=""\n'
  printf 'NAME="sda1" PKNAME="sda"\n'
  printf 'NAME="sda2" PKNAME="sda"\n'
  printf 'NAME="sda3" PKNAME="sda"\n'
  printf 'NAME="sda4" PKNAME="sda"\n'
  printf 'NAME="sda5" PKNAME="sda"\n'
  printf 'NAME="mapper-root" PKNAME="sda3"\n'
  exit 0
fi
if [[ "$*" == *"PARTTYPE,TYPE"* ]]; then
  printf 'NAME="sda1" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
  printf 'NAME="sda2" PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" TYPE="part"\n'
  printf 'NAME="sda5" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
  exit 0
fi
printf 'NAME="sda1" SIZE="2147483648" FSTYPE="vfat" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" LABEL="System Reserved" TYPE="part" MOUNTPOINT="/boot"\n'
printf 'NAME="sda2" SIZE="107374182400" FSTYPE="ext4" PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" LABEL="" TYPE="part" MOUNTPOINT=""\n'
printf 'NAME="sda3" SIZE="500000000000" FSTYPE="crypto_LUKS" PARTTYPE="" LABEL="" TYPE="part" MOUNTPOINT=""\n'
printf 'NAME="sda4" SIZE="1390104516608" FSTYPE="ntfs" PARTTYPE="" LABEL="Windows Data Disk" TYPE="part" MOUNTPOINT=""\n'
printf 'NAME="sda5" SIZE="536870912" FSTYPE="vfat" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" LABEL="" TYPE="part" MOUNTPOINT=""\n'
LSBLK_SHIM
  chmod +x "$tmp_lsblk_bin/lsblk"

  _parts_out="$(PATH="$tmp_lsblk_bin:$PATH" bash -c "source '$tmp_partfuncs'; list_disk_partitions /dev/sda")"
  _esp_out="$(PATH="$tmp_lsblk_bin:$PATH" bash -c "source '$tmp_partfuncs'; find_existing_esp /dev/sda")"

  if printf '%s' "$_parts_out" | grep -q '^/dev/sda2|' \
    && printf '%s' "$_parts_out" | grep -q '^/dev/sda4|.*(Windows Data Disk)' \
    && ! printf '%s' "$_parts_out" | grep -q '^/dev/sda1|' \
    && ! printf '%s' "$_parts_out" | grep -q '^/dev/sda3|' \
    && ! printf '%s' "$_parts_out" | grep -q '^/dev/sda5|' \
    && [[ "$_esp_out" == "/dev/sda1" ]]; then
    pass "runtime: list_disk_partitions/find_existing_esp parse lsblk -P correctly and never offer an ESP as a root candidate"
  else
    fail "runtime: list_disk_partitions/find_existing_esp parse lsblk -P correctly and never offer an ESP as a root candidate"
  fi
else
  fail "runtime: could not extract disk-partition helper functions from abora-installer.sh"
fi
rm -f "$tmp_partfuncs"
rm -rf "$tmp_lsblk_bin"

if command -v shellcheck >/dev/null 2>&1; then
  # -S error matches the dedicated "ShellCheck scripts" CI workflow step —
  # info/warning-level style nits (SC1007, SC2015, SC2016, SC2086, etc.) are
  # exactly the kind of thing check-all's shellcheck warning tier is for, not
  # a hard gate here on every push.
  if shellcheck -S error scripts/abora-update.sh scripts/abora-repair-flake-purity.sh scripts/check-release-files.sh; then
    pass "shellcheck: updater and repair scripts"
  else
    fail "shellcheck: updater and repair scripts"
  fi
else
  pass "shellcheck unavailable (updater lint skipped)"
fi

for file in "${nix_files[@]}"; do
  if [[ -f "$file" ]]; then
    pass "exists: $file"
  else
    fail "Missing file: $file"
  fi
done

for file in "${required_files[@]}"; do
  if [[ -f "$file" ]]; then
    pass "exists: $file"
  else
    fail "Missing file: $file"
  fi
done

if grep -q 'ABORA_NIXPKGS_PATH' scripts/dev-doctor.sh \
  && grep -q 'Nix daemon/store' scripts/dev-doctor.sh \
  && grep -q 'ABORA_NIXPKGS_PATH' docs/wiki/Building-Abora.md \
  && grep -q 'make doctor' docs/release-checklist.md; then
  pass "developer doctor documents nixpkgs and daemon/store failures"
else
  fail "developer doctor must document nixpkgs and daemon/store failures"
fi

_old_branding_matches="$(
  grep -RIEn \
    --exclude='check-scripts.sh' \
    '2026[.]7[.]27|current stable release|Tracks `main` directly' \
    README.md RELEASE_NOTES.md docs scripts nix \
    2>/dev/null || true
)"
if [[ -z "$_old_branding_matches" ]] \
  && grep -q 'Abora OS v4 Everest' RELEASE_NOTES.md \
  && grep -q 'git tag v4.0' docs/wiki/Release-Guide.md \
  && grep -q 'x86_64-v4.0.iso' RELEASE_NOTES.md \
  && grep -q 'SHA256SUMS-v4.0.txt' RELEASE_NOTES.md \
  && grep -q 'abora_release_stage="${ABORA_RELEASE_STAGE:-alpha}"' scripts/abora-installer.sh \
  && grep -q 'abora_release_channel="${ABORA_RELEASE_CHANNEL:-unstable}"' scripts/abora-installer.sh \
  && grep -q 'Abora OS v4 Everest' scripts/abora-installer.sh \
  && grep -q 'ABORA OS  —  v4 Everest' scripts/abora-boot.sh \
  && grep -q 'ABORA_DEFAULT_CHANNEL:-unstable' scripts/abora-welcome.sh \
  && grep -q "ABORA_DEFAULT_CHANNEL', 'unstable'" scripts/abora-welcome-gui.py \
  && grep -q 'ABORA_DEFAULT_CHANNEL:-unstable' scripts/abora-doctor.sh \
  && grep -q 'v4 Everest alpha default' docs/wiki/Updating-Abora.md \
  && grep -q 'release_name="${ABORA_RELEASE_NAME:-Abora OS v4 Everest}"' scripts/abora-support-report.sh \
  && grep -q "printf 'v4 Everest'" scripts/abora-ui.sh \
  && grep -q 'release_short="v4 Everest"' scripts/check-desktops.sh \
  && grep -q 'PRETTY_NAME = "Abora OS v4 Everest"' nix/profiles/live.nix \
  && grep -q 'PRETTY_NAME = "Abora OS v4 Everest"' nix/modules/installed-base.nix \
  && grep -q 'VERSION = "v4 Everest"' nix/profiles/live.nix \
  && grep -q 'VERSION_ID = "4"' nix/modules/installed-base.nix; then
  pass "runtime: v4 Everest branding is consistent"
else
  fail "runtime: v4 Everest branding is consistent"
  if [[ -n "$_old_branding_matches" ]]; then
    printf '%s\n' "$_old_branding_matches" | sed 's/^/              /'
  fi
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || continue
    if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
      pass "tracked by git: $file"
    else
      fail "untracked source file: $file"
    fi
  done
fi

if command -v nix >/dev/null 2>&1; then
  set +e
  _nix_eval_output="$(
    nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file "$repo_dir" 2>&1
  )"
  _nix_eval_status=$?
  set -e
  if [[ "$_nix_eval_status" -eq 0 ]]; then
    pass "nix flake evaluation"
  elif grep -q '/nix/var/nix/db/big-lock.*Permission denied' <<<"$_nix_eval_output"; then
    pass "nix store unavailable (flake eval skipped)"
  elif grep -q "/nix/var/nix/daemon-socket/socket.*Connection refused" <<<"$_nix_eval_output"; then
    pass "nix daemon unavailable (flake eval skipped)"
  elif grep -q "remote store 'daemon' previously failed" <<<"$_nix_eval_output"; then
    pass "nix daemon unavailable (flake eval skipped)"
  else
    fail "nix flake evaluation"
    printf '%s\n' "$_nix_eval_output" | sed 's/^/              /'
  fi
else
  pass "nix command unavailable (flake eval skipped)"
fi

# ── Pure-eval safety lint ──────────────────────────────────────────────────────
# Committed Nix and installer templates must never hardcode /nix/store paths.
# Flakes may only access source files that are part of the flake input or copied
# into the installed /etc/nixos tree.
_pure_eval_ok=1
_pure_eval_files=(
  flake.nix
  nix
  scripts
)
_pure_eval_matches="$(
  grep -RIEn \
    --exclude='check-scripts.sh' \
    --exclude='abora-repair-flake-purity.sh' \
    '(/nix/store/assets|source[[:space:]]*=[[:space:]]*"?/nix/store|builtins\.storePath)' \
    "${_pure_eval_files[@]}" 2>/dev/null || true
)"
if [[ -n "$_pure_eval_matches" ]]; then
  fail "pure-eval: forbidden hardcoded /nix/store path or builtins.storePath found"
  printf '%s\n' "$_pure_eval_matches" | while IFS= read -r _ln; do
    printf '              %s\n' "$_ln"
  done
  _pure_eval_ok=0
fi
[[ "$_pure_eval_ok" == 1 ]] && pass "pure-eval: no hardcoded /nix/store paths in Nix/templates"

_installed_mango_static_matches="$(
  grep -RIEn \
    '(/nix/store/assets|(\.\./\.\./|\.\./\.\./\.\./)assets/mango/config\.conf)' \
    nix/modules/abora-options.nix \
    nix/modules/installed-base.nix \
    2>/dev/null || true
)"
if [[ -n "$_installed_mango_static_matches" ]]; then
  fail "pure-eval: installed Mango modules contain repo-relative asset paths"
  printf '%s\n' "$_installed_mango_static_matches" | while IFS= read -r _ln; do
    printf '              %s\n' "$_ln"
  done
else
  pass "pure-eval: installed Mango modules use installed asset paths"
fi

tmp_mango_repair="$(mktemp -d)"
mkdir -p "$tmp_mango_repair/abora/desktops" "$tmp_mango_repair/.abora-upstream/assets/mango"
cp nix/modules/abora-options.nix "$tmp_mango_repair/abora/abora-options.nix"
cp nix/modules/installed-base.nix "$tmp_mango_repair/abora/installed-base.nix"
cp nix/modules/desktops/mangowm.nix "$tmp_mango_repair/abora/desktops/mangowm.nix"
cp assets/mango/config.conf "$tmp_mango_repair/.abora-upstream/assets/mango/config.conf"
if ABORA_SYSTEM_CONFIG="$tmp_mango_repair" bash scripts/abora-repair-flake-purity.sh --mango >/dev/null; then
  _repaired_mango_matches="$(
    grep -RIEn \
      '(/nix/store/assets|(\.\./\.\./|\.\./\.\./\.\./)assets/mango/config\.conf)' \
      "$tmp_mango_repair/abora" 2>/dev/null || true
  )"
  if [[ -n "$_repaired_mango_matches" ]]; then
    fail "pure-eval: Mango repair leaves forbidden installed asset paths"
    printf '%s\n' "$_repaired_mango_matches" | while IFS= read -r _ln; do
      printf '              %s\n' "$_ln"
    done
  elif [[ ! -s "$tmp_mango_repair/abora/mango/config.conf" ]]; then
    fail "pure-eval: Mango repair did not create abora/mango/config.conf"
  elif ! grep -q 'mangoConfigFile' "$tmp_mango_repair/abora/desktops/mangowm.nix"; then
    fail "pure-eval: Mango desktop module does not use a local config selector"
  else
    pass "pure-eval: Mango repair produces flake-local installed paths"
  fi
else
  fail "pure-eval: Mango repair script failed"
fi
rm -rf "$tmp_mango_repair"

tmp_ok="$(mktemp -d)"
tmp_empty="$(mktemp -d)"
tmp_update_flake="$(mktemp -d)"
trap 'rm -rf "$tmp_ok" "$tmp_empty" "$tmp_update_flake"; rm -f "${resolver_wrapper:-}" "${plan_tool_wrapper:-}"' EXIT

cat > "$tmp_update_flake/flake.nix" <<'EOF'
{
  broken =
EOF
if ABORA_SYSTEM_CONFIG="$tmp_update_flake" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-write-flake >/dev/null; then
  _update_flake_backup="$(compgen -G "$tmp_update_flake/flake.nix.backup-*" | head -n1 || true)"
  if [[ -n "$_update_flake_backup" ]] \
    && bash -c 'nix-instantiate --parse "$1" >/dev/null' _ "$tmp_update_flake/flake.nix" 2>/dev/null; then
    pass "runtime: updater writes flake.nix atomically with backup"
  elif [[ -n "$_update_flake_backup" ]] \
    && grep -q 'nixosConfigurations' "$tmp_update_flake/flake.nix"; then
    pass "runtime: updater writes flake.nix atomically with backup"
  else
    fail "runtime: updater flake writer did not produce valid flake and backup"
  fi
else
  fail "runtime: updater flake writer self-test"
fi

# path:/etc/abora/nixpkgs looks tempting because it points at the running
# system's nixpkgs tree, but on NixOS /etc entries resolve through
# /etc/static. Pure flake evaluation rejects that absolute path, breaking
# both `sudo abora update` and `sudo abora config apply`.
if grep -q 'inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";' "$tmp_update_flake/flake.nix" \
  && grep -q 'inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";' scripts/abora-installer.sh \
  && ! grep -q 'path:/etc/abora/nixpkgs' "$tmp_update_flake/flake.nix" \
  && ! grep -q 'path:/etc/abora/nixpkgs' scripts/abora-installer.sh; then
  pass "runtime: installed flake uses a pure nixos-unstable input"
else
  fail "runtime: installed flake uses a pure nixos-unstable input"
fi

# nixos-install must actually build through that flake (not the legacy
# NIX_PATH+configuration.nix path this used to take) for the input above to
# matter at all -- otherwise the very first install still evaluates
# through a different path than what built the live ISO, defeating the
# fix above on exactly the run where it counts most.
if grep -q 'nixos-install --root /mnt --no-root-passwd --flake "/mnt/etc/nixos#abora"' scripts/abora-installer.sh \
  && ! grep -q 'NIX_PATH=nixpkgs=\${nixpkgs}:nixos-config=/mnt/etc/nixos/configuration.nix' scripts/abora-installer.sh; then
  pass "runtime: nixos-install runs through the flake, not legacy NIX_PATH"
else
  fail "runtime: nixos-install runs through the flake, not legacy NIX_PATH"
fi

if grep -Fq 'type = lib.types.enum [ "auto" "nouveau" "nvidia" "nvidia-open" "amdgpu" "intel" "none" ];' nix/modules/abora-options.nix \
  && grep -Fq 'accepts "auto" as a compatibility-safe no-op' nix/modules/abora-options.nix; then
  pass "runtime: abora.gpu accepts legacy/batch auto values as a no-op"
else
  fail "runtime: abora.gpu accepts legacy/batch auto values as a no-op"
fi

if scripts/check-release-files.sh >/dev/null; then
  pass "runtime: release file manifest"
else
  fail "runtime: release file manifest"
fi

if grep -q '^scripts/abora-dotfiles-import.sh$' scripts/check-release-files.sh; then
  pass "runtime: release manifest includes dotfiles importer"
else
  fail "runtime: release manifest includes dotfiles importer"
fi

# Regression test: check-release-files.sh's own header comment says its list
# "mirrors abora-update.sh's required_upstream_paths()" -- but nothing ever
# verified that claim stayed true, and it silently drifted by 9 real files
# (all 3 Python GUIs, both C# tools' source/csproj/nix files) before this was
# added. A file missing here means `make check` won't catch it before a tag,
# even though `sudo abora update` against that tag will fail
# validate_upstream_checkout() for real users -- exactly the failure mode the
# earlier abora-update-resolver-deps.json bug shipped through. Extracts both
# lists straight from the source text (not by running abora-update.sh, which
# does real network/system work) and diffs them; nix/pkgs/scenefx-0_5.nix is
# the one documented, intentional exception (an internal mango build
# dependency the updater never syncs directly).
_update_paths="$(sed -n '/^required_upstream_paths() {/,/^}$/p' scripts/abora-update.sh \
  | grep -E '^[A-Za-z0-9_./-]+$' | sort -u)"
_release_paths="$(sed -n '/^required_paths() {/,/^}$/p' scripts/check-release-files.sh \
  | grep -E '^[A-Za-z0-9_./-]+$' | sort -u)"
_missing_from_release="$(comm -23 <(printf '%s\n' "$_update_paths") <(printf '%s\n' "$_release_paths"))"
if [[ -z "$_missing_from_release" ]]; then
  pass "runtime: check-release-files.sh mirrors abora-update.sh's required_upstream_paths"
else
  fail "runtime: check-release-files.sh mirrors abora-update.sh's required_upstream_paths"
  printf '%s\n' "$_missing_from_release" | while IFS= read -r _p; do
    printf '              missing from check-release-files.sh: %s\n' "$_p"
  done
fi

if [[ -n "$resolver_bin" ]]; then
  export ABORA_UPDATE_RESOLVER_BIN="$resolver_bin"

  _resolver_tags="v2.5.0 v3.14"
  if ABORA_RELEASE_TAGS="$_resolver_tags" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-ref 3.14 stable | grep -q '^v3\.14[[:space:]]'; then
    pass "runtime: resolver keeps 3.14 on v3.14"
  else
    fail "runtime: resolver keeps 3.14 on v3.14"
  fi

  # Regression test: this used to be a byte-for-byte copy of the "keeps
  # 3.14 on v3.14" test above (same tag list, same expectation), which
  # meant "prefers final over demo" was never actually exercised -- both
  # a demo tag and the final tag exist for the same version here, and the
  # final one must win (see UpdateResolver.cs's ResolveStableChannel).
  _resolver_tags="v2.5.0 v3.14-DEMO v3.14"
  if ABORA_RELEASE_TAGS="$_resolver_tags" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-ref 3.14 stable | grep -q '^v3\.14[[:space:]]'; then
    pass "runtime: resolver prefers final v3.14 when present"
  else
    fail "runtime: resolver prefers final v3.14 when present"
  fi

  _resolver_tags="v2.5.0"
  if ABORA_RELEASE_TAGS="$_resolver_tags" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-ref 3.14 stable | grep -q '^edge[[:space:]]'; then
    pass "runtime: resolver avoids stable-channel downgrade"
  else
    fail "runtime: resolver avoids stable-channel downgrade"
  fi

  if ABORA_RELEASE_TAGS="" ABORA_REMOTE_REFS="edge" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-ref 4.0 stable | grep -q '^edge[[:space:]]'; then
    pass "runtime: resolver falls back to edge when stable tags are unavailable"
  else
    fail "runtime: resolver falls back to edge when stable tags are unavailable"
  fi

  if ABORA_RELEASE_TAGS="v4.0-EVEREST-ALPHA v3.14" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-ref 4.0 demo | grep -q '^v4\.0-EVEREST-ALPHA[[:space:]]'; then
    pass "runtime: resolver recognizes Everest alpha tags as development releases"
  else
    fail "runtime: resolver recognizes Everest alpha tags as development releases"
  fi

  if ABORA_RELEASE_TAGS="v2.5.0" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-fallback 3.14 v2.5.0 | grep -q '^v2\.5\.0[[:space:]]'; then
    pass "runtime: resolver allows explicit fallback downgrade"
  else
    fail "runtime: resolver allows explicit fallback downgrade"
  fi

  # Regression test: installed_version() used to return the literal path
  # string "$config_dir/abora/VERSION" (unparsed, un-fed-to-version_lt-safe)
  # whenever that specific candidate file didn't exist, instead of falling
  # through to /etc/abora/VERSION and finally the repo's own VERSION file.
  # Point config_dir somewhere with no abora/VERSION and confirm the real
  # repo VERSION ("4.0") is still found via the final fallback candidate.
  _tmp_no_config_dir="$(mktemp -d)"
  _installed_version_check="$(ABORA_SYSTEM_CONFIG="$_tmp_no_config_dir" ABORA_RELEASE_TAGS="v99.0" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh --check 2>/dev/null | \
    awk -F'\t' '/^ABORA_UPDATE_AVAILABLE/ {print $2}' || true)"
  rm -rf "$_tmp_no_config_dir"
  if [[ "$_installed_version_check" == "$(tr -d '[:space:]' < "$repo_dir/VERSION")" ]]; then
    pass "runtime: installed_version() falls through to repo VERSION when installed paths are missing"
  else
    fail "runtime: installed_version() returned '${_installed_version_check}' instead of the repo VERSION"
  fi

  unset ABORA_UPDATE_RESOLVER_BIN
else
  pass "runtime: abora-update-resolver tests skipped (dotnet unavailable)"
fi

if [[ -n "$resolver_bin" ]]; then
  prealpha_dry_run_output="$(
    ABORA_PRE_ALPHA_ACCEPT="I ACCEPT THE RISK" \
    ABORA_INSTALLED_VERSION="4.0" \
    ABORA_SYSTEM_CONFIG="$tmp_update_flake" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    ABORA_UPDATE_RESOLVER_BIN="$resolver_bin" \
    bash scripts/abora-update.sh install pre-alpha --dry-run --ref test-prealpha 2>&1
  )"
  if printf '%s' "$prealpha_dry_run_output" | grep -q 'Selected update ref.*test-prealpha' \
    && printf '%s' "$prealpha_dry_run_output" | grep -q 'Dry run complete'; then
    pass "runtime: pre-alpha dry-run previews selected ref"
  else
    fail "runtime: pre-alpha dry-run previews selected ref"
  fi
else
  pass "runtime: pre-alpha dry-run test skipped (dotnet unavailable)"
fi

if ABORA_PRE_ALPHA_ACCEPT="I ACCEPT THE RISK" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-pre-alpha-confirm >/dev/null; then
  pass "runtime: pre-alpha warning accepts exact phrase"
else
  fail "runtime: pre-alpha warning accepts exact phrase"
fi

if ABORA_PRE_ALPHA_ACCEPT="I accept the risk" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-pre-alpha-confirm >/dev/null 2>&1; then
  fail "runtime: pre-alpha warning rejects non-exact phrase"
else
  pass "runtime: pre-alpha warning rejects non-exact phrase"
fi

if grep -q '^[[:space:]]*rollback)' scripts/abora.sh \
  && grep -q 'exec abora-update rollback' scripts/abora.sh \
  && grep -q '^[[:space:]]*channel)' scripts/abora.sh \
  && grep -q 'handle_channel_command "$@"' scripts/abora-update.sh \
  && grep -q '^[[:space:]]*dotfiles)' scripts/abora.sh \
  && grep -q 'exec abora-dotfiles-import' scripts/abora.sh \
  && grep -q '^[[:space:]]*network)' scripts/abora.sh \
  && grep -q 'exec abora-recovery network "$@"' scripts/abora.sh \
  && grep -q 'exec "$script_dir/abora-recovery.sh" network "$@"' scripts/abora.sh \
  && grep -q 'exec "$script_dir/abora-recovery.sh" "$@"' scripts/abora.sh \
  && grep -q '^[[:space:]]*logs|log)' scripts/abora.sh \
  && grep -q 'show_logs "$@"' scripts/abora.sh \
  && grep -q 'ABORA_LOG_LINES' scripts/abora.sh \
  && grep -q '^[[:space:]]*bug-report|bug)' scripts/abora.sh \
  && grep -q 'show_bug_report_template' scripts/abora.sh \
  && grep -q 'create_github_issue "$@"' scripts/abora.sh \
  && grep -q 'gh issue create --repo "$repo"' scripts/abora.sh \
  && grep -q '^[[:space:]]*build)' scripts/abora.sh \
  && grep -q 'command -v abora-build' scripts/abora.sh \
  && grep -q 'exec "$script_dir/abora-build.sh"' scripts/abora.sh \
  && grep -q '^[[:space:]]*adopt-nixos|adopt)' scripts/abora.sh \
  && grep -q 'exec "$script_dir/abora-adopt-nixos.sh"' scripts/abora.sh \
  && grep -q '^[[:space:]]*gaming)' scripts/abora.sh \
  && grep -q 'exec abora-gaming' scripts/abora.sh \
  && grep -q 'exec "$script_dir/abora-gaming.sh"' scripts/abora.sh \
  && grep -q 'exec abora-update channel "$@"' scripts/abora.sh \
  && ! grep -q 'ABORA_UPDATE_COMMAND=nixos abora-update channel' scripts/abora.sh \
  && grep -q 'abora channel set <stable|demo|unstable>' scripts/abora-update.sh; then
  pass "runtime: abora command routes update, channel, rollback, network, logs, bug-report, dotfiles, gaming, and pre-alpha"
else
  fail "runtime: abora command routes update, channel, rollback, network, logs, bug-report, dotfiles, gaming, and pre-alpha"
fi

# Regression test: `abora setup` was documented as "the installed
# reconfiguration launcher" in 5 separate doc files (docs/hardware-testing.md,
# docs/install-checklist.md, docs/release-checklist.md,
# docs/wiki/Updating-Abora.md, docs/wiki/Abora-Tools.md) but abora.sh's
# dispatcher had no "setup)" case at all -- `abora setup` failed outright
# with "Unknown Abora command: setup" (reproduced directly) despite every
# doc claiming it worked. Checks both that the dispatcher now has the case
# (statically) and that running it actually reaches the exec attempt at
# runtime (fails on "abora-setup: not found" -- expected on a bare
# checkout without the Nix-built wrapper on PATH -- rather than "Unknown
# Abora command", proving it's routed correctly).
_setup_run_out="$(./abora setup 2>&1 || true)"
if grep -q '^[[:space:]]*setup)' scripts/abora.sh \
  && grep -q 'exec abora-setup "\$@"' scripts/abora.sh \
  && ! printf '%s' "$_setup_run_out" | grep -q 'Unknown Abora command'; then
  pass "runtime: abora setup is routed to abora-setup, matching its documented behavior"
else
  fail "runtime: abora setup is routed to abora-setup, matching its documented behavior"
fi

build_help_out="$(scripts/abora-build.sh --help 2>&1)"
if printf '%s' "$build_help_out" | grep -q 'abora build --from-source' \
  && ./abora --help | grep -q 'abora build --from-source' \
  && grep -q 'abora = mkLive "cosmic";' flake.nix \
  && grep -q 'nixosConfigurations.abora.config.system.build.toplevel' scripts/abora-build.sh \
  && grep -q 'nixosConfigurations.abora-live-cosmic.config.system.build.toplevel' scripts/abora-build.sh \
  && grep -q 'does not expose the short "abora" flake alias yet' scripts/abora-build.sh \
  && grep -q 'before the short "abora" flake alias existed' scripts/abora-build.sh \
  && grep -q 'abora build --from-source --ref main' scripts/abora-build.sh \
  && grep -q 'ABORA_REPO_URLS' scripts/abora-build.sh \
  && grep -q 'ref_fallback_candidates()' scripts/abora-build.sh \
  && grep -q 'selected ref "%s" was unavailable; using branch fallback "%s"' scripts/abora-build.sh \
  && grep -q 'Abora compatibility build finished successfully' scripts/abora-build.sh \
  && grep -q 'Trying compatibility target' scripts/abora-build.sh \
  && grep -q 'https://github.com/AnimatedGTVR/Abora-OS.git' scripts/abora-build.sh \
  && grep -q 'aboraBuild = pkgs.writeShellScriptBin "abora-build"' nix/profiles/live.nix \
  && grep -q 'aboraBuild = pkgs.writeShellScriptBin "abora-build"' nix/modules/installed-base.nix \
  && grep -q '"abora/build.sh"' nix/profiles/live.nix \
  && grep -q '"abora/build.sh"' nix/modules/installed-base.nix; then
  pass "runtime: abora build --from-source is wired to the source build target"
else
  fail "runtime: abora build --from-source is wired to the source build target"
fi

tmp_abora_build_path="$(mktemp -d)"
cat >"$tmp_abora_build_path/abora-build" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
chmod +x "$tmp_abora_build_path/abora-build"
abora_build_wrapper_out="$(PATH="$tmp_abora_build_path:$PATH" ./abora build --from-source --ref edge 2>&1)"
rm -rf "$tmp_abora_build_path"
if printf '%s\n' "$abora_build_wrapper_out" | grep -qx -- '--from-source' \
  && printf '%s\n' "$abora_build_wrapper_out" | grep -qx -- '--ref' \
  && printf '%s\n' "$abora_build_wrapper_out" | grep -qx -- 'edge'; then
  pass "runtime: abora build wrapper preserves source-build arguments"
else
  fail "runtime: abora build wrapper preserves source-build arguments"
fi

abora_logs_help_out="$(./abora logs --help 2>&1)"
if printf '%s' "$abora_logs_help_out" | grep -Fq 'abora logs [--lines N]' \
  && grep -q 'abora logs --lines 200' docs/install-checklist.md \
  && grep -q 'abora logs --lines 200' docs/release-checklist.md \
  && grep -q 'abora logs --lines 200' docs/wiki/Recovery.md \
  && grep -q 'abora logs' docs/wiki/Abora-Tools.md \
  && grep -q 'abora logs%b' scripts/abora-installer.sh; then
  pass "runtime: abora logs is documented for live installer triage"
else
  fail "runtime: abora logs is documented for live installer triage"
fi

adopt_help_out="$(scripts/abora-adopt-nixos.sh --help 2>&1)"
if printf '%s' "$adopt_help_out" | grep -q 'abora adopt-nixos' \
  && printf '%s' "$adopt_help_out" | grep -q 'without erasing /home' \
  && ./abora --help | grep -q 'abora adopt-nixos' \
  && grep -q 'abora.user.name = null;' scripts/abora-adopt-nixos.sh \
  && grep -q 'desktop="none"' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora-backups' scripts/abora-adopt-nixos.sh \
  && grep -q 'sudo nixos-rebuild test' scripts/abora-adopt-nixos.sh \
  && grep -q 'aboraAdoptNixos = pkgs.writeShellScriptBin "abora-adopt-nixos"' nix/profiles/live.nix \
  && grep -q 'aboraAdoptNixos = pkgs.writeShellScriptBin "abora-adopt-nixos"' nix/modules/installed-base.nix \
  && grep -q '"abora/adopt-nixos.sh"' nix/profiles/live.nix \
  && grep -q '"abora/adopt-nixos.sh"' nix/modules/installed-base.nix; then
  pass "runtime: existing NixOS adoption path is non-destructive by default"
else
  fail "runtime: existing NixOS adoption path is non-destructive by default"
fi

# Regression test: abora-adopt-nixos.sh's copy list used to cover barely
# half of what nix/modules/installed-base.nix unconditionally requires
# (its own header comment: "the installer copies every required file via
# cp_required before the first nixos-rebuild, so the ./x paths are always
# present" -- true for the real installer's write_branding_assets(), but
# abora-adopt-nixos.sh has its own separate, hand-maintained copy list
# that had drifted, missing ~15 required files/dirs including
# adopt-nixos.sh itself, plus a destination-name bug (wallpaper-themes
# instead of the themes name installed-base.nix actually looks for) and a
# missing-parent-directory bug in copy_if_exists() (vendor/modularity and
# tools/moducpp-anix both failed to copy: "cp: cannot create directory").
# `sudo abora adopt-nixos --apply` followed by its own documented next
# step (`sudo nixos-rebuild test`) could not have completed a real
# adoption before this fix, regardless of the configuration.nix fixes
# made separately. This runs the real copy logic (not a copy of it)
# against this real repo checkout into a sandboxed directory, and checks
# every required destination path installed-base.nix's own source
# actually demands.
if command -v python3 >/dev/null 2>&1; then
  _required_dests="$(python3 -c "
import re
text = open('nix/modules/installed-base.nix').read()
let_block = text.split('\nin\n')[0]
lines = let_block.splitlines()
required = []
i = 0
while i < len(lines):
    m = re.match(r'\s*(\w+)\s*=\s*(.*)', lines[i])
    if m:
        name, rhs = m.groups()
        chunk = rhs
        j = i
        while ';' not in chunk and j < len(lines) - 1:
            j += 1
            chunk += ' ' + lines[j]
        if 'pathExists' not in chunk:
            paths = re.findall(r'\./([A-Za-z0-9_./-]+)', chunk)
            required += paths
    i += 1
print('\n'.join(sorted(set(required))))
")"

  tmp_adopt_copy="$(mktemp)"
  {
    sed -n '/^copy_if_exists() {/,/^}$/p' scripts/abora-adopt-nixos.sh
    sed -n '/^abora_dir="\$config_dir\/abora"$/,/^cat > "\$target_import"/p' scripts/abora-adopt-nixos.sh | sed '$d'
  } > "$tmp_adopt_copy"
  tmp_adopt_target="$(mktemp -d)"
  if bash -n "$tmp_adopt_copy" 2>/dev/null \
    && ( repo_dir="$repo_dir"; config_dir="$tmp_adopt_target"; source "$tmp_adopt_copy" ) >/dev/null 2>&1; then
    adopt_copy_ok=1
    while IFS= read -r required_path; do
      [[ -n "$required_path" ]] || continue
      if [[ ! -e "$tmp_adopt_target/abora/$required_path" ]]; then
        adopt_copy_ok=0
        printf '              missing after copy: abora/%s\n' "$required_path"
      fi
    done <<<"$_required_dests"
  else
    adopt_copy_ok=0
    printf '              copy logic itself failed to run\n'
  fi
  rm -f "$tmp_adopt_copy"
  rm -rf "$tmp_adopt_target"

  if [[ "$adopt_copy_ok" -eq 1 ]]; then
    pass "runtime: abora-adopt-nixos.sh copies every file installed-base.nix requires"
  else
    fail "runtime: abora-adopt-nixos.sh copies every file installed-base.nix requires"
  fi
fi

# Regression test: abora-update.sh's sync_abora_files() used to never copy
# check-full.sh, installer.sh, setup-launcher.sh, or setup.desktop into
# $abora_dir, even though it also copies installed-base.nix, which
# references all four as unconditional, non-pathExists-guarded path
# literals. `sudo abora update` on any system missing one of these (an
# install predating a feature, or a fresh checkout mirroring the update
# path) would drop in the new installed-base.nix but leave these paths
# missing, and the next nixos-rebuild would fail Nix evaluation outright --
# the same failure class the abora-adopt-nixos.sh copy-list gap above
# shipped. required_upstream_paths() (check-full.sh, setup-launcher.sh,
# setup.desktop) and check-release-files.sh's manifest (same three) had the
# same gap. Runs the real sync_abora_files() (not a copy of it) against
# this real repo checkout as its "upstream", with
# prepare_verified_upstream/drop_upstream_git_metadata stubbed out (both do
# real git/network work unrelated to the copy list itself), and checks
# every required destination path installed-base.nix's own source actually
# demands.
if command -v python3 >/dev/null 2>&1; then
  tmp_update_funcs="$(mktemp)"
  {
    sed -n '/^copy_upstream_file() {/,/^}$/p' scripts/abora-update.sh
    sed -n '/^copy_first_existing_upstream_file() {/,/^}$/p' scripts/abora-update.sh
    sed -n '/^install_mango_config_asset() {/,/^}$/p' scripts/abora-update.sh
    sed -n '/^rewrite_installed_mango_config_paths() {/,/^}$/p' scripts/abora-update.sh
    awk '/^sync_abora_files\(\) \{/{p=1} p{print} p && /drop_upstream_git_metadata/{print "}"; exit}' scripts/abora-update.sh
  } > "$tmp_update_funcs"
  tmp_update_target="$(mktemp -d)"
  if bash -n "$tmp_update_funcs" 2>/dev/null \
    && ( \
      prepare_verified_upstream() { return 0; }; \
      drop_upstream_git_metadata() { :; }; \
      config_dir="$tmp_update_target"; \
      upstream_dir="$repo_dir"; \
      mkdir -p "$config_dir/abora"; \
      source "$tmp_update_funcs"; \
      sync_abora_files "edge" \
    ) >/dev/null 2>&1; then
    update_copy_ok=1
    while IFS= read -r required_path; do
      [[ -n "$required_path" ]] || continue
      if [[ ! -e "$tmp_update_target/abora/$required_path" ]]; then
        update_copy_ok=0
        printf '              missing after copy: abora/%s\n' "$required_path"
      fi
    done <<<"$_required_dests"
  else
    update_copy_ok=0
    printf '              copy logic itself failed to run\n'
  fi
  rm -f "$tmp_update_funcs"
  rm -rf "$tmp_update_target"

  if [[ "$update_copy_ok" -eq 1 ]]; then
    pass "runtime: abora-update.sh copies every file installed-base.nix requires"
  else
    fail "runtime: abora-update.sh copies every file installed-base.nix requires"
  fi
fi

# Regression test: abora-adopt-nixos.sh's backup step used to crash on
# every run after the first against the same --config-dir. It backs up
# $config_dir into $config_dir/abora-backups/<timestamp>/ -- but from the
# second run onward, $config_dir already contains every prior backup, so
# `cp -a "$config_dir"/. "$backup_dir"/` tries to copy that whole tree
# (including the fresh, now-nested backup_dir itself) into itself. GNU cp
# detects this and refuses ("cp: cannot copy a directory ... into
# itself"), returning non-zero, which set -euo pipefail turns into the
# entire script aborting right there -- before any of the real adoption
# work (the file copies checked above) ever runs. Exercises the real
# backup logic for real, three runs in a row against the same directory,
# confirming it doesn't abort and doesn't grow backups inside backups.
tmp_backup_dir="$(mktemp -d)"
printf 'test config\n' > "$tmp_backup_dir/configuration.nix"
tmp_backup_snippet="$(mktemp)"
awk '/^timestamp="\$\(date \+%Y%m%d-%H%M%S\)"$/{p=1} p{print} p && /-exec cp -a/{exit}' \
  scripts/abora-adopt-nixos.sh > "$tmp_backup_snippet"
backup_all_ok=1
if [[ -s "$tmp_backup_snippet" ]] && bash -n "$tmp_backup_snippet" 2>/dev/null; then
  for run in 1 2 3; do
    if ! ( config_dir="$tmp_backup_dir"; set -euo pipefail; source "$tmp_backup_snippet" ) >/dev/null 2>&1; then
      backup_all_ok=0
    fi
    sleep 1.1
  done
  backup_count="$(find "$tmp_backup_dir/abora-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  [[ "$backup_count" -eq 3 ]] || backup_all_ok=0
  nested_count="$(find "$tmp_backup_dir/abora-backups" -mindepth 2 -maxdepth 2 -type d -name 'abora-backups' 2>/dev/null | wc -l)"
  [[ "$nested_count" -eq 0 ]] || backup_all_ok=0
else
  backup_all_ok=0
fi
rm -f "$tmp_backup_snippet"
rm -rf "$tmp_backup_dir"

if [[ "$backup_all_ok" -eq 1 ]]; then
  pass "runtime: abora-adopt-nixos.sh's backup step survives repeated runs against the same config-dir"
else
  fail "runtime: abora-adopt-nixos.sh's backup step survives repeated runs against the same config-dir"
fi

# Regression test for ensure_import_in_configuration(): both of its
# branches used to produce a real syntax/semantic break on the *standard*
# nixos-generate-config output shape (function header on its own line,
# "imports =" and its "[" on separate lines) -- inserting right after
# "imports =" landed the new path *before* the "[", which Nix parses as
# function application (`imports = ./abora-adopt.nix [ ... ];` calls the
# path as a function) rather than list concatenation; the "no imports at
# all" fallback replaced the *first* "{" in the file, which for the
# standard format is the function argument list's own brace, not the
# config body's, producing a hard parse error. Extracts the real function
# (it can't be sourced wholesale -- this script parses its own $@ at load
# time) and confirms the real `nix-instantiate` can both parse and
# evaluate the result for four real shapes: multi-line imports (the
# standard shape), single-line imports, a function-header body with no
# imports at all, and a bare attrset with no function header and no
# imports.
if command -v nix-instantiate >/dev/null 2>&1; then
  tmp_adopt_fn="$(mktemp)"
  awk '/^ensure_import_in_configuration\(\) \{/{p=1} p{print} p && /^}$/{exit}' \
    scripts/abora-adopt-nixos.sh > "$tmp_adopt_fn"
  tmp_adopt_dir="$(mktemp -d)"

  cat > "$tmp_adopt_dir/multiline.nix" <<'EOF'
{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
}
EOF
  cat > "$tmp_adopt_dir/singleline.nix" <<'EOF'
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
}
EOF
  cat > "$tmp_adopt_dir/noimports-header.nix" <<'EOF'
{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
}
EOF
  cat > "$tmp_adopt_dir/noimports-bare.nix" <<'EOF'
{
  boot.loader.systemd-boot.enable = true;
}
EOF
  printf '{ imports = [ ]; }\n' > "$tmp_adopt_dir/abora-adopt.nix"

  adopt_all_ok=1
  for shape in multiline singleline noimports-header noimports-bare; do
    cp "$tmp_adopt_dir/$shape.nix" "$tmp_adopt_dir/configuration.nix"
    if ! ( configuration_nix="$tmp_adopt_dir/configuration.nix"; source "$tmp_adopt_fn"; ensure_import_in_configuration ) \
      || ! nix-instantiate --parse "$tmp_adopt_dir/configuration.nix" >/dev/null 2>&1 \
      || ! nix-instantiate --eval -E \
           "let raw = import $tmp_adopt_dir/configuration.nix; cfg = if builtins.isFunction raw then raw { config = {}; pkgs = {}; lib = (import <nixpkgs> {}).lib; } else raw; in builtins.length cfg.imports" \
           >/dev/null 2>&1; then
      adopt_all_ok=0
      printf '              %s shape failed to parse/eval after ensure_import_in_configuration\n' "$shape"
    fi
    rm -f "$tmp_adopt_dir/configuration.nix"
  done
  rm -f "$tmp_adopt_fn"
  rm -rf "$tmp_adopt_dir"

  if [[ "$adopt_all_ok" -eq 1 ]]; then
    pass "runtime: ensure_import_in_configuration produces valid Nix for standard configuration.nix shapes"
  else
    fail "runtime: ensure_import_in_configuration produces valid Nix for standard configuration.nix shapes"
  fi
fi

# The interactive wizard (run with zero args) is a real, separate code path
# from the flag-based one above -- exercise it for real rather than just
# grepping source, same as the rest of this file's "runtime:" checks.
tmp_adopt_wizard="$(mktemp -d)"
printf '{ ... }:\n{\n}\n' > "$tmp_adopt_wizard/configuration.nix"
adopt_wizard_out="$(
  printf 'gnome\ny\nn\n' \
    | ABORA_ASSUME_NIXOS=1 ABORA_SYSTEM_CONFIG="$tmp_adopt_wizard" \
      scripts/abora-adopt-nixos.sh 2>&1
)"
rm -rf "$tmp_adopt_wizard"
if printf '%s' "$adopt_wizard_out" | grep -q 'Abora NixOS Adoption Wizard' \
  && printf '%s' "$adopt_wizard_out" | grep -q 'Desktop profile : gnome' \
  && printf '%s' "$adopt_wizard_out" | grep -q 'Gaming layer    : enabled' \
  && printf '%s' "$adopt_wizard_out" | grep -q 'No changes made' \
  && grep -q 'run_interactive_wizard' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.enable = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.steam = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.controllerSupport = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.mangohud = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.gamemode = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.launchers = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'exec sudo "\$0" --apply' scripts/abora-adopt-nixos.sh \
  && grep -q 'exec "\$clone_dir/abora" adopt-nixos' scripts/abora-adopt-bootstrap.sh; then
  pass "runtime: adopt-nixos interactive wizard asks desktop/gaming and confirms before applying"
else
  fail "runtime: adopt-nixos interactive wizard asks desktop/gaming and confirms before applying"
fi

tmp_bad_upstream="$(mktemp -d)"
mkdir -p "$tmp_bad_upstream"
if ABORA_SYSTEM_CONFIG="$tmp_update_flake" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-validate-upstream "$tmp_bad_upstream" test-ref >/dev/null 2>&1; then
  fail "runtime: updater rejects incomplete upstream checkout"
else
  pass "runtime: updater rejects incomplete upstream checkout"
fi
rm -rf "$tmp_bad_upstream"

if grep -q 'ref_fallback_candidates()' scripts/abora-update.sh \
  && grep -q 'edge)' scripts/abora-update.sh \
  && grep -q 'main)' scripts/abora-update.sh \
  && grep -q "Selected ref '\${selected_ref}' was unavailable; using branch fallback '\${cloned_ref}'" scripts/abora-update.sh \
  && grep -q 'sudo ABORA_REPO_REF=<branch> abora update' scripts/abora-update.sh; then
  pass "runtime: updater can fall back between edge and main branches"
else
  fail "runtime: updater can fall back between edge and main branches"
fi

if git rev-parse -q --verify refs/tags/v3.14 >/dev/null; then
  tmp_release_upstream="$(mktemp -d)"
  git archive v3.14 | tar -x -C "$tmp_release_upstream"
  if ABORA_SYSTEM_CONFIG="$tmp_update_flake" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-validate-upstream "$tmp_release_upstream" v3.14 >/dev/null 2>&1; then
    pass "runtime: v3.14 manifest matches tagged layout"
  else
    fail "runtime: v3.14 manifest matches tagged layout"
  fi
  rm -rf "$tmp_release_upstream"
else
  pass "runtime: v3.14 tag unavailable (manifest check skipped)"
fi

if scripts/check-release-files.sh >/dev/null \
  && grep -q '^assets/anix-languages$' scripts/check-release-files.sh \
  && grep -q '^nix/pkgs/moducpp-anix.nix$' scripts/check-release-files.sh \
  && grep -q '^tools/moducpp-anix$' scripts/check-release-files.sh \
  && grep -q '^scripts/abora-build.sh$' scripts/check-release-files.sh \
  && grep -q '^scripts/abora-adopt-nixos.sh$' scripts/check-release-files.sh \
  && grep -q '^scripts/abora-gaming.sh$' scripts/check-release-files.sh \
  && grep -q '^scripts/abora-custom-packages.sh$' scripts/check-release-files.sh \
  && grep -q '^assets/Abora-LOGO.png$' scripts/check-release-files.sh \
  && grep -q '^assets/Abora-Text.png$' scripts/check-release-files.sh \
  && grep -q '^docs/wiki/Abora-Gaming.md$' scripts/check-release-files.sh \
  && grep -q '^docs/wiki/ANIX-V2-Languages.md$' scripts/check-release-files.sh \
  && grep -q '^docs/wiki/Updating-Abora.md$' scripts/check-release-files.sh \
  && grep -q '^vendor/modularity$' scripts/check-release-files.sh \
  && [[ -f assets/anix-languages/mako.json ]] \
  && [[ -f assets/anix-languages/moducpp.json ]] \
  && [[ -f nix/pkgs/moducpp-anix.nix ]] \
  && [[ -f tools/moducpp-anix ]] \
  && [[ -f vendor/modularity/README.md ]] \
  && [[ -f assets/Abora-LOGO.png ]] \
  && [[ -f assets/Abora-Text.png ]] \
  && [[ -f scripts/abora-gaming.sh ]] \
  && [[ -f docs/wiki/Abora-Gaming.md ]]; then
  pass "runtime: release manifest includes ANIX adapters, Modularity skeleton, and gaming layer"
else
  fail "runtime: release manifest includes ANIX adapters, Modularity skeleton, and gaming layer"
fi

if grep -q 'release_has_gaming_layer' scripts/abora-update.sh \
  && grep -q '! version_lt "$(tag_base_version "$selected_ref")" "4.0"' scripts/abora-update.sh \
  && grep -A5 'release_has_welcome_config_gui' scripts/abora-update.sh | grep -q '! version_lt "$(tag_base_version "$selected_ref")" "4.0"' \
  && grep -q 'repo_git_url="${ABORA_REPO_GIT_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"' scripts/abora-update.sh \
  && grep -q 'https://github.com/AboraProject/Abora-OS.git' scripts/abora-update.sh \
  && ! grep -RIE --exclude='check-scripts.sh' -q 'github(:|\.com/)AnimatedGTVR/abora-os|AnimatedGTVR/abora-os|abora-os[.]git' README.md RELEASE_NOTES.md DISCORD_CHANGELOG.md docs scripts nix packaging flake.nix Makefile \
  && grep -q 'scripts/abora-build.sh' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-build.sh" "$abora_dir/build.sh"' scripts/abora-update.sh \
  && grep -q 'scripts/abora-adopt-nixos.sh' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-adopt-nixos.sh" "$abora_dir/adopt-nixos.sh"' scripts/abora-update.sh \
  && grep -q 'scripts/abora-gaming.sh' scripts/abora-update.sh \
  && grep -q 'scripts/abora-custom-packages.sh' scripts/abora-update.sh \
  && grep -q 'scripts/abora-dotfiles-import.sh' scripts/abora-update.sh \
  && grep -q 'assets/Abora-LOGO.png' scripts/abora-update.sh \
	  && grep -q 'assets/Abora-Text.png' scripts/abora-update.sh \
	  && grep -q 'cp /etc/abora/Abora-LOGO.png "${root}/etc/nixos/abora/Abora-LOGO.png"' scripts/abora-installer.sh \
	  && grep -q 'cp /etc/abora/Abora-Text.png "${root}/etc/nixos/abora/Abora-Text.png"' scripts/abora-installer.sh \
	  && grep -q '"abora/Abora-LOGO.png".source = ../../assets/Abora-LOGO.png' nix/profiles/live.nix \
	  && grep -q '"abora/Abora-Text.png".source = ../../assets/Abora-Text.png' nix/profiles/live.nix \
	  && grep -q 'vendor/modularity' scripts/abora-update.sh \
  && grep -q 'cp -R "$upstream_dir/vendor/modularity" "$abora_dir/vendor/modularity"' scripts/abora-update.sh \
  && grep -q 'docs/wiki/ANIX-V2-Languages.md' scripts/abora-update.sh \
  && grep -q 'docs/wiki/Updating-Abora.md' scripts/abora-update.sh \
  && grep -q 'Check your internet connection, then run: sudo abora update' scripts/abora-update.sh \
  && grep -q 'sudo ABORA_REPO_REF=edge abora update' docs/wiki/Updating-Abora.md \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-gaming.sh" "$abora_dir/gaming.sh"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-custom-packages.sh" "$abora_dir/custom-packages.sh"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-dotfiles-import.sh" "$abora_dir/dotfiles-import.sh"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/assets/Abora-LOGO.png" "$abora_dir/Abora-LOGO.png"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/assets/Abora-Text.png" "$abora_dir/Abora-Text.png"' scripts/abora-update.sh \
  && grep -q 'cp -R "$upstream_dir/docs" "$abora_dir/docs"' scripts/abora-update.sh; then
  pass "runtime: updater syncs Abora Gaming command"
else
  fail "runtime: updater syncs Abora Gaming command"
fi

tmp_update_store_fail="$(mktemp -d)"
tmp_update_store_log="$tmp_update_store_fail/rebuild.log"
tmp_update_store_funcs="$tmp_update_store_fail/funcs.sh"
cat > "$tmp_update_store_log" <<'EOF'
error: Cannot build '/nix/store/1xp6ll0yg3f325f3vnfnqwbq2z70kr10-etc.drv'.
       Reason: 1 dependency failed.
error: cannot create '/nix/store/irbl4jlxqfv7ylq2cmlk2424xf885aa7-unit-path'
EOF
sed -n '/^explain_update_failure() {/,/^}$/p' scripts/abora-update.sh > "$tmp_update_store_funcs"
set +e
update_store_diag_out="$(
  bash -c '
    set -euo pipefail
    source "$1"
    ABORA_NC=""; ABORA_CYAN=""; ABORA_DIM=""; ABORA_WHITE=""; ABORA_BLUE=""
    abora_warn() { printf "WARN %s\n" "$1"; }
    abora_dim_line() { printf "%s\n" "$1"; }
    explain_update_failure "$2"
  ' bash "$tmp_update_store_funcs" "$tmp_update_store_log" 2>&1
)"
update_store_diag_status=$?
set -e
rm -rf "$tmp_update_store_fail"
if [[ "$update_store_diag_status" -eq 0 ]] \
  && grep -q 'Nix could not create or finish a store path' <<<"$update_store_diag_out" \
  && grep -q 'df -h /nix/store / /tmp' <<<"$update_store_diag_out" \
  && grep -q 'sudo nix-collect-garbage -d' <<<"$update_store_diag_out" \
  && grep -q 'show_update_space_status /nix/store' scripts/abora-update.sh; then
  pass "runtime: updater explains Nix store create failures"
else
  fail "runtime: updater explains Nix store create failures"
fi

tmp_update_disk_full_fail="$(mktemp -d)"
tmp_update_disk_full_log="$tmp_update_disk_full_fail/sync.log"
tmp_update_disk_full_funcs="$tmp_update_disk_full_fail/funcs.sh"
cat > "$tmp_update_disk_full_log" <<'EOF'
error: copy-fd: write returned: No space left on device
fatal: cannot copy '/nix/store/bcnisk3ydfgv26v2gw321ky24g00yww2-git-2.49.0'
error: committing transaction: database or disk is full, database or disk is full (in '/nix/var/nix/db/db.sqlite')
EOF
sed -n '/^explain_update_failure() {/,/^}$/p' scripts/abora-update.sh > "$tmp_update_disk_full_funcs"
set +e
update_disk_full_diag_out="$(
  bash -c '
    set -euo pipefail
    source "$1"
    ABORA_NC=""; ABORA_CYAN=""; ABORA_DIM=""; ABORA_WHITE=""; ABORA_BLUE=""
    abora_warn() { printf "WARN %s\n" "$1"; }
    abora_dim_line() { printf "%s\n" "$1"; }
    explain_update_failure "$2"
  ' bash "$tmp_update_disk_full_funcs" "$tmp_update_disk_full_log" 2>&1
)"
update_disk_full_diag_status=$?
set -e
rm -rf "$tmp_update_disk_full_fail"
if [[ "$update_disk_full_diag_status" -eq 0 ]] \
  && grep -q 'Disk space or the Nix database appears full' <<<"$update_disk_full_diag_out" \
  && grep -q 'df -h /nix/store / /tmp' <<<"$update_disk_full_diag_out" \
  && grep -q 'Free non-Nix space first' <<<"$update_disk_full_diag_out" \
  && grep -q 'sudo nix-collect-garbage -d' <<<"$update_disk_full_diag_out" \
  && grep -q 'explain_update_failure "/tmp/abora-update-sync.log"' scripts/abora-update.sh \
  && grep -q 'explain_update_failure "/tmp/abora-update-flake.log"' scripts/abora-update.sh; then
  pass "runtime: updater explains disk-full sync and flake failures"
else
  fail "runtime: updater explains disk-full sync and flake failures"
fi

update_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-update.sh --help 2>&1)"
channel_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-update.sh channel --help 2>&1)"
channel_bad_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-update.sh channel nope 2>&1 || true)"
if printf '%s' "$update_help_out" | grep -q 'abora channel set <stable|demo|unstable>' \
  && printf '%s' "$update_help_out" | grep -q 'abora update --check' \
  && printf '%s' "$channel_help_out" | grep -q 'sudo abora channel set <stable|demo|unstable>' \
  && ! printf '%s' "$channel_help_out" | grep -q 'Unknown channel subcommand' \
  && printf '%s' "$channel_bad_out" | grep -q 'Unknown channel subcommand: nope' \
  && ! printf '%s' "$channel_bad_out" | grep -q 'Update failed before completion' \
  && ! printf '%s' "$update_help_out" | grep -q 'This command does not take extra arguments' \
  && ! printf '%s' "$update_help_out" | grep -q 'Update failed before completion'; then
  pass "runtime: updater help is clean and Abora-first"
else
  fail "runtime: updater help is clean and Abora-first"
fi

abora_help_out="$(./abora --help 2>&1)"
abora_learn_out="$(./abora learn 2>&1)"
anix_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/anix.sh --help 2>&1)"
anix_learn_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/anix.sh learn 2>&1)"
if printf '%s' "$abora_help_out" | grep -q 'abora learn' \
  && printf '%s' "$abora_learn_out" | grep -q 'Abora quick start' \
  && printf '%s' "$abora_learn_out" | grep -q 'anix learn' \
  && printf '%s' "$anix_help_out" | grep -q 'anix learn' \
  && printf '%s' "$anix_learn_out" | grep -q 'ANIX quick start' \
  && printf '%s' "$anix_learn_out" | grep -q 'anix package add fastfetch' \
  && grep -q 'abora learn' docs/wiki/Abora-Tools.md \
  && grep -q 'anix learn' docs/wiki/ANIX-V1.md; then
  pass "runtime: Abora and ANIX expose beginner command cheat sheets"
else
  fail "runtime: Abora and ANIX expose beginner command cheat sheets"
fi

welcome_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-welcome.sh --help 2>&1)"
recovery_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-recovery.sh --help 2>&1)"
welcome_bad_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-welcome.sh nope 2>&1 || true)"
recovery_bad_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-recovery.sh nope 2>&1 || true)"
if printf '%s' "$welcome_help_out" | grep -q 'abora welcome startup off' \
  && printf '%s' "$welcome_help_out" | grep -q 'Show desktop, wallpaper, gaming, update, Flathub, and ANIX status' \
  && printf '%s' "$recovery_help_out" | grep -q 'abora recovery report' \
  && printf '%s' "$recovery_help_out" | grep -q 'abora recovery network' \
  && printf '%s' "$recovery_help_out" | grep -q 'Create a redacted support archive' \
  && printf '%s' "$welcome_bad_out" | grep -q 'Unknown welcome command: nope' \
  && printf '%s' "$welcome_bad_out" | grep -q 'abora welcome status' \
  && printf '%s' "$recovery_bad_out" | grep -q 'Unknown recovery command: nope' \
  && printf '%s' "$recovery_bad_out" | grep -q 'abora recovery rollback' \
  && grep -q '1) abora doctor' scripts/abora-welcome.sh \
  && grep -q '2) abora apps' scripts/abora-welcome.sh \
  && grep -q '6) abora recovery' scripts/abora-welcome.sh \
  && grep -q 'run_cmd abora support-report' scripts/abora-recovery.sh \
  && grep -q 'run_cmd abora doctor' scripts/abora-recovery.sh \
  && grep -q 'run_diag()' scripts/abora-recovery.sh \
  && grep -q 'Command exited with status' scripts/abora-recovery.sh \
  && grep -q 'network_diagnostics()' scripts/abora-recovery.sh \
  && grep -q 'nmcli networking connectivity check' scripts/abora-recovery.sh \
  && grep -q 'curl -fsI --connect-timeout 5 --max-time 8 https://cache.nixos.org' scripts/abora-recovery.sh \
  && grep -q 'abora repair --mango' scripts/abora-repair-flake-purity.sh \
  && grep -q 'sudo abora config apply' scripts/abora-repair-flake-purity.sh; then
  pass "runtime: welcome and recovery help are actionable"
else
  fail "runtime: welcome and recovery help are actionable"
fi

config_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-config.sh --help 2>&1)"
apps_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-apps.sh --help 2>&1)"
if printf '%s' "$config_help_out" | grep -q 'abora config set timezone' \
  && printf '%s' "$config_help_out" | grep -q 'gaming.big-picture' \
  && printf '%s' "$apps_help_out" | grep -q 'abora apps catalog' \
  && printf '%s' "$apps_help_out" | grep -q 'abora apps bundle <name>' \
  && ! printf '%s' "$apps_help_out" | grep -q 'abora-apps catalog' \
  && grep -q "run 'abora apps add <id>'" scripts/abora-apps.sh \
  && grep -q 'sudo abora apps bundle gaming' scripts/abora.sh \
  && ! grep -q 'sudo abora apps add gaming' scripts/abora.sh \
  && grep -q "Run 'abora apps catalog'" scripts/abora-apps.sh \
  && ! grep -q "abora-apps add" scripts/abora-apps.sh; then
  pass "runtime: config and apps help use public commands"
else
  fail "runtime: config and apps help use public commands"
fi

gaming_bundle_out="$(
  bash -c 'source scripts/abora-app-catalog.sh; abora_catalog_bundle_ids gaming' 2>/dev/null
)"
if grep -qx 'steam' <<<"$gaming_bundle_out" \
  && grep -qx 'lutris' <<<"$gaming_bundle_out" \
  && grep -qx 'heroic' <<<"$gaming_bundle_out" \
  && grep -qx 'bottles' <<<"$gaming_bundle_out" \
  && grep -qx 'wine' <<<"$gaming_bundle_out" \
  && grep -qx 'winetricks' <<<"$gaming_bundle_out" \
  && grep -qx 'mangohud' <<<"$gaming_bundle_out" \
  && grep -qx 'gamemode' <<<"$gaming_bundle_out"; then
  pass "runtime: gaming app bundle contains the expected platform/tools"
else
  fail "runtime: gaming app bundle contains the expected platform/tools"
  printf '              bundle output: %s\n' "$gaming_bundle_out"
fi

if grep -q '"id": "mako"' assets/anix-languages/mako.json \
  && grep -q '"extensions": \[".mko"\]' assets/anix-languages/mako.json \
  && grep -q '"command": \["mko", "run"\]' assets/anix-languages/mako.json \
  && grep -q '"id": "moducpp"' assets/anix-languages/moducpp.json \
  && grep -q '".moducpp"' assets/anix-languages/moducpp.json \
  && grep -q '".mcpp"' assets/anix-languages/moducpp.json \
  && grep -q '"command": \["moducpp-anix"\]' assets/anix-languages/moducpp.json \
  && grep -q 'using ANIX;' examples/anix-v2/simple.mko \
  && grep -q 'using ANIX;' examples/anix-v2/workstation.mko \
  && grep -q 'add ANIX;' examples/anix-v2/simple.moducpp \
  && grep -q 'add ANIX;' examples/anix-v2/workstation.moducpp; then
  pass "runtime: MAKO and ModuCPP manifests match shipped examples"
else
  fail "runtime: MAKO and ModuCPP manifests match shipped examples"
fi

if grep -q 'sudo abora update' docs/wiki/FAQ.md \
  && grep -q 'make iso-all' docs/wiki/Building-Abora.md \
  && grep -q 'abora build --from-source' docs/wiki/Building-Abora.md \
  && grep -q 'nix build .#nixosConfigurations.abora.config.system.build.toplevel' docs/wiki/Building-Abora.md \
  && grep -q 'ANIX standalone tarball' docs/wiki/Building-Abora.md \
  && grep -q 'abora-cosmic-' RELEASE_NOTES.md \
  && grep -q 'ANIX standalone package' RELEASE_NOTES.md \
  && grep -q 'Abora Gaming' RELEASE_NOTES.md \
  && grep -q 'abora hardware-test' RELEASE_NOTES.md \
  && grep -q 'abora gaming status' README.md \
  && grep -q 'abora gaming install steam' README.md \
  && grep -q 'abora gaming doctor' scripts/abora.sh \
  && grep -q 'abora gaming repair-cache' scripts/abora.sh \
  && grep -q 'abora gaming doctor' nix/modules/installed-base.nix \
  && grep -q 'abora gaming repair-cache' nix/modules/installed-base.nix \
  && grep -q 'abora gaming steam on' RELEASE_NOTES.md \
  && grep -q 'abora gaming install wine winetricks' RELEASE_NOTES.md \
  && grep -q 'Wine and Winetricks' RELEASE_NOTES.md \
  && grep -q 'Steam, Wine, launchers' docs/wiki/Abora-Tools.md \
  && grep -q 'abora gaming install steam' docs/wiki/Abora-Gaming.md \
  && grep -q 'abora gaming controllers on' docs/wiki/Abora-Gaming.md \
  && grep -q 'abora gaming mangohud on' docs/wiki/Abora-Gaming.md \
  && grep -q 'abora gaming gamemode on' docs/wiki/Abora-Gaming.md \
  && grep -q 'abora gaming launchers on' docs/wiki/Abora-Gaming.md \
  && grep -q 'abora.gaming.controllerSupport = true' docs/release-checklist.md \
  && grep -q 'anix enable gaming.launchers' RELEASE_NOTES.md \
  && grep -q 'current alpha release line' docs/wiki/FAQ.md \
  && grep -q 'current alpha release line' docs/wiki/Home.md \
  && grep -q 'ANIX v2 Languages](ANIX-V2-Languages.md)' docs/wiki/_Sidebar.md \
  && grep -q 'sudo abora rollback' docs/wiki/Updating-Abora.md \
  && grep -q 'Abora OS v4 Everest' DISCORD_CHANGELOG.md \
  && grep -q 'abora support-report' DISCORD_CHANGELOG.md \
  && grep -q 'abora hardware-test --with-report' DISCORD_CHANGELOG.md \
  && ! grep -q 'abora-support-report' DISCORD_CHANGELOG.md \
  && grep -q 'abora support-report' docs/install-checklist.md \
  && grep -q 'sudo abora update' docs/wiki/Abora-Tools.md \
  && grep -q 'sudo abora update' nix/modules/installed-base.nix; then
  pass "runtime: release docs describe multi-edition, ANIX, and gaming flow"
else
  fail "runtime: release docs describe multi-edition, ANIX, and gaming flow"
fi

if grep -q 'open_live_terminal()' scripts/abora-installer.sh \
  && grep -q 'debug_tools_menu()' scripts/abora-installer.sh \
  && grep -q 'source_build_menu()' scripts/abora-installer.sh \
  && grep -q 'Open terminal|Drop to the live environment shell' scripts/abora-installer.sh \
  && grep -q 'Debug installer|View logs, run hardware tests, or collect a report' scripts/abora-installer.sh \
  && grep -q 'Build from source|Advanced commands for compiling Abora yourself' scripts/abora-installer.sh \
  && grep -q 'abora hardware-test --with-report' scripts/abora-installer.sh \
  && grep -q 'abora build --from-source' scripts/abora-installer.sh \
  && grep -q 'nixosConfigurations.abora.config.system.build.toplevel' scripts/abora-installer.sh \
  && grep -q 'make iso-all' scripts/abora-installer.sh \
  && grep -q 'check_install_environment live' scripts/abora-installer.sh \
  && grep -q 'check_install_environment final' scripts/abora-installer.sh \
  && grep -q 'Selected install values will be checked after disk and user setup' scripts/abora-installer.sh \
  && grep -q 'Disk tools' scripts/abora-installer.sh \
  && grep -q 'Use lsblk, dmesg, or nvme/sata tools' scripts/abora-installer.sh \
  && grep -q 'network_tools_menu()' scripts/abora-installer.sh \
  && grep -q 'quick_wifi_connect()' scripts/abora-installer.sh \
  && grep -q 'open_nmtui_or_explain()' scripts/abora-installer.sh \
  && grep -q 'log_network_snapshot()' scripts/abora-installer.sh \
  && grep -q 'network snapshot start' scripts/abora-installer.sh \
  && grep -q 'visible Wi-Fi networks' scripts/abora-installer.sh \
  && grep -q 'cache.nixos.org reachable' scripts/abora-installer.sh \
  && grep -q 'Network tools|Status, nmtui, quick Wi-Fi, and rescan' scripts/abora-installer.sh \
  && grep -q 'failed_install_menu()' scripts/abora-installer.sh \
  && grep -q 'Try installer again|Return to the first screen' scripts/abora-installer.sh \
  && grep -q 'Network tools|Fix Wi-Fi, DNS, or cache reachability' scripts/abora-installer.sh \
  && grep -q 'Debug tools|View logs, hardware test, support report' scripts/abora-installer.sh \
  && grep -q 'Open terminal|Drop to the live shell' scripts/abora-installer.sh \
  && grep -q 'Interactive picker failed; using numbered fallback menu' scripts/abora-installer.sh \
  && grep -q 'Interactive picker returned an unknown choice; using numbered fallback menu' scripts/abora-installer.sh \
  && grep -q 'tui_size_warning()' scripts/abora-installer.sh \
  && grep -q 'Open terminal' docs/install-checklist.md \
  && grep -q 'Debug installer' docs/wiki/Installation.md \
  && grep -q 'Build from source' docs/install-checklist.md; then
  pass "runtime: installer first screen exposes terminal, debug, and source-build tools"
else
  fail "runtime: installer first screen exposes terminal, debug, and source-build tools"
fi

if grep -q '/etc/abora/anix-languages' scripts/abora-installer.sh \
  && grep -q 'etc/nixos/abora/anix-languages' scripts/abora-installer.sh \
  && grep -q '/etc/abora/pkgs/moducpp-anix.nix' scripts/abora-installer.sh \
  && grep -q 'etc/nixos/abora/pkgs/moducpp-anix.nix' scripts/abora-installer.sh \
  && grep -q '"abora/pkgs/moducpp-anix.nix"' nix/profiles/live.nix \
  && grep -q '"abora/anix-languages".source = anixLanguagesDir' nix/modules/installed-base.nix \
  && grep -q 'moducpp-anix = final.callPackage ./pkgs/moducpp-anix.nix' nix/modules/installed-base.nix; then
  pass "runtime: installer copies ANIX language adapters"
else
  fail "runtime: installer copies ANIX language adapters"
fi

# Regression test: a real fresh install (reproduced by actually running the
# installer through nixos-install in QEMU, not just static review) failed
# with "path '/mnt/etc/nixos/abora/pkgs/abora-update-resolver-deps.json'
# does not exist" -- nix/pkgs/abora-update-resolver.nix's/abora-plan-tool.nix's
# `nugetDeps = ./abora-*-deps.json;` is a path relative to wherever the .nix
# file itself ends up, so the deps.json has to be shipped and copied
# alongside its .nix file at every hop (live ISO -> installed target ->
# later abora update syncs), not just the .nix file itself.
if grep -q '"abora/pkgs/abora-update-resolver-deps.json".source = ../pkgs/abora-update-resolver-deps.json' nix/profiles/live.nix \
  && grep -q '"abora/pkgs/abora-plan-tool-deps.json".source = ../pkgs/abora-plan-tool-deps.json' nix/profiles/live.nix \
  && grep -q 'cp_required /etc/abora/pkgs/abora-update-resolver-deps.json' scripts/abora-installer.sh \
  && grep -q 'cp_required /etc/abora/pkgs/abora-plan-tool-deps.json' scripts/abora-installer.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/nix/pkgs/abora-update-resolver-deps.json"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/nix/pkgs/abora-plan-tool-deps.json"' scripts/abora-update.sh; then
  pass "runtime: installer and updater ship nugetDeps json alongside the C# tool .nix files"
else
  fail "runtime: installer and updater ship nugetDeps json alongside the C# tool .nix files"
fi

if grep -q 'effectsAudioFile' nix/modules/installed-base.nix \
  && grep -q 'builtins.pathExists ./effects/v3StartingAbora.mp3' nix/modules/installed-base.nix \
  && grep -q 'builtins.pathExists ./effects/LaunchingAbora.mp3' nix/modules/installed-base.nix \
  && grep -q '/etc/abora/effects/LaunchingAbora.mp3' scripts/abora-installer.sh \
  && grep -q 'assets/Effects/LaunchingAbora.mp3' scripts/abora-update.sh; then
  pass "runtime: installed systems tolerate either Abora startup sound filename"
else
  fail "runtime: installed systems tolerate either Abora startup sound filename"
fi

if grep -q 'dotfilesImportScript[[:space:]]*= ./dotfiles-import.sh;' nix/modules/installed-base.nix \
  && grep -q 'aboraDotfilesImport = pkgs.writeShellScriptBin "abora-dotfiles-import"' nix/modules/installed-base.nix \
  && grep -q 'aboraDotfilesImport' nix/modules/installed-base.nix \
  && grep -q 'buildScript[[:space:]]*= ./build.sh;' nix/modules/installed-base.nix \
  && grep -q 'adoptNixosScript[[:space:]]*= ./adopt-nixos.sh;' nix/modules/installed-base.nix \
  && grep -q '"abora/dotfiles-import.sh"' nix/modules/installed-base.nix \
  && grep -q '"abora/build.sh"' nix/modules/installed-base.nix \
  && grep -q '"abora/adopt-nixos.sh"' nix/modules/installed-base.nix \
  && grep -q '/etc/abora/build.sh' scripts/abora-installer.sh \
  && grep -q '/etc/abora/adopt-nixos.sh' scripts/abora-installer.sh \
  && grep -q '/etc/abora/check-full.sh' scripts/abora-installer.sh \
  && grep -q '/etc/abora/dotfiles-import.sh' scripts/abora-installer.sh \
  && grep -q '/etc/abora/abora-options.nix' scripts/abora-installer.sh \
  && grep -q '/etc/abora/desktops' scripts/abora-installer.sh \
  && grep -q '/etc/abora/wallpapers' scripts/abora-installer.sh \
  && grep -q '/etc/abora/themes' scripts/abora-installer.sh \
  && grep -q '/etc/abora/vendor/modularity' scripts/abora-installer.sh \
  && grep -q 'etc/nixos/abora/vendor/modularity' scripts/abora-installer.sh \
  && grep -q 'cp -a /etc/abora/wallpapers/.' scripts/abora-installer.sh \
  && grep -q 'cp -a /etc/abora/themes/.' scripts/abora-installer.sh \
  && grep -q '../../assets/wallpapers/collection' nix/modules/abora-options.nix \
  && grep -q '../../assets/wallpapers/collection' nix/modules/installed-base.nix \
  && grep -q '../../assets/wallpaper-themes' nix/modules/installed-base.nix \
  && grep -q 'build.sh adopt-nixos.sh' scripts/abora-installer.sh \
  && grep -q 'dotfiles-import.sh' scripts/abora-installer.sh; then
  pass "runtime: installed systems expose dotfiles import and source build helper"
else
  fail "runtime: installed systems expose dotfiles import and source build helper"
fi

if grep -q '/etc/abora/docs/wiki/ANIX-V2-Languages.md' scripts/abora-installer.sh \
  && grep -q '/etc/abora/docs/wiki/Abora-Gaming.md' scripts/abora-installer.sh \
  && grep -q '/etc/abora/docs/wiki/Updating-Abora.md' scripts/abora-installer.sh \
  && grep -q 'for doc in ANIX-V1 ANIX-V2-Languages TinyPM Abora-Tools Abora-Gaming Recovery Updating-Abora' scripts/abora-installer.sh; then
  pass "runtime: installer ships current local docs"
else
  fail "runtime: installer ships current local docs"
fi

if grep -q 'dotfiles-import.log' scripts/abora-support-report.sh \
  && grep -q 'Dotfiles import log' scripts/abora-check-full.sh \
  && grep -q '~/.local/state/abora/dotfiles-import.log' docs/wiki/Abora-Tools.md; then
  pass "runtime: diagnostics include dotfiles import log"
else
  fail "runtime: diagnostics include dotfiles import log"
fi

tmp_support_home="$(mktemp -d)"
tmp_support_out="$(mktemp -d)"
mkdir -p "$tmp_support_home/state/abora"
{
  printf 'token = "ghp_super-secret"\n'
  printf 'hashedPassword = "$y$j9T$secret-hash"\n'
  printf 'ordinary line\n'
} > "$tmp_support_home/state/abora/dotfiles-import.log"
support_archive="$(
  HOME="$tmp_support_home/home" \
  XDG_STATE_HOME="$tmp_support_home/state" \
  ABORA_RELEASE_NAME='token = "report-secret"' \
  ABORA_SUPPORT_OUTPUT_DIR="$tmp_support_out" \
  bash scripts/abora-support-report.sh 2>/dev/null
)"
support_dotfiles_log="$tmp_support_out/extracted-dotfiles-import.log"
support_report_txt="$tmp_support_out/extracted-report.txt"
if [[ -f "$support_archive" ]] \
  && tar -xOf "$support_archive" "$(basename "${support_archive%.tar.gz}")/dotfiles-import.log" > "$support_dotfiles_log" \
  && tar -xOf "$support_archive" "$(basename "${support_archive%.tar.gz}")/report.txt" > "$support_report_txt" \
  && grep -q '\[redacted\]' "$support_dotfiles_log" \
  && grep -q '\[redacted\]' "$support_report_txt" \
  && grep -q 'ordinary line' "$support_dotfiles_log" \
  && ! grep -q 'super-secret\|secret-hash' "$support_dotfiles_log" \
  && ! grep -q 'report-secret' "$support_report_txt"; then
  pass "runtime: support report redacts copied logs"
else
  fail "runtime: support report redacts copied logs"
fi
rm -rf "$tmp_support_home" "$tmp_support_out"

# abora-support-report.sh vendors its own copy of abora-check-full.sh's
# redact_stream() (no shared source) — nothing keeps them mirrored, so a fix
# to one (e.g. the missing trailing "@" that let the credential-URL pattern
# devour plain timestamps like "16:41:11") can silently drift from the other.
redact_stream_check_full="$(sed -n '/^redact_stream() {/,/^}/p' scripts/abora-check-full.sh)"
redact_stream_support_report="$(sed -n '/^redact_stream() {/,/^}/p' scripts/abora-support-report.sh)"
if [[ -n "$redact_stream_check_full" ]] \
  && [[ "$redact_stream_check_full" == "$redact_stream_support_report" ]]; then
  pass "runtime: redact_stream is identical in abora-check-full.sh and abora-support-report.sh"
else
  fail "runtime: redact_stream is identical in abora-check-full.sh and abora-support-report.sh"
fi

# The credential-URL redaction pattern must require a trailing "@" so it only
# matches real embedded-credential URLs (user:pass@host), not any bare
# "word:word" text — otherwise plain timestamps and host:port pairs get
# mangled into "[redacted-user]:[redacted]" throughout the whole report.
# eval the exact function body extracted above (renamed to avoid clobbering
# anything) rather than re-deriving the regex, so the test exercises the
# real source, not a hand-copied approximation of it.
eval "$(printf '%s' "$redact_stream_check_full" | sed '1s/^redact_stream/_redact_stream_under_test/')"
redact_probe_out="$(printf 'Generated: 2026-08-16T16:43:28-04:00\nport: talking to host:8080 now\nurl: https://user:pass@example.com/repo\n' \
  | _redact_stream_under_test)"
if printf '%s' "$redact_probe_out" | grep -q '2026-08-16T16:43:28-04:00' \
  && printf '%s' "$redact_probe_out" | grep -q 'host:8080' \
  && printf '%s' "$redact_probe_out" | grep -q '\[redacted-user\]:\[redacted\]@example.com/repo' \
  && ! printf '%s' "$redact_probe_out" | grep -q 'user:pass'; then
  pass "runtime: redact_stream credential regex does not devour timestamps or host:port pairs"
else
  fail "runtime: redact_stream credential regex does not devour timestamps or host:port pairs"
fi

if grep -q 'redact_file "$tmp" >>"$report"' scripts/abora-check-full.sh \
  && grep -q 'redact_file "$tmp" >>"$report_dir/report.txt"' scripts/abora-support-report.sh \
  && grep -q 'Abora network diagnostics' scripts/abora-support-report.sh \
  && grep -q 'abora-recovery network' scripts/abora-support-report.sh \
  && grep -q 'abora support-report \[--output-dir DIR\]' scripts/abora-support-report.sh \
  && grep -q 'Abora support archive created' scripts/abora-support-report.sh \
  && grep -q 'nmcli networking connectivity check' scripts/abora-check-full.sh \
  && grep -q 'nmcli radio' scripts/abora-check-full.sh \
  && grep -q 'cache.nixos.org' scripts/abora-check-full.sh \
  && grep -q 'redact_file "$file" | sed -n' scripts/abora-check-full.sh \
  && grep -q 'trap '\''rm -f "$tmp"'\'' RETURN' scripts/abora-check-full.sh \
  && grep -q 'trap '\''rm -f "$tmp"'\'' RETURN' scripts/abora-support-report.sh \
  && grep -q 'Support archives redact obvious password' docs/wiki/Abora-Tools.md \
  && grep -q 'bug report template' docs/wiki/Abora-Tools.md \
  && grep -q 'Abora Bug Report Template' docs/bug-report-template.md \
  && grep -q 'abora logs --lines 200' docs/bug-report-template.md \
  && grep -q 'abora bug-report --github --web' docs/bug-report-template.md \
  && grep -q 'abora bug-report --github --web --with-support-report' docs/wiki/Abora-Tools.md \
  && grep -q 'abora support-report --output-dir ~/Desktop' docs/bug-report-template.md \
  && grep -q 'abora support-report --output-dir ~/Desktop' docs/wiki/Abora-Tools.md \
  && grep -q 'review the archive before posting' docs/wiki/Recovery.md \
  && grep -q 'abora recovery network' docs/wiki/Recovery.md \
  && grep -q 'abora network' docs/wiki/Recovery.md \
  && grep -q 'Failed checks do not stop the report' docs/wiki/Recovery.md \
  && grep -q 'review' docs/hardware-testing.md \
  && grep -q 'abora hardware-test --with-report' docs/hardware-testing.md \
  && grep -q 'abora hardware-test' docs/wiki/FAQ.md \
  && grep -q 'Quick Wi-Fi connect' docs/wiki/FAQ.md \
  && grep -q 'abora network' docs/wiki/FAQ.md \
  && grep -q 'abora recovery network' docs/wiki/FAQ.md; then
  pass "runtime: check-full and docs describe redacted diagnostics"
else
  fail "runtime: check-full and docs describe redacted diagnostics"
fi

if grep -q 'gaming_steam=' scripts/abora-installer.sh \
  && grep -q 'gaming_vulkan=' scripts/abora-installer.sh \
  && grep -q 'Vulkan tools' scripts/abora-installer.sh \
  && grep -q 'abora.gaming.steam = ${gaming_steam_nix};' scripts/abora-installer.sh \
  && grep -q 'abora.gaming.vulkanTools = ${gaming_vulkan_nix};' scripts/abora-installer.sh \
  && grep -q 'set_nix_bool_assignment "$abora_local" "abora.gaming.steam"' scripts/abora-installer.sh \
  && grep -q 'set_nix_bool_assignment "$abora_local" "abora.gaming.vulkanTools"' scripts/abora-installer.sh; then
  pass "runtime: installer persists Abora Gaming Steam and Vulkan options"
else
  fail "runtime: installer persists Abora Gaming Steam and Vulkan options"
fi

if grep -q 'jq' nix/pkgs/anix.nix \
  && grep -q 'moducpp-anix' nix/pkgs/anix.nix \
  && grep -q 'ANIX_SYSTEM_LANGUAGE_DIR' nix/pkgs/anix.nix \
  && grep -q 'assets/anix-languages' nix/pkgs/anix.nix \
  && grep -q 'Abora-Gaming.md' nix/pkgs/anix.nix; then
  pass "runtime: Nix ANIX package bundles v2 language support and gaming docs"
else
  fail "runtime: Nix ANIX package bundles v2 language support and gaming docs"
fi

# ── Standalone package + release-metadata smoke tests ─────────────────────────
# These build real (throwaway) packages/manifests via package-anix.sh and
# release-metadata.sh rather than just grepping source, since the actual
# packaging/tarball-manifest logic is exactly what would otherwise only get
# caught by a real `make release`.
tmp_anix_pkg_out="$tmp_ok/anix-package-out"
tmp_anix_pkg_list="$tmp_ok/anix-package-files.txt"
if ABORA_OUT_DIR="$tmp_anix_pkg_out" scripts/package-anix.sh >/dev/null; then
  anix_pkg_file="$(find "$tmp_anix_pkg_out/packages" -type f -name 'anix-*-abora-*.tar.gz' | head -n 1)"
  if [[ -n "$anix_pkg_file" ]] \
    && tar -tzf "$anix_pkg_file" > "$tmp_anix_pkg_list" \
    && grep -q 'anix/share/anix/languages/mako.json' "$tmp_anix_pkg_list" \
    && grep -q 'anix/share/anix/languages/moducpp.json' "$tmp_anix_pkg_list" \
    && grep -q 'anix/share/anix/tools/moducpp-anix' "$tmp_anix_pkg_list" \
    && grep -q 'anix/share/anix/docs/wiki/ANIX-V2-Languages.md' "$tmp_anix_pkg_list" \
    && grep -q 'anix/share/anix/docs/wiki/Abora-Gaming.md' "$tmp_anix_pkg_list"; then
    pass "runtime: standalone ANIX package bundles v2 language support and gaming docs"
  else
    fail "runtime: standalone ANIX package bundles v2 language support and gaming docs"
  fi
else
  fail "runtime: standalone ANIX package bundles v2 language support and gaming docs"
fi

mkdir -p "$tmp_ok/iso" "$tmp_ok/packages" "$tmp_ok/release"
for edition in cosmic hyprland gnome kde other; do
  touch "$tmp_ok/iso/abora-${edition}-test-x86_64-${release_tag}.iso"
done
touch "$tmp_ok/packages/tinypm-v0.0.0-abora-${release_tag}.tar.gz"
touch "$tmp_ok/packages/anix-v0.0.0-abora-${release_tag}.tar.gz"
if ABORA_OUT_DIR="$tmp_ok" ABORA_RELEASE_STAMP=test scripts/release-metadata.sh >/dev/null; then
  if [[ -f "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" ]] \
    && [[ -f "$tmp_ok/release/RELEASE_MANIFEST-${release_tag}.txt" ]] \
    && [[ -f "$tmp_ok/release/RELEASE_NOTES-${release_tag}.md" ]] \
    && grep -q "abora-cosmic-test-x86_64-${release_tag}.iso" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "abora-hyprland-test-x86_64-${release_tag}.iso" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "abora-gnome-test-x86_64-${release_tag}.iso" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "abora-kde-test-x86_64-${release_tag}.iso" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "abora-other-test-x86_64-${release_tag}.iso" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "tinypm-v0.0.0-abora-${release_tag}.tar.gz" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "anix-v0.0.0-abora-${release_tag}.tar.gz" "$tmp_ok/release/SHA256SUMS-${release_tag}.txt"; then
    pass "runtime: release-metadata checksum generation includes every edition"
  else
    fail "runtime: release-metadata checksum generation includes every edition"
  fi
else
  fail "runtime: release-metadata checksum generation includes every edition"
fi

tmp_release_fallback="$(mktemp -d)"
mkdir -p "$tmp_release_fallback/iso" "$tmp_release_fallback/packages" "$tmp_release_fallback/release"
for edition in cosmic gnome; do
  touch "$tmp_release_fallback/iso/abora-${edition}-2026.01.01-x86_64-${release_tag}.iso"
done
for edition in cosmic hyprland gnome kde other; do
  touch "$tmp_release_fallback/iso/abora-${edition}-2026.07.27-x86_64-${release_tag}.iso"
done
if ABORA_OUT_DIR="$tmp_release_fallback" scripts/release-metadata.sh >/dev/null; then
  if [[ -f "$tmp_release_fallback/release/SHA256SUMS-${release_tag}.txt" ]] \
    && grep -q "abora-cosmic-2026.07.27-x86_64-${release_tag}.iso" "$tmp_release_fallback/release/SHA256SUMS-${release_tag}.txt" \
    && grep -q "abora-other-2026.07.27-x86_64-${release_tag}.iso" "$tmp_release_fallback/release/SHA256SUMS-${release_tag}.txt" \
    && ! grep -q "2026.01.01" "$tmp_release_fallback/release/SHA256SUMS-${release_tag}.txt"; then
    pass "runtime: release-metadata falls back to newest local ISO stamp"
  else
    fail "runtime: release-metadata falls back to newest local ISO stamp"
  fi
else
  fail "runtime: release-metadata falls back to newest local ISO stamp"
fi

if grep -q 'out/iso/.*iso' .github/workflows/build-iso.yml \
  && grep -A2 'branches:' .github/workflows/build-iso.yml | grep -q 'edge' \
  && grep -A2 'branches:' .github/workflows/publish-tinypm-package.yml | grep -q 'edge' \
  && grep -q 'edge only' .github/workflows/flake-check.yml \
  && grep -q 'vendor/tinypm/Cargo.toml' .github/workflows/publish-tinypm-package.yml \
  && grep -q 'out/packages/tinypm' .github/workflows/build-iso.yml \
  && grep -q 'out/packages/anix' .github/workflows/build-iso.yml \
  && grep -q 'out/release/SHA256SUMS' .github/workflows/build-iso.yml \
  && grep -q 'out/packages/tinypm' .github/workflows/release-iso.yml \
  && grep -q 'out/packages/anix' .github/workflows/release-iso.yml \
  && grep -q 'out/release/RELEASE_NOTES' .github/workflows/release-iso.yml \
  && grep -q 'Abora OS v4 Everest (${tag})' .github/workflows/release-iso.yml; then
  pass "runtime: GitHub workflows publish generated release bundle paths"
else
  fail "runtime: GitHub workflows publish generated release bundle paths"
fi

if grep -q 'COPY --from=build /build/target/release/tinypm /usr/local/bin/tinypm' packaging/tinypm/Dockerfile \
  && grep -q 'COPY --from=build /build/target/release/grab /usr/local/bin/grab' packaging/tinypm/Dockerfile \
  && grep -q 'cargo build --release --locked' packaging/tinypm/Dockerfile \
  && [[ -f vendor/tinypm/Cargo.toml ]] \
  && [[ -f vendor/tinypm/src/bin/grab.rs ]]; then
  pass "runtime: TinyPM container builds the real Rust binaries"
else
  fail "runtime: TinyPM container builds the real Rust binaries"
fi

empty_output="$(ABORA_OUT_DIR="$tmp_empty" scripts/release-metadata.sh 2>&1 || true)"
if printf '%s' "$empty_output" | grep -q "No ISO files found"; then
  pass "runtime: release-metadata empty-dir guard"
else
  fail "runtime: release-metadata empty-dir guard"
fi

# ── anix.sh end-to-end behavior tests ──────────────────────────────────────────
# Each block below runs the real scripts/anix.sh against a throwaway
# ANIX_SYSTEM_CONFIG directory (ANIX_NO_SUDO/ANIX_ASSUME_YES bypass root and
# prompts — see anix.sh's confirm()/run_as_root()), then asserts on the
# actual file/git state it produced, not just its printed output.
tmp_anix="$tmp_ok/anix.nix"
printf '%s\n' \
  '{ ... }:' \
  '{' \
  '  anix.enable = true;' \
  '  anix.hostname = "testbox";' \
  '  anix.timezone = "UTC";' \
  '  anix.keyboard.console = "us";' \
  '  anix.keyboard.xkb = "us";' \
  '  anix.desktop = "gnome";' \
  '  anix.wallpaper = "titlis-alps.jpg";' \
  '}' > "$tmp_anix"
anix_output="$(
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  ANIX_CONFIG_FILE="$tmp_anix" \
  ANIX_SYSTEM_CONFIG="$tmp_ok" \
  scripts/anix.sh show 2>&1
)"
if printf '%s' "$anix_output" | grep -q "testbox" \
  && printf '%s' "$anix_output" | grep -q "titlis-alps.jpg"; then
  pass "runtime: anix fallback UI show"
else
  fail "runtime: anix fallback UI show"
fi

tmp_anix_config_dir="$tmp_ok/anix-config"
mkdir -p "$tmp_anix_config_dir"
if ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_config_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh config set snapshots.push true >/dev/null \
  && grep -q "snapshots.push=true" "$tmp_anix_config_dir/.anix/config"; then
  pass "runtime: anix tool config set"
else
  fail "runtime: anix tool config set"
fi

tmp_anix_quickstart_dir="$tmp_ok/anix-quickstart"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_quickstart_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh quickstart >/dev/null \
  && [[ -f "$tmp_anix_quickstart_dir/anix.nix" ]] \
  && git -C "$tmp_anix_quickstart_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pass "runtime: anix quickstart"
else
  fail "runtime: anix quickstart"
fi

anix_docs_output="$(
  ANIX_NO_SUDO=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_quickstart_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh docs 2>&1
)"
if printf '%s' "$anix_docs_output" | grep -q "ANIX-V1"; then
  pass "runtime: anix docs"
else
  fail "runtime: anix docs"
fi

tmp_anix_save_dir="$tmp_ok/anix-save"
mkdir -p "$tmp_anix_save_dir"
printf '%s\n' '{ ... }: { networking.hostName = "testbox"; }' > "$tmp_anix_save_dir/configuration.nix"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_save_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh save "anix: test snapshot" >/dev/null \
  && git -C "$tmp_anix_save_dir" log --oneline -1 | grep -q "anix: test snapshot"; then
  pass "runtime: anix local snapshot"
else
  fail "runtime: anix local snapshot"
fi

tmp_anix_switch_dir="$tmp_ok/anix-switch"
tmp_anix_bin="$tmp_ok/anix-bin"
tmp_anix_log="$tmp_ok/anix-rebuild.log"
mkdir -p "$tmp_anix_switch_dir" "$tmp_anix_bin"
printf '%s\n' \
  '{' \
  '  outputs = { nixpkgs, ... }: {' \
  '    nixosConfigurations = {' \
  '      gaming = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ ]; };' \
  '    };' \
  '  };' \
  '}' > "$tmp_anix_switch_dir/flake.nix"
git -C "$tmp_anix_switch_dir" -c init.defaultBranch=main init >/dev/null
git -C "$tmp_anix_switch_dir" -c user.name=ANIX -c user.email=anix@localhost add -A
git -C "$tmp_anix_switch_dir" -c user.name=ANIX -c user.email=anix@localhost commit -m "initial" >/dev/null
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$ANIX_REBUILD_LOG"' > "$tmp_anix_bin/nixos-rebuild"
chmod +x "$tmp_anix_bin/nixos-rebuild"
if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh switch nix gaming --now >/dev/null \
  && grep -q "switch --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix switch maps flake profile"
else
  fail "runtime: anix switch maps flake profile"
fi

# `anix switch nix` (family only, no profile) must fall through to the
# "Usage: anix switch nix <profile> [--now]" message rather than misreading
# the leftover "nix" positional as an unrecognized --flag.
anix_switch_family_only_output="$(
  PATH="$tmp_anix_bin:$PATH" \
    ANIX_NO_SUDO=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh switch nix 2>&1 || true
)"
if printf '%s' "$anix_switch_family_only_output" | grep -q "Usage: anix switch nix <profile>" \
  && ! printf '%s' "$anix_switch_family_only_output" | grep -q "Unknown switch option"; then
  pass "runtime: anix switch with family only shows usage"
else
  fail "runtime: anix switch with family only shows usage"
fi

# Simulates the "git needs root" case (a repo owned by a different UID —
# git calls this "dubious ownership" and refuses to operate as the invoking
# user): the fake `git` here fails for the calling user but succeeds via
# ANIX_ROOT_PATH's copy, exercising stage_config_for_flake()'s run_as_root
# fallback rather than just the happy path where a single git works for both.
tmp_anix_untracked_dir="$tmp_ok/anix-untracked-flake"
tmp_anix_untracked_bin="$tmp_ok/anix-untracked-bin"
tmp_anix_untracked_rootbin="$tmp_ok/anix-untracked-rootbin"
mkdir -p "$tmp_anix_untracked_dir" "$tmp_anix_untracked_bin" "$tmp_anix_untracked_rootbin"
git -C "$tmp_anix_untracked_dir" -c init.defaultBranch=main init >/dev/null
printf '%s\n' \
  '{' \
  '  outputs = { nixpkgs, ... }: {' \
  '    nixosConfigurations.abora = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ ]; };' \
  '  };' \
  '}' > "$tmp_anix_untracked_dir/flake.nix"
printf '%s\n' '{ ... }: { anix.hostname = "tracked"; }' > "$tmp_anix_untracked_dir/anix.nix"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "${ANIX_FAKE_GIT_NEEDS_ROOT:-0}" == 1 ]]; then' \
  '  printf "dubious ownership\n" >&2' \
  '  exit 128' \
  'fi' \
  "exec $(command -v git) \"\$@\"" > "$tmp_anix_untracked_bin/git"
chmod +x "$tmp_anix_untracked_bin/git"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  "exec $(command -v git) \"\$@\"" > "$tmp_anix_untracked_rootbin/git"
chmod +x "$tmp_anix_untracked_rootbin/git"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'target=""' \
  'while [[ $# -gt 0 ]]; do' \
  '  case "$1" in --flake) shift; target="${1%%#*}" ;; esac' \
  '  shift || true' \
  'done' \
  'git -C "$target" ls-files --error-unmatch flake.nix >/dev/null' > "$tmp_anix_untracked_bin/nixos-rebuild"
chmod +x "$tmp_anix_untracked_bin/nixos-rebuild"
cp "$tmp_anix_untracked_bin/nixos-rebuild" "$tmp_anix_untracked_rootbin/nixos-rebuild"
if PATH="$tmp_anix_untracked_bin:$PATH" \
  ANIX_FAKE_GIT_NEEDS_ROOT=1 \
  ANIX_ROOT_PATH="$tmp_anix_untracked_rootbin:$PATH" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_untracked_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply >/dev/null 2>&1; then
  pass "runtime: anix stages untracked flake before apply"
else
  fail "runtime: anix stages untracked flake before apply"
fi

tmp_anix_pkgs_dir="$tmp_ok/anix-pkgs-header"
tmp_anix_pkgs_bin="$tmp_ok/anix-pkgs-bin"
mkdir -p "$tmp_anix_pkgs_dir" "$tmp_anix_pkgs_bin"
printf '%s\n' \
  '{' \
  '  outputs = { nixpkgs, ... }: {' \
  '    nixosConfigurations.abora = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ ]; };' \
  '  };' \
  '}' > "$tmp_anix_pkgs_dir/flake.nix"
printf '%s\n' \
  '{ ... }:' \
  '{' \
  '  anix.enable = true;' \
  '  anix.packages = with pkgs; [ git ];' \
  '}' > "$tmp_anix_pkgs_dir/anix.nix"
git -C "$tmp_anix_pkgs_dir" -c init.defaultBranch=main init >/dev/null
git -C "$tmp_anix_pkgs_dir" -c user.name=ANIX -c user.email=anix@localhost add -A
git -C "$tmp_anix_pkgs_dir" -c user.name=ANIX -c user.email=anix@localhost commit -m "initial" >/dev/null
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'target=""' \
  'while [[ $# -gt 0 ]]; do' \
  '  case "$1" in --flake) shift; target="${1%%#*}" ;; esac' \
  '  shift || true' \
  'done' \
  'grep -Eq "^[[:space:]]*\\{[[:space:]]*pkgs,[[:space:]]*\\.\\.\\.[[:space:]]*\\}:" "$target/anix.nix"' > "$tmp_anix_pkgs_bin/nixos-rebuild"
chmod +x "$tmp_anix_pkgs_bin/nixos-rebuild"
if PATH="$tmp_anix_pkgs_bin:$PATH" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_pkgs_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply >/dev/null 2>&1; then
  pass "runtime: anix repairs pkgs module argument before apply"
else
  fail "runtime: anix repairs pkgs module argument before apply"
fi

anix_profiles_output="$(
  PATH="$tmp_anix_bin:$PATH" \
    ANIX_NO_SUDO=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh profiles 2>&1
)"
if PATH="$tmp_anix_bin:$PATH" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh status >/dev/null \
  && printf '%s' "$anix_profiles_output" | grep -q "gaming"; then
  pass "runtime: anix status and profiles"
else
  fail "runtime: anix status and profiles"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh test nix gaming >/dev/null \
  && grep -q "test --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix test activation"
else
  fail "runtime: anix test activation"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh boot nix gaming >/dev/null \
  && grep -q "boot --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix boot activation"
else
  fail "runtime: anix boot activation"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh rollback nix --now >/dev/null \
  && grep -q "switch --rollback" "$tmp_anix_log"; then
  pass "runtime: anix generation rollback"
else
  fail "runtime: anix generation rollback"
fi

if [[ -n "$plan_tool_bin" ]]; then
export ABORA_PLAN_TOOL_BIN="$plan_tool_bin"
tmp_anix_plan_dir="$tmp_ok/anix-plan"
mkdir -p "$tmp_anix_plan_dir"

anix_plan_json='{"planVersion":1,"language":"test","operations":[{"op":"set","key":"hostname","value":"planhost"},{"op":"enable","feature":"bluetooth"},{"op":"enable","feature":"gaming"},{"op":"enable","feature":"gaming.steam"},{"op":"enable","feature":"gaming.big-picture"},{"op":"enable","feature":"gaming.controllers"},{"op":"enable","feature":"gaming.mangohud"},{"op":"enable","feature":"gaming.gamemode"},{"op":"enable","feature":"gaming.vulkan"},{"op":"enable","feature":"gaming.launchers"},{"op":"package.add","name":"firefox"}]}'
printf '%s' "$anix_plan_json" > "$tmp_anix_plan_dir/plan.json"
if ANIX_SYSTEM_CONFIG="$tmp_anix_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh validate-plan "$tmp_anix_plan_dir/plan.json" >/dev/null; then
  pass "runtime: anix validate-plan accepts a well-formed plan"
else
  fail "runtime: anix validate-plan accepts a well-formed plan"
fi

anix_bad_plan_json='{"planVersion":1,"language":"test","operations":[{"op":"set","key":"not-a-real-key","value":"x"}]}'
printf '%s' "$anix_bad_plan_json" > "$tmp_anix_plan_dir/bad-plan.json"
if ANIX_SYSTEM_CONFIG="$tmp_anix_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh validate-plan "$tmp_anix_plan_dir/bad-plan.json" >/dev/null 2>&1; then
  fail "runtime: anix validate-plan rejects an unknown set key"
else
  pass "runtime: anix validate-plan rejects an unknown set key"
fi

tmp_anix_apply_plan_dir="$tmp_ok/anix-apply-plan"
mkdir -p "$tmp_anix_apply_plan_dir"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_apply_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_plan_dir/plan.json" --yes >/dev/null 2>&1; then
  :
fi
if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"planhost"' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.steam[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.controllerSupport[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.vulkanTools[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix apply-plan writes every operation as one transaction"
else
  fail "runtime: anix apply-plan writes every operation as one transaction"
fi

tmp_anix_gaming_deps_dir="$tmp_ok/anix-gaming-deps"
mkdir -p "$tmp_anix_gaming_deps_dir"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh enable gaming.big-picture >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.steam[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh enable gaming.autostart >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.bigPictureAutostart[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh enable gaming.gamescope >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.gamescopeSession[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh disable gaming.steam >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.steam[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureAutostart[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.gamescopeSession[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.controllerSupport[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix gaming toggles enable and disable required parent options"
else
  fail "runtime: anix gaming toggles enable and disable required parent options"
fi

tmp_anix_native_dir="$tmp_ok/anix-native-plan"
mkdir -p "$tmp_anix_native_dir"
printf '%s\n' \
  'set hostname nativehost' \
  'enable bluetooth' \
  'package add git' > "$tmp_anix_native_dir/plan.anix"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_native_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh run "$tmp_anix_native_dir/plan.anix" --yes >/dev/null 2>&1; then
  :
fi
if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"nativehost"' "$tmp_anix_native_dir/anix.nix" 2>/dev/null \
  && grep -q "git" "$tmp_anix_native_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix run applies a .anix Native file as one plan"
else
  fail "runtime: anix run applies a .anix Native file as one plan"
fi

# `anix run <file> --language` with no value after --language must print the
# usage message, not crash silently: the old `shift 2` failed under `set -e`
# when only one positional remained, exiting with no output at all.
anix_run_missing_lang_value_out="$(
  ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_native_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh run "$tmp_anix_native_dir/plan.anix" --language 2>&1 || true
)"
if printf '%s' "$anix_run_missing_lang_value_out" | grep -q "Usage: anix run <file>"; then
  pass "runtime: anix run with a valueless --language shows usage instead of crashing silently"
else
  fail "runtime: anix run with a valueless --language shows usage instead of crashing silently"
fi

tmp_anix_diff_plan_dir="$tmp_ok/anix-diff-plan"
mkdir -p "$tmp_anix_diff_plan_dir"
anix_diff_plan_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_plan_dir/plan.json" 2>&1
)"
if printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*set hostname" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable bluetooth" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.steam" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.big-picture" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "also ADD enable gaming.enable" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.controllers" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.launchers"; then
  pass "runtime: anix diff-plan labels new settings as ADD"
else
  fail "runtime: anix diff-plan labels new settings as ADD"
fi

# Regression check: enable/disable ops must compare against the real current
# boolean in anix.nix, not report ADD/REMOVE unconditionally regardless of
# state (a real bug caught by hand-testing — read_anix_bool_option originally
# used '|' as its sed delimiter while also using '|' for alternation in the
# pattern, which silently broke the read and made every feature look unset).
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_plan_dir/plan.json" --yes >/dev/null 2>&1; then
  :
fi
anix_diff_plan_same_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_plan_dir/plan.json" 2>&1
)"
if printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*set hostname" \
  && printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*enable bluetooth" \
  && printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*enable gaming.big-picture"; then
  pass "runtime: anix diff-plan labels already-applied settings as SAME"
else
  fail "runtime: anix diff-plan labels already-applied settings as SAME"
fi

printf 'disable bluetooth\n' > "$tmp_anix_diff_plan_dir/disable.anix"
anix_diff_plan_change_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_diff_plan_dir/disable.anix" 2>&1
)"
if printf '%s' "$anix_diff_plan_change_output" | grep -q "CHANGE.*disable bluetooth"; then
  pass "runtime: anix diff-plan labels a real flip as CHANGE"
else
  fail "runtime: anix diff-plan labels a real flip as CHANGE"
fi

tmp_anix_diff_deps_dir="$tmp_ok/anix-diff-deps"
mkdir -p "$tmp_anix_diff_deps_dir"
cat > "$tmp_anix_diff_deps_dir/anix.nix" <<'EOF'
{ pkgs, ... }:
{
  anix.gaming.enable = true;
  anix.gaming.steam = true;
  anix.gaming.bigPictureShortcut = true;
  anix.gaming.bigPictureAutostart = true;
  anix.gaming.gamescopeSession = true;
  anix.gaming.controllerSupport = true;
}
EOF
printf '%s\n' 'disable gaming.steam' > "$tmp_anix_diff_deps_dir/disable-steam.anix"
anix_diff_deps_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_diff_deps_dir/disable-steam.anix" 2>&1
)"
if printf '%s' "$anix_diff_deps_output" | grep -q "CHANGE.*disable gaming.steam" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.bigPictureShortcut" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.bigPictureAutostart" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.gamescopeSession" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.controllerSupport"; then
  pass "runtime: anix diff-plan previews implied gaming dependency changes"
else
  fail "runtime: anix diff-plan previews implied gaming dependency changes"
fi
unset ABORA_PLAN_TOOL_BIN
else
  pass "runtime: anix plan-JSON tests skipped (dotnet unavailable)"
fi

tmp_anix_lang_dir="$tmp_ok/anix-language"
tmp_anix_lang_adapters="$tmp_ok/anix-language-adapters"
mkdir -p "$tmp_anix_lang_dir" "$tmp_anix_lang_adapters"
printf '%s\n' \
  '{' \
  '  "id": "stub",' \
  '  "name": "Stub",' \
  '  "extensions": [".stub"],' \
  '  "command": ["cat"],' \
  '  "planVersion": 1' \
  '}' > "$tmp_anix_lang_adapters/stub.json"
anix_language_list_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_lang_dir" \
    ANIX_SYSTEM_LANGUAGE_DIR="$tmp_anix_lang_adapters" \
    ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh language list 2>&1
)"
if printf '%s' "$anix_language_list_output" | grep -q "Stub"; then
  pass "runtime: anix language list shows an installed adapter manifest"
else
  fail "runtime: anix language list shows an installed adapter manifest"
fi

if ANIX_SYSTEM_CONFIG="$tmp_anix_lang_dir" \
  ANIX_SYSTEM_LANGUAGE_DIR="$tmp_anix_lang_adapters" \
  ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
  ANIX_NO_SUDO=1 \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh language use stub >/dev/null 2>&1 \
  && grep -q "language=stub" "$tmp_anix_lang_dir/.anix/config" 2>/dev/null; then
  pass "runtime: anix language use persists the default frontend"
else
  fail "runtime: anix language use persists the default frontend"
fi

tmp_installed_anix_lang="$tmp_ok/installed-anix-languages"
mkdir -p "$tmp_installed_anix_lang/etc/nixos/abora/anix-languages" \
         "$tmp_installed_anix_lang/etc/anix"
cp assets/anix-languages/*.json "$tmp_installed_anix_lang/etc/nixos/abora/anix-languages/"
ln -s "$tmp_installed_anix_lang/etc/nixos/abora/anix-languages" \
      "$tmp_installed_anix_lang/etc/anix/languages"
installed_anix_language_list_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_installed_anix_lang/etc/nixos" \
    ANIX_SYSTEM_LANGUAGE_DIR="$tmp_installed_anix_lang/etc/anix/languages" \
    ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh language list 2>&1
)"
if printf '%s' "$installed_anix_language_list_output" | grep -q "MAKO" \
  && printf '%s' "$installed_anix_language_list_output" | grep -q "ModuCPP" \
  && grep -q 'builtins.pathExists ./anix-languages' nix/modules/installed-base.nix \
  && grep -q '"anix/languages".source = anixLanguagesDir' nix/modules/installed-base.nix; then
  pass "runtime: installed systems expose real ANIX language adapters"
else
  fail "runtime: installed systems expose real ANIX language adapters"
fi

# ── ANIX v2 end-to-end: real example files through real adapters ───────────
# Each example is run through the actual `anix run`, with the real adapter
# manifests in assets/anix-languages, against an isolated config dir. This
# exercises the whole path (adapter resolution -> real mko/moducpp-anix
# process -> plan validation -> transactional write), not just the plan
# engine in isolation like the tests above. Skips per-frontend when the
# frontend's own tool isn't installed, matching the existing `command -v
# nix` skip pattern, rather than failing the whole suite on a missing dev
# tool that isn't part of this repo.

anix_e2e_run() {
  local example="$1" config_dir="$2"
  ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$config_dir" \
    ANIX_SYSTEM_LANGUAGE_DIR="$repo_dir/assets/anix-languages" \
    ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh run "$example" --yes >/dev/null 2>&1
}

if [[ -n "$plan_tool_bin" ]]; then
export ABORA_PLAN_TOOL_BIN="$plan_tool_bin"
tmp_anix_e2e_anix="$tmp_ok/anix-e2e-anix"
mkdir -p "$tmp_anix_e2e_anix"
anix_e2e_run "examples/anix-v2/simple.anix" "$tmp_anix_e2e_anix" || true
if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_anix/anix.nix" 2>/dev/null; then
  pass "runtime: e2e .anix simple example applies through anix run"
else
  fail "runtime: e2e .anix simple example applies through anix run"
fi

# do_set only bans '"', '\', and '${' for timezone/keyboard.xkb/gc.days/
# gc.dates -- a systemd OnCalendar-style gc.dates value like "Sun 03:00:00"
# is legal there and via a JSON Plan's "value" field, but
# NativePlanBuilder's `set` used to require exactly 3 whitespace-split
# tokens, silently truncating/rejecting any value containing a space.
tmp_anix_e2e_spaced_value="$tmp_ok/anix-e2e-spaced-value"
mkdir -p "$tmp_anix_e2e_spaced_value"
printf 'set gc.dates Sun 03:00:00\n' > "$tmp_anix_e2e_spaced_value/plan.anix"
anix_e2e_run "$tmp_anix_e2e_spaced_value/plan.anix" "$tmp_anix_e2e_spaced_value" || true
if grep -Eq 'anix\.garbageCollect\.dates[[:space:]]*=[[:space:]]*"Sun 03:00:00"' "$tmp_anix_e2e_spaced_value/anix.nix" 2>/dev/null; then
  pass "runtime: native .anix 'set' preserves a space-containing value"
else
  fail "runtime: native .anix 'set' preserves a space-containing value"
fi

tmp_anix_e2e_anix_ws="$tmp_ok/anix-e2e-anix-workstation"
mkdir -p "$tmp_anix_e2e_anix_ws"
anix_e2e_run "examples/anix-v2/workstation.anix" "$tmp_anix_e2e_anix_ws" || true
if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest-workstation"' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -q "firefox" "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -q "git" "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null; then
  pass "runtime: e2e .anix workstation example applies through anix run"
else
  fail "runtime: e2e .anix workstation example applies through anix run"
fi

if command -v mko >/dev/null 2>&1; then
  tmp_anix_e2e_mko="$tmp_ok/anix-e2e-mko"
  mkdir -p "$tmp_anix_e2e_mko"
  anix_e2e_run "examples/anix-v2/simple.mko" "$tmp_anix_e2e_mko" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_mko/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .mko simple example applies through anix run"
  else
    fail "runtime: e2e .mko simple example applies through anix run"
  fi

  tmp_anix_e2e_mko_ws="$tmp_ok/anix-e2e-mko-workstation"
  mkdir -p "$tmp_anix_e2e_mko_ws"
  anix_e2e_run "examples/anix-v2/workstation.mko" "$tmp_anix_e2e_mko_ws" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest-workstation"' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -q "firefox" "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -q "git" "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .mko workstation example applies through anix run"
  else
    fail "runtime: e2e .mko workstation example applies through anix run"
  fi
else
  pass "mko unavailable (MAKO e2e tests skipped)"
fi

if command -v moducpp-anix >/dev/null 2>&1; then
  tmp_anix_e2e_moducpp="$tmp_ok/anix-e2e-moducpp"
  mkdir -p "$tmp_anix_e2e_moducpp"
  anix_e2e_run "examples/anix-v2/simple.moducpp" "$tmp_anix_e2e_moducpp" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_moducpp/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .moducpp simple example applies through anix run"
  else
    fail "runtime: e2e .moducpp simple example applies through anix run"
  fi

  tmp_anix_e2e_moducpp_ws="$tmp_ok/anix-e2e-moducpp-workstation"
  mkdir -p "$tmp_anix_e2e_moducpp_ws"
  anix_e2e_run "examples/anix-v2/workstation.moducpp" "$tmp_anix_e2e_moducpp_ws" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest-workstation"' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -q "firefox" "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -q "git" "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .moducpp workstation example applies through anix run"
  else
    fail "runtime: e2e .moducpp workstation example applies through anix run"
  fi
else
  pass "moducpp-anix unavailable (ModuCPP e2e tests skipped)"
fi
unset ABORA_PLAN_TOOL_BIN
else
  pass "runtime: anix e2e run tests skipped (dotnet unavailable)"
fi

# ── ANIX v2 failure paths: invalid input must never mutate state ───────────

if [[ -n "$plan_tool_bin" ]]; then
export ABORA_PLAN_TOOL_BIN="$plan_tool_bin"
tmp_anix_fail_bad_plan="$tmp_ok/anix-fail-bad-plan"
mkdir -p "$tmp_anix_fail_bad_plan"
printf '%s' '{"planVersion":1,"language":"test","operations":[{"op":"set","key":"totally-not-a-key","value":"x"}]}' \
  > "$tmp_anix_fail_bad_plan/bad.json"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_bad_plan" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_fail_bad_plan/bad.json" --yes >/dev/null 2>&1; then
  fail "runtime: apply-plan rejects an invalid plan without writing anix.nix"
elif [[ -f "$tmp_anix_fail_bad_plan/anix.nix" ]]; then
  fail "runtime: apply-plan rejects an invalid plan without writing anix.nix"
else
  pass "runtime: apply-plan rejects an invalid plan without writing anix.nix"
fi

tmp_anix_fail_malformed_json="$tmp_ok/anix-fail-malformed-json"
mkdir -p "$tmp_anix_fail_malformed_json"
printf '{ this is not json' > "$tmp_anix_fail_malformed_json/malformed.json"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_malformed_json" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_fail_malformed_json/malformed.json" --yes >/dev/null 2>&1; then
  fail "runtime: apply-plan rejects malformed JSON without writing anix.nix"
elif [[ -f "$tmp_anix_fail_malformed_json/anix.nix" ]]; then
  fail "runtime: apply-plan rejects malformed JSON without writing anix.nix"
else
  pass "runtime: apply-plan rejects malformed JSON without writing anix.nix"
fi

tmp_anix_fail_unknown_adapter="$tmp_ok/anix-fail-unknown-adapter"
mkdir -p "$tmp_anix_fail_unknown_adapter"
printf 'not real source content\n' > "$tmp_anix_fail_unknown_adapter/script.nosuchlang"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_unknown_adapter" \
  ANIX_SYSTEM_LANGUAGE_DIR="$tmp_empty/no-system-languages" \
  ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh run "$tmp_anix_fail_unknown_adapter/script.nosuchlang" --yes >/dev/null 2>&1; then
  fail "runtime: run rejects an unresolvable language without writing anix.nix"
elif [[ -f "$tmp_anix_fail_unknown_adapter/anix.nix" ]]; then
  fail "runtime: run rejects an unresolvable language without writing anix.nix"
else
  pass "runtime: run rejects an unresolvable language without writing anix.nix"
fi

tmp_anix_fail_adapter_error="$tmp_ok/anix-fail-adapter-error"
tmp_anix_fail_adapter_dir="$tmp_ok/anix-fail-adapter-manifests"
mkdir -p "$tmp_anix_fail_adapter_error" "$tmp_anix_fail_adapter_dir"
printf '%s\n' \
  '{' \
  '  "id": "always-fails",' \
  '  "name": "Always Fails",' \
  '  "extensions": [".fails"],' \
  '  "command": ["false"],' \
  '  "planVersion": 1' \
  '}' > "$tmp_anix_fail_adapter_dir/always-fails.json"
printf 'anything\n' > "$tmp_anix_fail_adapter_error/script.fails"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_adapter_error" \
  ANIX_SYSTEM_LANGUAGE_DIR="$tmp_anix_fail_adapter_dir" \
  ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh run "$tmp_anix_fail_adapter_error/script.fails" --yes >/dev/null 2>&1; then
  fail "runtime: run surfaces an adapter's own failure without writing anix.nix"
elif [[ -f "$tmp_anix_fail_adapter_error/anix.nix" ]]; then
  fail "runtime: run surfaces an adapter's own failure without writing anix.nix"
else
  pass "runtime: run surfaces an adapter's own failure without writing anix.nix"
fi
unset ABORA_PLAN_TOOL_BIN
else
  pass "runtime: anix plan failure-path tests skipped (dotnet unavailable)"
fi

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$repo_dir/scripts/abora-desktop-profiles.sh"
gnome_config_block="$(abora_desktop_config_block gnome us abora)"
gnome_package_block="$(abora_desktop_package_block gnome)"
if printf '%s\n' "$gnome_config_block" | grep -q "environment.systemPackages"; then
  fail "runtime: desktop config block contains environment.systemPackages"
elif ! printf '%s\n' "$gnome_package_block" | grep -q "gnomeExtensions.dash-to-dock"; then
  fail "runtime: GNOME package block missing extension packages"
else
  pass "runtime: desktop package/config split"
fi

# abora-desktop-preview.sh is the standalone-user path onto the exact same
# abora_desktop_config_block/abora_desktop_package_block functions just
# exercised above, so verify its own arg handling/output plumbing works
# end to end rather than only unit-testing the library functions directly.
preview_out="$("$repo_dir/scripts/abora-desktop-preview.sh" hyprland de previewuser)"
if ! printf '%s\n' "$preview_out" | grep -q 'xkb.layout = "de"'; then
  fail "runtime: abora-desktop-preview.sh did not interpolate xkb layout"
elif ! printf '%s\n' "$preview_out" | grep -q 'previewuser'; then
  fail "runtime: abora-desktop-preview.sh did not interpolate username"
else
  pass "runtime: abora-desktop-preview.sh renders a real desktop config"
fi

if "$repo_dir/scripts/abora-desktop-preview.sh" not-a-real-desktop-profile \
    >/dev/null 2>&1; then
  fail "runtime: abora-desktop-preview.sh accepted an unknown desktop profile"
else
  pass "runtime: abora-desktop-preview.sh rejects an unknown desktop profile"
fi

# abora-hardware-test.sh is now packaged standalone (nix/pkgs/hardware-test.nix)
# specifically because it has no /etc/abora dependency beyond its ui.sh
# fallback -- confirm it actually runs clean end to end on whatever machine
# is running the checks, not just that it parses.
if "$repo_dir/scripts/abora-hardware-test.sh" >/dev/null 2>&1; then
  pass "runtime: abora-hardware-test.sh runs end to end"
else
  fail "runtime: abora-hardware-test.sh exited non-zero"
fi

# abora-config.sh backs the `abora config` command CLAUDE.md documents as
# read/writing abora-local.nix without requiring Nix knowledge, including
# that `user` and `disk` are intentionally read-only through this CLI — none
# of that was previously exercised at runtime, only checked for existence.
tmp_config="$(mktemp -d)"
tmp_config_module="$tmp_config/abora-local.nix"
cat > "$tmp_config_module" <<'EOF'
{ config, ... }:
{
  abora.hostname = "abora";
  abora.locale = "en_US.UTF-8";
  abora.timezone = "UTC";
  abora.keyboard.console = "us";
  abora.keyboard.xkb = "us";
  abora.desktop = "cosmic";
  abora.wallpaper = "titlis-alps.jpg";
  abora.gpu = "none";
  abora.stateVersion = "26.05";
  abora.user.name = "abora";
  abora.user.hashedPassword = "";
  abora.disk = null;

  networking.networkmanager.enable = true;
  users.users.root.hashedPassword = "!";
}
EOF

config_show_out="$(
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh show 2>&1
)"
if printf '%s' "$config_show_out" | grep -q "abora" \
  && printf '%s' "$config_show_out" | grep -q "titlis-alps.jpg"; then
  pass "runtime: abora config show reads abora-local.nix"
else
  fail "runtime: abora config show reads abora-local.nix"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set hostname new-hostname >/dev/null 2>&1 \
  && grep -q 'abora.hostname = "new-hostname";' "$tmp_config_module"; then
  pass "runtime: abora config set writes a new value"
else
  fail "runtime: abora config set writes a new value"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set gaming yes >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.steam off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.big-picture off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.controllers off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.mangohud off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.gamemode off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.vulkan false >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.launchers false >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.steam = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.controllerSupport = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.mangohud = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.gamemode = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.vulkanTools = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.launchers = false;' "$tmp_config_module"; then
  pass "runtime: abora config set writes gaming booleans"
else
  fail "runtime: abora config set writes gaming booleans"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set gaming.big-picture true >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_config_module" \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.autostart true >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureAutostart = true;' "$tmp_config_module" \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.gamescope true >/dev/null 2>&1 \
  && grep -q 'abora.gaming.gamescopeSession = true;' "$tmp_config_module"; then
  pass "runtime: abora config gaming launcher keys enable required parent options"
else
  fail "runtime: abora config gaming launcher keys enable required parent options"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set diagnostics true >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set vm-guests true >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set mobile-broadband true >/dev/null 2>&1 \
  && grep -q 'abora.extras.diagnostics = true;' "$tmp_config_module" \
  && grep -q 'abora.extras.virtualizationGuests = true;' "$tmp_config_module" \
  && grep -q 'abora.extras.mobileBroadband = true;' "$tmp_config_module" \
  && grep -q 'lib.optionals config.abora.extras.diagnostics' nix/modules/installed-base.nix \
  && grep -q 'lib.optionals config.abora.extras.mobileBroadband' nix/modules/installed-base.nix \
  && grep -q 'config.abora.extras.virtualizationGuests' nix/modules/installed-base.nix \
  && grep -q 'abora.extras.diagnostics = false;' scripts/abora-installer.sh; then
  pass "runtime: lean extras are opt-in instead of always installed"
else
  fail "runtime: lean extras are opt-in instead of always installed"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set gaming maybe >/dev/null 2>&1; then
  fail "runtime: abora config set rejects invalid gaming boolean"
else
  pass "runtime: abora config set rejects invalid gaming boolean"
fi

if grep -q "Adw.SwitchRow(title='Abora Gaming')" scripts/abora-config-gui.py \
  && grep -q "read_bool_setting('gaming.enable'" scripts/abora-config-gui.py \
  && grep -q "read_bool_setting('gaming.steam'" scripts/abora-config-gui.py \
  && grep -q "'gaming.steam'" scripts/abora-config-gui.py \
  && grep -q "'gaming.big-picture'" scripts/abora-config-gui.py \
  && grep -q "'gaming.gamescope'" scripts/abora-config-gui.py \
  && grep -q "'gaming.controllers'" scripts/abora-config-gui.py \
  && grep -q "'gaming.mangohud'" scripts/abora-config-gui.py \
  && grep -q "'gaming.gamemode'" scripts/abora-config-gui.py \
  && grep -q "'gaming.vulkan'" scripts/abora-config-gui.py \
  && grep -q "'gaming.launchers'" scripts/abora-config-gui.py \
  && grep -q "'gaming.autostart'" scripts/abora-config-gui.py; then
  pass "runtime: abora config GUI exposes gaming toggles"
else
  fail "runtime: abora config GUI exposes gaming toggles"
fi

if grep -q 'read_bool_setting gaming.enable' scripts/abora-welcome.sh \
  && grep -q 'abora_kv "Gaming"' scripts/abora-welcome.sh \
  && grep -q 'abora gaming status' scripts/abora-welcome.sh \
  && grep -q "read_local_bool('gaming.enable'" scripts/abora-welcome-gui.py \
  && grep -q "title='Gaming'" scripts/abora-welcome-gui.py \
  && grep -q "\\['abora', 'gaming', 'status'\\]" scripts/abora-welcome-gui.py \
  && grep -q "\\['abora', 'doctor'\\]" scripts/abora-welcome-gui.py \
  && grep -q "\\['abora', 'apps'\\]" scripts/abora-welcome-gui.py \
  && grep -q "\\['abora', 'desktop', 'list'\\]" scripts/abora-welcome-gui.py \
  && grep -q "\\['abora', 'recovery'\\]" scripts/abora-welcome-gui.py; then
  pass "runtime: abora welcome exposes gaming status and action"
else
  fail "runtime: abora welcome exposes gaming status and action"
fi

# Abora Gaming Welcome is a deliberately separate app from Abora Welcome
# (see abora-gaming-welcome-gui.py's own module docstring for why) --
# the normal welcome only hands off to it via a button, it doesn't embed
# gaming-specific platform/sign-in UI itself.
if grep -q "class GamingWelcomeWindow" scripts/abora-gaming-welcome-gui.py \
  && grep -q "def read_gaming_catalog" scripts/abora-gaming-welcome-gui.py \
  && grep -q "category != 'Gaming'" scripts/abora-gaming-welcome-gui.py \
  && grep -q "'bottles', 'wine', 'winetricks', 'gamemode'" scripts/abora-gaming-welcome-gui.py \
  && grep -q "def _steam_installed" scripts/abora-gaming-welcome-gui.py \
  && grep -q "'Open Steam'" scripts/abora-gaming-welcome-gui.py \
  && grep -q "'Install Steam'" scripts/abora-gaming-welcome-gui.py \
  && grep -q "command_path('abora'), 'gaming', 'install', app_id" scripts/abora-gaming-welcome-gui.py \
	  && grep -q 'gaming enable && exec' scripts/abora-gaming-welcome-gui.py \
	  && grep -q 'command_path("abora-update")' scripts/abora-gaming-welcome-gui.py \
	  && grep -q 'lib.optional (gamingWelcomeGuiScript != null) aboraGamingWelcomeGui' nix/modules/installed-base.nix \
	  && grep -q 'lib.optional config.abora.gaming.enable aboraGamingWelcomeDesktopPkg' nix/modules/installed-base.nix \
	  && grep -q "GAMING_WELCOME_COMMAND" scripts/abora-welcome-gui.py \
	  && grep -q "'abora-gaming-welcome-gui'" scripts/abora-welcome-gui.py \
	  && grep -q "python3', fallback" scripts/abora-welcome-gui.py \
  && grep -q "_open_gaming_welcome" scripts/abora-welcome-gui.py \
  && grep -q "welcome)" scripts/abora-gaming.sh \
  && grep -q "launch_welcome" scripts/abora-gaming.sh \
  && grep -q "abora-gaming-welcome-gui" scripts/abora-gaming.sh; then
  pass "runtime: Abora Gaming Welcome is a separate app with a hand-off from Abora Welcome"
else
  fail "runtime: Abora Gaming Welcome is a separate app with a hand-off from Abora Welcome"
fi

if grep -q 'export GSK_RENDERER=' nix/modules/installed-base.nix \
  && grep -q 'export GDK_BACKEND=' nix/modules/installed-base.nix \
  && grep -q 'export GSK_RENDERER=' nix/profiles/live.nix \
  && grep -q 'export GDK_BACKEND=' nix/profiles/live.nix; then
  pass "runtime: installed GUI wrappers match live renderer/backend fallbacks"
else
  fail "runtime: installed GUI wrappers match live renderer/backend fallbacks"
fi

if grep -q 'writeShellScriptBin "abora-gaming-welcome-gui"' nix/modules/installed-base.nix \
  && grep -q 'writeShellScriptBin "abora-gaming-welcome-gui"' nix/profiles/live.nix \
  && grep -q 'export ABORA_APPS_SCRIPT=' nix/modules/installed-base.nix \
  && grep -q 'export ABORA_APPS_SCRIPT=' nix/profiles/live.nix \
  && grep -q 'export ABORA_APP_CATALOG=' nix/modules/installed-base.nix \
  && grep -q 'export ABORA_APP_CATALOG=' nix/profiles/live.nix \
  && grep -q 'exec .*gaming-welcome-gui.py' nix/modules/installed-base.nix \
  && grep -q 'exec .*gaming-welcome-gui.py' nix/profiles/live.nix \
  && grep -q 'abora/gaming-welcome-gui.py".source' nix/modules/installed-base.nix \
  && grep -q 'abora/gaming-welcome-gui.py".source' nix/profiles/live.nix \
  && grep -q 'aboraGaming' nix/profiles/live.nix \
  && grep -q 'aboraGamingWelcomeGui' nix/modules/installed-base.nix; then
  pass "runtime: live and installed systems both ship Gaming Welcome wrapper"
else
  fail "runtime: live and installed systems both ship Gaming Welcome wrapper"
fi

# Found by actually clicking through the gaming welcome GUI: the "Sign In"
# card treats Steam as installed via read_installed_apps() OR
# shutil.which('steam'), but the Platforms list's button only checked
# read_installed_apps() -- so a Steam installed outside Abora's own app
# tracking showed "Installed" in one place and a live "Install" button for
# the same app just below it. _set_platform_button_state must also fall
# back to _steam_installed() for the steam row.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "
import re
text = open('scripts/abora-gaming-welcome-gui.py').read()
m = re.search(r'def _set_platform_button_state.*?(?=\n    def )', text, re.S)
import sys
sys.exit(0 if m and '_steam_installed()' in m.group(0) else 1)
"; then
    pass "runtime: gaming welcome Platforms Steam row matches Sign In's installed detection"
  else
    fail "runtime: gaming welcome Platforms Steam row matches Sign In's installed detection"
  fi
fi

if python3 - <<'PY'
import re
from pathlib import Path
text = Path('scripts/abora-gaming-welcome-gui.py').read_text()
sudo = re.search(r'def sudo_prefix\(\).*?(?=\n\ndef )', text, re.S)
enable = re.search(r'def _enable_gaming\(self\).*?(?=\n    def )', text, re.S)
install = re.search(r'def _install\(self, app_id: str\).*?(?=\n    def )', text, re.S)
cmd = re.search(r'def command_path\(tool: str\).*?(?=\n\ndef )', text, re.S)
ok = (
    sudo and 'SUDO_ASKPASS' in sudo.group(0)
    and 'No graphical privilege helper found' in sudo.group(0)
    and enable and 'sudo_prefix_or_status(self)' in enable.group(0)
    and install and 'sudo_prefix_or_status(self)' in install.group(0)
    and cmd and "'abora': '/etc/abora/abora.sh'" in cmd.group(0)
    and cmd and "'abora-update': '/etc/abora/update.sh'" in cmd.group(0)
)
raise SystemExit(0 if ok else 1)
PY
then
  pass "runtime: gaming welcome handles missing GUI privilege helper cleanly"
else
  fail "runtime: gaming welcome handles missing GUI privilege helper cleanly"
fi

if python3 - <<'PY'
import re
from pathlib import Path
text = Path('scripts/abora-gaming-welcome-gui.py').read_text()
formatter = re.search(r'def command_failure_message\(proc: subprocess.CompletedProcess\).*?(?=\n\ndef )', text, re.S)
runner = re.search(r'def _run_background\(self, label: str, command: list\[str\], on_done\).*?(?=\n    def )', text, re.S)
done = re.search(r'def _on_background_done\(self, ok: bool, message: str, on_done\).*?(?=\n    def )', text, re.S)
ok = (
    'ABORA_GAMING_WELCOME_TIMEOUT' in text
    and formatter
    and 'proc.stdout' in formatter.group(0)
    and 'proc.stderr' in formatter.group(0)
    and 'Failed — run abora gaming doctor or abora logs' in formatter.group(0)
    and 'fetcher-cache.*sqlite' in formatter.group(0)
    and 'local fetch-cache disk I/O error' in formatter.group(0)
    and 'abora gaming repair-cache' in formatter.group(0)
    and 'nix-collect-garbage -d' in formatter.group(0)
    and runner
    and 'command_failure_message(proc)' in runner.group(0)
    and 'COMMAND_TIMEOUT_SECONDS' in runner.group(0)
    and 'subprocess.TimeoutExpired' in runner.group(0)
    and 'slow connection or cold cache' in runner.group(0)
    and '_set_busy(True)' in runner.group(0)
    and done
    and '_refresh_buttons()' in done.group(0)
    and '_set_busy(False)' in done.group(0)
    and 'Gaming Doctor' in text
    and "['doctor']" in text
    and 'Repair Nix Cache' in text
    and "['repair-cache']" in text
    and 'def _run_local_tool' in text
)
raise SystemExit(0 if ok else 1)
PY
then
  pass "runtime: gaming welcome shows app-manager failures, repair tools, and locks duplicate actions"
else
  fail "runtime: gaming welcome shows app-manager failures, repair tools, and locks duplicate actions"
fi

tmp_gaming_config="$(mktemp -d)"
tmp_gaming_module="$tmp_gaming_config/abora-local.nix"
cat > "$tmp_gaming_module" <<'EOF'
{ config, ... }:
{
  abora.hostname = "abora";
  abora.locale = "en_US.UTF-8";
  abora.timezone = "UTC";
  abora.keyboard.console = "us";
  abora.keyboard.xkb = "us";
  abora.desktop = "cosmic";
  abora.wallpaper = "titlis-alps.jpg";
  abora.gpu = "none";
  abora.stateVersion = "26.05";
  abora.gaming.enable = false;
  abora.gaming.steam = false;
  abora.gaming.bigPictureShortcut = false;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.controllerSupport = false;
  abora.gaming.mangohud = false;
  abora.gaming.gamemode = false;
  abora.gaming.vulkanTools = false;
  abora.gaming.launchers = false;
  abora.user.name = "abora";
  abora.user.hashedPassword = "";
  abora.disk = null;
}
EOF
if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh enable >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.mangohud = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.gamemode = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.vulkanTools = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh gamescope on >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh autostart off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh autostart on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureAutostart = true;' "$tmp_gaming_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh controllers off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh mangohud off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh gamemode off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh vulkan off >/dev/null 2>&1 \
	  && PATH="/usr/bin:/bin" \
	    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
	    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
	    bash scripts/abora-gaming.sh launchers off >/dev/null 2>&1 \
	  && PATH="/usr/bin:/bin" \
	    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
	    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
	    bash scripts/abora-gaming.sh disable >/dev/null 2>&1 \
	  && grep -q 'abora.gaming.enable = false;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_module" \
	  && PATH="/usr/bin:/bin" \
	    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
	    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
	    bash scripts/abora-gaming.sh enable >/dev/null 2>&1 \
	  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.gamescopeSession = false;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.mangohud = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.gamemode = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.vulkanTools = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_module"; then
  pass "runtime: abora gaming toggles write config"
else
  fail "runtime: abora gaming toggles write config"
fi

if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh bigpicture off >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_module" \
  && bash scripts/abora-gaming.sh help 2>&1 | grep -q 'abora gaming big-picture' \
  && bash scripts/abora-gaming.sh help 2>&1 | grep -q 'abora gaming steam on|off'; then
  pass "runtime: abora gaming exposes friendly Big Picture commands"
else
  fail "runtime: abora gaming exposes friendly Big Picture commands"
fi

tmp_gaming_parent_config="$(mktemp -d)"
tmp_gaming_parent_module="$tmp_gaming_parent_config/abora-local.nix"
cp "$tmp_gaming_module" "$tmp_gaming_parent_module"
if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh big-picture on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh autostart on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureAutostart = true;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh gamescope on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.gamescopeSession = true;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh steam off >/dev/null 2>&1 \
  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.gamescopeSession = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.controllerSupport = false;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh steam on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_gaming_parent_module"; then
  pass "runtime: abora gaming launcher commands enable required parent options"
else
  fail "runtime: abora gaming launcher commands enable required parent options"
fi

tmp_gaming_status_path="$(mktemp -d)"
touch "$tmp_gaming_status_path/gamemoderun" "$tmp_gaming_status_path/heroic-games-launcher"
chmod +x "$tmp_gaming_status_path/gamemoderun" "$tmp_gaming_status_path/heroic-games-launcher"
cat > "$tmp_gaming_status_path/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/test 10000000 3000000 7000000 30%% /nix/store\n'
EOF
chmod +x "$tmp_gaming_status_path/df"
tmp_gaming_status_out="$tmp_ok/gaming-status.out"
if PATH="$tmp_gaming_status_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh status >"$tmp_gaming_status_out" 2>&1 \
  && grep -q 'GameMode: installed' "$tmp_gaming_status_out" \
  && grep -q 'Heroic: installed' "$tmp_gaming_status_out" \
  && ! grep -q 'GameMode: missing' "$tmp_gaming_status_out" \
  && grep -q 'print_status_any "GameMode" gamemoderun gamemoded' scripts/abora-gaming.sh; then
  pass "runtime: abora gaming status accepts common command aliases"
else
  fail "runtime: abora gaming status accepts common command aliases"
fi

tmp_gaming_doctor_out="$tmp_ok/gaming-doctor.out"
if PATH="$tmp_gaming_status_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh doctor >"$tmp_gaming_doctor_out" 2>&1 \
  && grep -q 'Gaming layer:' "$tmp_gaming_doctor_out" \
  && grep -q 'Big Picture autostart:' "$tmp_gaming_doctor_out" \
  && grep -q 'Controller support:' "$tmp_gaming_doctor_out" \
  && grep -q 'MangoHud option:' "$tmp_gaming_doctor_out" \
  && grep -q 'GameMode option:' "$tmp_gaming_doctor_out" \
  && grep -q 'Vulkan tools option:' "$tmp_gaming_doctor_out" \
  && grep -q 'Launcher bundle:' "$tmp_gaming_doctor_out" \
  && grep -q 'Low free space near' "$tmp_gaming_doctor_out" \
  && grep -q 'nix-collect-garbage -d' "$tmp_gaming_doctor_out" \
  && grep -Eq 'abora gaming (install steam|big-picture)' "$tmp_gaming_doctor_out"; then
  pass "runtime: abora gaming doctor reports all gaming config toggles"
else
  fail "runtime: abora gaming doctor reports all gaming config toggles"
fi

tmp_gaming_cache_home="$(mktemp -d)"
mkdir -p "$tmp_gaming_cache_home/.cache/nix"
touch "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite" \
  "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite-wal"
tmp_gaming_cache_out="$tmp_ok/gaming-repair-cache.out"
if HOME="$tmp_gaming_cache_home" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh repair-cache >"$tmp_gaming_cache_out" 2>&1 \
  && grep -q 'Cleared local Nix fetch cache files' "$tmp_gaming_cache_out" \
  && [[ ! -e "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite" ]] \
  && [[ ! -e "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite-wal" ]]; then
  pass "runtime: abora gaming repair-cache clears stale Nix fetch cache files"
else
  fail "runtime: abora gaming repair-cache clears stale Nix fetch cache files"
fi

tmp_gaming_logs_path="$(mktemp -d)"
tmp_gaming_logs_out="$tmp_ok/gaming-logs.out"
cat > "$tmp_gaming_logs_path/abora" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*"
EOF
chmod +x "$tmp_gaming_logs_path/abora"
if PATH="$tmp_gaming_logs_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh logs 77 >"$tmp_gaming_logs_out" 2>&1 \
  && grep -qx 'logs --lines 77' "$tmp_gaming_logs_out" \
  && grep -q 'abora gaming logs' scripts/abora-gaming.sh; then
  pass "runtime: abora gaming logs delegates to abora logs"
else
  fail "runtime: abora gaming logs delegates to abora logs"
fi

tmp_gaming_path="$(mktemp -d)"
cat > "$tmp_gaming_path/abora-apps" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  case "${2:-}" in
    steam|lutris|heroic|bottles|wine|winetricks|gamemode|mangohud) exit 0 ;;
    *) exit 1 ;;
  esac
fi
printf '%s\n' "$*" > "$ABORA_GAMING_APPS_LOG"
EOF
chmod +x "$tmp_gaming_path/abora-apps"
tmp_gaming_apps_log="$tmp_ok/gaming-apps.log"
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steam >/dev/null 2>&1 \
  && grep -q '^add steam$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
  && PATH="$tmp_gaming_path:/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
    bash scripts/abora-gaming.sh uninstall steam >/dev/null 2>&1 \
  && grep -q '^remove steam$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.gamescopeSession = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.controllerSupport = false;' "$tmp_gaming_module"; then
  pass "runtime: abora gaming install/remove delegates to app manager"
else
  fail "runtime: abora gaming install/remove delegates to app manager"
fi

tmp_gaming_fail_path="$(mktemp -d)"
cat > "$tmp_gaming_fail_path/abora-apps" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  [[ "${2:-}" == "steam" ]] && exit 0
  exit 1
fi
printf '%s\n' "$*" > "$ABORA_GAMING_APPS_LOG"
exit 1
EOF
chmod +x "$tmp_gaming_fail_path/abora-apps"
tmp_gaming_fail_config="$(mktemp -d)"
tmp_gaming_fail_module="$tmp_gaming_fail_config/abora-local.nix"
cat > "$tmp_gaming_fail_module" <<'EOF'
{ config, ... }:
{
  abora.gaming.enable = false;
  abora.gaming.steam = false;
  abora.gaming.bigPictureShortcut = false;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.controllerSupport = false;
  abora.gaming.mangohud = false;
  abora.gaming.gamemode = false;
  abora.gaming.vulkanTools = false;
  abora.gaming.launchers = false;
}
EOF
cp "$tmp_gaming_fail_module" "$tmp_ok/gaming-failed-install.before"
if PATH="$tmp_gaming_fail_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_fail_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_ok/gaming-failed-apps.log" \
  bash scripts/abora-gaming.sh install steam >/tmp/abora-gaming-failed-install.out 2>&1; then
  fail "runtime: abora gaming restores toggles when app install fails"
elif cmp -s "$tmp_gaming_fail_module" "$tmp_ok/gaming-failed-install.before" \
  && grep -q 'Restored previous gaming settings because the app install failed' /tmp/abora-gaming-failed-install.out; then
  pass "runtime: abora gaming restores toggles when app install fails"
else
  fail "runtime: abora gaming restores toggles when app install fails"
  sed 's/^/              /' /tmp/abora-gaming-failed-install.out
fi
rm -rf "$tmp_gaming_fail_path" "$tmp_gaming_fail_config"

tmp_gaming_remove_fail_path="$(mktemp -d)"
cat > "$tmp_gaming_remove_fail_path/abora-apps" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  [[ "${2:-}" == "steam" ]] && exit 0
  exit 1
fi
printf '%s\n' "$*" > "$ABORA_GAMING_APPS_LOG"
exit 1
EOF
chmod +x "$tmp_gaming_remove_fail_path/abora-apps"
tmp_gaming_remove_fail_config="$(mktemp -d)"
tmp_gaming_remove_fail_module="$tmp_gaming_remove_fail_config/abora-local.nix"
cat > "$tmp_gaming_remove_fail_module" <<'EOF'
{ config, ... }:
{
  abora.gaming.enable = true;
  abora.gaming.steam = true;
  abora.gaming.bigPictureShortcut = true;
  abora.gaming.bigPictureAutostart = true;
  abora.gaming.gamescopeSession = true;
  abora.gaming.controllerSupport = true;
  abora.gaming.mangohud = true;
  abora.gaming.gamemode = true;
  abora.gaming.vulkanTools = true;
  abora.gaming.launchers = true;
}
EOF
cp "$tmp_gaming_remove_fail_module" "$tmp_ok/gaming-failed-remove.before"
if PATH="$tmp_gaming_remove_fail_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_remove_fail_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_ok/gaming-failed-remove-apps.log" \
  bash scripts/abora-gaming.sh remove steam >/tmp/abora-gaming-failed-remove.out 2>&1; then
  fail "runtime: abora gaming restores toggles when app removal fails"
elif cmp -s "$tmp_gaming_remove_fail_module" "$tmp_ok/gaming-failed-remove.before" \
  && grep -q 'Restored previous gaming settings because the app removal failed' /tmp/abora-gaming-failed-remove.out; then
  pass "runtime: abora gaming restores toggles when app removal fails"
else
  fail "runtime: abora gaming restores toggles when app removal fails"
  sed 's/^/              /' /tmp/abora-gaming-failed-remove.out
fi
rm -rf "$tmp_gaming_remove_fail_path" "$tmp_gaming_remove_fail_config"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install wine winetricks --dry-run >/dev/null 2>&1 \
  && grep -q '^add wine winetricks --dry-run$' "$tmp_gaming_apps_log"; then
  pass "runtime: abora gaming install accepts Wine tooling"
else
  fail "runtime: abora gaming install accepts Wine tooling"
fi

tmp_gaming_lean_config="$(mktemp -d)"
tmp_gaming_lean_module="$tmp_gaming_lean_config/abora-local.nix"
cat > "$tmp_gaming_lean_module" <<'EOF'
{ config, ... }:
{
  abora.gaming.enable = false;
  abora.gaming.steam = false;
  abora.gaming.bigPictureShortcut = false;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.controllerSupport = false;
  abora.gaming.mangohud = false;
  abora.gaming.gamemode = false;
  abora.gaming.vulkanTools = false;
  abora.gaming.launchers = false;
}
EOF
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_lean_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install wine >/dev/null 2>&1 \
  && grep -q '^add wine$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.mangohud = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.gamemode = false;' "$tmp_gaming_lean_module"; then
  pass "runtime: abora gaming install enables only the needed feature family"
else
  fail "runtime: abora gaming install enables only the needed feature family"
fi

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_lean_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install mangohud gamemode >/dev/null 2>&1 \
  && grep -q 'abora.gaming.mangohud = true;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.gamemode = true;' "$tmp_gaming_lean_module" \
  && PATH="$tmp_gaming_path:/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_lean_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
    bash scripts/abora-gaming.sh remove wine mangohud gamemode >/dev/null 2>&1 \
  && grep -q '^remove wine mangohud gamemode$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.launchers = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.mangohud = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.gamemode = false;' "$tmp_gaming_lean_module"; then
  pass "runtime: abora gaming remove disables reinstalling feature families"
else
  fail "runtime: abora gaming remove disables reinstalling feature families"
fi

tmp_gaming_before_stale_remove="$tmp_ok/gaming-before-stale-remove.nix"
cp "$tmp_gaming_module" "$tmp_gaming_before_stale_remove"
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh remove stale-removed-app >/dev/null 2>&1 \
  && grep -q '^remove stale-removed-app$' "$tmp_gaming_apps_log" \
  && cmp -s "$tmp_gaming_module" "$tmp_gaming_before_stale_remove"; then
  pass "runtime: abora gaming remove lets app manager clean stale ids"
else
  fail "runtime: abora gaming remove lets app manager clean stale ids"
fi

tmp_gaming_before_bad="$tmp_ok/gaming-before-bad.nix"
cp "$tmp_gaming_module" "$tmp_gaming_before_bad"
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steem >/tmp/abora-gaming-bad-app.out 2>&1; then
  fail "runtime: abora gaming rejects unknown apps before writing config"
elif cmp -s "$tmp_gaming_module" "$tmp_gaming_before_bad"; then
  pass "runtime: abora gaming rejects unknown apps before writing config"
else
  fail "runtime: abora gaming rejects unknown apps before writing config"
fi

tmp_gaming_before_dry="$tmp_ok/gaming-before-dry.nix"
cp "$tmp_gaming_module" "$tmp_gaming_before_dry"
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steam --dry-run >/dev/null 2>&1 \
  && cmp -s "$tmp_gaming_module" "$tmp_gaming_before_dry"; then
  pass "runtime: abora gaming install --dry-run is read-only"
else
  fail "runtime: abora gaming install --dry-run is read-only"
fi

tmp_gaming_before_flag="$tmp_ok/gaming-before-flag.nix"
cp "$tmp_gaming_module" "$tmp_gaming_before_flag"
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steam --not-a-real-option >/tmp/abora-gaming-bad-flag.out 2>&1; then
  fail "runtime: abora gaming rejects unknown install flags before writing config"
elif cmp -s "$tmp_gaming_module" "$tmp_gaming_before_flag"; then
  pass "runtime: abora gaming rejects unknown install flags before writing config"
else
  fail "runtime: abora gaming rejects unknown install flags before writing config"
fi

tmp_gaming_before="$tmp_ok/gaming-before.nix"
cp "$tmp_gaming_module" "$tmp_gaming_before"
if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install >/tmp/abora-gaming-noarg.out 2>&1; then
  fail "runtime: abora gaming install without an app is read-only"
elif cmp -s "$tmp_gaming_module" "$tmp_gaming_before"; then
  pass "runtime: abora gaming install without an app is read-only"
else
  fail "runtime: abora gaming install without an app is read-only"
fi

if grep -q 'writeShellScriptBin "abora-steam-big-picture"' nix/modules/abora-options.nix \
  && grep -q 'steam steam://open/bigpicture' nix/modules/abora-options.nix \
  && grep -q 'steam -gamepadui' nix/modules/abora-options.nix \
  && grep -q 'exec steam -bigpicture' nix/modules/abora-options.nix \
  && grep -q 'Steam Gamepad UI failed; trying legacy Big Picture mode' nix/modules/abora-options.nix \
  && grep -q 'Exec=abora-steam-big-picture' nix/modules/abora-options.nix \
  && grep -q 'writeShellScriptBin "abora-steam-gamescope-session"' nix/modules/abora-options.nix \
  && grep -q 'gamescope -e -f -- abora-steam-big-picture --session' nix/modules/abora-options.nix \
  && grep -q 'Exec=abora-steam-gamescope-session' nix/modules/abora-options.nix \
  && grep -q 'abora-steam-gamescope-session' docs/wiki/Abora-Gaming.md \
  && grep -q 'cfg.gaming.steam && cfg.gaming.bigPictureShortcut' nix/modules/abora-options.nix \
  && grep -q 'cfg.gaming.steam && cfg.gaming.gamescopeSession' nix/modules/abora-options.nix \
  && grep -q 'cfg.gaming.steam && cfg.gaming.bigPictureAutostart' nix/modules/abora-options.nix \
  && ! grep -q '^[[:space:]]\+\[Desktop Entry\]' nix/modules/abora-options.nix \
  && grep -q 'programs.steam.enable = lib.mkDefault true' nix/modules/abora-options.nix \
  && grep -q 'gaming.steam' scripts/abora-config.sh \
  && grep -q 'gaming.controllers' scripts/abora-config.sh \
  && grep -q 'gaming.launchers' scripts/abora-gaming.sh \
  && grep -q 'session|gamescope-session' scripts/abora-gaming.sh \
  && grep -q 'pkgIf cfg.gaming.vulkanTools "vulkan-tools"' nix/modules/abora-options.nix \
  && grep -q 'pkgIf cfg.gaming.launchers "winetricks"' nix/modules/abora-options.nix \
  && grep -q 'wineIf cfg.gaming.launchers' nix/modules/abora-options.nix \
  && grep -q 'Run: abora gaming install steam' nix/modules/abora-options.nix \
  && grep -q 'steam steam://open/bigpicture' scripts/abora-gaming.sh \
  && grep -q 'steam -gamepadui' scripts/abora-gaming.sh \
  && grep -q 'Steam Gamepad UI failed; trying legacy Big Picture mode' scripts/abora-gaming.sh \
  && grep -q 'gamescope -e -f --' scripts/abora-gaming.sh \
  && grep -q 'Run: abora gaming install steam' scripts/abora-gaming.sh; then
  pass "runtime: Abora Gaming Big Picture launcher has Steam flag fallback"
else
  fail "runtime: Abora Gaming Big Picture launcher has Steam flag fallback"
fi

if python3 - <<'PY'
import re
from pathlib import Path
text = Path('nix/modules/abora-options.nix').read_text()

def desktop_text(var):
    m = re.search(rf'{var}\s*=\s*pkgs\.writeTextFile\s*\{{.*?text\s*=\s*\'\'\n(.*?)\n\s*\'\';\n\s*\}};', text, re.S)
    return m.group(1) if m else ''

launcher = desktop_text('steamBigPictureDesktop')
session = desktop_text('gamescopeSessionDesktop')
autostart = re.search(r'environment\.etc\."xdg/autostart/abora-steam-big-picture\.desktop"\.text\s*=\s*\'\'\n(.*?)\n\s*\'\';', text, re.S)
autostart_text = autostart.group(1) if autostart else ''

def has_lines(block, *lines):
    return all(line in block for line in lines)

ok = (
    has_lines(
        launcher,
        '[Desktop Entry]',
        'Type=Application',
        'Name=Steam Big Picture',
        'Exec=abora-steam-big-picture',
        'Icon=steam',
        'Categories=Game;',
        'Terminal=false',
    )
    and has_lines(
        session,
        '[Desktop Entry]',
        'Type=Application',
        'Name=Abora Gaming',
        'Exec=abora-steam-gamescope-session',
    )
    and has_lines(
        autostart_text,
        '[Desktop Entry]',
        'Type=Application',
        'Exec=abora-steam-big-picture',
        'X-GNOME-Autostart-enabled=true',
    )
)
raise SystemExit(0 if ok else 1)
PY
then
  pass "runtime: Abora Gaming desktop/session entries keep required fields"
else
  fail "runtime: Abora Gaming desktop/session entries keep required fields"
fi

tmp_steam_path="$(mktemp -d)"
tmp_steam_log="$tmp_ok/steam-big-picture.log"
cat > "$tmp_steam_path/steam" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$tmp_steam_log"
case "\$*" in
  steam://open/bigpicture|-gamepadui*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp_steam_path/steam"
: > "$tmp_steam_log"
if PATH="$tmp_steam_path:/usr/bin:/bin" bash scripts/abora-gaming.sh big-picture >/dev/null 2>&1 \
  && grep -qx 'steam://open/bigpicture' "$tmp_steam_log" \
  && : > "$tmp_steam_log" \
  && PATH="$tmp_steam_path:/usr/bin:/bin" bash scripts/abora-gaming.sh big-picture --session >/dev/null 2>&1 \
  && grep -qx -- '-gamepadui' "$tmp_steam_log" \
  && [[ "$(wc -l < "$tmp_steam_log" | tr -d ' ')" == "1" ]] \
  && : > "$tmp_steam_log" \
  && PATH="$tmp_steam_path:/usr/bin:/bin" bash scripts/abora-gaming.sh session >/dev/null 2>&1 \
  && grep -qx -- '-gamepadui' "$tmp_steam_log" \
  && [[ "$(wc -l < "$tmp_steam_log" | tr -d ' ')" == "1" ]]; then
  pass "runtime: Abora Gaming Big Picture uses desktop URI and session-safe Steam mode"
else
  fail "runtime: Abora Gaming Big Picture uses desktop URI and session-safe Steam mode"
fi

tmp_steam_fallback_path="$(mktemp -d)"
tmp_steam_fallback_log="$tmp_ok/steam-big-picture-fallback.log"
cat > "$tmp_steam_fallback_path/steam" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$tmp_steam_fallback_log"
case "\$*" in
  -bigpicture*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp_steam_fallback_path/steam"
: > "$tmp_steam_fallback_log"
if PATH="$tmp_steam_fallback_path:/usr/bin:/bin" bash scripts/abora-gaming.sh big-picture --session >/tmp/steam-big-picture-fallback.out 2>&1 \
  && grep -qx -- '-gamepadui' "$tmp_steam_fallback_log" \
  && grep -qx -- '-bigpicture' "$tmp_steam_fallback_log" \
  && grep -q 'trying legacy Big Picture mode' /tmp/steam-big-picture-fallback.out; then
  pass "runtime: Abora Gaming Big Picture explains legacy fallback"
else
  fail "runtime: Abora Gaming Big Picture explains legacy fallback"
fi

tmp_dotfiles_src="$(mktemp -d)"
tmp_dotfiles_home="$(mktemp -d)"
tmp_dotfiles_cache="$(mktemp -d)"
mkdir -p "$tmp_dotfiles_src/.config/hypr" "$tmp_dotfiles_src/.config/waybar" "$tmp_dotfiles_home"
printf 'source-dotfile\n' > "$tmp_dotfiles_src/.zshrc"
printf 'hyprland config\n' > "$tmp_dotfiles_src/.config/hypr/hyprland.conf"
printf 'existing\n' > "$tmp_dotfiles_home/.zshrc"
git -C "$tmp_dotfiles_src" init >/dev/null 2>&1
git -C "$tmp_dotfiles_src" config user.email test@example.invalid
git -C "$tmp_dotfiles_src" config user.name "Abora Test"
git -C "$tmp_dotfiles_src" add . >/dev/null
git -C "$tmp_dotfiles_src" commit -m dotfiles >/dev/null 2>&1
dotfiles_dry_run_out="$(HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh --dry-run "$tmp_dotfiles_src" 2>&1)"
if grep -q 'would copy' <<<"$dotfiles_dry_run_out" \
  && HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh "$tmp_dotfiles_src" >/dev/null \
  && grep -q 'existing' "$tmp_dotfiles_home/.zshrc" \
  && grep -q 'hyprland config' "$tmp_dotfiles_home/.config/hypr/hyprland.conf" \
  && HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh --replace "$tmp_dotfiles_src" >/dev/null \
  && grep -q 'source-dotfile' "$tmp_dotfiles_home/.zshrc" \
  && HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh \
      --git-url "file://$tmp_dotfiles_src" "$tmp_dotfiles_cache/checkout" >/dev/null 2>&1 \
  && [[ -d "$tmp_dotfiles_cache/checkout/.git" ]] \
  && grep -q 'source-dotfile' "$tmp_dotfiles_cache/checkout/.zshrc" \
  && mkdir -p "$tmp_dotfiles_cache/abora-dotfiles" \
  && printf 'stale\n' > "$tmp_dotfiles_cache/abora-dotfiles/partial" \
  && HOME="$tmp_dotfiles_home" XDG_CACHE_HOME="$tmp_dotfiles_cache" \
    bash scripts/abora-dotfiles-import.sh \
      --git-url "file://$tmp_dotfiles_src" "$tmp_dotfiles_cache/abora-dotfiles" >/dev/null 2>&1 \
  && [[ ! -e "$tmp_dotfiles_cache/abora-dotfiles/partial" ]] \
  && [[ -d "$tmp_dotfiles_cache/abora-dotfiles/.git" ]] \
  && mkdir -p "$tmp_dotfiles_cache/manual-nonempty" \
  && printf 'keep\n' > "$tmp_dotfiles_cache/manual-nonempty/file" \
  && ! HOME="$tmp_dotfiles_home" XDG_CACHE_HOME="$tmp_dotfiles_cache" \
    bash scripts/abora-dotfiles-import.sh \
      --git-url "file://$tmp_dotfiles_src" "$tmp_dotfiles_cache/manual-nonempty" >/dev/null 2>&1 \
  && grep -q 'keep' "$tmp_dotfiles_cache/manual-nonempty/file"; then
  pass "runtime: dotfiles importer preserves by default and replaces on request"
else
  fail "runtime: dotfiles importer preserves by default and replaces on request"
fi
rm -rf "$tmp_dotfiles_src" "$tmp_dotfiles_home" "$tmp_dotfiles_cache"

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set hostname 'not a valid host!' >/dev/null 2>&1; then
  fail "runtime: abora config set rejects an invalid hostname"
elif grep -q 'abora.hostname = "not a valid host!"' "$tmp_config_module"; then
  fail "runtime: abora config set rejects an invalid hostname"
else
  pass "runtime: abora config set rejects an invalid hostname"
fi

# user/disk are deliberately absent from do_set's key case, falling through
# to "Unknown key" -- that's the actual read-only enforcement mechanism.
set +e
config_user_out="$(
  ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set user someone 2>&1
)"
config_user_status=$?
set -e
if [[ "$config_user_status" -eq 0 ]] || ! grep -q "Unknown key" <<<"$config_user_out"; then
  fail "runtime: abora config set rejects the read-only 'user' key"
elif grep -q 'abora.user.name = "someone"' "$tmp_config_module"; then
  fail "runtime: abora config set rejects the read-only 'user' key"
else
  pass "runtime: abora config set rejects the read-only 'user' key"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set disk /dev/sda >/dev/null 2>&1; then
  fail "runtime: abora config set rejects the read-only 'disk' key"
else
  pass "runtime: abora config set rejects the read-only 'disk' key"
fi

# Belt-and-suspenders injection guard: a value carrying '"', '\', or '${'
# could otherwise break out of the Nix double-quoted string it's written
# into.
if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set wallpaper '"; evil = true; "' >/dev/null 2>&1; then
  fail "runtime: abora config set rejects a Nix-breaking value"
elif grep -q "evil" "$tmp_config_module"; then
  fail "runtime: abora config set rejects a Nix-breaking value"
else
  pass "runtime: abora config set rejects a Nix-breaking value"
fi

# Legacy (pre-v2.5) abora-local.nix used raw NixOS options instead of the
# abora.* module — do_set migrates it in place on first write.
tmp_legacy_config="$(mktemp -d)"
tmp_legacy_module="$tmp_legacy_config/abora-local.nix"
cat > "$tmp_legacy_module" <<'EOF'
{ ... }:
{
  networking.hostName = "legacybox";
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
  services.desktopManager.gnome.enable = true;
  users.users."quinn" = {
    hashedPassword = "!";
  };
  system.stateVersion = "26.05";
}
EOF
# Regression test: the username fixture here used to be "abora" -- the
# exact string migrate_legacy_config's (previously broken) username regex
# silently fell back to on a match failure, so a real extraction bug could
# never have been caught by this test no matter what the regex actually
# did. Using a distinct name ("quinn") and asserting on it directly closes
# that gap.
if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_legacy_config" \
  scripts/abora-config.sh set hostname migrated-host >/dev/null 2>&1 \
	  && grep -q 'abora.hostname = "migrated-host";' "$tmp_legacy_module" \
	  && grep -q 'abora.desktop = "gnome";' "$tmp_legacy_module" \
	  && grep -q 'abora.user.name = "quinn";' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.mangohud = true;' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.gamemode = true;' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.launchers = true;' "$tmp_legacy_module" \
	  && compgen -G "${tmp_legacy_module}.legacy.*" >/dev/null; then
  pass "runtime: abora config migrates a legacy abora-local.nix on write"
else
  fail "runtime: abora config migrates a legacy abora-local.nix on write"
fi

# Security regression test: abora-local.nix carries a hashedPassword field
# (see the fixture above and abora-installer.sh's own generation of this
# file) -- it must never be world-readable, or any local user on the
# machine could read the hash straight out of /etc/nixos and run an
# offline attack against it, exactly what /etc/shadow's own restrictive
# permissions exist to prevent. The migration path above used to leave it
# 0644 (and its .legacy.* backup, via a plain `cp` that doesn't preserve
# source permissions on a new destination, at whatever the umask gives).
# Checks both the migrated file and its backup are 0600.
_migrated_mode="$(stat -c '%a' "$tmp_legacy_module" 2>/dev/null || echo unknown)"
_backup_path="$(compgen -G "${tmp_legacy_module}.legacy.*" | head -n1)"
_backup_mode="$(stat -c '%a' "$_backup_path" 2>/dev/null || echo unknown)"
if [[ "$_migrated_mode" == "600" && "$_backup_mode" == "600" ]]; then
  pass "runtime: migrated abora-local.nix and its legacy backup are 0600, not world-readable"
else
  fail "runtime: migrated abora-local.nix and its legacy backup are 0600, not world-readable"
  printf '              migrated=%s backup=%s\n' "$_migrated_mode" "$_backup_mode"
fi

# Same fixed-file guarantee for the installer's own first-time creation
# path (abora-installer.sh, not the config-migration path above).
if grep -q 'chmod 0600 "\${cfgdir}/abora-local.nix"' scripts/abora-installer.sh; then
  pass "runtime: installer chmods a freshly-created abora-local.nix to 0600"
else
  fail "runtime: installer chmods a freshly-created abora-local.nix to 0600"
fi

# Static check for the self-elevation guard itself (abora-config.sh, right
# after local_module is defined): a non-owning, non-root user reading a
# now-0600 abora-local.nix needs this to `exec sudo "$0" "$@"` rather than
# every scattered read call site (read_option, desktop/GPU detection, the
# legacy migration, ...) failing or silently reading nothing. Not
# exercised dynamically below -- doing that safely would mean either a
# real interactive sudo prompt (hangs this suite) or mocking sudo, neither
# worth it for one guard clause; this at least catches the guard being
# deleted or its condition broken.
if grep -q 'ABORA_NO_SUDO:-0.*!= "1".*&&.*-f "\$local_module".*&&.*! -r "\$local_module"' scripts/abora-config.sh \
  && grep -q 'exec sudo "\$0" "\$@"' scripts/abora-config.sh; then
  pass "runtime: abora-config.sh self-elevates via sudo when abora-local.nix isn't readable"
else
  fail "runtime: abora-config.sh self-elevates via sudo when abora-local.nix isn't readable"
fi

# Security regression test: separately from whether elevation happens,
# abora-config.sh must never silently succeed with empty/wrong data when
# abora-local.nix can't be read at all (e.g. elevation is unavailable, or
# -- as simulated here via ABORA_NO_SUDO=1, the same switch every other
# test in this suite already relies on to avoid a real sudo prompt -- it's
# deliberately skipped). A genuinely unreadable file (chmod 000, unreadable
# even to its own owner) must make abora-config.sh fail closed.
tmp_unreadable_config="$(mktemp -d)"
tmp_unreadable_module="$tmp_unreadable_config/abora-local.nix"
printf '{ abora.hostname = "x"; }\n' > "$tmp_unreadable_module"
chmod 000 "$tmp_unreadable_module"
set +e
_unreadable_out="$(ABORA_NO_SUDO=1 ABORA_SYSTEM_CONFIG="$tmp_unreadable_config" \
  scripts/abora-config.sh show 2>&1)"
_unreadable_status=$?
set -e
chmod 600 "$tmp_unreadable_module"
rm -rf "$tmp_unreadable_config"
if [[ "$_unreadable_status" -ne 0 ]]; then
  pass "runtime: abora config fails closed (not silently) against an unreadable abora-local.nix"
else
  fail "runtime: abora config fails closed (not silently) against an unreadable abora-local.nix"
  printf '              output: %s\n' "$_unreadable_out"
fi

# Static guard for a real fix that isn't cheap to verify behaviorally in
# this suite (it needs a full NixOS module eval realizing abora-options.nix's
# package references, which takes minutes -- verified manually instead, see
# the commit that introduced this line): anix.nix's "anix.gaming.* is set
# but anix.gaming.enable isn't true" warning used to fire even when
# abora.gaming.enable was already true from another source (the common real
# sequence: installer sets it in abora-local.nix, then `anix enable
# gaming.vulkan` only touches anix.gaming.vulkanTools) -- a false-positive
# warning on every single rebuild of an entirely normal, working config.
# This just guards against the fix's condition being silently deleted.
if grep -q 'config.abora.gaming.enable != true' nix/modules/anix.nix \
  && grep -q 'abora.gaming.steam = lib.mkForce cfg.gaming.steam;' nix/modules/anix.nix \
  && grep -q 'abora.gaming.controllerSupport = lib.mkForce cfg.gaming.controllerSupport;' nix/modules/anix.nix \
  && grep -q 'abora.gaming.mangohud = lib.mkForce cfg.gaming.mangohud;' nix/modules/anix.nix \
  && grep -q 'abora.gaming.gamemode = lib.mkForce cfg.gaming.gamemode;' nix/modules/anix.nix \
  && grep -q 'abora.gaming.launchers = lib.mkForce cfg.gaming.launchers;' nix/modules/anix.nix \
  && grep -q 'gaming.steam|steam' scripts/anix.sh \
  && grep -q 'gaming.controllers|gaming.controller|gaming.controllerSupport' scripts/anix.sh \
  && grep -q 'gaming.launchers|launchers' scripts/anix.sh \
  && grep -q 'anix.gaming.steam = true;' scripts/anix.sh \
  && grep -q 'anix.gaming.launchers = true;' scripts/anix.sh \
  && grep -q 'write_anix_gaming_dependencies' scripts/anix.sh \
  && grep -q 'gaming.bigPictureAutostart' scripts/anix.sh; then
  pass "runtime: anix.nix gaming warning checks abora.gaming.enable, not just anix.gaming.enable"
else
  fail "runtime: anix.nix gaming warning checks abora.gaming.enable, not just anix.gaming.enable"
fi

# Regression test for a real, silent boot-breaking bug: `limine
# bios-install` fails outright ("no BIOS boot partition specified or
# detected", confirmed against a real `limine` binary) on a GPT disk with
# no bios_grub partition -- exactly what "use an existing partition" mode
# produces, since it never repartitions the disk at all. nixpkgs'
# limine-install.py never checks that subprocess's exit code, so the
# failure is completely silent: a Legacy-BIOS machine using this mode
# would end up with a fully unbootable install and no error anywhere.
# Fixed with a new abora.diskBiosSupport option the installer sets to
# false only for this mode (UEFI boot through the reused ESP is
# unaffected either way). Extracts the real conditional from
# abora-installer.sh and runs it directly for both modes, and confirms
# the option is both declared in abora-options.nix and actually written
# into the generated config.
tmp_bios_snippet="$(mktemp)"
sed -n '/^    # "Use an existing partition" mode never creates a bios_grub partition$/,/^    fi$/p' scripts/abora-installer.sh \
  > "$tmp_bios_snippet"
_bios_existing="$(install_disk_mode="existing"; . "$tmp_bios_snippet"; printf '%s' "$disk_bios_support_nix")"
_bios_erase="$(install_disk_mode="erase"; . "$tmp_bios_snippet"; printf '%s' "$disk_bios_support_nix")"
rm -f "$tmp_bios_snippet"

if [[ "$_bios_existing" == "false" ]] \
  && [[ "$_bios_erase" == "true" ]] \
  && grep -q 'abora.diskBiosSupport = ${disk_bios_support_nix};' scripts/abora-installer.sh \
  && grep -q 'diskBiosSupport = lib.mkOption' nix/modules/abora-options.nix \
  && grep -q 'biosSupport         = cfg.diskBiosSupport;' nix/modules/abora-options.nix; then
  pass "runtime: installer disables Limine BIOS install for the no-bios_grub-partition disk mode"
else
  fail "runtime: installer disables Limine BIOS install for the no-bios_grub-partition disk mode"
fi

# Regression test for validate_boot()'s BIOS-boot-partition check
# (_has_bios_boot_partition): validate_boot()'s existing bootloader check
# only confirmed limine-bios.sys was *copied* into /mnt/boot, which
# nixpkgs' limine-install.py does unconditionally before it runs the
# subprocess that can actually fail (`limine bios-install <device>`,
# confirmed to exit 1 on a GPT disk with no BIOS-boot partition -- see the
# disk-mode commit above) -- so the file's presence proved nothing about
# whether BIOS boot would actually work. Extracts the real
# _has_bios_boot_partition function (it depends on the shared lsblk -P
# parsing prelude, so pulls that in too) and exercises it against a fake
# lsblk on PATH for both the present and missing case.
tmp_biosboot_funcs="$(mktemp)"
tmp_lsblk_bin2="$(mktemp -d)"
{
  sed -n '/^readonly ESP_PARTTYPE_GUID=/,/^check_install_environment()/p' scripts/abora-installer.sh | sed '$d'
  sed -n '/^readonly BIOS_BOOT_PARTTYPE_GUID=/,/^validate_boot()/p' scripts/abora-installer.sh | sed '$d'
} > "$tmp_biosboot_funcs"
if [[ -s "$tmp_biosboot_funcs" ]] && bash -n "$tmp_biosboot_funcs" 2>/dev/null; then
  cat > "$tmp_lsblk_bin2/lsblk" <<'LSBLK_SHIM2'
#!/usr/bin/env bash
if [[ "${DISK_HAS_BIOSGRUB:-0}" == "1" ]]; then
  printf 'NAME="sda1" PARTTYPE="21686148-6449-6e6f-744e-656564454649" TYPE="part"\n'
  printf 'NAME="sda2" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
else
  printf 'NAME="sda1" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
  printf 'NAME="sda2" PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" TYPE="part"\n'
fi
LSBLK_SHIM2
  chmod +x "$tmp_lsblk_bin2/lsblk"

  if PATH="$tmp_lsblk_bin2:$PATH" DISK_HAS_BIOSGRUB=1 bash -c "source '$tmp_biosboot_funcs'; _has_bios_boot_partition /dev/sda" \
    && ! PATH="$tmp_lsblk_bin2:$PATH" DISK_HAS_BIOSGRUB=0 bash -c "source '$tmp_biosboot_funcs'; _has_bios_boot_partition /dev/sda"; then
    pass "runtime: _has_bios_boot_partition correctly detects a missing BIOS-boot partition"
  else
    fail "runtime: _has_bios_boot_partition correctly detects a missing BIOS-boot partition"
  fi
else
  fail "runtime: could not extract _has_bios_boot_partition from abora-installer.sh"
fi
rm -f "$tmp_biosboot_funcs"
rm -rf "$tmp_lsblk_bin2"

# Regression test: abora-repair-flake-purity.sh's post-repair `git add`
# used to be one call listing all four paths at once. `git add` fails (and
# stages NOTHING it was given, not just the bad pathspec) the instant one
# path doesn't match a real file -- and abora/desktops/mangowm.nix doesn't
# exist on installs from before nix/modules/desktops became its own
# directory (release_uses_modern_layout in abora-update.sh). On exactly
# those legacy installs, a freshly-created abora/mango/config.conf (this
# same script's own job when it's missing) would silently stay untracked,
# invisible to a pure `nix flake` evaluation -- the exact failure this
# script exists to repair. Runs the real script end-to-end (not a copy of
# its logic) against a sandbox git repo that's missing mangowm.nix, the
# same setup the "pure-eval: Mango repair" test above uses except with
# that one file left out, and checks the other three real files still got
# staged. abora-installer.sh's install-time counterpart had the identical
# multi-path `git add` pattern (checked statically below, since
# reproducing its full chroot-install context here isn't worth the cost).
tmp_repair_git="$(mktemp -d)"
mkdir -p "$tmp_repair_git/abora/desktops" "$tmp_repair_git/.abora-upstream/assets/mango"
git -C "$tmp_repair_git" init -q
git -C "$tmp_repair_git" config user.email test@example.com
git -C "$tmp_repair_git" config user.name test
cp nix/modules/abora-options.nix "$tmp_repair_git/abora/abora-options.nix"
cp nix/modules/installed-base.nix "$tmp_repair_git/abora/installed-base.nix"
cp assets/mango/config.conf "$tmp_repair_git/.abora-upstream/assets/mango/config.conf"
# abora/desktops/mangowm.nix intentionally left out -- the legacy-install case.
if ABORA_SYSTEM_CONFIG="$tmp_repair_git" bash scripts/abora-repair-flake-purity.sh --mango >/dev/null 2>&1; then
  _repair_staged="$(git -C "$tmp_repair_git" diff --cached --name-only)"
  if grep -qx 'abora/mango/config.conf' <<<"$_repair_staged" \
    && grep -qx 'abora/abora-options.nix' <<<"$_repair_staged" \
    && grep -qx 'abora/installed-base.nix' <<<"$_repair_staged"; then
    pass "runtime: flake-purity repair stages existing files even when mangowm.nix is missing"
  else
    fail "runtime: flake-purity repair stages existing files even when mangowm.nix is missing"
    printf '              staged: %s\n' "${_repair_staged:-<none>}"
  fi
else
  fail "runtime: flake-purity repair stages existing files even when mangowm.nix is missing"
  printf '              repair script itself failed to run\n'
fi
rm -rf "$tmp_repair_git"

if grep -q 'for _branding_git_path in' scripts/abora-installer.sh \
  && grep -A6 'for _branding_git_path in' scripts/abora-installer.sh | grep -q 'git -C "\${root}/etc/nixos" add "\$_branding_git_path"'; then
  pass "runtime: installer's branding git-add stages each path independently"
else
  fail "runtime: installer's branding git-add stages each path independently"
fi

# Regression test: abora-recovery.sh's interactive menu used to let a
# failing action kill the whole script instead of returning to the menu.
# Every menu choice runs under the script's own `set -euo pipefail`; run_cmd
# (used by rollback/report/rebuild/anix-doctor/abora-doctor) just runs "$@"
# as its last statement with no guard, so a nonzero exit propagated straight
# through `set -e` and exited the entire process -- reproduced directly:
# choosing "5) Run ANIX doctor" with a failing `anix` on PATH terminated the
# script immediately, before it ever showed the menu a second time or
# reached the "Press Enter to continue" prompt, leaving no way to try any
# other recovery option in that session -- exactly backwards for a tool
# whose whole purpose is recovering an already-broken system. Runs the real
# script's interactive menu (not a copy of its logic) with a fake `anix`
# that always fails, feeding choice "5" then "q", and checks the menu
# banner actually rendered twice (proving the loop survived) and the
# script exited 0 (a clean quit, not a crash).
tmp_recovery_bin="$(mktemp -d)"
cat > "$tmp_recovery_bin/anix" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp_recovery_bin/anix"
set +e
_recovery_menu_out="$(printf '5\n\nq\n' | PATH="$tmp_recovery_bin:$PATH" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-recovery.sh menu 2>&1)"
_recovery_menu_status=$?
set -e
rm -rf "$tmp_recovery_bin"
_recovery_menu_renders="$(grep -c 'Roll back previous generation' <<<"$_recovery_menu_out")"
if [[ "$_recovery_menu_status" -eq 0 && "$_recovery_menu_renders" -ge 2 ]]; then
  pass "runtime: recovery menu survives a failing action and returns to the menu"
else
  fail "runtime: recovery menu survives a failing action and returns to the menu"
  printf '              exit status: %s, menu renders: %s (need 0 and >=2)\n' \
    "$_recovery_menu_status" "$_recovery_menu_renders"
fi

# Regression test: abora-welcome.sh's interactive menu had the identical
# bug -- `abora doctor` (choice "1" in the first-run welcome menu) exits 1
# whenever it finds any problem at all, which killed the entire first-run
# welcome flow before the user ever saw the app manager, gaming setup,
# snapshot, desktop switch, or recovery options. Reproduces with a fake
# always-failing `abora`, feeding choice "1" then "q".
tmp_welcome_bin="$(mktemp -d)"
cat > "$tmp_welcome_bin/abora" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp_welcome_bin/abora"
set +e
_welcome_menu_out="$(printf '1\n\nq\n' | PATH="$tmp_welcome_bin:$PATH" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-welcome.sh menu 2>&1)"
_welcome_menu_status=$?
set -e
rm -rf "$tmp_welcome_bin"
_welcome_menu_renders="$(grep -c 'Run system doctor' <<<"$_welcome_menu_out")"
if [[ "$_welcome_menu_status" -eq 0 && "$_welcome_menu_renders" -ge 2 ]]; then
  pass "runtime: welcome menu survives a failing action and returns to the menu"
else
  fail "runtime: welcome menu survives a failing action and returns to the menu"
  printf '              exit status: %s, menu renders: %s (need 0 and >=2)\n' \
    "$_welcome_menu_status" "$_welcome_menu_renders"
fi

# Regression test: anix.sh's "ANIX Control Center" terminal menus had the
# same bug, but worse -- do_set/do_toggle/do_switch/do_rollback/do_save/
# do_tool_config/do_tinypm/do_package/do_doctor/do_apply all call `exit`
# (not `return`) on failure, so even a subshell-less `|| true` at the call
# site couldn't have caught it; each call needed wrapping in its own `(
# ... )` subshell so the exit only ends that subshell. Reproduced directly:
# typing a hostname containing a space into "Settings > Hostname" killed
# the entire `anix --gui` session before it ever returned to the settings
# menu or the control center. Runs the real terminal UI end-to-end (no
# DISPLAY/zenity, so it falls back to do_gui_terminal) against a sandboxed
# ANIX_SYSTEM_CONFIG, entering Settings (2) -> Hostname (2) -> an invalid
# value, and checks the control center/settings banners rendered more than
# once and the whole process exited cleanly.
tmp_anix_menu_cfg="$(mktemp -d)"
printf '{ ... }: { imports = [ ./anix.nix ]; }\n' > "$tmp_anix_menu_cfg/configuration.nix"
set +e
_anix_menu_out="$(
  printf '2\n2\nbad hostname\nq\n0\nq\n' | \
    DISPLAY= WAYLAND_DISPLAY= \
    ANIX_SYSTEM_CONFIG="$tmp_anix_menu_cfg" ANIX_NO_SUDO=1 ANIX_ASSUME_YES=1 \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/anix.sh --gui 2>&1
)"
_anix_menu_status=$?
set -e
rm -rf "$tmp_anix_menu_cfg"
_anix_menu_renders="$(grep -c 'ANIX Control Center\|ANIX Settings' <<<"$_anix_menu_out")"
if [[ "$_anix_menu_status" -eq 0 && "$_anix_menu_renders" -ge 3 ]] \
  && grep -q '( do_toggle "\$wanted" "\$feature" ) || true' scripts/anix.sh \
  && grep -q '( do_switch nix "\$profile" ) || true' scripts/anix.sh \
  && grep -q '( do_rollback ) || true' scripts/anix.sh \
  && grep -q '( do_save "\${message:-anix: local config snapshot}" ) || true' scripts/anix.sh \
  && grep -q '( do_tool_config show ) || true' scripts/anix.sh \
  && grep -q '( do_tinypm install ) || true' scripts/anix.sh \
  && grep -q '( do_package add "\$pkg" ) || true' scripts/anix.sh \
  && grep -q '( do_doctor ) || true' scripts/anix.sh \
  && grep -q '( do_apply ) || true' scripts/anix.sh; then
  pass "runtime: ANIX terminal menus survive a failing action and return to the menu"
else
  fail "runtime: ANIX terminal menus survive a failing action and return to the menu"
  printf '              exit status: %s, menu renders: %s (need 0 and >=3)\n' \
    "$_anix_menu_status" "$_anix_menu_renders"
fi

# Regression test: abora-apps.sh's render_apps_module() used to silently
# drop an apps.list entry that's no longer in the app catalog (a catalog
# entry can be renamed or removed across releases after a user already has
# it installed) with zero warning anywhere -- `abora apps installed` still
# listed it as installed (it reads apps.list directly, not apps.nix), while
# the actual generated apps.nix silently no longer contained it, so the
# app would quietly stop being part of environment.systemPackages on every
# subsequent rebuild with no indication why. Runs the real
# render_apps_module() (not a copy of it) against a sandboxed apps.list
# containing one real catalog app and one stale id, and checks: the stale
# id produces a warning on stderr, that warning does NOT leak into the
# generated apps.nix (it's written via `{ ... } > "$tmp"`, so a
# stdout-printing warning would corrupt the file), and the real app is
# still rendered correctly.
tmp_apps_render="$(mktemp -d)"
mkdir -p "$tmp_apps_render/abora"
printf 'firefox\nstale-removed-app\n' > "$tmp_apps_render/abora/apps.list"
_apps_render_stdout="$(mktemp)"
_apps_render_stderr="$(mktemp)"
(
  # shellcheck source=/dev/null
  source scripts/abora-ui.sh
  # shellcheck source=/dev/null
  source scripts/abora-app-catalog.sh
  config_dir="$tmp_apps_render"
  abora_dir="$config_dir/abora"
  apps_list="$abora_dir/apps.list"
  apps_module="$abora_dir/apps.nix"
  run_as_root() { "$@"; }
  read_selected_ids() { grep -v '^[[:space:]]*$' "$apps_list" | grep -v '^[[:space:]]*#' || true; }
  eval "$(sed -n '/^render_apps_module() {/,/^}$/p' scripts/abora-apps.sh)"
  render_apps_module
) >"$_apps_render_stdout" 2>"$_apps_render_stderr"
if [[ ! -s "$_apps_render_stdout" ]] \
  && grep -q "Skipping 'stale-removed-app'" "$_apps_render_stderr" \
  && [[ -f "$tmp_apps_render/abora/apps.nix" ]] \
  && ! grep -q 'Skipping' "$tmp_apps_render/abora/apps.nix" \
  && grep -q 'firefox' "$tmp_apps_render/abora/apps.nix"; then
  pass "runtime: render_apps_module warns (on stderr, not into apps.nix) about a stale catalog entry"
else
  fail "runtime: render_apps_module warns (on stderr, not into apps.nix) about a stale catalog entry"
fi
rm -f "$_apps_render_stdout" "$_apps_render_stderr"
rm -rf "$tmp_apps_render"

tmp_apps_remove_stale="$(mktemp -d)"
mkdir -p "$tmp_apps_remove_stale/abora"
printf 'firefox\nstale-removed-app\n' > "$tmp_apps_remove_stale/abora/apps.list"
(
  # shellcheck source=/dev/null
  source scripts/abora-ui.sh
  # shellcheck source=/dev/null
  source scripts/abora-app-catalog.sh
  config_dir="$tmp_apps_remove_stale"
  abora_dir="$config_dir/abora"
  apps_list="$abora_dir/apps.list"
  apps_module="$abora_dir/apps.nix"
  run_as_root() { "$@"; }
  eval "$(sed -n '/^read_selected_ids() {/,/^}$/p' scripts/abora-apps.sh)"
  eval "$(sed -n '/^write_selected_ids() {/,/^}$/p' scripts/abora-apps.sh)"
  eval "$(sed -n '/^render_apps_module() {/,/^}$/p' scripts/abora-apps.sh)"
  eval "$(sed -n '/^selected_has_id() {/,/^}$/p' scripts/abora-apps.sh)"
  eval "$(sed -n '/^validate_remove_ids() {/,/^}$/p' scripts/abora-apps.sh)"
  validate_remove_ids stale-removed-app
  keeping=()
  while IFS= read -r app_id; do
    [[ -n "$app_id" ]] || continue
    case " stale-removed-app " in
      *" $app_id "*) ;;
      *) keeping+=("$app_id") ;;
    esac
  done < <(read_selected_ids)
  write_selected_ids "${keeping[@]+"${keeping[@]}"}"
  render_apps_module
) >/dev/null 2>&1
_apps_remove_stale_status=$?
if [[ "$_apps_remove_stale_status" -eq 0 ]] \
  && grep -qx 'firefox' "$tmp_apps_remove_stale/abora/apps.list" \
  && ! grep -q 'stale-removed-app' "$tmp_apps_remove_stale/abora/apps.list" \
  && ! grep -q 'stale-removed-app' "$tmp_apps_remove_stale/abora/apps.nix"; then
  pass "runtime: abora apps remove can clean stale catalog entries"
else
  fail "runtime: abora apps remove can clean stale catalog entries"
fi
rm -rf "$tmp_apps_remove_stale"

# Regression test from a real Abora Gaming ISO app-install failure: Nix can
# fail before Steam/Heroic/etc. are even evaluated if the user's local
# fetcher-cache SQLite DB is damaged ("pragma synchronous = off": disk I/O
# error in ~/.cache/nix/fetcher-cache-v*.sqlite). The old app manager just
# let nixos-rebuild's wall of text fall through, so it looked like the app
# entry was bad. Extract the real rebuild/error-explainer functions and
# feed them a fake failing nixos-rebuild that emits the same class of error,
# then confirm the output points at the local cache and disk-space checks.
tmp_apps_rebuild_diag="$(mktemp -d)"
tmp_apps_rebuild_funcs="$tmp_apps_rebuild_diag/funcs.sh"
tmp_apps_rebuild_bin="$tmp_apps_rebuild_diag/bin"
mkdir -p "$tmp_apps_rebuild_bin"
{
  sed -n '/^run_as_root() {/,/^}$/p' scripts/abora-apps.sh
  sed -n '/^stage_config_for_flake() {/,/^}$/p' scripts/abora-apps.sh
  sed -n '/^explain_nix_failure() {/,/^}$/p' scripts/abora-apps.sh
  sed -n '/^rebuild_system() {/,/^}$/p' scripts/abora-apps.sh
} > "$tmp_apps_rebuild_funcs"
cat > "$tmp_apps_rebuild_bin/nixos-rebuild" <<'NIXREBUILDEOF'
#!/usr/bin/env bash
printf '%s\n' "error: executing SQLite statement 'pragma synchronous = off': disk I/O error, disk I/O error (in '/home/abora/.cache/nix/fetcher-cache-v4.sqlite')"
exit 1
NIXREBUILDEOF
chmod +x "$tmp_apps_rebuild_bin/nixos-rebuild"
set +e
_apps_rebuild_diag_out="$(
  PATH="$tmp_apps_rebuild_bin:/usr/bin:/bin" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash -c '
    set -euo pipefail
    source "$1"
    ABORA_NC=""; ABORA_CYAN=""; ABORA_DIM=""; ABORA_WHITE=""; ABORA_BLUE=""
    abora_step() { printf "STEP %s\n" "$1"; }
    abora_warn() { printf "WARN %s\n" "$1"; }
    abora_dim_line() { printf "%s\n" "$1"; }
    config_dir=/tmp/abora-test-config
    flake_target=abora
    ABORA_NO_SUDO=1
    rebuild_system
  ' bash "$tmp_apps_rebuild_funcs" 2>&1
)"
_apps_rebuild_diag_status=$?
set -e
rm -rf "$tmp_apps_rebuild_diag"
if [[ "$_apps_rebuild_diag_status" -ne 0 ]] \
  && grep -q 'local fetch-cache disk I/O error' <<<"$_apps_rebuild_diag_out" \
  && grep -q 'abora gaming repair-cache' <<<"$_apps_rebuild_diag_out" \
  && grep -q 'rm -f ~/.cache/nix/fetcher-cache-v' <<<"$_apps_rebuild_diag_out" \
  && grep -q 'df -h' <<<"$_apps_rebuild_diag_out"; then
  pass "runtime: abora apps explains Nix fetch-cache disk I/O failures"
else
  fail "runtime: abora apps explains Nix fetch-cache disk I/O failures"
  printf '              exit status: %s\n' "$_apps_rebuild_diag_status"
  printf '              output: %s\n' "$_apps_rebuild_diag_out"
fi

tmp_apps_rebuild_rollback="$(mktemp -d)"
mkdir -p "$tmp_apps_rebuild_rollback/config/abora" "$tmp_apps_rebuild_rollback/bin"
printf '{ }\n' > "$tmp_apps_rebuild_rollback/config/flake.nix"
printf 'firefox\n' > "$tmp_apps_rebuild_rollback/config/abora/apps.list"
cat > "$tmp_apps_rebuild_rollback/config/abora/apps.nix" <<'EOF'
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    firefox
  ];
}
EOF
cp "$tmp_apps_rebuild_rollback/config/abora/apps.list" "$tmp_apps_rebuild_rollback/apps.list.before"
cp "$tmp_apps_rebuild_rollback/config/abora/apps.nix" "$tmp_apps_rebuild_rollback/apps.nix.before"
cat > "$tmp_apps_rebuild_rollback/bin/nixos-rebuild" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'simulated rebuild failure'
exit 1
EOF
chmod +x "$tmp_apps_rebuild_rollback/bin/nixos-rebuild"
if PATH="$tmp_apps_rebuild_rollback/bin:/usr/bin:/bin" \
  ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_apps_rebuild_rollback/config" \
  ABORA_APP_CATALOG_LIB="$repo_dir/scripts/abora-app-catalog.sh" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-apps.sh add steam >/tmp/abora-apps-rollback.out 2>&1; then
  fail "runtime: abora apps restores app state when rebuild fails"
elif cmp -s "$tmp_apps_rebuild_rollback/config/abora/apps.list" "$tmp_apps_rebuild_rollback/apps.list.before" \
  && cmp -s "$tmp_apps_rebuild_rollback/config/abora/apps.nix" "$tmp_apps_rebuild_rollback/apps.nix.before" \
  && grep -q 'Restored the previous app selection because the rebuild failed' /tmp/abora-apps-rollback.out; then
  pass "runtime: abora apps restores app state when rebuild fails"
else
  fail "runtime: abora apps restores app state when rebuild fails"
  sed 's/^/              /' /tmp/abora-apps-rollback.out
fi
rm -rf "$tmp_apps_rebuild_rollback"

# Regression test: root helpers must preserve command failures. A bad sudo
# password, failed cp, failed nixos-rebuild, or failed standalone-package
# install should never be turned into "success" just because run_as_root()
# returned 0 unconditionally after running the command.
tmp_root_helpers="$(mktemp -d)"
sed -n '/^run_as_root() {/,/^}$/p' scripts/abora-apps.sh > "$tmp_root_helpers/apps.sh"
sed -n '/^run_as_root() {/,/^}$/p' scripts/abora-custom-packages.sh > "$tmp_root_helpers/custom.sh"
set +e
bash -c 'source "$1"; ABORA_NO_SUDO=1; run_as_root false' bash "$tmp_root_helpers/apps.sh"
_apps_root_helper_status=$?
bash -c 'source "$1"; ABORA_NO_SUDO=1; run_as_root false' bash "$tmp_root_helpers/custom.sh"
_custom_root_helper_status=$?
set -e
rm -rf "$tmp_root_helpers"
if [[ "$_apps_root_helper_status" -ne 0 && "$_custom_root_helper_status" -ne 0 ]]; then
  pass "runtime: app root helpers preserve command failures"
else
  fail "runtime: app root helpers preserve command failures"
  printf '              abora-apps rc: %s, custom-packages rc: %s\n' \
    "$_apps_root_helper_status" "$_custom_root_helper_status"
fi

# Regression test: abora-custom-packages.sh used to rely on two separate
# `trap ... RETURN` calls (one per function) to clean up its temp
# extraction dir and downloaded zip. Both were broken: `trap ... RETURN`
# never fires on `exit` (only a normal function return), and every real
# error path here calls `exit`; and `trap` isn't function-scoped in bash,
# so the inner function's trap silently overwrote the outer one's, so even
# the success path leaked the downloaded zip. Reproduced directly: `abora
# apps custom update modularity-stable --zip <bad.zip>` (missing the
# expected bin/Modularity executable, a real user mistake -- wrong zip,
# corrupted download) left its extraction tmp dir behind in /tmp every
# time. Runs the real script end-to-end against a real, deliberately
# malformed zip fixture and diffs /tmp before/after.
if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
  tmp_badzip_dir="$(mktemp -d)"
  mkdir -p "$tmp_badzip_dir/Modularity-1.0.0-Linux/bin"
  touch "$tmp_badzip_dir/Modularity-1.0.0-Linux/bin/NOT_Modularity"
  (cd "$tmp_badzip_dir" && zip -qr bad.zip Modularity-1.0.0-Linux)
  _tmp_before="$(find /tmp -maxdepth 1 -name 'tmp.*' 2>/dev/null | sort)"
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-custom-packages.sh update modularity-stable \
    --zip "$tmp_badzip_dir/bad.zip" --version 1.0.0 >/dev/null 2>&1 || true
  _tmp_after="$(find /tmp -maxdepth 1 -name 'tmp.*' 2>/dev/null | sort)"
  _tmp_leaked="$(comm -13 <(printf '%s\n' "$_tmp_before") <(printf '%s\n' "$_tmp_after"))"
  rm -rf "$tmp_badzip_dir" $_tmp_leaked
  if [[ -z "$_tmp_leaked" ]]; then
    pass "runtime: abora-custom-packages.sh cleans up its temp extraction dir on a bad zip"
  else
    fail "runtime: abora-custom-packages.sh cleans up its temp extraction dir on a bad zip"
    printf '              leaked: %s\n' "$_tmp_leaked"
  fi
else
  pass "zip/unzip unavailable (custom-packages temp-cleanup test skipped)"
fi

# Regression test: abora.sh's create_github_issue() (`abora bug-report
# --github`) built its auto-generated issue body with six `printf '- ...'`
# calls. bash's builtin printf treats a format string starting with '-' as
# an option flag, not literal text -- confirmed directly:
# `printf -- '- Command: x\n'` is fine, but plain `printf '- Command:
# x\n'` fails with "printf: - : invalid option". The very first of the six
# calls crashed every single time, under this function's own `set -e`,
# so `abora bug-report --github` (without --body-file) failed on every
# real invocation before gh was ever reached -- and leaked its $tmp_body
# temp file too, since the crash happened before the cleanup that follows
# it. Runs the real command end-to-end with a fake gh on PATH (so it never
# touches the network) and checks it exits 0, prints all three
# auto-collected pointer lines, and leaves no temp file behind.
tmp_gh_bin="$(mktemp -d)"
cat > "$tmp_gh_bin/gh" <<'GHEOF'
#!/usr/bin/env bash
exit 0
GHEOF
chmod +x "$tmp_gh_bin/gh"
_bugreport_tmp_before="$(find /tmp -maxdepth 1 -name 'tmp.*' 2>/dev/null | sort)"
set +e
_bugreport_out="$(PATH="$tmp_gh_bin:$PATH" bash scripts/abora.sh bug-report --github --dry-run --title "test issue" 2>&1)"
_bugreport_status=$?
set -e
_bugreport_tmp_after="$(find /tmp -maxdepth 1 -name 'tmp.*' 2>/dev/null | sort)"
_bugreport_leaked="$(comm -13 <(printf '%s\n' "$_bugreport_tmp_before") <(printf '%s\n' "$_bugreport_tmp_after"))"
rm -rf "$tmp_gh_bin" $_bugreport_leaked
if [[ "$_bugreport_status" -eq 0 ]] \
  && grep -q '^- Command: `abora bug-report --github`$' <<<"$_bugreport_out" \
  && grep -q '^- Logs: run `abora logs --lines 200`$' <<<"$_bugreport_out" \
  && grep -q '^- Network diagnostics: run `abora network`$' <<<"$_bugreport_out" \
  && [[ -z "$_bugreport_leaked" ]]; then
  pass "runtime: abora bug-report --github builds its auto-generated body without crashing"
else
  fail "runtime: abora bug-report --github builds its auto-generated body without crashing"
  printf '              exit status: %s, leaked: %s\n' "$_bugreport_status" "${_bugreport_leaked:-<none>}"
fi

# Regression test: abora-build.sh --from-source used to silently reuse an
# already-cloned checkout at the default/--checkout location with no `git
# fetch`/`checkout` at all -- the "Source ref: <requested>" status line
# always showed what --ref asked for, regardless of what was actually
# checked out there. A second `abora build --from-source --ref X` run
# against an already-cloned checkout silently kept building whatever ref
# the *first* run had checked out, while claiming to build X. Reproduced
# directly: a checkout cloned on "edge" stayed on "edge" (branch and file
# content unchanged) after a second run requesting "main". Runs the real
# script twice against a real local two-branch git repo (no network) and
# confirms the second run, which asks for the other branch, actually
# switches to it.
if command -v git >/dev/null 2>&1; then
  tmp_build_repo="$(mktemp -d)"
  tmp_build_checkout="$(mktemp -d)"
  (
    set -e
    cd "$tmp_build_repo"
    git init -q
    git config user.email a@b.c
    git config user.name test
    printf '{ description = "fake"; }\n' > flake.nix
    git checkout -q -b edge
    git add flake.nix
    git commit -q -m edge
    printf 'edge-marker\n' > MARKER.txt
    git add MARKER.txt
    git commit -q -m marker
    git checkout -q -b main
    printf 'main-marker\n' > MARKER.txt
    git commit -q -am marker
    git checkout -q edge
  ) >/dev/null 2>&1
  rmdir "$tmp_build_checkout"
  git clone -q --branch edge "$tmp_build_repo" "$tmp_build_checkout" >/dev/null 2>&1
  (
    cd /tmp
    ABORA_SOURCE_DIR="$tmp_build_checkout" ABORA_REPO_URLS="$tmp_build_repo" \
      bash "$repo_dir/scripts/abora-build.sh" --from-source --ref main --target ".#doesnotexist" \
      >/dev/null 2>&1 || true
  )
  _build_ref_after="$(git -C "$tmp_build_checkout" branch --show-current 2>/dev/null || true)"
  _build_marker_after="$(cat "$tmp_build_checkout/MARKER.txt" 2>/dev/null || true)"
  rm -rf "$tmp_build_repo" "$tmp_build_checkout"
  if [[ "$_build_ref_after" == "main" && "$_build_marker_after" == "main-marker" ]]; then
    pass "runtime: abora build --from-source switches an already-cloned checkout to the requested --ref"
  else
    fail "runtime: abora build --from-source switches an already-cloned checkout to the requested --ref"
    printf '              branch after: %s, marker after: %s (wanted main / main-marker)\n' \
      "$_build_ref_after" "$_build_marker_after"
  fi
else
  pass "git unavailable (abora-build ref-switch test skipped)"
fi

# Regression test: check-all-files.sh's find_files()/find_shebang_scripts()
# used to have no exclusion for `obj`/`bin` directories -- each C# project
# under tools/ has its own local .gitignore with those bare names (a
# standard dotnet template convention) that git respects but plain `find`
# doesn't know about. A prior `dotnet build` (which this same suite's own
# resolver/plan-tool tests routinely trigger) leaves dozens of generated
# *.json files on disk that check-all-files.sh would otherwise "check" as
# if they were real repo source -- harmless while they happen to be
# well-formed, but a stale/interrupted build leaving a truncated one
# behind would fail that check for something never committed at all.
# Extracts the real find_files() function and runs it against a sandbox
# tree shaped like a real dotnet project layout (a real committed .json
# alongside a fake tools/*/obj/*.json), confirming the real file is found
# and the build-artifact one is not.
tmp_findfiles_funcs="$(mktemp)"
sed -n '/^find_files() {/,/^}$/p' scripts/check-all-files.sh > "$tmp_findfiles_funcs"
tmp_findfiles_tree="$(mktemp -d)"
mkdir -p "$tmp_findfiles_tree/nix/pkgs" "$tmp_findfiles_tree/tools/fake-project/obj/Debug"
printf '{"real": true}\n' > "$tmp_findfiles_tree/nix/pkgs/real-deps.json"
printf '{"generated": true}\n' > "$tmp_findfiles_tree/tools/fake-project/obj/Debug/project.assets.json"
if bash -n "$tmp_findfiles_funcs" 2>/dev/null; then
  _findfiles_out="$(cd "$tmp_findfiles_tree" && bash -c "source '$tmp_findfiles_funcs'; find_files json")"
else
  _findfiles_out="<extraction failed>"
fi
rm -f "$tmp_findfiles_funcs"
rm -rf "$tmp_findfiles_tree"
if grep -qx 'nix/pkgs/real-deps.json' <<<"$_findfiles_out" \
  && ! grep -q 'obj/Debug/project.assets.json' <<<"$_findfiles_out"; then
  pass "runtime: check-all-files.sh's find_files() excludes tools/*/obj and tools/*/bin build artifacts"
else
  fail "runtime: check-all-files.sh's find_files() excludes tools/*/obj and tools/*/bin build artifacts"
  printf '              found: %s\n' "$_findfiles_out"
fi

# Regression test: rebuild-vm.sh's fresh-workspace clone used to be a plain
# `git clone` with no --branch -- checking out the repo's default HEAD
# branch (stable) instead of $repo_branch (edge by default), silently, on
# exactly the scenario this script exists for: a fresh or reset persistent
# build workspace. Reproduced directly against a real local two-branch
# repo (no network): a fresh clone with ABORA_REPO_BRANCH=edge against a
# repo whose default HEAD is "stable" landed on stable every time. Runs
# the real script end-to-end (build-iso.sh is expected to fail in this
# sandbox -- there's no real flake.nix -- only the clone step is being
# checked) and confirms the resulting workspace checkout is actually on
# the requested branch.
if command -v git >/dev/null 2>&1; then
  tmp_vm_repo="$(mktemp -d)"
  tmp_vm_workspace="$(mktemp -d)"
  (
    set -e
    cd "$tmp_vm_repo"
    git init -q
    git config user.email a@b.c
    git config user.name test
    printf 'stable-fake\n' > MARKER.txt
    git checkout -q -b stable
    git add MARKER.txt
    git commit -q -m stable
    git checkout -q -b edge
    printf 'edge-fake\n' > MARKER.txt
    git commit -q -am edge
    git symbolic-ref HEAD refs/heads/stable
    git checkout -q stable
  ) >/dev/null 2>&1
  rmdir "$tmp_vm_workspace"
  (
    cd /tmp
    ABORA_VM_WORKSPACE="$tmp_vm_workspace" ABORA_REPO_URL="$tmp_vm_repo" ABORA_REPO_BRANCH="edge" \
      bash "$repo_dir/scripts/rebuild-vm.sh" >/dev/null 2>&1 || true
  )
  _vm_branch_after="$(git -C "$tmp_vm_workspace/abora-os" branch --show-current 2>/dev/null || true)"
  _vm_marker_after="$(cat "$tmp_vm_workspace/abora-os/MARKER.txt" 2>/dev/null || true)"
  rm -rf "$tmp_vm_repo" "$tmp_vm_workspace"
  if [[ "$_vm_branch_after" == "edge" && "$_vm_marker_after" == "edge-fake" ]]; then
    pass "runtime: rebuild-vm.sh clones the requested branch on a fresh workspace"
  else
    fail "runtime: rebuild-vm.sh clones the requested branch on a fresh workspace"
    printf '              branch after: %s, marker after: %s (wanted edge / edge-fake)\n' \
      "$_vm_branch_after" "$_vm_marker_after"
  fi
else
  pass "git unavailable (rebuild-vm branch test skipped)"
fi

# Regression test: abora-hardware-test.sh's list_disks()/has_internal_disk()
# filtered only on TYPE=disk and RM=0, with no name-prefix exclusion --
# zram (RAM-backed swap) reports TYPE=disk too, confirmed directly against
# a real machine (lsblk -P: /dev/zram0 TYPE="disk", RM="0", TRAN=""), so
# this hardware-readiness tool counted it as a real disk target and toward
# "at least one fixed internal disk is visible", exactly backwards for a
# check whose whole purpose is telling a user whether their machine has
# real, safe-to-install storage. abora-installer.sh already excludes the
# same name prefixes (collect_disks()'s ^(fd|loop|ram|sr|zram) filter).
# Extracts the real functions and runs them against a fake lsblk including
# a zram device, confirming it's excluded from both.
tmp_hwtest_funcs="$(mktemp)"
sed -n '/^list_disks() {/,/^}$/p; /^has_internal_disk() {/,/^}$/p' scripts/abora-hardware-test.sh > "$tmp_hwtest_funcs"
tmp_hwtest_bin="$(mktemp -d)"
cat > "$tmp_hwtest_bin/lsblk" <<'LSBLKEOF'
#!/usr/bin/env bash
if [[ "$*" == *"-P"* ]]; then
  printf 'NAME="zram0" SIZE="8G" MODEL="" TRAN="" RM="0" TYPE="disk"\n'
  printf 'NAME="sda" SIZE="256G" MODEL="Fake SSD" TRAN="sata" RM="0" TYPE="disk"\n'
else
  printf 'zram0 0 disk\n'
  printf 'sda 0 disk\n'
fi
LSBLKEOF
chmod +x "$tmp_hwtest_bin/lsblk"
if bash -n "$tmp_hwtest_funcs" 2>/dev/null; then
  set +e
  _hwtest_disks="$(PATH="$tmp_hwtest_bin:$PATH" bash -c "source '$tmp_hwtest_funcs'; list_disks")"
  PATH="$tmp_hwtest_bin:$PATH" bash -c "source '$tmp_hwtest_funcs'; has_internal_disk"
  _hwtest_internal_rc=$?
  set -e
else
  _hwtest_disks="<extraction failed>"
  _hwtest_internal_rc=99
fi
rm -f "$tmp_hwtest_funcs"
rm -rf "$tmp_hwtest_bin"
if ! grep -q 'zram0' <<<"$_hwtest_disks" \
  && grep -q '/dev/sda' <<<"$_hwtest_disks" \
  && [[ "$_hwtest_internal_rc" -eq 0 ]]; then
  pass "runtime: abora-hardware-test.sh excludes zram/loop/ram/sr/fd from disk detection"
else
  fail "runtime: abora-hardware-test.sh excludes zram/loop/ram/sr/fd from disk detection"
  printf '              list_disks: %s, has_internal_disk rc: %s\n' "$_hwtest_disks" "$_hwtest_internal_rc"
fi

# Regression test: abora-custom-packages.sh's install_modularity_zip() hard
# requires unzip ("unzip is required to install Modularity Stable", exit 1
# otherwise) to run `abora apps custom update modularity-stable --zip
# <file>`, a real documented feature (abora.sh's own help text, this
# script's usage). unzip was never declared in installed-base.nix's
# environment.systemPackages, so on a genuinely clean install this feature
# would fail every time with no way to fix it short of installing unzip
# out of band. Static check since this is a package-declaration fact, not
# behavior to execute.
if grep -qE '^\s*unzip\s*$' nix/modules/installed-base.nix; then
  pass "runtime: installed-base.nix declares unzip (required by abora apps custom update --zip)"
else
  fail "runtime: installed-base.nix declares unzip (required by abora apps custom update --zip)"
fi

# Regression test: a bare `abora update` (no extra arguments) -- the
# primary, documented way to run an update ("Sync the latest Abora files
# and rebuild the system", per this script's own usage text) -- used to
# be grouped into the same case arm as an explicit `--help` request
# (`""|help|-h|--help)`), so it just printed usage and exited 0 instead
# of ever reaching the real update logic. Every `abora update` invocation
# was silently a no-op. Reproduced directly and confirmed: with no
# ABORA_SYSTEM_CONFIG pointing at a real install, the real update path
# fails with "NixOS config directory not found" -- that error, not the
# usage banner, is what a bare invocation should produce.
tmp_update_nonexistent="$(mktemp -u)"
set +e
_update_bare_out="$(ABORA_SYSTEM_CONFIG="$tmp_update_nonexistent" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh 2>&1)"
set -e
if grep -q 'NixOS config directory not found' <<<"$_update_bare_out" \
  && ! grep -q 'Sync the latest Abora files and rebuild the system' <<<"$_update_bare_out"; then
  pass "runtime: bare 'abora update' reaches the real update logic, not just usage"
else
  fail "runtime: bare 'abora update' reaches the real update logic, not just usage"
  printf '%s\n' "$_update_bare_out" | sed 's/^/              /'
fi

# Regression test: `abora rollback` (-> `abora-update.sh rollback`) used
# to have no matching case arm in the command-routing block that handles
# channel/fallback/install, so the literal "rollback" argument was never
# consumed -- it fell straight through to the "$# -gt 0" extra-arguments
# check and failed with "This command does not take extra arguments
# yet." every single time, never reaching the real
# `nixos-rebuild switch --rollback` logic. Reproduced directly: same
# "NixOS config directory not found" check as above proves it now
# reaches the real rollback path instead of the bogus arguments error.
set +e
_update_rollback_out="$(ABORA_SYSTEM_CONFIG="$tmp_update_nonexistent" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh rollback 2>&1)"
set -e
if grep -q 'NixOS config directory not found' <<<"$_update_rollback_out" \
  && ! grep -q 'does not take extra arguments' <<<"$_update_rollback_out"; then
  pass "runtime: 'abora update rollback' reaches the real rollback logic"
else
  fail "runtime: 'abora update rollback' reaches the real rollback logic"
  printf '%s\n' "$_update_rollback_out" | sed 's/^/              /'
fi

# Regression test: anix.power.thermald defaulted to true in both the
# nixosOption (nix/modules/anix.nix) and the anix.nix template render_template()
# writes on `anix init`/`anix quickstart` -- but thermald is Intel's
# laptop-specific thermal daemon, and it exits nonzero on non-mobile
# hardware instead of no-op'ing. Since `nixos-rebuild switch` treats any
# failed unit as a hard activation error, every desktop-class Abora
# install had a perpetually-failing thermald.service, and every
# nixos-rebuild -- including `abora update`'s -- failed because of it.
# Reproduced on real desktop hardware: thermald logged "Non mobile ...
# THD engine" errors and the whole update aborted. Checks both defaults
# are false now: the nixosOption's static default, and a real render_template()
# run (not a copy of it).
if sed -n '/thermald = lib.mkOption {/,/description = "Enable thermald when available.";/p' nix/modules/anix.nix \
  | grep -q 'default = false;'; then
  pass "runtime: anix.power.thermald nixosOption defaults to false"
else
  fail "runtime: anix.power.thermald nixosOption defaults to false"
fi

tmp_thermald_render="$(mktemp -d)"
ANIX_SYSTEM_CONFIG="$tmp_thermald_render" ANIX_NO_SUDO=1 ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/anix.sh init >/dev/null 2>&1 || true
if grep -qx '  anix.power.thermald = false;' "$tmp_thermald_render/anix.nix" 2>/dev/null; then
  pass "runtime: anix init's generated anix.nix defaults power.thermald to false"
else
  fail "runtime: anix init's generated anix.nix defaults power.thermald to false"
fi
rm -rf "$tmp_thermald_render"

# Regression test: scripts/abora-setup.desktop is installed identically on
# both the live ISO and every installed system (nix/modules/installed-base.nix),
# but commit 15dc9ec89453f5e376cc8c97d3bb06485c072d4f changed its Name/Comment
# to installed-inappropriate wording ("Install Abora OS" / "Install Abora OS
# from the live desktop"). abora-setup-launcher.sh correctly detects live vs.
# installed and only runs an installer on the live ISO (--reconfig otherwise),
# but the static .desktop label doesn't know that, so users who already
# installed saw a launcher that claimed to reinstall/install the OS. Reported
# via Discord: "after i installed abora os and booted up theres a gui app
# that just says install abora os". Checks the label is context-neutral.
if grep -qx 'Name=Start Abora' scripts/abora-setup.desktop \
  && grep -qx 'Comment=Install or reconfigure Abora OS' scripts/abora-setup.desktop \
  && ! grep -q 'Name=Install Abora OS' scripts/abora-setup.desktop \
  && ! grep -q 'from the live desktop' scripts/abora-setup.desktop; then
  pass "runtime: abora-setup.desktop label is context-neutral (not install-only wording)"
else
  fail "runtime: abora-setup.desktop label is context-neutral (not install-only wording)"
fi

# Security regression test: abora_wu_run (abora-ui.sh, the shared helper
# behind `abora update`'s real progress UI, and mirrored in
# abora-update.sh's own fallback copy) and abora-doctor.sh's ANIX-doctor
# check all log to fixed, predictable /tmp paths by design -- so a failed
# `abora update` can tell the user exactly where to look. A plain `>`
# redirect to a predictable path in a world-writable directory is a
# classic local symlink race: an attacker who pre-plants a symlink there
# before this root-privileged flow runs gets root to truncate/overwrite
# whatever the symlink points at. Reproduced directly before the fix
# (a plain `>` through a symlinked path really did clobber the target's
# real content); abora_safe_create_file (abora-ui.sh) closes it by
# rm -f'ing the name (never follows a symlink) then creating the real
# file with noclobber (fails closed if a symlink races back into place).
# This test proves the fix, not just that the helper exists: it plants an
# actual symlink pointing at a "sensitive" file with real content and
# checks that content survives untouched.
_symlink_race_dir="$(mktemp -d)"
_symlink_race_sensitive="$_symlink_race_dir/sensitive"
_symlink_race_target="$_symlink_race_dir/predictable.log"
printf 'SENSITIVE CONTENT MUST SURVIVE\n' > "$_symlink_race_sensitive"
ln -s "$_symlink_race_sensitive" "$_symlink_race_target"
if (source "$repo_dir/scripts/abora-ui.sh"; abora_safe_create_file "$_symlink_race_target") \
  && [[ ! -L "$_symlink_race_target" ]] \
  && grep -qx 'SENSITIVE CONTENT MUST SURVIVE' "$_symlink_race_sensitive"; then
  pass "runtime: abora_safe_create_file survives a symlink race, sensitive target untouched"
else
  fail "runtime: abora_safe_create_file survives a symlink race, sensitive target untouched"
fi
rm -rf "$_symlink_race_dir"

_log_summary_dir="$(mktemp -d)"
_log_summary_file="$_log_summary_dir/rebuild.log"
cat > "$_log_summary_file" <<'EOF'
building '/nix/store/root-problem.drv'...
error: undefined variable 'missingWallpaperAsset'
       at /etc/nixos/abora/installed-base.nix:42:17:
building '/nix/store/fontconfig-conf.drv'...
error: Cannot build '/nix/store/fontconfig-conf.drv'.
       Reason: 1 dependency failed.
       Output paths:
         /nix/store/fontconfig-conf
error: Cannot build '/nix/store/system-path.drv'.
       Reason: 1 dependency failed.
       Output paths:
         /nix/store/system-path
error: Cannot build '/nix/store/noisy-01.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-02.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-03.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-04.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-05.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-06.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-07.drv'.
       Reason: 1 dependency failed.
error: Cannot build '/nix/store/noisy-08.drv'.
       Reason: 1 dependency failed.
fatal: activation helper disappeared after build
EOF
_log_summary_out="$(
  COLUMNS=100 bash -c '
    source "$1"
    ABORA_NC=""; ABORA_YELLOW=""; ABORA_FAINT=""
    abora_log_tail "$2"
  ' bash "$repo_dir/scripts/abora-ui.sh" "$_log_summary_file"
)"
if grep -q "Important log lines" <<<"$_log_summary_out" \
  && grep -q "undefined variable 'missingWallpaperAsset'" <<<"$_log_summary_out" \
  && grep -q "activation helper disappeared after build" <<<"$_log_summary_out" \
  && grep -q "Last log lines" <<<"$_log_summary_out"; then
  pass "runtime: abora_log_tail highlights root errors before dependency-noise tails"
else
  fail "runtime: abora_log_tail highlights root errors before dependency-noise tails"
fi
rm -rf "$_log_summary_dir"

if grep -q 'local synced_ui="\$config_dir/abora/ui.sh"' scripts/abora-update.sh \
  && grep -q 'ABORA_UI_LIB="\${synced_ui}"' scripts/abora-update.sh \
  && grep -q 'resolve_resolver_bin()' scripts/abora-update.sh \
  && grep -q 'tools/abora-update-resolver/bin/Debug/net10.0/abora-update-resolver' scripts/abora-update.sh \
  && grep -q 'resolver_bin="$(resolve_resolver_bin)"' scripts/abora-update.sh \
  && grep -q 'abora-update-build.log' scripts/abora-update.sh \
  && grep -q 'Checking the new Abora system' scripts/abora-update.sh \
  && grep -q -- '--no-link' scripts/abora-update.sh \
  && grep -q -- '--show-trace' scripts/abora-update.sh \
  && grep -q 'Switching to the new Abora system' scripts/abora-update.sh \
  && grep -q 'Continuing with the synced updater' scripts/abora-update.sh \
  && grep -q 'ABORA_UPDATE_REEXECED:-0.*!= 1.*config_dir/abora/anix.sh' scripts/abora-update.sh \
  && grep -q 'ABORA_UPDATE_REEXECED:-0.*== 1' scripts/abora-update.sh; then
  pass "runtime: updater re-execs with synced UI and builds before switching"
else
  fail "runtime: updater re-execs with synced UI and builds before switching"
fi

# Real-world case: an already-full /nix/store meant the build and rebuild
# steps each ran for hours -- retrying copies into a store with no room --
# before finally failing with a cascade of confusing "1 dependency failed"
# noise. show_update_space_status only ever warned, never stopped; nothing
# bounded how long the two longest-running steps could run. This is a
# grep-based structural check rather than sourcing abora-update.sh directly,
# because the file executes its update flow top-to-bottom when run/sourced
# (matching the "updater re-execs..." test above it) rather than being a
# safe-to-source function library like abora-ui.sh.
if grep -q '^require_minimum_free_space()' scripts/abora-update.sh \
  && grep -q 'ABORA_UPDATE_CRITICAL_FREE_GIB:-3' scripts/abora-update.sh \
  && grep -q 'too low to safely build' scripts/abora-update.sh \
  && [[ "$(grep -c 'require_minimum_free_space /nix/store || exit 1' scripts/abora-update.sh)" -ge 2 ]]; then
  pass "runtime: updater hard-stops on critically low free space instead of just warning"
else
  fail "runtime: updater hard-stops on critically low free space instead of just warning"
fi

if grep -q 'build_timeout="\${ABORA_BUILD_TIMEOUT:-3600}"' scripts/abora-update.sh \
  && grep -q 'switch_timeout="\${ABORA_SWITCH_TIMEOUT:-1800}"' scripts/abora-update.sh \
  && grep -q 'timeout "\$build_timeout"' scripts/abora-update.sh \
  && grep -q 'timeout "\$switch_timeout"' scripts/abora-update.sh \
  && grep -q '^explain_step_failure()' scripts/abora-update.sh \
  && grep -q 'status" -eq 124' scripts/abora-update.sh \
  && grep -q 'was still running after' scripts/abora-update.sh; then
  pass "runtime: updater bounds the build and switch steps with a timeout"
else
  fail "runtime: updater bounds the build and switch steps with a timeout"
fi

# The build/switch exit status has to be captured via `cmd || status=$?` on
# its own line, not `cmd; status=$?` on the next -- this file has `set -e`
# at the top, so a failing standalone command exits the whole script right
# there and the status-capture line (and the timeout-aware explanation)
# would simply never run. Guards against silently reintroducing that.
if grep -q 'toplevel" || build_status=\$?' scripts/abora-update.sh \
  && grep -q 'flake_config_name}" || switch_status=\$?' scripts/abora-update.sh; then
  pass "runtime: updater captures build/switch exit status without tripping set -e"
else
  fail "runtime: updater captures build/switch exit status without tripping set -e"
fi

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

printf '\nAll script checks passed.\n'
