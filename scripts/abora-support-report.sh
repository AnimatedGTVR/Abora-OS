#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

version="${ABORA_VERSION:-v2.0.0-dev}"
output_root="${ABORA_SUPPORT_OUTPUT_DIR:-/tmp}"
timestamp="$(date +%Y%m%d-%H%M%S)"
report_dir="${output_root}/abora-support-${timestamp}"
archive_path="${report_dir}.tar.gz"

capture_section() {
    local title="$1"
    shift

    printf '## %s\n\n' "$title" >>"$report_dir/report.txt"
    if "$@" >>"$report_dir/report.txt" 2>&1; then
        :
    else
        printf '[command failed]\n' >>"$report_dir/report.txt"
    fi
    printf '\n' >>"$report_dir/report.txt"
}

copy_if_exists() {
    local source_path="$1"
    local target_name="$2"

    [[ -f "$source_path" ]] || return 0
    cp "$source_path" "$report_dir/$target_name"
}

main() {
    mkdir -p "$report_dir"

    printf 'Abora OS support report\n' >"$report_dir/report.txt"
    printf 'Version: %s\n' "$version" >>"$report_dir/report.txt"
    printf 'Timestamp: %s\n\n' "$(date -Is)" >>"$report_dir/report.txt"

    capture_section "System" uname -a
    capture_section "OS release" sh -lc 'cat /etc/os-release'
    capture_section "Hostnamectl" hostnamectl
    capture_section "Uptime" uptime
    capture_section "Kernel command line" sh -lc 'cat /proc/cmdline'
    capture_section "Memory" free -h
    capture_section "CPU" lscpu
    capture_section "Block devices" lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN,RM,ROTA
    capture_section "Filesystems" df -h
    capture_section "PCI" lspci -nnk
    capture_section "USB" lsusb
    capture_section "IP links" ip -br link
    capture_section "IP addresses" ip -br addr
    capture_section "Routes" ip route
    capture_section "Wireless" iw dev
    capture_section "Bluetooth" sh -lc 'rfkill list || true'
    capture_section "Dmesg (tail)" sh -lc 'dmesg | tail -n 200'
    capture_section "Current boot journal (tail)" journalctl -b -n 300 --no-pager

    copy_if_exists /tmp/abora-generate-config.log abora-generate-config.log
    copy_if_exists /tmp/abora-install.log abora-install.log

    tar -C "$output_root" -czf "$archive_path" "$(basename "$report_dir")"

    printf '%s\n' "$archive_path"
}

main "$@"
