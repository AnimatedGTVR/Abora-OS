#!/usr/bin/env bash
# Behaviour tests for the abora dispatcher, abora-build and abora-ui helpers (scripts/core/abora.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

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

testlib_finish
