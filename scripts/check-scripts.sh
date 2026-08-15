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
trap 'rm -rf "$tmp_ok" "$tmp_empty" "$tmp_update_flake"; rm -f "${resolver_wrapper:-}"' EXIT

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

if [[ -n "$resolver_bin" ]]; then
  export ABORA_UPDATE_RESOLVER_BIN="$resolver_bin"

  _resolver_tags="v2.5.0 v3.14"
  if ABORA_RELEASE_TAGS="$_resolver_tags" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-resolve-ref 3.14 stable | grep -q '^v3\.14[[:space:]]'; then
    pass "runtime: resolver keeps 3.14 on v3.14"
  else
    fail "runtime: resolver keeps 3.14 on v3.14"
  fi

  _resolver_tags="v2.5.0 v3.14"
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
  && grep -q 'exec abora-update channel "$@"' scripts/abora.sh \
  && ! grep -q 'ABORA_UPDATE_COMMAND=nixos abora-update channel' scripts/abora.sh \
  && grep -q 'abora channel set <stable|demo|unstable>' scripts/abora-update.sh; then
  pass "runtime: abora command routes update, channel, rollback, network, logs, bug-report, dotfiles, gaming, and pre-alpha"
else
  fail "runtime: abora command routes update, channel, rollback, network, logs, bug-report, dotfiles, gaming, and pre-alpha"
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
  && grep -q '^docs/wiki/Abora-Gaming.md$' scripts/check-release-files.sh \
  && grep -q '^docs/wiki/ANIX-V2-Languages.md$' scripts/check-release-files.sh \
  && grep -q '^docs/wiki/Updating-Abora.md$' scripts/check-release-files.sh \
  && grep -q '^vendor/modularity$' scripts/check-release-files.sh \
  && [[ -f assets/anix-languages/mako.json ]] \
  && [[ -f assets/anix-languages/moducpp.json ]] \
  && [[ -f nix/pkgs/moducpp-anix.nix ]] \
  && [[ -f tools/moducpp-anix ]] \
  && [[ -f vendor/modularity/README.md ]] \
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
  && grep -q 'vendor/modularity' scripts/abora-update.sh \
  && grep -q 'cp -R "$upstream_dir/vendor/modularity" "$abora_dir/vendor/modularity"' scripts/abora-update.sh \
  && grep -q 'docs/wiki/ANIX-V2-Languages.md' scripts/abora-update.sh \
  && grep -q 'docs/wiki/Updating-Abora.md' scripts/abora-update.sh \
  && grep -q 'Check your internet connection, then run: sudo abora update' scripts/abora-update.sh \
  && grep -q 'sudo ABORA_REPO_REF=edge abora update' docs/wiki/Updating-Abora.md \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-gaming.sh" "$abora_dir/gaming.sh"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-custom-packages.sh" "$abora_dir/custom-packages.sh"' scripts/abora-update.sh \
  && grep -q 'copy_upstream_file "$upstream_dir/scripts/abora-dotfiles-import.sh" "$abora_dir/dotfiles-import.sh"' scripts/abora-update.sh \
  && grep -q 'cp -R "$upstream_dir/docs" "$abora_dir/docs"' scripts/abora-update.sh; then
  pass "runtime: updater syncs Abora Gaming command"
else
  fail "runtime: updater syncs Abora Gaming command"
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
  && grep -q "Run 'abora apps catalog'" scripts/abora-apps.sh \
  && ! grep -q "abora-apps add" scripts/abora-apps.sh; then
  pass "runtime: config and apps help use public commands"
else
  fail "runtime: config and apps help use public commands"
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

if grep -q 'gaming_vulkan=' scripts/abora-installer.sh \
  && grep -q 'Vulkan tools' scripts/abora-installer.sh \
  && grep -q 'abora.gaming.vulkanTools = ${gaming_vulkan_nix};' scripts/abora-installer.sh \
  && grep -q 'set_nix_bool_assignment "$abora_local" "abora.gaming.vulkanTools"' scripts/abora-installer.sh; then
  pass "runtime: installer persists Abora Gaming Vulkan tools"
else
  fail "runtime: installer persists Abora Gaming Vulkan tools"
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

tmp_anix_plan_dir="$tmp_ok/anix-plan"
mkdir -p "$tmp_anix_plan_dir"

