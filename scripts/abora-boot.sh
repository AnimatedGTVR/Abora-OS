#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

title_file="/etc/abora/title.txt"
version="${ABORA_VERSION:-v2.5.0}"
product_name="${ABORA_PRODUCT_NAME:-Abora OS}"
product_short="${ABORA_PRODUCT_SHORT:-Abora}"
product_tagline="${ABORA_PRODUCT_TAGLINE:-Choose how you want to start.}"

BLUE=$'\033[38;5;33m'
ACCENT=$'\033[38;5;87m'
MAGENTA=$'\033[38;5;207m'
CYAN=$'\033[38;5;44m'
WHITE=$'\033[1;97m'
DIM=$'\033[38;5;242m'
FAINT=$'\033[38;5;237m'
NC=$'\033[0m'
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
    local cols
    cols="$(tput cols 2>/dev/null || printf '80')"
    printf '%b' "$FAINT"
    local i
    for ((i = 0; i < cols - 4; i++)); do
        printf '─'
    done
    printf '%b\n' "$NC"
}

show_header() {
    local title="${1:-${product_name} ${version} live boot}"
    local subtitle="${2:-${product_tagline}}"
    local cols inner left right pad max_left

    clear_screen
    printf '\n'

    cols="$(tput cols 2>/dev/null || printf '80')"

    if [[ "$cols" -ge 78 ]]; then
        # ASCII art logo on wide terminals
        printf '  %b▸▸%b %bABORA OS%b  %b%s%s%s%b\n' \
            "$ACCENT" "$NC" \
            "$WHITE" "$NC" \
            "$DIM" \
            "$version" \
            "$FAINT" \
            "  " \
            "$NC"
        printf '\n'
        printf '  %b    ,ggg,                                                         _,gggggg,_          ,gg,%b\n' "$FAINT" "$NC"
        printf '  %b   dP""8I   ,dPYb,                                              ,d8P""d8P"Y8b,       i8""8i %b\n' "$FAINT" "$NC"
        printf '  %b  dP   88   IP'"'"'`Yb                                             ,d8'"'"'   Y8   "8b,dP    `8,,8'"'"' %b\n' "$FAINT" "$NC"
        printf '  %b dP    88   I8  8I                                             d8'"'"'    `Ybaaad88P'"'"'     `88'"'"'  %b\n' "$FAINT" "$NC"
        printf '  %b,8'"'"'    88   I8  8'"'"'                                             8P       `""""Y8       dP"8,%b\n' "$FAINT" "$NC"
        printf '  %bd88888888   I8 dP         ,ggggg,     ,gggggg,    ,gggg,gg     8b            d8      dP'"'"' `8a %b\n' "$FAINT" "$NC"
    else
        # Compact header on narrow terminals
        printf '%b╭─' "$BLUE"
        inner=$((cols - 6))
        [[ $inner -lt 18 ]] && inner=18
        left="  ▸ ABORA OS"
        right="${version}  "
        max_left=$((inner - ${#right} - 1))
        [[ $max_left -lt 6 ]] && max_left=6
        if [[ "${#left}" -gt "$max_left" ]]; then
            left="${left:0:$max_left}"
        fi
        pad=$((inner - ${#left} - ${#right}))
        [[ $pad -lt 1 ]] && pad=1
        printf '%b%s%b' "$WHITE" "$left" "$NC"
        printf '%*s' "$pad" ''
        printf '%b%s%b' "$DIM" "$right" "$NC"
        printf '╮%b\n' "$BLUE"
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
    local key="" i="" display_num=""

    while true; do
        show_header "$prompt" "Use the arrow keys or number to jump, then press Enter."

        for i in "${!options[@]}"; do
            if [[ $((i + 1)) -le 9 ]]; then
                display_num="$((i + 1))"
            elif [[ $((i + 1)) -eq 10 ]]; then
                display_num="0"
            else
                display_num=" "
            fi

            if [[ "$i" -eq "$selected" ]]; then
                printf '%b▸%b %b%s%b %b%s%b\n' \
                    "$ACCENT" "$NC" \
                    "$FAINT" "$display_num" "$NC" \
                    "$WHITE" "${options[$i]}" "$NC"
            else
                printf '  %b%s%b %b%s%b\n' \
                    "$FAINT" "$display_num" "$NC" \
                    "$DIM" "${options[$i]}" "$NC"
            fi
        done

        printf '\n'
        draw_rule
        printf '%b<↑↓> navigate  <1-%d> jump  <enter> confirm%b\n' "$DIM" "${#options[@]}" "$NC"

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
            [1-9])
                local num_idx=$((key - 1))
                if [[ "$num_idx" -lt "${#options[@]}" ]]; then
                    menu_result="$num_idx"
                    return 0
                fi
                ;;
            "")
                menu_result="$selected"
                return 0
                ;;
        esac
    done
}

show_stage_loading() {
    local phase_one=(
        "Checking the live environment"
        "Loading Abora tools"
        "Preparing the installer handoff"
    )
    local phase_two=(
        "Starting installer services"
        "Loading setup screens"
        "Opening the installer"
    )
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local idx=0
    local message=""
    local total_steps=$(( ${#phase_one[@]} + ${#phase_two[@]} ))
    local completed=0
    local progress=0
    local bar_width=34
    local filled=0
    local empty=0
    local bar=""

    draw_stage_frame() {
        local stage_label="$1"
        local status_label="$2"
        local spinner_frame="$3"

        progress=$(( completed * 100 / total_steps ))
        filled=$(( progress * bar_width / 100 ))
        empty=$(( bar_width - filled ))
        bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"

        clear_screen
        printf '\n'
        draw_rule
        printf '  %b%s%b\n' "$WHITE" "Launching ${product_name}" "$NC"
        printf '  %b%s%b\n' "$DIM" "Preparing the live environment and installer." "$NC"
        draw_rule
        printf '\n'
        printf '  %b%s%b\n' "$WHITE" "$stage_label" "$NC"
        printf '  %b%s%b %s\n' "$ACCENT" "$spinner_frame" "$NC" "$status_label"
        printf '\n'
        printf '  %b[%s]%b %b%3d%%%b\n' "$BLUE" "$bar" "$NC" "$WHITE" "$progress" "$NC"
        printf '\n'
        printf '  %bStage 1%b  live boot checks, core tooling, installer handoff\n' "$FAINT" "$NC"
        printf '  %bStage 2%b  installer services, setup screens, launch\n' "$FAINT" "$NC"
    }

    for message in "${phase_one[@]}"; do
        for idx in "${!frames[@]}"; do
            draw_stage_frame "Abora Stage 1" "$message" "${frames[$idx]}"
            sleep 0.06
        done
        completed=$((completed + 1))
    done

    for message in "${phase_two[@]}"; do
        for idx in "${!frames[@]}"; do
            draw_stage_frame "Abora Stage 2" "$message" "${frames[$idx]}"
            sleep 0.06
        done
        completed=$((completed + 1))
    done

    draw_stage_frame "Abora Stage 2" "Opening the installer" "✓"
    sleep 0.20
}

launch_installer() {
    show_stage_loading
    ABORA_SKIP_INSTALLER_LOADING=1 "$BASH_BIN" /etc/abora/installer.sh || pause_prompt
}

pause_prompt() {
    printf '\n'
    printf '%bPress ENTER to continue...%b' "$DIM" "$NC"
    read -r
}

autoboot_installer() {
    local key=""

    show_header "${product_name} ${version} live boot" "Installer-first startup."
    printf '%bAuto-starting installer in 3 seconds...%b\n' "$DIM" "$NC"
    printf '%bPress any key to open the boot menu instead.%b\n' "$DIM" "$NC"

    IFS= read -rsn1 -t 3 key || true
    if [[ -z "$key" ]]; then
        launch_installer
    fi
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

start_installer_now() {
    launch_installer
}

boot_menu() {
    local choice=""

    autoboot_installer

    while true; do
        menu_choose \
            "Select an action" \
            "Install ${product_name}" \
            "Open live shell" \
            "Reboot" \
            "Power off"
        choice="$menu_result"

        case "$choice" in
            0)
                start_installer_now
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
