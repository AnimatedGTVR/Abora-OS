#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

version="${ABORA_VERSION:-v2.5.0}"
product_name="${ABORA_PRODUCT_NAME:-Abora OS}"

BLUE=$'\033[38;5;33m'
ACCENT=$'\033[38;5;87m'
WHITE=$'\033[1;97m'
DIM=$'\033[38;5;242m'
FAINT=$'\033[38;5;237m'
NC=$'\033[0m'

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


show_stage_loading() {
    local phase_one=(
        "Checking the live environment"
        "Loading Abora tools"
        "Mounting filesystems"
    )
    local phase_two=(
        "Starting live services"
        "Preparing the shell environment"
        "Ready"
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
        printf '  %b%s%b\n' "$DIM" "Preparing the live environment." "$NC"
        draw_rule
        printf '\n'
        printf '  %b%s%b\n' "$WHITE" "$stage_label" "$NC"
        printf '  %b%s%b %s\n' "$ACCENT" "$spinner_frame" "$NC" "$status_label"
        printf '\n'
        printf '  %b[%s]%b %b%3d%%%b\n' "$BLUE" "$bar" "$NC" "$WHITE" "$progress" "$NC"
        printf '\n'
        printf '  %bStage 1%b  live boot checks, core tooling, filesystems\n' "$FAINT" "$NC"
        printf '  %bStage 2%b  live services, shell environment\n' "$FAINT" "$NC"
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

    draw_stage_frame "Abora Stage 2" "Ready" "✓"
    sleep 0.30
}

boot_sequence() {
    show_stage_loading
    clear_screen

    if "$BASH_BIN" /etc/abora/installer.sh; then
        # installer exited cleanly (user chose reboot/poweroff from finish screen)
        exit 0
    else
        # installer crashed or was aborted — drop to live shell
        printf '\n'
        draw_rule
        printf '  %bInstaller exited. You are now in the live shell.%b\n' "$WHITE" "$NC"
        printf '  %bRun %babora-install%b to restart it.%b\n' "$DIM" "$WHITE" "$DIM" "$NC"
        draw_rule
        printf '\n'
        exec "$BASH_BIN" --login
    fi
}

boot_sequence
