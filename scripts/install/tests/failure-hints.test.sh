#!/usr/bin/env bash
# Tests install_failure_hint: given the end of an install log, it should name the likely cause in plain
# language (or say nothing when it can't tell). These are the failures reported in issue #32 and #33:
# signature / key errors, build failures, installs that fail or stick on real hardware.
#
# Run: bash scripts/install/tests/failure-hints.test.sh
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
installer="$root/scripts/install/abora-installer.sh"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

fn="$(sed -n '/^install_failure_hint() {/,/^}/p' "$installer")"
[[ -n "$fn" ]] || { fail "install_failure_hint not found in abora-installer.sh"; exit 1; }
eval "$fn"

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT

# hint_for "log text" -> prints the hint (empty if none)
hint_for() {
    printf '%s\n' "$1" >"$dir/log"
    install_failure_hint "$dir/log" 2>/dev/null
}

expect_hint() {
    local name="$1" log="$2" needle="$3" got
    got="$(hint_for "$log")"
    if [[ "$got" == *"$needle"* ]]; then pass "$name"; else fail "$name: wanted a hint containing '$needle', got '${got:-<nothing>}'"; fi
}

expect_hint "full disk" 'error: writing to file: No space left on device' "ran out of space"
expect_hint "out of memory" 'cc1plus: out of memory allocating 65536 bytes' "ran out of memory"
expect_hint "oom killer" 'Out of memory: Killed process 4211 (nix-daemon)' "ran out of memory"
expect_hint "clock: certificate not yet valid" 'curl: (60) SSL certificate problem: certificate is not yet valid' "clock is wrong"
expect_hint "clock: expired certificate" 'error: unable to download: SSL certificate has expired' "clock is wrong"
expect_hint "untrusted key (the 'key verification' report)" 'error: cannot add path /nix/store/abc-foo because it lacks a signature by a trusted key' "signature was not trusted"
expect_hint "untrusted public key" 'warning: ignoring substitute for abc because it is signed by an untrusted public key' "signature was not trusted"
expect_hint "no network: dns" 'curl: (6) Could not resolve host: cache.nixos.org' "network failed"
expect_hint "no network: timeout" 'error: unable to download https://cache.nixos.org/x.narinfo: Connection timed out' "network failed"
# The three kinds of "hash mismatch" get different advice (DistroWatch's 4.0 review).
expect_hint "hash mismatch: a pinned download changed" "error: hash mismatch in fixed-output derivation '/nix/store/abc-src.drv': specified: sha256-aaa got: sha256-bbb" "didn't match the hash Abora pins"
expect_hint "hash mismatch: a store path copied off the media" "error: hash mismatch importing path '/nix/store/abc-glibc-2.40'" "USB stick or the computer's memory"
expect_hint "hash mismatch: NAR hash of a store path" "error: NAR hash mismatch in input 'path:/nix/store/xyz-source'" "USB stick or the computer's memory"
expect_hint "hash mismatch: a GitHub flake input changed upstream" "error: NAR hash mismatch in input 'github:NixOS/nixpkgs/abc'" "didn't match the hash Abora pins"
expect_hint "hash mismatch: the installer's own config" "error: NAR hash mismatch in input path:/mnt/etc/nixos" "Abora installer bug"
expect_hint "disk error" 'blk_update_request: I/O error, dev sda, sector 4096' "disk reported errors"
expect_hint "build timed out" 'error: build of /nix/store/x.drv timed out after 5400 seconds' "no output for a very long time"

# A log with nothing recognisable gives no hint (and a non-zero exit), rather than a wrong guess.
if hint_for 'building the system... done' >/dev/null; then fail "unrecognised log should give no hint"; else pass "unrecognised log gives no hint"; fi

# Only the end of the log is read, so an old, recovered problem earlier in the log doesn't cause a wrong hint.
{
    printf 'curl: (6) Could not resolve host: cache.nixos.org\n'
    for _ in $(seq 1 400); do printf 'building something\n'; done
    printf 'error: Target system build failed\n'
} >"$dir/log"
if install_failure_hint "$dir/log" >/dev/null 2>&1; then fail "an old network error far above the failure should not be blamed"; else pass "only the end of the log is considered"; fi

# install_failure_facts pulls the exact derivation, path and hashes out of the log.
facts_fn="$(sed -n '/^install_failure_facts() {/,/^}/p' "$installer")"
eval "$facts_fn"
{
    printf 'copying path /nix/store/aaa-foo\n'
    printf "error: hash mismatch in fixed-output derivation '/nix/store/abc-linux-firmware-src.drv':\n"
    printf '         specified: sha256-AAAA\n'
    printf '            got:    sha256-BBBB\n'
    printf "error: builder for '/nix/store/def-linux-firmware.drv' failed with exit code 1\n"
    printf "error: builder for '/nix/store/def-linux-firmware.drv' failed with exit code 1\n"
} >"$dir/log"
facts="$(install_failure_facts "$dir/log")"
if [[ "$facts" == *"Failed build: builder for '/nix/store/def-linux-firmware.drv' failed with exit code 1"* \
    && "$facts" == *"Hash mismatch: hash mismatch in fixed-output derivation '/nix/store/abc-linux-firmware-src.drv'"* \
    && "$facts" == *"specified: sha256-AAAA"* && "$facts" == *"got:    sha256-BBBB"* \
    && "$(grep -c 'Failed build' <<<"$facts")" -eq 1 ]]; then
    pass "failure facts name the failed build, the path, and both hashes, once each"
else
    fail "failure facts: got '${facts}'"
fi
printf 'everything fine\n' >"$dir/log"
[[ -z "$(install_failure_facts "$dir/log")" ]] && pass "no facts for a log without a specific failure" || fail "facts for a log without a failure"

# log_target_partitions: removable, readable-elsewhere filesystems, never the boot stick.
targets_fn="$(sed -n '/^log_target_partitions() {/,/^}/p' "$installer")"
eval "$targets_fn"
boot_media_disks() { printf 'sdb\n'; }
lsblk() {
    printf '%s\n' \
        '/dev/sda1 part ext4 0 sata 500G root sda' \
        '/dev/sdb1 part iso9660 1 usb 4G ABORA_LIVE sdb' \
        '/dev/sdb2 part vfat 1 usb 4M EFIBOOT sdb' \
        '/dev/sdc1 part vfat 1 usb 15G MY\x20STICK sdc' \
        '/dev/sdd1 part swap 1 usb 2G  sdd'
}
targets="$(log_target_partitions)"
unset -f lsblk boot_media_disks
if [[ "$targets" == "/dev/sdc1|15G MY STICK (vfat)" ]]; then
    pass "log USB choices skip internal disks, the boot stick, and unusable filesystems"
else
    fail "log USB choices: got '${targets}'"
fi

# Missing log file: no hint, no crash.
if install_failure_hint "$dir/does-not-exist" >/dev/null 2>&1; then fail "missing log should give no hint"; else pass "missing log gives no hint"; fi

if [[ "$failures" -eq 0 ]]; then
    printf '\nAll failure hint checks passed.\n'
else
    printf '\n%d check(s) failed.\n' "$failures"
    exit 1
fi
