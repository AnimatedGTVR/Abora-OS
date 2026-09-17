#!/usr/bin/env bash
# Behaviour tests for the flake-purity repair tool (scripts/config/abora-repair-flake-purity.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-repair-flake-purity.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

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

testlib_finish
