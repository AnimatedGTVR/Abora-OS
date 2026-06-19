#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
iso_dir="${ABORA_ISO_DIR:-$out_dir/iso}"
qemu_dir="${ABORA_QEMU_DIR:-$out_dir/qemu}"
log_dir="${ABORA_LOG_DIR:-$out_dir/logs}"
iso_path="${ABORA_ISO_PATH:-}"
disk_path="${ABORA_QEMU_DISK:-$qemu_dir/abora-qemu.qcow2}"
memory_mb="${ABORA_QEMU_MEMORY_MB:-4096}"
cpu_count="${ABORA_QEMU_CPUS:-4}"
disk_size="${ABORA_QEMU_DISK_SIZE:-32G}"
boot_mode="${ABORA_QEMU_BOOT:-iso}"
nographic="${ABORA_QEMU_NOGRAPHIC:-0}"
fresh="${ABORA_QEMU_FRESH:-0}"
serial_stdio="${ABORA_QEMU_SERIAL_STDIO:-0}"
firmware_code=""
firmware_vars=""

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "qemu-system-x86_64 is required. Install qemu on your host." >&2
    exit 1
fi
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "qemu-img is required. Install qemu on your host." >&2
    exit 1
fi

case "$boot_mode" in
    iso|live|install) boot_mode="iso" ;;
    disk|installed|hard-drive|harddrive) boot_mode="disk" ;;
    *)
        echo "Invalid ABORA_QEMU_BOOT: $boot_mode (use iso or disk)." >&2
        exit 1
        ;;
esac

if [[ "$boot_mode" == "iso" && -z "$iso_path" ]]; then
    latest_iso="$(find "$iso_dir" "$out_dir" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -n 1 | cut -d' ' -f2-)"
    if [[ -z "${latest_iso:-}" ]]; then
        echo "No ISO found in $out_dir. Build one first with \`make iso\` or set ABORA_ISO_PATH." >&2
        exit 1
    fi
    iso_path="$latest_iso"
fi

if [[ "$boot_mode" == "iso" && ! -f "$iso_path" ]]; then
    echo "ISO not found: $iso_path" >&2
    exit 1
fi

mkdir -p "$out_dir" "$iso_dir" "$qemu_dir" "$log_dir"

# Fresh disk: wipe old image so installation starts clean
if [[ "$fresh" == "1" && -f "$disk_path" ]]; then
    echo "  Removing old disk image for fresh start…"
    rm -f "$disk_path"
fi

if [[ ! -f "$disk_path" ]]; then
    qemu-img create -f qcow2 "$disk_path" "$disk_size" >/dev/null
fi

# Auto-switch to disk boot when the qcow2 file is large enough to contain
# a real installation (> 200 MiB).  A freshly-created empty disk is ~200 KB.
# This lets "make qemu" work correctly after installation without the user
# having to remember "make qemu-disk".
if [[ "$boot_mode" == "iso" && -f "$disk_path" ]]; then
    _disk_bytes="$(stat -c '%s' "$disk_path" 2>/dev/null || echo 0)"
    if (( _disk_bytes > 209715200 )); then
        echo "  Found existing installation on $disk_path ($(( _disk_bytes / 1073741824 )) GiB) — booting disk."
        echo "  Use 'make qemu-fresh' to wipe and reinstall from scratch."
        boot_mode="disk"
    fi
fi

# UEFI firmware (optional — enables UEFI boot, mirrors real hardware better)
for d in \
    /usr/share/OVMF \
    /usr/share/edk2/x64 \
    /run/current-system/sw/share/OVMF \
    /nix/var/nix/profiles/system/sw/share/OVMF
do
    if [[ -f "$d/OVMF_CODE.fd" ]]; then
        firmware_code="$d/OVMF_CODE.fd"
        firmware_vars="$d/OVMF_VARS.fd"
        break
    fi
done

# Base QEMU arguments
qemu_args=(
    -m "$memory_mb"
    -smp "$cpu_count"
    -drive "file=$disk_path,format=qcow2,if=virtio"
    -netdev user,id=n1
    -device virtio-net-pci,netdev=n1
)

# KVM acceleration
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    qemu_args+=( -enable-kvm -cpu host )
else
    echo "  Note: /dev/kvm not available — running without hardware acceleration (slow)." >&2
    qemu_args+=( -cpu qemu64 )
fi

# UEFI firmware
if [[ -n "$firmware_code" && -f "${firmware_vars:-}" ]]; then
    vars_copy="$qemu_dir/OVMF_VARS.fd"
    if [[ ! -f "$vars_copy" ]]; then
        cp "$firmware_vars" "$vars_copy"
    fi
    qemu_args+=(
        -drive "if=pflash,format=raw,readonly=on,file=$firmware_code"
        -drive "if=pflash,format=raw,file=$vars_copy"
    )
fi

# Boot device
if [[ "$boot_mode" == "iso" ]]; then
    # order=c  → HDD is the persistent default (warm reboots go to disk)
    # once=d   → override to CD-ROM for this cold boot only
    # Without order=c, SeaBIOS may still try the CD on warm reboots because
    # it sees a bootable disc present — order=c prevents that.
    qemu_args+=(
        -boot order=c,once=d
        -cdrom "$iso_path"
    )
else
    # Disk-only boot: no ISO attached at all, hard disk is the only device.
    qemu_args+=( -boot order=c )
fi

# Display
if [[ "$nographic" == "1" ]]; then
    # Headless: all output (serial + monitor) in this terminal
    qemu_args+=( -nographic -serial mon:stdio )
else
    # Graphical: prefer GTK, fall back to SDL, then sdl2
    if qemu-system-x86_64 -display gtk,help >/dev/null 2>&1 || \
       qemu-system-x86_64 -display help 2>&1 | grep -q '^gtk'; then
        qemu_args+=( -display gtk,show-cursor=on,grab-on-hover=off )
    else
        qemu_args+=( -display sdl,grab-on-hover=off )
    fi
    qemu_args+=(
        -vga virtio
        -usb
        -device usb-tablet
    )
    if [[ "$serial_stdio" == "1" ]]; then
        # Keep the graphical window, but mirror the guest serial stream into
        # this terminal for installer debugging.
        qemu_args+=( -serial stdio )
    else
        # Also pipe serial to a log file so boot messages are accessible.
        qemu_args+=( -serial "file:$log_dir/abora-serial.log" )
    fi
fi

# Print launch info
if [[ "$boot_mode" == "iso" ]]; then
    echo "Booting Abora installer ISO in QEMU:"
    echo "  ISO:  $iso_path"
else
    echo "Booting installed Abora disk in QEMU:"
fi
echo "  Disk: $disk_path"
if [[ "$nographic" != "1" && "$serial_stdio" != "1" ]]; then
    echo "  Serial log: $log_dir/abora-serial.log"
fi
if [[ "$serial_stdio" == "1" && "$nographic" != "1" ]]; then
    echo "  Serial: live output mirrored into this terminal"
fi
echo "  Close the QEMU window or press Ctrl+C here to stop the VM."
echo ""

trap 'echo; echo "QEMU stopped."; exit 0' INT
set +e
qemu-system-x86_64 "${qemu_args[@]}"
rc=$?
set -e

case "$rc" in
    0|130)
        echo "QEMU stopped."
        exit 0
        ;;
    *)
        echo "QEMU exited with status $rc." >&2
        exit "$rc"
        ;;
esac
