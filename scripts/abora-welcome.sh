#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
[[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]] && ui_lib="/etc/abora/ui.sh"

# shellcheck source=/dev/null
source "$ui_lib"

read_setting() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    local file="${ABORA_SYSTEM_CONFIG:-/etc/nixos}/abora-local.nix"
    [[ -f "$file" ]] || return 0
    sed -nE "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\\1|p" "$file" | head -n1
}

show_status() {
    local desktop wallpaper channel flathub anix_state
    desktop="$(read_setting desktop)"
    wallpaper="$(read_setting wallpaper)"
    channel="stable"
    [[ -f /etc/nixos/abora/channel ]] && channel="$(tr -d '[:space:]' < /etc/nixos/abora/channel)"
    flathub="not configured"
    if command -v flatpak >/dev/null 2>&1 && flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -Fxq flathub; then
        flathub="configured"
    fi
    anix_state="ready"
    [[ -f /etc/nixos/anix.nix ]] || anix_state="not initialized"

    abora_card_start "System"
    abora_kv "desktop" "${desktop:-unknown}"
    abora_kv "wallpaper" "${wallpaper:-unknown}"
    abora_kv "updates" "$channel"
    abora_kv "Flathub" "$flathub"
    abora_kv "ANIX" "$anix_state"
    abora_card_end
}

menu() {
    abora_banner "Welcome To Abora" "A few useful first steps."
    show_status
    printf '\n'
    printf '  %b1%b  Run system doctor\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b2%b  Open app manager\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b3%b  Create first ANIX snapshot\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b4%b  Switch desktop\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b5%b  Open recovery tools\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %bq%b  Quit\n\n' "$ABORA_DIM" "$ABORA_NC"
}

case "${1:-menu}" in
    status)
        abora_banner "Welcome To Abora" "Current system status."
        show_status
        printf '\n'
        ;;
    menu|"")
        while true; do
            menu
            read -r -p "  Choose: " choice
            case "$choice" in
                1) abora-doctor ;;
                2) abora-apps ;;
                3) anix save "anix: first Abora snapshot" ;;
                4) abora-desktop list ;;
                5) abora-recovery ;;
                q|Q) exit 0 ;;
                *) abora_warn "Unknown choice: $choice" ;;
            esac
            printf '\n'
            read -r -p "  Press Enter to continue..." _
        done
        ;;
    help|--help|-h)
        abora_banner "Welcome" "Usage: abora-welcome [status]"
        ;;
    *)
        abora_error "Unknown welcome command: $1"
        exit 1
        ;;
esac
