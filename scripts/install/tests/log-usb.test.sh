#!/usr/bin/env bash
# Tests which drives the failed-install screen offers for "Save logs to a USB drive": removable partitions with a
# filesystem other computers read, never the stick Abora booted from. A fake lsblk stands in for the real one.
# Run: bash scripts/install/tests/log-usb.test.sh
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/scripts/install/abora-installer.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

for name in log_target_partitions lsblk_field; do
    fn="$(sed -n "/^${name}() {/,/^}/p" "$script")"
    [[ -n "$fn" ]] || { fail "$name not found in abora-installer.sh"; exit 1; }
    eval "$fn"
done

# sdb is the Abora stick (an ISO with a FAT boot partition); sda is a USB stick whose label has a space; vda is
# the target disk. A partition's TRAN is empty in real lsblk output: that empty field is what broke the old
# `lsblk -r | read` parsing on a 4.2 test VM.
mkdir -p "$work/bin"
cat >"$work/bin/lsblk" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *-dno\ TRAN\ /dev/sda*) echo usb ;;
  *-dno\ TRAN\ /dev/sdb*) echo usb ;;
  *-dno\ TRAN\ /dev/vda*) echo "" ;;
  *-P*)
    cat <<'OUT'
NAME="/dev/sda" TYPE="disk" FSTYPE="" RM="1" SIZE="64M" LABEL="" PKNAME=""
NAME="/dev/sda1" TYPE="part" FSTYPE="vfat" RM="1" SIZE="63M" LABEL="MY\x20STICK" PKNAME="/dev/sda"
NAME="/dev/sdb" TYPE="disk" FSTYPE="iso9660" RM="1" SIZE="2G" LABEL="ABORA" PKNAME=""
NAME="/dev/sdb2" TYPE="part" FSTYPE="vfat" RM="1" SIZE="10M" LABEL="ABORA-EFI" PKNAME="/dev/sdb"
NAME="/dev/vda" TYPE="disk" FSTYPE="" RM="0" SIZE="32G" LABEL="" PKNAME=""
NAME="/dev/vda1" TYPE="part" FSTYPE="ext4" RM="0" SIZE="32G" LABEL="" PKNAME="/dev/vda"
OUT
    ;;
esac
FAKE
chmod +x "$work/bin/lsblk"
PATH="$work/bin:$PATH"
boot_media_disks() { echo sdb; }

out="$(log_target_partitions 2>&1)"
[[ "$out" == "/dev/sda1|63M MY STICK (vfat)" ]] && pass "offers the USB stick with its real size and label" \
    || fail "expected only the USB stick, got: $out"
grep -q sdb <<<"$out" && fail "offered the stick Abora booted from" || pass "never offers the boot stick"
grep -q vda <<<"$out" && fail "offered a fixed disk" || pass "never offers a fixed disk"
grep -qi "subscript" <<<"$out" && fail "bash error in the output: $out" || pass "no bash errors"

[[ "$(lsblk_field LABEL 'NAME="/dev/x" LABEL="a\x22b"')" == 'a"b' ]] && pass "decodes lsblk escapes" \
    || fail "lsblk_field didn't decode \\x22"

if (( failures )); then
    printf '\n%d log-USB check(s) failed.\n' "$failures"
    exit 1
fi
printf '\nAll log-USB checks passed.\n'
