#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

title_file="/etc/abora/title.txt"
gui_launcher="/etc/abora/launch-gui.sh"
version="${ABORA_VERSION:-v1.0.1}"

BLUE='\033[38;5;33m'
MAGENTA='\033[38;5;207m'
WHITE='\033[1;37m'
DIM='\033[38;5;245m'
NC='\033[0m'
menu_result=""

bash_bin() {
    local candidate=""

    for candidate in "${BASH:-}" /run/current-system/sw/bin/bash /usr/bin/bash /bin/bash; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

BASH_BIN="$(bash_bin)"

clear_screen() {
    clear || printf '\033c'
}

draw_rule() {
    printf '%b' "$DIM"
    printf '────────────────────────────────────────────────────────────\n'
    printf '%b' "$NC"
}

show_header() {
    local title="${1:-Abora OS ${version} live boot}"
    local subtitle="${2:-Choose how you want to start.}"

    clear_screen

    if [[ -f "$title_file" ]]; then
        printf '%b' "$WHITE"
        cat "$title_file"
        printf '%b' "$NC"
    fi

    printf '\n'
    printf '%b%s%b\n' "$WHITE" "$title" "$NC"
    printf '%b%s%b\n' "$DIM" "$subtitle" "$NC"
    draw_rule
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
        show_header "$prompt" "Use the arrow keys, then press Enter."

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

    show_header "Abora OS ${version} live boot" "Installer-first startup."
    printf '%bAuto-starting installer in 3 seconds...%b\n' "$DIM" "$NC"
    printf '%bPress any key to open the boot menu instead.%b\n' "$DIM" "$NC"

    IFS= read -rsn1 -t 3 key || true
    if [[ -z "$key" ]]; then
        "$BASH_BIN" /etc/abora/installer.sh || pause_prompt
    fi
}

launch_gui_tool() {
    local app_id="$1"
    local label="$2"

    clear_screen
    printf '%bStarting %s on tty2%b\n' "$WHITE" "$label" "$NC"
    printf '%bClose the app window to return to the live boot menu.%b\n\n' "$DIM" "$NC"

    if [[ ! -x "$gui_launcher" ]]; then
        printf '%bThe GUI launcher is not available in this build.%b\n' "$MAGENTA" "$NC"
        pause_prompt
        return 1
    fi

    if command -v openvt >/dev/null 2>&1; then
        openvt -c 2 -f -s -w -- env ABORA_RETURN_VT=1 "$gui_launcher" "$app_id"
        return 0
    fi

    env ABORA_RETURN_VT=1 "$gui_launcher" "$app_id"
}

open_shell() {
    clear_screen
    printf '%bOpening live shell on tty2%b\n' "$WHITE" "$NC"
    printf '%bType `exit` there to return, then press Alt+F1 for the boot menu if needed.%b\n\n' "$DIM" "$NC"

    if command -v openvt >/dev/null 2>&1; then
        openvt -c 2 -f -s -w -- env ABORA_BOOT_MENU=1 "$BASH_BIN" --login
        return 0
    fi

    printf '%bTTY switching tools were unavailable, falling back to tty1.%b\n\n' "$DIM" "$NC"
    ABORA_BOOT_MENU=1 "$BASH_BIN" --login
}

boot_menu() {
    local choice=""

    autoboot_installer

    while true; do
        menu_choose \
            "Select an action" \
            "Install Abora OS" \
            "Open Abora Welcome" \
            "Open Abora Center" \
            "Open live shell" \
            "Reboot" \
            "Power off"
        choice="$menu_result"

        case "$choice" in
            0)
                "$BASH_BIN" /etc/abora/installer.sh || pause_prompt
                ;;
            1)
                launch_gui_tool "abora-welcome" "Abora Welcome"
                ;;
            2)
                launch_gui_tool "abora-center" "Abora Center"
                ;;
            3)
                open_shell
                ;;
            4)
                reboot
                ;;
            5)
                poweroff
                ;;
        esac
    done
}

boot_menu
