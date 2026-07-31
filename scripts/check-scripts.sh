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
  "scripts/abora.sh"
  "scripts/abora-boot.sh"
  "scripts/abora-check-full.sh"
  "scripts/abora-config.sh"
  "scripts/abora-desktop.sh"
  "scripts/abora-desktop-profiles.sh"
  "scripts/abora-dotfiles-import.sh"
  "scripts/abora-doctor.sh"
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
  "docs/wiki/TinyPM-V4.md"
  "docs/wiki/Abora-Tools.md"
  "docs/wiki/Recovery.md"
  "vendor/tinypm/bin/tinypm"
  "vendor/tinypm/lib/tinypm/core/version.sh"
  "vendor/tinypm/lib/tinypm/providers/anix.sh"
)

failed=0

pass() {
  printf '[ok]   %s\n' "$1"
}

fail() {
  printf '[fail] %s\n' "$1"
  failed=1
}

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
  elif ! grep -q 'builtins.readFile ../mango/config.conf' "$tmp_mango_repair/abora/desktops/mangowm.nix"; then
    fail "pure-eval: Mango desktop module was not rewritten to installed relative path"
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
trap 'rm -rf "$tmp_ok" "$tmp_empty" "$tmp_update_flake"' EXIT

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

prealpha_dry_run_output="$(
  ABORA_PRE_ALPHA_ACCEPT="I ACCEPT THE RISK" \
  ABORA_INSTALLED_VERSION="4.0" \
  ABORA_SYSTEM_CONFIG="$tmp_update_flake" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-update.sh install pre-alpha --dry-run --ref test-prealpha 2>&1
)"
if printf '%s' "$prealpha_dry_run_output" | grep -q 'Selected update ref.*test-prealpha' \
  && printf '%s' "$prealpha_dry_run_output" | grep -q 'Dry run complete'; then
  pass "runtime: pre-alpha dry-run previews selected ref"
else
  fail "runtime: pre-alpha dry-run previews selected ref"
fi

if grep -q '^[[:space:]]*rollback)' scripts/abora.sh \
  && grep -q 'exec abora-update rollback' scripts/abora.sh \
  && grep -q '^[[:space:]]*channel)' scripts/abora.sh \
  && grep -q 'handle_channel_command "$@"' scripts/abora-update.sh; then
  pass "runtime: abora command routes update, channel, rollback, and pre-alpha"
else
  fail "runtime: abora command routes update, channel, rollback, and pre-alpha"
fi

tmp_bad_upstream="$(mktemp -d)"
mkdir -p "$tmp_bad_upstream"
if ABORA_SYSTEM_CONFIG="$tmp_update_flake" ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/abora-update.sh __test-validate-upstream "$tmp_bad_upstream" test-ref >/dev/null 2>&1; then
  fail "runtime: updater rejects incomplete upstream checkout"
else
  pass "runtime: updater rejects incomplete upstream checkout"
fi
rm -rf "$tmp_bad_upstream"

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
  && [[ -f assets/anix-languages/mako.json ]] \
  && [[ -f assets/anix-languages/moducpp.json ]] \
  && [[ -f nix/pkgs/moducpp-anix.nix ]] \
  && [[ -f tools/moducpp-anix ]]; then
  pass "runtime: release manifest includes ANIX language adapters"
else
  fail "runtime: release manifest includes ANIX language adapters"
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
  && grep -q 'ANIX standalone tarball' docs/wiki/Building-Abora.md \
  && grep -q 'abora-cosmic-' RELEASE_NOTES.md \
  && grep -q 'ANIX standalone package' RELEASE_NOTES.md \
  && grep -q 'sudo abora rollback' docs/wiki/Updating-Abora.md \
  && grep -q 'sudo abora update' docs/wiki/Abora-Tools.md \
  && grep -q 'sudo abora update' nix/modules/installed-base.nix; then
  pass "runtime: release docs describe multi-edition and ANIX package flow"
else
  fail "runtime: release docs describe multi-edition and ANIX package flow"
fi

if grep -q '/etc/abora/anix-languages' scripts/abora-installer.sh \
  && grep -q 'etc/nixos/abora/anix-languages' scripts/abora-installer.sh \
  && grep -q '/etc/abora/pkgs/moducpp-anix.nix' scripts/abora-installer.sh \
  && grep -q 'etc/nixos/abora/pkgs/moducpp-anix.nix' scripts/abora-installer.sh \
  && grep -q '"abora/pkgs/moducpp-anix.nix"' nix/profiles/live.nix \
  && grep -q 'moducpp-anix = final.callPackage ./pkgs/moducpp-anix.nix' nix/modules/installed-base.nix; then
  pass "runtime: installer copies ANIX language adapters"
else
  fail "runtime: installer copies ANIX language adapters"
fi

if grep -q 'jq' nix/pkgs/anix.nix \
  && grep -q 'moducpp-anix' nix/pkgs/anix.nix \
  && grep -q 'ANIX_SYSTEM_LANGUAGE_DIR' nix/pkgs/anix.nix \
  && grep -q 'assets/anix-languages' nix/pkgs/anix.nix; then
  pass "runtime: Nix ANIX package bundles v2 language support"
else
  fail "runtime: Nix ANIX package bundles v2 language support"
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
    && grep -q 'anix/share/anix/docs/wiki/ANIX-V2-Languages.md' "$tmp_anix_pkg_list"; then
    pass "runtime: standalone ANIX package bundles v2 language support"
  else
    fail "runtime: standalone ANIX package bundles v2 language support"
  fi
else
  fail "runtime: standalone ANIX package bundles v2 language support"
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

anix_plan_json='{"planVersion":1,"language":"test","operations":[{"op":"set","key":"hostname","value":"planhost"},{"op":"enable","feature":"bluetooth"},{"op":"package.add","name":"firefox"}]}'
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
  && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null; then
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
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable bluetooth"; then
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
  && printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*enable bluetooth"; then
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

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

printf '\nAll script checks passed.\n'
