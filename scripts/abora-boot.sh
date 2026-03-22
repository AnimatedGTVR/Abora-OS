#!/usr/bin/env bash
set -euo pipefail

logo_file="/etc/abora/fastfetch-logo.txt"

clear_screen() {
    clear || printf '\033c'
}

show_header() {
    clear_screen

    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch \
            --logo-type file-raw \
            --logo "$logo_file" \
            --structure Title:Separator:OS:Kernel:Uptime:Memory:Disk:LocalIP \
            --separator "  "
    elif [[ -f "$logo_file" ]]; then
        cat "$logo_file"
        printf '\n'
        printf 'Abora OS %s\n' "${ABORA_VERSION:-live}"
    fi

    printf '\n'
    printf 'Abora Live Boot\n'
    printf 'Simple live installer and recovery shell\n'
    printf '\n'
}

pause_prompt() {
    printf '\n'
    read -r -p "Press ENTER to continue..."
}

open_shell() {
    printf '\nOpening live shell. Type `exit` to return to the boot menu.\n\n'
    ABORA_BOOT_MENU=1 exec bash --login
}

while true; do
    show_header
    printf '[1] Install Abora OS\n'
    printf '[2] Open live shell\n'
    printf '[3] Reboot\n'
    printf '[4] Power off\n'
    printf '\n'

    read -r -p "Select an option [1-4]: " choice

    case "$choice" in
        1)
            /etc/abora/installer.sh || pause_prompt
            ;;
        2)
            open_shell
            ;;
        3)
            reboot
            ;;
        4)
            poweroff
            ;;
        *)
            printf '\nUnknown option: %s\n' "${choice:-<empty>}"
            pause_prompt
            ;;
    esac
done
