#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
iso_path="${ABORA_ISO_PATH:-}"
disk_path="${ABORA_QEMU_DISK:-$out_dir/abora-qemu.qcow2}"
memory_mb="${ABORA_QEMU_MEMORY_MB:-4096}"
cpu_count="${ABORA_QEMU_CPUS:-4}"
disk_size="${ABORA_QEMU_DISK_SIZE:-32G}"
firmware_code=""
firmware_vars=""

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "qemu-system-x86_64 is required to run the ISO in QEMU." >&2
    exit 1
fi

if ! command -v qemu-img >/dev/null 2>&1; then
    echo "qemu-img is required to create the QEMU disk image." >&2
    exit 1
fi

if [[ -z "$iso_path" ]]; then
    latest_iso="$(find "$out_dir" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)"
    if [[ -z "${latest_iso:-}" ]]; then
        echo "No ISO found in $out_dir. Build one first with \`make iso\` or set ABORA_ISO_PATH." >&2
        exit 1
    fi
    iso_path="$latest_iso"
fi

if [[ ! -f "$iso_path" ]]; then
    echo "ISO not found: $iso_path" >&2
    exit 1
fi

mkdir -p "$out_dir"

if [[ ! -f "$disk_path" ]]; then
    qemu-img create -f qcow2 "$disk_path" "$disk_size" >/dev/null
fi

if [[ -f /usr/share/OVMF/OVMF_CODE.fd ]]; then
    firmware_code="/usr/share/OVMF/OVMF_CODE.fd"
    firmware_vars="/usr/share/OVMF/OVMF_VARS.fd"
elif [[ -f /usr/share/edk2/x64/OVMF_CODE.fd ]]; then
    firmware_code="/usr/share/edk2/x64/OVMF_CODE.fd"
    firmware_vars="/usr/share/edk2/x64/OVMF_VARS.fd"
fi

qemu_args=(
    -m "$memory_mb"
    -smp "$cpu_count"
    -boot "order=c,once=d,menu=on"
    -cdrom "$iso_path"
    -drive "file=$disk_path,format=qcow2,if=virtio"
    -netdev user,id=n1
    -device virtio-net-pci,netdev=n1
)

if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    qemu_args+=( -enable-kvm -cpu host )
fi

if [[ -n "$firmware_code" && -n "$firmware_vars" && -f "$firmware_vars" ]]; then
    vars_copy="$out_dir/OVMF_VARS.fd"
    if [[ ! -f "$vars_copy" ]]; then
        cp "$firmware_vars" "$vars_copy"
    fi

    qemu_args+=(
        -drive "if=pflash,format=raw,readonly=on,file=$firmware_code"
        -drive "if=pflash,format=raw,file=$vars_copy"
    )
fi

echo "Booting ISO in QEMU:"
echo "  ISO:  $iso_path"
echo "  Disk: $disk_path"

exec qemu-system-x86_64 "${qemu_args[@]}"
