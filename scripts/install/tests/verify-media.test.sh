#!/usr/bin/env bash
# Tests the installer's protection against corrupt packages: damaged_store_paths finds paths whose contents no
# longer match their checksum, verify_install_media repairs them once and otherwise stops with advice that fits,
# and nixos_install_with_healing retries once, only after a corrupt-path failure.
# A fake nix-store stands in for the real one, so no Nix is needed.
# Run: bash scripts/install/tests/verify-media.test.sh
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/scripts/install/abora-installer.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

for name in damaged_store_paths repair_store_paths verify_install_media nixos_install_with_healing; do
    fn="$(sed -n "/^${name}() {/,/^}/p" "$script")"
    [[ -n "$fn" ]] || { fail "$name not found in abora-installer.sh"; exit 1; }
    eval "$fn"
done

# --- a fake nix-store -----------------------------------------------------------------------------------------
# State: $work/bad lists store paths that are "damaged"; repaired paths are removed from it, but only when
# $work/can-repair exists (the machine has a network). -qR lists the closure, --verify-path complains about
# damaged ones, --repair-path fixes one.
mkdir -p "$work/bin"
cat >"$work/bin/nix-store" <<'FAKE'
#!/usr/bin/env bash
state="${FAKE_NIX_DIR:?}"
case "$1" in
  -qR) cat "$state/closure" ;;
  --verify-path)
      shift; rc=0
      if [[ -e "$state/verify-breaks" ]]; then echo "error: path '$1' is not valid" >&2; exit 1; fi
      for p in "$@"; do
          if grep -qxF "$p" "$state/bad" 2>/dev/null; then
              echo "path '$p' was modified! expected hash 'sha256:aaaa', got 'sha256:bbbb'" >&2; rc=1
          fi
      done
      exit "$rc" ;;
  --repair-path)
      [[ -e "$state/can-repair" ]] || { echo "error: cannot repair: no network" >&2; exit 1; }
      grep -vxF "$2" "$state/bad" >"$state/bad.new" 2>/dev/null; mv "$state/bad.new" "$state/bad"; echo "repaired $2" >> "$state/repairs" ;;
esac
FAKE
chmod +x "$work/bin/nix-store"
export PATH="$work/bin:$PATH" FAKE_NIX_DIR="$work"

install_log="$work/install.log"
msg() { :; }; ok() { printf '  ok: %s\n' "$1" >>"$work/ui"; }; warn() { printf '  warn: %s\n' "$1" >>"$work/ui"; }
die() { printf 'DIE: %s\n' "$1" >>"$work/ui"; return 99; }

fresh() { # fresh [damaged paths...]
    : >"$work/ui"; : >"$install_log"; rm -f "$work/can-repair" "$work/repairs"
    printf '/nix/store/aaa-glibc\n/nix/store/bbb-bash\n/nix/store/ccc-abora\n' >"$work/closure"
    : >"$work/bad"; for p in "$@"; do printf '%s\n' "$p" >>"$work/bad"; done
}

# 1. An intact system passes, quietly.
fresh
bad="$(damaged_store_paths /nix/store/sys)"; rc=$?
[[ $rc -eq 0 && -z "$bad" ]] && pass "an intact closure reports nothing" || fail "intact closure: rc=$rc out=$bad"
verify_install_media /nix/store/sys; rc=$?
[[ $rc -eq 0 ]] && grep -q "intact" "$work/ui" && pass "verify_install_media passes an intact system" || fail "verify intact: rc=$rc"

# 2. Damaged paths are named.
fresh /nix/store/bbb-bash /nix/store/ccc-abora
bad="$(damaged_store_paths /nix/store/sys)"; rc=$?
[[ $rc -eq 1 && "$bad" == $'/nix/store/bbb-bash\n/nix/store/ccc-abora' ]] && pass "damaged paths are listed, exit status 1" || fail "damaged: rc=$rc out=$bad"

# 3. With a network they are replaced, and the install goes on.
fresh /nix/store/bbb-bash; : >"$work/can-repair"
verify_install_media /nix/store/sys; rc=$?
if [[ $rc -eq 0 ]] && grep -q "replaced" "$work/ui" && grep -qxF "repaired /nix/store/bbb-bash" "$work/repairs" \
   && grep -q "\[damaged\] /nix/store/bbb-bash" "$install_log"; then
    pass "damaged packages are re-fetched and the install continues"
else fail "repair path: rc=$rc ui=$(cat "$work/ui")"; fi

# 4. Without a network, the install stops, names the package, and blames the media or memory, not Abora.
fresh /nix/store/ccc-abora
verify_install_media /nix/store/sys; rc=$?
if [[ $rc -eq 99 ]] && grep -q "ccc-abora" "$work/ui" && grep -q "USB stick" "$work/ui" && grep -q "memtest86+" "$work/ui" \
   && grep -q "\[still damaged\]" "$install_log"; then
    pass "unrepairable damage stops the install with advice that fits the cause"
else fail "unrepairable: rc=$rc ui=$(cat "$work/ui")"; fi

