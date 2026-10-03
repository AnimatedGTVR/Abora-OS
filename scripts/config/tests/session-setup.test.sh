#!/usr/bin/env bash
# Behaviour tests for first-login session setup and wallpaper seeding (scripts/config/abora-session-setup.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-session-setup.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

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

testlib_finish
