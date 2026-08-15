#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

version="${ABORA_VERSION:-4.0}"
release_name="${ABORA_RELEASE_NAME:-Abora OS v4 Everest}"
output_root="${ABORA_SUPPORT_OUTPUT_DIR:-/tmp}"
timestamp="$(date +%Y%m%d-%H%M%S)"
report_dir="${output_root}/abora-support-${timestamp}"
archive_path="${report_dir}.tar.gz"

usage() {
    cat <<EOF
Usage:
  abora support-report [--output-dir DIR]

Collect a redacted support archive for Abora OS bug reports.

Default output:
  ${output_root}/abora-support-<timestamp>.tar.gz

Environment:
  ABORA_SUPPORT_OUTPUT_DIR=/path  choose the output directory
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir|--out)
            [[ -n "${2:-}" ]] || {
                printf 'abora support-report: --output-dir needs a directory\n' >&2
                exit 2
            }
            output_root="$2"
            report_dir="${output_root}/abora-support-${timestamp}"
            archive_path="${report_dir}.tar.gz"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'abora support-report: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

capture_section() {
    local title="$1"
    local tmp
    shift

    printf '## %s\n\n' "$title" >>"$report_dir/report.txt"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    if "$@" >"$tmp" 2>&1; then
        :
    else
        printf '[command failed]\n' >>"$tmp"
    fi
    redact_file "$tmp" >>"$report_dir/report.txt"
    rm -f "$tmp"
    trap - RETURN
    printf '\n' >>"$report_dir/report.txt"
}

copy_if_exists() {
    local source_path="$1"
    local target_name="$2"

    [[ -f "$source_path" ]] || return 0
    redact_file "$source_path" > "$report_dir/$target_name"
}

redact_stream() {
    sed -E \
        -e 's@(^|[^[:alnum:]_])(hashedPassword|password|passwd|secret|token|api[_-]?key)([[:space:]]*[:=][[:space:]]*)("[^"]*"|'\''[^'\'']*'\''|[^[:space:];]+)@\1\2\3"[redacted]"@Ig' \
        -e 's@(github\.com/[^[:space:]]+://)?([^[:space:]@/]+):([^[:space:]@]+)@\[redacted-user\]:[redacted]@g'
}

redact_file() {
    local source_path="$1"
    redact_stream < "$source_path"
}

main() {
    mkdir -p "$report_dir"

    {
        printf 'Abora OS support report\n'
        printf 'Release: %s\n' "$release_name"
        printf 'Version ID: %s\n' "$version"
        printf 'Timestamp: %s\n\n' "$(date -Is)"
    } | redact_stream >"$report_dir/report.txt"

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
    if command -v abora >/dev/null 2>&1; then
        capture_section "Abora network diagnostics" abora network
    elif command -v abora-recovery >/dev/null 2>&1; then
        capture_section "Abora network diagnostics" abora-recovery network
    fi
    capture_section "Bluetooth" sh -lc 'rfkill list || true'
    capture_section "Dmesg (tail)" sh -lc 'dmesg | tail -n 200'
    capture_section "Current boot journal (tail)" journalctl -b -n 300 --no-pager

    copy_if_exists /tmp/abora-generate-config.log abora-generate-config.log
    copy_if_exists /tmp/abora-install.log abora-install.log
    copy_if_exists "${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/abora/dotfiles-import.log" dotfiles-import.log

    tar -C "$output_root" -czf "$archive_path" "$(basename "$report_dir")"

    printf 'Abora support archive created:\n' >&2
    printf '  %s\n' "$archive_path" >&2
    printf 'Review it before posting publicly. Obvious secrets are redacted, but you should still check it.\n' >&2
    printf '%s\n' "$archive_path"
}

main "$@"