# 5. The check can be skipped, and an unreadable closure doesn't block an install.
fresh /nix/store/ccc-abora
ABORA_INSTALL_SKIP_VERIFY=1 verify_install_media /nix/store/sys; rc=$?
[[ $rc -eq 0 ]] && pass "ABORA_INSTALL_SKIP_VERIFY=1 skips the check" || fail "skip: rc=$rc"
fresh; : >"$work/closure"
verify_install_media /nix/store/sys; rc=$?
[[ $rc -eq 0 ]] && grep -q "Could not check" "$work/ui" && pass "an unreadable closure warns and continues" || fail "no closure: rc=$rc"

# 6. A check that itself fails (path not valid, I/O error...) is "could not check", never "corrupt".
fresh; : >"$work/verify-breaks"
bad="$(damaged_store_paths /nix/store/sys)"; rc=$?
[[ $rc -eq 2 && -z "$bad" ]] && pass "a failing check with no modified path is 'could not check', not 'damaged'" || fail "verify-breaks: rc=$rc out=$bad"
verify_install_media /nix/store/sys; rc=$?
if [[ $rc -eq 0 ]] && grep -q "Could not check" "$work/ui" && ! grep -q "do not match" "$work/ui" && ! grep -q "DIE" "$work/ui"; then
    pass "an unreadable check warns and the install goes on (no false 'bad USB stick')"
else fail "verify-breaks flow: rc=$rc ui=$(cat "$work/ui")"; fi
rm -f "$work/verify-breaks"

# 7. The count of damaged packages is the real count.
fresh /nix/store/aaa-glibc /nix/store/bbb-bash /nix/store/ccc-abora
verify_install_media /nix/store/sys >/dev/null 2>&1
grep -q "3 package(s)" "$work/ui" && pass "the damaged-package count is exact" || fail "count: $(cat "$work/ui")"

# --- nixos_install_with_healing -------------------------------------------------------------------------------
nix_config=""
calls="$work/install-calls"
# Fakes: run_with_log_panel runs the command (our fake nixos-install); the fake fails the first N times.
run_with_log_panel() { shift 2; "$@"; }
cat >"$work/bin/nixos-install" <<'FAKE'
#!/usr/bin/env bash
echo run >> "$FAKE_NIX_DIR/install-calls"
n=$(wc -l < "$FAKE_NIX_DIR/install-calls")
if (( n <= $(cat "$FAKE_NIX_DIR/fail-times") )); then
    cat "$FAKE_NIX_DIR/fail-text" >> "$FAKE_NIX_DIR/install.log"
    exit 1
fi
exit 0
FAKE
chmod +x "$work/bin/nixos-install"
try_install() { # try_install FAILS "failure text" [damaged path]
    fresh ${3:+"$3"}; : >"$work/install-calls"; printf '%s\n' "$1" >"$work/fail-times"; printf '%s\n' "$2" >"$work/fail-text"
    [[ -n "${3:-}" ]] && : >"$work/can-repair"
    nixos_install_with_healing /nix/store/sys; return $?
}

try_install 0 ""; rc=$?
[[ $rc -eq 0 && $(wc -l <"$calls") -eq 1 ]] && pass "a clean install runs once" || fail "clean install: rc=$rc calls=$(wc -l <"$calls")"

try_install 1 "error: hash mismatch importing path '/nix/store/bbb-bash'; wanted sha256:aa, got sha256:bb" /nix/store/bbb-bash; rc=$?
if [[ $rc -eq 0 && $(wc -l <"$calls") -eq 2 ]] && grep -qxF "repaired /nix/store/bbb-bash" "$work/repairs"; then
    pass "a corrupt copy is replaced and the install is retried once, then succeeds"
else fail "corrupt-then-ok: rc=$rc calls=$(wc -l <"$calls")"; fi

try_install 5 "error: hash mismatch importing path '/nix/store/bbb-bash'" /nix/store/bbb-bash; rc=$?
[[ $rc -ne 0 && $(wc -l <"$calls") -eq 2 ]] && pass "it never retries more than once" || fail "retry cap: rc=$rc calls=$(wc -l <"$calls")"

try_install 5 "error: builder for '/nix/store/x.drv' failed with exit code 1"; rc=$?
[[ $rc -ne 0 && $(wc -l <"$calls") -eq 1 ]] && pass "an ordinary failure is not retried" || fail "ordinary failure retried: calls=$(wc -l <"$calls")"

try_install 5 "error: hash mismatch in fixed-output derivation '/nix/store/y.drv': specified: sha256-aa got: sha256-bb"; rc=$?
[[ $rc -ne 0 && $(wc -l <"$calls") -eq 1 ]] && pass "a source-hash mismatch is not retried (a retry cannot fix it)" || fail "fixed-output retried: calls=$(wc -l <"$calls")"

# 8. Old corruption text already in the log must not trigger a retry for an unrelated failure.
{ echo "error: hash mismatch importing path '/nix/store/bbb-bash'"; echo "[damaged] /nix/store/bbb-bash"; } >"$install_log"
: >"$work/install-calls"; echo 5 >"$work/fail-times"; echo "error: No space left on device" >"$work/fail-text"
rm -f "$work/bad"; : >"$work/bad"
nixos_install_with_healing /nix/store/sys; rc=$?
[[ $rc -ne 0 && $(wc -l <"$calls") -eq 1 ]] && pass "stale corruption lines in the log do not cause a retry" || fail "stale log retried: rc=$rc calls=$(wc -l <"$calls")"

echo
if (( failures )); then echo "$failures check(s) failed."; exit 1; fi
echo "All media verification checks passed."
