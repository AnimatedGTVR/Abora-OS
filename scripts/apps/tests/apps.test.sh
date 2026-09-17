#!/usr/bin/env bash
# Behaviour tests for the app manager, catalog and custom packages (scripts/apps/abora-apps.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-apps.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

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

testlib_finish
