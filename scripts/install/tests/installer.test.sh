#!/usr/bin/env bash
# Behaviour tests for the Denali installer's disk, boot and flake logic (scripts/install/abora-installer.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-installer.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

# Regression test for the "use an existing partition" install mode
# (list_disk_partitions/find_existing_esp/_partitions_with_children):
# extracts the real functions from abora-installer.sh (it can't be
# sourced wholesale -- it unconditionally runs `main "$@"` at the bottom)
# and exercises them against a fake `lsblk` on PATH, no root or real
# block devices required. Covers two real bug classes this code went
# through several rounds of real fixes for:
#   1. lsblk's default columnar output is space-padded/aligned, not a
#      fixed delimiter, so any value containing a space (a Windows
#      "System Reserved" LABEL being the most common real example)
#      silently shifted every field after it out of position under
#      naive `awk` field splitting -- switched to `lsblk -P`
#      (KEY="value" pairs) parsed with a portable match() loop instead.
#   2. list_disk_partitions() tagged ESP-typed partitions with "[ESP]"
#      but didn't exclude them from the candidate *root* list -- an
#      operator could select the very ESP find_existing_esp() found to
#      reuse unformatted as their new root partition instead, and
#      partition_disk_existing() would then mkfs.ext4 over it. sda5
#      below is an unmounted, unused ESP (plausible real state: left
#      over after a previous install was wiped) that must never appear
#      in list_disk_partitions()'s output even though it would pass
#      every other filter (not mounted, no busy children).
tmp_partfuncs="$(mktemp)"

tmp_lsblk_bin="$(mktemp -d)"

sed -n '/^readonly ESP_PARTTYPE_GUID=/,/^check_install_environment()/p' scripts/abora-installer.sh \
  | sed '$d' > "$tmp_partfuncs"

if [[ -s "$tmp_partfuncs" ]] && bash -n "$tmp_partfuncs" 2>/dev/null; then
  cat > "$tmp_lsblk_bin/lsblk" <<'LSBLK_SHIM'
#!/usr/bin/env bash
if [[ "$*" == *"NAME,PKNAME"* ]]; then
  printf 'NAME="sda" PKNAME=""\n'
  printf 'NAME="sda1" PKNAME="sda"\n'
  printf 'NAME="sda2" PKNAME="sda"\n'
  printf 'NAME="sda3" PKNAME="sda"\n'
  printf 'NAME="sda4" PKNAME="sda"\n'
  printf 'NAME="sda5" PKNAME="sda"\n'
  printf 'NAME="mapper-root" PKNAME="sda3"\n'
  exit 0
fi

if [[ "$*" == *"PARTTYPE,TYPE"* ]]; then
  printf 'NAME="sda1" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
  printf 'NAME="sda2" PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" TYPE="part"\n'
  printf 'NAME="sda5" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
  exit 0
fi

printf 'NAME="sda1" SIZE="2147483648" FSTYPE="vfat" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" LABEL="System Reserved" TYPE="part" MOUNTPOINT="/boot"\n'

printf 'NAME="sda2" SIZE="107374182400" FSTYPE="ext4" PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" LABEL="" TYPE="part" MOUNTPOINT=""\n'

printf 'NAME="sda3" SIZE="500000000000" FSTYPE="crypto_LUKS" PARTTYPE="" LABEL="" TYPE="part" MOUNTPOINT=""\n'

printf 'NAME="sda4" SIZE="1390104516608" FSTYPE="ntfs" PARTTYPE="" LABEL="Windows Data Disk" TYPE="part" MOUNTPOINT=""\n'

printf 'NAME="sda5" SIZE="536870912" FSTYPE="vfat" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" LABEL="" TYPE="part" MOUNTPOINT=""\n'

LSBLK_SHIM

  chmod +x "$tmp_lsblk_bin/lsblk"

  _parts_out="$(PATH="$tmp_lsblk_bin:$PATH" bash -c "source '$tmp_partfuncs'; list_disk_partitions /dev/sda")"

  _esp_out="$(PATH="$tmp_lsblk_bin:$PATH" bash -c "source '$tmp_partfuncs'; find_existing_esp /dev/sda")"

  if printf '%s' "$_parts_out" | grep -q '^/dev/sda2|' \
    && printf '%s' "$_parts_out" | grep -q '^/dev/sda4|.*(Windows Data Disk)' \
    && ! printf '%s' "$_parts_out" | grep -q '^/dev/sda1|' \
    && ! printf '%s' "$_parts_out" | grep -q '^/dev/sda3|' \
    && ! printf '%s' "$_parts_out" | grep -q '^/dev/sda5|' \
    && [[ "$_esp_out" == "/dev/sda1" ]]; then

    pass "runtime: list_disk_partitions/find_existing_esp parse lsblk -P correctly and never offer an ESP as a root candidate"

  else

    fail "runtime: list_disk_partitions/find_existing_esp parse lsblk -P correctly and never offer an ESP as a root candidate"

  fi

else

  fail "runtime: could not extract disk-partition helper functions from abora-installer.sh"

fi

rm -f "$tmp_partfuncs"

rm -rf "$tmp_lsblk_bin"

# Regression test for a real, silent boot-breaking bug: `limine
# bios-install` fails outright ("no BIOS boot partition specified or
# detected", confirmed against a real `limine` binary) on a GPT disk with
# no bios_grub partition -- exactly what "use an existing partition" mode
# produces, since it never repartitions the disk at all. nixpkgs'
# limine-install.py never checks that subprocess's exit code, so the
# failure is completely silent: a Legacy-BIOS machine using this mode
# would end up with a fully unbootable install and no error anywhere.
# Fixed with a new abora.diskBiosSupport option the installer sets to
# false only for this mode (UEFI boot through the reused ESP is
# unaffected either way). Extracts the real conditional from
# abora-installer.sh and runs it directly for both modes, and confirms
# the option is both declared in abora-options.nix and actually written
# into the generated config.
tmp_bios_snippet="$(mktemp)"

