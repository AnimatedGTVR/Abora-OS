#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
support_report_script="${ABORA_SUPPORT_REPORT_SCRIPT:-$script_dir/abora-support-report.sh}"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
with_report=0
fail_count=0
warn_count=0
pass_count=0
report_path=""

if [[ ! -f "$ui_lib" && -f "$script_dir/../core/abora-ui.sh" ]]; then
    ui_lib="$script_dir/../core/abora-ui.sh"
fi
if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

if [[ -f "$ui_lib" ]]; then
    # shellcheck source=/dev/null
    source "$ui_lib"
else
    # Minimal fallback UI -- used when abora-ui.sh isn't available (e.g. a
    # bare checkout before install, or a corrupted /etc/abora).
    ABORA_DIM=$'\033[38;5;242m'
    ABORA_NC=$'\033[0m'
    ABORA_CYAN=$'\033[38;5;44m'
    ABORA_WHITE=$'\033[1;97m'
    ABORA_BLUE=$'\033[38;5;33m'
    ABORA_ACCENT=$'\033[38;5;87m'
    ABORA_GREEN=$'\033[38;5;77m'
    ABORA_RED=$'\033[38;5;203m'
    ABORA_YELLOW=$'\033[38;5;222m'
    abora_banner()     { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_info()       { printf '  %b·%b  %s\n' "$ABORA_CYAN" "$ABORA_NC" "$1"; }
    abora_rule()       { printf '  %b%s%b\n' "$ABORA_DIM" "────────────────────────────────────────" "$ABORA_NC"; }
    abora_card_start() { printf '  %b┌─ %s ─%b\n' "$ABORA_BLUE" "${1:-}" "$ABORA_NC"; }
    abora_card_end()   { printf '  %b└────────%b\n' "$ABORA_BLUE" "$ABORA_NC"; }
fi

section() {
    printf '\n'
    printf '  %b▸ %s%b\n' "$ABORA_ACCENT" "$1" "$ABORA_NC"
    abora_rule
}

pass() {
    pass_count=$((pass_count + 1))
    printf '  %b✓%b  %b%s%b\n' "$ABORA_GREEN" "$ABORA_NC" "$ABORA_GREEN" "$1" "$ABORA_NC"
}

warn() {
    warn_count=$((warn_count + 1))
    printf '  %b!%b  %b%s%b\n' "$ABORA_YELLOW" "$ABORA_NC" "$ABORA_YELLOW" "$1" "$ABORA_NC"
}

fail() {
    fail_count=$((fail_count + 1))
    printf '  %b✗%b  %b%s%b\n' "$ABORA_RED" "$ABORA_NC" "$ABORA_RED" "$1" "$ABORA_NC"
}

info() {
    abora_info "$1"
}

usage() {
    cat <<'EOF'
Usage:
  abora-hardware-test
  abora-hardware-test --with-report

Checks whether the current machine looks like a good candidate for Abora
hardware testing. This is a readiness check, not a replacement for a real
USB boot and install.
EOF
}

have_command() {
    command -v "$1" >/dev/null 2>&1
}

memory_gib() {
    awk '/MemTotal:/ { printf "%.1f", $2 / 1024 / 1024 }' /proc/meminfo 2>/dev/null || printf '0'
}

# TYPE=disk alone does not mean real storage -- zram (RAM-backed swap)
# reports TYPE=disk too, confirmed directly against a real machine (lsblk
# -P showed /dev/zram0 as TYPE="disk", RM="0", TRAN=""), so the RM/TYPE
# checks below never excluded it on their own: this hardware-readiness
# tool reported zram0 as one of "2 disk target(s)" and counted it toward
# "at least one fixed internal disk is visible" -- the opposite of what
# those checks exist to confirm. abora-installer.sh already excludes
# exactly these name prefixes for the same reason (collect_disks()'s
# ^(fd|loop|ram|sr|zram) filter); both functions below mirror it.
list_disks() {
    lsblk -dn -P -e 7,11 -o NAME,SIZE,MODEL,TRAN,RM,TYPE 2>/dev/null | awk '
        {
            name = size = model = tran = rm = type = ""
            for (i = 1; i <= NF; i++) {
                split($i, pair, "=")
                key = pair[1]
                value = pair[2]
                gsub(/^"/, "", value)
                gsub(/"$/, "", value)
                if (key == "NAME") name = value
                if (key == "SIZE") size = value
                if (key == "MODEL") model = value
                if (key == "TRAN") tran = value
                if (key == "RM") rm = value
                if (key == "TYPE") type = value
            }
            if (type != "disk") {
                next
            }
            if (name ~ /^(fd|loop|ram|sr|zram)/) {
                next
            }
            if (model == "") model = "Unknown model"
            if (tran == "") tran = "internal"
            removable = (rm == "1" ? "removable" : "fixed")
            printf "/dev/%s  %s  %s  [%s, %s]\n", name, size, model, tran, removable
        }
    '
}

has_internal_disk() {
    lsblk -dn -e 7,11 -o NAME,RM,TYPE 2>/dev/null \
        | awk '$3 == "disk" && $2 == "0" && $1 !~ /^(fd|loop|ram|sr|zram)/ { found = 1 } END { exit(found ? 0 : 1) }'
}

has_transport() {
    local wanted="$1"
    lsblk -dn -e 7,11 -o TRAN,TYPE 2>/dev/null | awk -v wanted="$wanted" '$2 == "disk" && $1 == wanted { found = 1 } END { exit(found ? 0 : 1) }'
}

wifi_interfaces() {
    ip -br link 2>/dev/null | awk '$1 ~ /^(wl|wlan)/ { print $1 }'
}

ethernet_interfaces() {
    ip -br link 2>/dev/null | awk '$1 ~ /^(en|eth)/ { print $1 }'
}

bluetooth_present() {
    if have_command rfkill && rfkill list 2>/dev/null | grep -qi bluetooth; then
        return 0
    fi
    if have_command lsusb && lsusb 2>/dev/null | grep -qi bluetooth; then
        return 0
    fi
    if have_command lspci && lspci 2>/dev/null | grep -qi bluetooth; then
        return 0
    fi
    return 1
}

audio_present() {
    if have_command lspci && lspci 2>/dev/null | grep -Ei 'audio|multimedia audio controller' >/dev/null; then
        return 0
    fi
    if have_command lsusb && lsusb 2>/dev/null | grep -qi audio; then
        return 0
    fi
    return 1
}

gpu_lines() {
    if have_command lspci; then
        lspci 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true
    fi
}

main() {
    local arg=""
    local virt=""
    local mem=""
    local disk_count=0
    local gpu_output=""
    local wifi_output=""
    local eth_output=""

    for arg in "$@"; do
        case "$arg" in
            --with-report)
                with_report=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n\n' "$arg" >&2
                usage >&2
                exit 1
                ;;
        esac
    done

    abora_banner "Hardware Readiness Test" "Checks whether this machine is a suitable Abora test target."
    abora_info "This does not replace a real Abora USB boot."

    section "Firmware and platform"
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    if [[ -n "$virt" && "$virt" != "none" ]]; then
        warn "This machine appears virtualized (${virt}). Use a real machine for final confidence."
    else
        pass "Running on bare metal"
    fi

    if [[ -d /sys/firmware/efi ]]; then
        pass "UEFI firmware detected"
    else
        warn "No UEFI firmware detected. BIOS testing is still useful, but the UEFI path remains untested."
    fi

    if [[ "$(uname -m)" == "x86_64" ]]; then
        pass "x86_64 platform detected"
    else
        warn "Non-x86_64 platform detected: $(uname -m)"
    fi

    section "CPU and memory"
    mem="$(memory_gib)"
    info "Memory: ${mem} GiB"
    if awk -v mem="$mem" 'BEGIN { exit(mem >= 4.0 ? 0 : 1) }'; then
        pass "Memory meets the 4 GiB minimum for comfortable testing"
    else
        warn "Memory is under 4 GiB. Abora may still boot, but testing could feel cramped."
    fi

    if have_command lscpu; then
        info "CPU: $(lscpu 2>/dev/null | awk -F: '/Model name:/ { gsub(/^[ \t]+/, "", $2); print $2; exit }')"
    fi

    section "Storage"
    disk_count="$(list_disks | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    if [[ "$disk_count" -gt 0 ]]; then
        pass "Detected ${disk_count} disk target(s)"
        list_disks | sed 's/^/  /'
    else
        fail "No installable disks were detected by lsblk"
    fi

    if has_internal_disk; then
        pass "At least one fixed internal disk is visible"
    else
        fail "No fixed internal disk is visible. Abora would have nowhere safe to install."
    fi

    if has_transport "nvme"; then
        pass "NVMe storage is present"
    elif has_transport "sata"; then
        pass "SATA storage is present"
    else
        warn "No NVMe or SATA disk transport was detected"
    fi

    section "Graphics"
    gpu_output="$(gpu_lines)"
    if [[ -n "$gpu_output" ]]; then
        pass "Graphics controller(s) detected"
        printf '%s\n' "$gpu_output" | sed 's/^/  /'
        if printf '%s\n' "$gpu_output" | grep -qi nvidia; then
            warn "NVIDIA hardware detected. Test boot graphics, suspend, and multi-monitor behavior carefully."
            info "The installer's GPU step (and 'abora config set gpu') can pick nouveau, nvidia, or nvidia-open."
        fi
    else
        warn "No graphics controller details were detected via lspci"
    fi

    section "Networking and peripherals"
    eth_output="$(ethernet_interfaces)"
    wifi_output="$(wifi_interfaces)"

    if [[ -n "$eth_output" ]]; then
        pass "Ethernet interface(s) detected"
        printf '%s\n' "$eth_output" | sed 's/^/  /'
    else
        warn "No Ethernet interfaces detected"
    fi

    if [[ -n "$wifi_output" ]]; then
        pass "Wi-Fi interface(s) detected"
        printf '%s\n' "$wifi_output" | sed 's/^/  /'
    else
        warn "No Wi-Fi interfaces detected"
    fi

    if bluetooth_present; then
        pass "Bluetooth hardware appears to be present"
    else
        warn "Bluetooth hardware was not detected"
    fi

    if audio_present; then
        pass "Audio hardware appears to be present"
    else
        warn "Audio hardware was not detected from PCI/USB data"
    fi

    section "Abora tooling"
    if [[ -x "$support_report_script" ]]; then
        pass "Support report tool is available"
    else
        warn "Support report tool is not available at ${support_report_script}"
    fi

    if [[ "$with_report" -eq 1 ]]; then
        if [[ -x "$support_report_script" ]]; then
            report_path="$("$support_report_script" 2>/dev/null || true)"
            if [[ -n "$report_path" && -f "$report_path" ]]; then
                pass "Support report created: ${report_path}"
            else
                warn "Support report generation did not complete cleanly"
            fi
        else
            warn "Skipped report generation because the support report tool is unavailable"
        fi
    else
        info "Run with --with-report to save a support archive at the same time."
    fi

    section "Summary"

    abora_card_start "Results"
    printf '  %b│%b  %bPassed%b    %b%d%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_GREEN" "$ABORA_NC" "$ABORA_GREEN" "$pass_count" "$ABORA_NC"
    printf '  %b│%b  %bWarnings%b  %b%d%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_YELLOW" "$ABORA_NC" "$ABORA_YELLOW" "$warn_count" "$ABORA_NC"
    printf '  %b│%b  %bFailures%b  %b%d%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_RED" "$ABORA_NC" "$ABORA_RED" "$fail_count" "$ABORA_NC"
    printf '  %b│%b\n' "$ABORA_BLUE" "$ABORA_NC"
    abora_card_end

    if [[ "$fail_count" -gt 0 ]]; then
        fail "This machine is not a safe hardware test target yet."
        exit 1
    elif [[ "$warn_count" -gt 0 ]]; then
        warn "This machine looks usable for Abora hardware testing, but keep the warnings in mind."
        exit 0
    else
        pass "This machine looks ready for a first Abora hardware test."
    fi
}

main "$@"
