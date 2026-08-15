#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
[[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]] && ui_lib="/etc/abora/ui.sh"

# shellcheck source=/dev/null
source "$ui_lib"

run_cmd() {
    printf '\n'
    abora_step "$*"
    "$@"
}

run_diag() {
    local rc
    printf '\n'
    abora_step "$*"
    set +e
    "$@"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
        abora_warn "Command exited with status ${rc}; continuing diagnostics."
    fi
}

menu() {
    abora_banner "Recovery" "Rollback, repair, and collect diagnostics."
    printf '  %b1%b  Roll back previous generation\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b2%b  Run support report\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b3%b  Repair Flathub remote\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b4%b  Rebuild current config\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b5%b  Run ANIX doctor\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b6%b  Run Abora doctor\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b7%b  Network diagnostics\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %bq%b  Quit\n\n' "$ABORA_DIM" "$ABORA_NC"
}

usage() {
    abora_banner "Recovery" "Rollback, repair, and collect diagnostics."
    printf '  %babora recovery%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Open the interactive recovery menu."
    printf '\n'
    printf '  %babora recovery rollback%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Roll back to the previous NixOS generation with ANIX."
    printf '\n'
    printf '  %babora recovery report%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create a redacted support archive."
    printf '\n'
    printf '  %babora recovery flathub%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Re-add the Flathub system remote."
    printf '\n'
    printf '  %babora recovery rebuild%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Rebuild the current /etc/nixos#abora config."
    printf '\n'
    printf '  %babora recovery anix%b  /  %babora recovery doctor%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Run ANIX or Abora health checks."
    printf '\n'
    printf '  %babora recovery network%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show NetworkManager, Wi-Fi, DNS, and cache connectivity status."
    printf '\n'
}

repair_flathub() {
    if ! command -v flatpak >/dev/null 2>&1; then
        abora_error "flatpak is not installed."
        return 1
    fi
    run_cmd flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

rebuild_current() {
    run_cmd sudo nixos-rebuild switch --flake /etc/nixos#abora
}

network_diagnostics() {
    abora_banner "Network Diagnostics" "Connectivity, Wi-Fi, DNS, and Abora cache checks."

    if command -v systemctl >/dev/null 2>&1; then
        run_diag systemctl --no-pager --full status NetworkManager
    else
        abora_warn "systemctl is not available."
    fi

    if command -v nmcli >/dev/null 2>&1; then
        run_diag nmcli networking connectivity check
        run_diag nmcli device status
        run_diag nmcli radio
        run_diag nmcli -f SSID,SIGNAL,SECURITY device wifi list
    else
        abora_warn "nmcli is not available."
    fi

    if command -v resolvectl >/dev/null 2>&1; then
        run_diag resolvectl status
    else
        abora_warn "resolvectl is not available."
    fi

    if command -v ping >/dev/null 2>&1; then
        run_diag ping -c 2 -W 3 1.1.1.1
    fi

    if command -v curl >/dev/null 2>&1; then
        run_diag curl -fsI --connect-timeout 5 --max-time 8 https://cache.nixos.org
    else
        abora_warn "curl is not available."
    fi
}

case "${1:-menu}" in
    rollback)
        run_cmd anix rollback nix --now
        ;;
    report)
        run_cmd abora support-report
        ;;
    flathub)
        repair_flathub
        ;;
    rebuild)
        rebuild_current
        ;;
    anix)
        run_cmd anix doctor
        ;;
    doctor)
        run_cmd abora doctor
        ;;
    network)
        network_diagnostics
        ;;
    menu|"")
        while true; do
            menu
            read -r -p "  Choose: " choice
            case "$choice" in
                1) run_cmd anix rollback nix --now ;;
                2) run_cmd abora support-report ;;
                3) repair_flathub ;;
                4) rebuild_current ;;
                5) run_cmd anix doctor ;;
                6) run_cmd abora doctor ;;
                7) network_diagnostics ;;
                q|Q) exit 0 ;;
                *) abora_warn "Unknown choice: $choice" ;;
            esac
            printf '\n'
            read -r -p "  Press Enter to continue..." _
        done
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        abora_error "Unknown recovery command: $1"
        usage >&2
        exit 1
        ;;
esac