sed -n '/^    # "Use an existing partition" mode never creates a bios_grub partition$/,/^    fi$/p' scripts/abora-installer.sh \
  > "$tmp_bios_snippet"

_bios_existing="$(install_disk_mode="existing"; . "$tmp_bios_snippet"; printf '%s' "$disk_bios_support_nix")"

_bios_erase="$(install_disk_mode="erase"; . "$tmp_bios_snippet"; printf '%s' "$disk_bios_support_nix")"

rm -f "$tmp_bios_snippet"

if [[ "$_bios_existing" == "false" ]] \
  && [[ "$_bios_erase" == "true" ]] \
  && grep -q 'abora.diskBiosSupport = ${disk_bios_support_nix};' scripts/abora-installer.sh \
  && grep -q 'diskBiosSupport = lib.mkOption' nix/modules/abora-options.nix \
  && grep -q 'biosSupport         = cfg.diskBiosSupport;' nix/modules/abora-options.nix; then
  pass "runtime: installer disables Limine BIOS install for the no-bios_grub-partition disk mode"
else
  fail "runtime: installer disables Limine BIOS install for the no-bios_grub-partition disk mode"
fi

# Release-mode disk selection must stay explicit. The short release flow
# once auto-selected the only visible installable disk, which made QEMU
# fast but made real hardware too easy to wipe by muscle memory. Guard
# that release_disk() delegates to the full disk picker instead; that
# picker always asks, supports terminal/debug recovery when no disk is
# found, and exposes the existing-partition mode.
_release_disk_body="$(sed -n '/^release_disk() {/,/^}$/p' scripts/abora-installer.sh)"

if grep -q 'step_disk' <<<"$_release_disk_body" \
  && ! grep -q 'Using detected disk' <<<"$_release_disk_body" \
  && grep -q 'Use an existing partition' scripts/abora-installer.sh; then
  pass "runtime: release installer always uses the explicit disk picker"
else
  fail "runtime: release installer always uses the explicit disk picker"
fi

# Regression test for validate_boot()'s BIOS-boot-partition check
# (_has_bios_boot_partition): validate_boot()'s existing bootloader check
# only confirmed limine-bios.sys was *copied* into /mnt/boot, which
# nixpkgs' limine-install.py does unconditionally before it runs the
# subprocess that can actually fail (`limine bios-install <device>`,
# confirmed to exit 1 on a GPT disk with no BIOS-boot partition -- see the
# disk-mode commit above) -- so the file's presence proved nothing about
# whether BIOS boot would actually work. Extracts the real
# _has_bios_boot_partition function (it depends on the shared lsblk -P
# parsing prelude, so pulls that in too) and exercises it against a fake
# lsblk on PATH for both the present and missing case.
tmp_biosboot_funcs="$(mktemp)"

tmp_lsblk_bin2="$(mktemp -d)"

{

  sed -n '/^readonly ESP_PARTTYPE_GUID=/,/^check_install_environment()/p' scripts/abora-installer.sh | sed '$d'

  sed -n '/^readonly BIOS_BOOT_PARTTYPE_GUID=/,/^validate_boot()/p' scripts/abora-installer.sh | sed '$d'

} > "$tmp_biosboot_funcs"

if [[ -s "$tmp_biosboot_funcs" ]] && bash -n "$tmp_biosboot_funcs" 2>/dev/null; then
  cat > "$tmp_lsblk_bin2/lsblk" <<'LSBLK_SHIM2'
#!/usr/bin/env bash
if [[ "${DISK_HAS_BIOSGRUB:-0}" == "1" ]]; then
  printf 'NAME="sda1" PARTTYPE="21686148-6449-6e6f-744e-656564454649" TYPE="part"\n'
  printf 'NAME="sda2" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
else
  printf 'NAME="sda1" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" TYPE="part"\n'
  printf 'NAME="sda2" PARTTYPE="0fc63daf-8483-4772-8e79-3d69d8477de4" TYPE="part"\n'
fi

LSBLK_SHIM2

  chmod +x "$tmp_lsblk_bin2/lsblk"

  if PATH="$tmp_lsblk_bin2:$PATH" DISK_HAS_BIOSGRUB=1 bash -c "source '$tmp_biosboot_funcs'; _has_bios_boot_partition /dev/sda" \
    && ! PATH="$tmp_lsblk_bin2:$PATH" DISK_HAS_BIOSGRUB=0 bash -c "source '$tmp_biosboot_funcs'; _has_bios_boot_partition /dev/sda"; then

    pass "runtime: _has_bios_boot_partition correctly detects a missing BIOS-boot partition"

  else

    fail "runtime: _has_bios_boot_partition correctly detects a missing BIOS-boot partition"

  fi

else

  fail "runtime: could not extract _has_bios_boot_partition from abora-installer.sh"

fi

rm -f "$tmp_biosboot_funcs"

rm -rf "$tmp_lsblk_bin2"

if grep -q 'for _branding_git_path in' scripts/abora-installer.sh \
  && grep -A6 'for _branding_git_path in' scripts/abora-installer.sh | grep -q 'git -C "\${root}/etc/nixos" add "\$_branding_git_path"'; then
  pass "runtime: installer's branding git-add stages each path independently"
else
  fail "runtime: installer's branding git-add stages each path independently"
fi

testlib_finish
