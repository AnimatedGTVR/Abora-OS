#!/usr/bin/env bash
set -euo pipefail

title_file="/etc/abora/title.txt"

BLUE='\033[38;5;33m'
MAGENTA='\033[38;5;207m'
WHITE='\033[1;37m'
DIM='\033[38;5;245m'
NC='\033[0m'
menu_result=""

clear_screen() {
    clear || printf '\033c'
}

show_header() {
    clear_screen

    if [[ -f "$title_file" ]]; then
        printf '%b' "$WHITE"
        cat "$title_file"
        printf '%b' "$NC"
    fi

    printf '\n'
    printf '%bAbora live boot%b\n' "$WHITE" "$NC"
    printf '%bLet'\''s set up your machine...%b\n' "$DIM" "$NC"
    printf '\n'
}

read_key() {
    local key=""
    IFS= read -rsn1 key || true
    if [[ "$key" == $'\033' ]]; then
        local rest=""
        IFS= read -rsn2 -t 0.05 rest || true
        key+="$rest"
    fi
    printf '%s' "$key"
}

menu_choose() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local key=""
    local i=""

    while true; do
        show_header
        printf '%b%s%b\n' "$BLUE" "$prompt" "$NC"
        printf '\n'

        for i in "${!options[@]}"; do
            if [[ "$i" -eq "$selected" ]]; then
                printf '%b› %s%b\n' "$MAGENTA" "${options[$i]}" "$NC"
            else
                printf '  %s\n' "${options[$i]}"
            fi
        done

        printf '\n'
        printf '%b<↑↓> navigate • enter submit%b\n' "$DIM" "$NC"

        key="$(read_key)"
        case "$key" in
            $'\033[A')
                if [[ "$selected" -gt 0 ]]; then
                    selected=$((selected - 1))
                else
                    selected=$((${#options[@]} - 1))
                fi
                ;;
            $'\033[B')
                if [[ "$selected" -lt $((${#options[@]} - 1)) ]]; then
                    selected=$((selected + 1))
                else
                    selected=0
                fi
                ;;
            "")
                menu_result="$selected"
                return 0
                ;;
        esac
    done
}

pause_prompt() {
    printf '\n'
    read -r -p "Press ENTER to continue..."
}

autoboot_installer() {
    local key=""

    show_header
    printf '%bAuto-starting installer in 3 seconds...%b\n' "$DIM" "$NC"
    printf '%bPress any key to open the boot menu instead.%b\n' "$DIM" "$NC"

    IFS= read -rsn1 -t 3 key || true
    if [[ -z "$key" ]]; then
        /etc/abora/installer.sh || pause_prompt
    fi
}

open_shell() {
    clear_screen
    printf '%bOpening live shell%b\n' "$WHITE" "$NC"
    printf '%bType `exit` to return to the boot menu.%b\n\n' "$DIM" "$NC"
    ABORA_BOOT_MENU=1 bash --login
}

boot_menu() {
    local choice=""

    autoboot_installer

    while true; do
        menu_choose \
            "Select an action" \
            "Install Abora OS" \
            "Open live shell" \
            "Reboot" \
            "Power off"
        choice="$menu_result"

        case "$choice" in
            0)
                /etc/abora/installer.sh || pause_prompt
                ;;
            1)
                open_shell
                ;;
            2)
                reboot
                ;;
            3)
                poweroff
                ;;
        esac
    done
}

boot_menu