anix_plan_json='{"planVersion":1,"language":"test","operations":[{"op":"set","key":"hostname","value":"planhost"},{"op":"enable","feature":"bluetooth"},{"op":"enable","feature":"gaming"},{"op":"enable","feature":"gaming.big-picture"},{"op":"enable","feature":"gaming.vulkan"},{"op":"package.add","name":"firefox"}]}'
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
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.vulkanTools[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix apply-plan writes every operation as one transaction"
else
  fail "runtime: anix apply-plan writes every operation as one transaction"
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

tmp_anix_diff_plan_dir="$tmp_ok/anix-diff-plan"
mkdir -p "$tmp_anix_diff_plan_dir"
anix_diff_plan_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_plan_dir/plan.json" 2>&1
)"
if printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*set hostname" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable bluetooth" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.big-picture"; then
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

tmp_anix_e2e_anix="$tmp_ok/anix-e2e-anix"
mkdir -p "$tmp_anix_e2e_anix"
anix_e2e_run "examples/anix-v2/simple.anix" "$tmp_anix_e2e_anix" || true
if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_anix/anix.nix" 2>/dev/null; then
  pass "runtime: e2e .anix simple example applies through anix run"
else
  fail "runtime: e2e .anix simple example applies through anix run"
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

# ── ANIX v2 failure paths: invalid input must never mutate state ───────────

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
    scripts/abora-config.sh set gaming.big-picture off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.vulkan false >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.vulkanTools = false;' "$tmp_config_module"; then
  pass "runtime: abora config set writes gaming booleans"
else
  fail "runtime: abora config set writes gaming booleans"
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
  && grep -q "'gaming.big-picture'" scripts/abora-config-gui.py \
  && grep -q "'gaming.gamescope'" scripts/abora-config-gui.py \
  && grep -q "'gaming.vulkan'" scripts/abora-config-gui.py \
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
  abora.gaming.bigPictureShortcut = true;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.vulkanTools = true;
  abora.user.name = "abora";
  abora.user.hashedPassword = "";
  abora.disk = null;
}
EOF
if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh enable >/dev/null 2>&1 \
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
    bash scripts/abora-gaming.sh vulkan off >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.gamescopeSession = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.vulkanTools = false;' "$tmp_gaming_module"; then
  pass "runtime: abora gaming toggles write config"
else
  fail "runtime: abora gaming toggles write config"
fi

if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh bigpicture off >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_module" \
  && bash scripts/abora-gaming.sh help 2>&1 | grep -q 'abora gaming big-picture'; then
  pass "runtime: abora gaming exposes friendly Big Picture commands"
else
  fail "runtime: abora gaming exposes friendly Big Picture commands"
fi

if grep -q 'writeShellScriptBin "abora-steam-big-picture"' nix/modules/abora-options.nix \
  && grep -q 'steam -gamepadui' nix/modules/abora-options.nix \
  && grep -q 'exec steam -bigpicture' nix/modules/abora-options.nix \
  && grep -q 'Exec=abora-steam-big-picture' nix/modules/abora-options.nix \
  && grep -q 'gamescope -e -- abora-steam-big-picture' nix/modules/abora-options.nix \
  && grep -q 'pkgIf cfg.gaming.vulkanTools "vulkan-tools"' nix/modules/abora-options.nix \
  && grep -q 'steam -gamepadui' scripts/abora-gaming.sh; then
  pass "runtime: Abora Gaming Big Picture launcher has Steam flag fallback"
else
  fail "runtime: Abora Gaming Big Picture launcher has Steam flag fallback"
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
  users.users.abora = {
    hashedPassword = "!";
  };
  system.stateVersion = "26.05";
}
EOF
if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_legacy_config" \
  scripts/abora-config.sh set hostname migrated-host >/dev/null 2>&1 \
  && grep -q 'abora.hostname = "migrated-host";' "$tmp_legacy_module" \
  && grep -q 'abora.desktop = "gnome";' "$tmp_legacy_module" \
  && compgen -G "${tmp_legacy_module}.legacy.*" >/dev/null; then
  pass "runtime: abora config migrates a legacy abora-local.nix on write"
else
  fail "runtime: abora config migrates a legacy abora-local.nix on write"
fi

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

printf '\nAll script checks passed.\n'
