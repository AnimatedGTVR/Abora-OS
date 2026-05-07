#!/usr/bin/env bash
set -euo pipefail

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

menu() {
    abora_banner "Recovery" "Rollback, repair, and collect diagnostics."
    printf '  %b1%b  Roll back previous generation\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b2%b  Run support report\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b3%b  Repair Flathub remote\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b4%b  Rebuild current config\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b5%b  Run ANIX doctor\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b6%b  Run Abora doctor\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %bq%b  Quit\n\n' "$ABORA_DIM" "$ABORA_NC"
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

case "${1:-menu}" in
    rollback)
        run_cmd anix rollback nix --now
        ;;
    report)
        run_cmd abora-support-report
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
        run_cmd abora-doctor
        ;;
    menu|"")
        while true; do
            menu
            read -r -p "  Choose: " choice
            case "$choice" in
                1) run_cmd anix rollback nix --now ;;
                2) run_cmd abora-support-report ;;
                3) repair_flathub ;;
                4) rebuild_current ;;
                5) run_cmd anix doctor ;;
                6) run_cmd abora-doctor ;;
                q|Q) exit 0 ;;
                *) abora_warn "Unknown choice: $choice" ;;
            esac
            printf '\n'
            read -r -p "  Press Enter to continue..." _
        done
        ;;
    help|--help|-h)
        abora_banner "Recovery" "Usage: abora recovery [rollback|report|flathub|rebuild|anix|doctor]"
        ;;
    *)
        abora_error "Unknown recovery command: $1"
        exit 1
        ;;
esac
