#!/usr/bin/env bash
# Behaviour tests for support reports, check-full, recovery, welcome and hardware-test (scripts/support/abora-support-report.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-support-report.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

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

# abora-hardware-test.sh is now packaged standalone (nix/pkgs/hardware-test.nix)
# specifically because it has no /etc/abora dependency beyond its ui.sh
# fallback -- confirm it actually runs clean end to end on whatever machine
# is running the checks, not just that it parses.
if "$repo_dir/scripts/abora-hardware-test.sh" >/dev/null 2>&1; then
  pass "runtime: abora-hardware-test.sh runs end to end"
else
  fail "runtime: abora-hardware-test.sh exited non-zero"
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

testlib_finish
