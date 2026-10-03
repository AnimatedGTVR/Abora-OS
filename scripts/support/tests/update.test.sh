#!/usr/bin/env bash
# Behaviour tests for the updater (resolver, sync, diagnostics, routing) (scripts/support/abora-update.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-update.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

# The flake writer test below creates this and later updater tests reuse it.
tmp_update_flake="$(mktemp -d)"
testlib_cleanup_paths+=("$tmp_update_flake")

# Every path installed-base.nix requires unconditionally (also computed by the
# adopt-nixos suite, which checks its own copy list against the same set).
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
fi

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

# path:/etc/abora/nixpkgs and path:/mnt/etc/nixos/abora/nixpkgs look
# tempting because they point at a local nixpkgs tree, but they are both
# bad installed-system flake inputs: /etc resolves through /etc/static in
# pure eval, and /mnt-local copied paths can lock with stale nar hashes
# across install retries. The installer must write a GitHub nixpkgs ref
# and copy the release-pinned target lock instead of regenerating it on the
# half-installed target.
if grep -q 'inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";' "$tmp_update_flake/flake.nix" \
  && grep -q 'inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";' scripts/abora-installer.sh \
  && grep -q '/etc/abora/target-flake.lock' scripts/abora-installer.sh \
  && grep -q 'cp /etc/abora/target-flake.lock "${cfgdir}/flake.lock"' scripts/abora-installer.sh \
  && grep -q 'write_installed_flake "$root"' scripts/abora-installer.sh \
  && grep -q '^lock_target_flake()' scripts/abora-installer.sh \
  && grep -q '^build_target_system()' scripts/abora-installer.sh \
  && grep -q -- '--no-write-lock-file' scripts/abora-installer.sh \
  && grep -q 'lock_target_flake "/mnt"' scripts/abora-installer.sh \
  && grep -q 'mktemp -d /tmp/abora-target-flake' scripts/abora-installer.sh \
  && grep -q 'mktemp -d /tmp/abora-validate-flake' scripts/abora-installer.sh \
  && grep -q 'build_target_system "/mnt" "$system_path_file"' scripts/abora-installer.sh \
  && grep -q -- '--no-channel-copy' scripts/abora-installer.sh \
  && ! grep -q 'path:/etc/abora/nixpkgs' "$tmp_update_flake/flake.nix" \
  && ! grep -q 'path:/etc/abora/nixpkgs' scripts/abora-installer.sh \
  && ! grep -q 'path:/mnt/etc/nixos/abora/nixpkgs' scripts/abora-installer.sh \
  && ! grep -q 'rm -f "${cfgdir}/flake.lock"' scripts/abora-installer.sh \
  && ! grep -q 'flake lock "${cfgdir}"' scripts/abora-installer.sh \
  && ! grep -q 'flake metadata.*"${cfgdir}"' scripts/abora-installer.sh \
  && ! grep -q '"${cfgdir}#nixosConfigurations' scripts/abora-installer.sh; then
  pass "runtime: installed flake uses a release-pinned pure nixos-unstable input"
else
  fail "runtime: installed flake uses a release-pinned pure nixos-unstable input"
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
# setup.desktop) and check-release-files' manifest (same three) had the
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

testlib_finish
