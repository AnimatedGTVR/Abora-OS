#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
desktop_profiles_lib="${ABORA_DESKTOP_PROFILES_LIB:-$script_dir/abora-desktop-profiles.sh}"
app_catalog_lib="${ABORA_APP_CATALOG_LIB:-$script_dir/abora-app-catalog.sh}"

if [[ ! -f "$desktop_profiles_lib" && -f /etc/abora/desktop-profiles.sh ]]; then
    desktop_profiles_lib="/etc/abora/desktop-profiles.sh"
fi

if [[ ! -f "$app_catalog_lib" && -f /etc/abora/app-catalog.sh ]]; then
    app_catalog_lib="/etc/abora/app-catalog.sh"
fi

# shellcheck source=/dev/null
source "$desktop_profiles_lib"
# shellcheck source=/dev/null
source "$app_catalog_lib"

disk=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
keyboard_value="us"
xkb_layout_value="us"
anix_enabled="yes"
desktop_profile="gnome"
desktop_label="GNOME"
desktop_variant_id="gnome"
wallpaper_name="oceandusk.png"
starter_apps_bundle="favorites"
starter_apps_label="Fan Favorites"
github_identity="Skipped"
user_password_hash=""
efi_part=""
root_part=""
config_log="/tmp/abora-generate-config.log"
install_log="/tmp/abora-install.log"
support_report_output="/tmp/abora-last-support-report.txt"

title_file="/etc/abora/title.txt"
version="${ABORA_VERSION:-v2.0.0-dev}"

BLUE='\033[38;5;33m'
MAGENTA='\033[38;5;207m'
CYAN='\033[38;5;51m'
YELLOW='\033[38;5;220m'
WHITE='\033[1;37m'
DIM='\033[38;5;245m'
GREEN='\033[38;5;84m'
RED='\033[38;5;203m'
NC='\033[0m'
menu_result=""
prompt_result=""
step_action="next"

clear_screen() {
    clear || printf '\033c'
}

draw_rule() {
    printf '%b' "$DIM"
    printf '────────────────────────────────────────────────────────────\n'
    printf '%b' "$NC"
}

show_header() {
    local title="${1:-Abora OS ${version} installer}"
    local subtitle="${2:-Set up your machine.}"

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

info() {
    printf '%b[*] %s%b\n' "$BLUE" "$1" "$NC"
}

success() {
    printf '%b[ok] %s%b\n' "$GREEN" "$1" "$NC"
}

error_msg() {
    printf '%b[x] %s%b\n' "$RED" "$1" "$NC" >&2
}

pause_prompt() {
    printf '\n'
    read -r -p "Press ENTER to continue..."
}

terminal_cols() {
    local cols=""
    cols="$(tput cols 2>/dev/null || printf '80')"
    printf '%s' "${cols:-80}"
}

terminal_rows() {
    local rows=""
    rows="$(tput lines 2>/dev/null || printf '24')"
    printf '%s' "${rows:-24}"
}

print_log_tail() {
    local logfile="$1"
    local cols=""
    local max_lines=15
    local width=0
    local line=""
    local first_error=""
    local first_error_line=0
    local current_line=0

    cols="$(terminal_cols)"
    width=$((cols - 4))

    if [[ "$width" -lt 20 ]]; then
        width=20
    fi

    if [[ ! -s "$logfile" ]]; then
        printf '%bNo log output was captured.%b\n' "$DIM" "$NC"
        return 0
    fi

    # Show the first "error:" line if it appears before the tail window
    first_error="$(grep -m1 '^error:' "$logfile" 2>/dev/null || true)"
    first_error_line="$(grep -nm1 '^error:' "$logfile" 2>/dev/null | cut -d: -f1 || true)"
    current_line="$(wc -l < "$logfile" 2>/dev/null || printf '0')"

    if [[ -n "$first_error" ]] && [[ -n "$first_error_line" ]] && \
       [[ "$first_error_line" -lt $(( current_line - max_lines )) ]]; then
        printf '%b--- First error (line %s) ---%b\n' "$DIM" "$first_error_line" "$NC"
        while IFS= read -r line; do
            if [[ "${#line}" -gt "$width" ]]; then
                printf '%s...\n' "${line:0:$((width - 3))}"
            else
                printf '%s\n' "$line"
            fi
        done < <(sed -n "${first_error_line},$((first_error_line + 4))p" "$logfile")
        printf '%b--- Recent output ---%b\n' "$DIM" "$NC"
    fi

    while IFS= read -r line; do
        # Skip noisy Nix download/ETA lines — they show inaccurate time estimates
        [[ "$line" =~ ETA[[:space:]] ]] && continue
        [[ "$line" =~ ^[[:space:]]*[0-9]+\.[0-9]+\ (GiB|MiB|KiB)[[:space:]] ]] && continue
        if [[ "${#line}" -gt "$width" ]]; then
            printf '%s...\n' "${line:0:$((width - 3))}"
        else
            printf '%s\n' "$line"
        fi
    done < <(tail -n "$max_lines" "$logfile")
}

show_failure_screen() {
    local title="$1"
    local subtitle="$2"
    local logfile="$3"
    local report_path=""

    show_header "$title" "$subtitle"
    printf '%bRecent log lines%b\n' "$WHITE" "$NC"
    draw_rule
    print_log_tail "$logfile"
    printf '\n'
    printf '%bFull log:%b %s\n' "$DIM" "$NC" "$logfile"

    if [[ -f "$support_report_output" ]]; then
        report_path="$(cat "$support_report_output" 2>/dev/null || true)"
        if [[ -n "$report_path" ]]; then
            printf '%bSupport report:%b %s\n' "$DIM" "$NC" "$report_path"
        fi
    fi
}

repeat_char() {
    local char="$1"
    local count="$2"
    local output=""

    while [[ "$count" -gt 0 ]]; do
        output+="$char"
        count=$((count - 1))
    done

    printf '%s' "$output"
}

trunc() {
    local str="$1"
    local max="$2"
    if [[ "${#str}" -gt "$max" ]]; then
        printf '%s...' "${str:0:$((max - 3))}"
    else
        printf '%s' "$str"
    fi
}

draw_progress_bar() {
    local percent="$1"
    local width=""
    local filled=0
    local empty=0

    if [[ "$percent" -lt 0 ]]; then
        percent=0
    elif [[ "$percent" -gt 100 ]]; then
        percent=100
    fi

    width=$(( $(terminal_cols) - 24 ))
    if [[ "$width" -lt 20 ]]; then
        width=20
    elif [[ "$width" -gt 42 ]]; then
        width=42
    fi

    filled=$((percent * width / 100))
    empty=$((width - filled))

    printf '%b[' "$BLUE"
    printf '%b' "$MAGENTA"
    repeat_char "█" "$filled"
    printf '%b' "$DIM"
    repeat_char "░" "$empty"
    printf '%b] %3d%%%b\n' "$NC" "$percent" "$NC"
}

format_elapsed() {
    local seconds="$1"
    local minutes=0
    local hours=0

    hours=$((seconds / 3600))
    minutes=$(((seconds % 3600) / 60))
    seconds=$((seconds % 60))

    if [[ "$hours" -gt 0 ]]; then
        printf '%02dh %02dm %02ds' "$hours" "$minutes" "$seconds"
    else
        printf '%02dm %02ds' "$minutes" "$seconds"
    fi
}

install_status_summary() {
    local logfile="$1"
    local elapsed="${2:-0}"

    if [[ ! -s "$logfile" ]]; then
        printf 'Preparing the install environment'
        return 0
    fi

    if grep -qi 'installing the boot loader' "$logfile"; then
        printf 'Installing the bootloader'
    elif grep -qi 'setting up /etc' "$logfile"; then
        printf 'Activating the new system'
    elif grep -qi 'activating the configuration' "$logfile"; then
        printf 'Activating the new system'
    elif grep -qi 'running activation' "$logfile"; then
        printf 'Activating the new system'
    elif grep -qi 'created.*symlinks in user environment' "$logfile"; then
        printf 'Linking system environment'
    elif grep -qi 'building the configuration' "$logfile"; then
        printf 'Building the system configuration'
    elif grep -qi "copying path '/nix/store" "$logfile"; then
        printf 'Copying system packages'
    elif grep -qi 'writing the system profile' "$logfile"; then
        printf 'Writing the installed system'
    else
        printf 'Writing the installed system'
    fi
}

install_progress_percent() {
    local logfile="$1"
    local elapsed="$2"
    local line_count=0
    local progress=45

    if [[ -f "$logfile" ]]; then
        line_count="$(wc -l < "$logfile")"
    fi

    progress=$((45 + line_count / 8 + elapsed / 6))

    if grep -qi 'building the configuration' "$logfile" 2>/dev/null; then
        [[ "$progress" -lt 60 ]] && progress=60
    fi

    if grep -qi "copying path '/nix/store" "$logfile" 2>/dev/null; then
        [[ "$progress" -lt 70 ]] && progress=70
    fi

    if grep -qi 'created.*symlinks in user environment' "$logfile" 2>/dev/null; then
        [[ "$progress" -lt 82 ]] && progress=82
    fi

    if grep -qi 'activating the configuration\|setting up /etc\|running activation' "$logfile" 2>/dev/null; then
        [[ "$progress" -lt 88 ]] && progress=88
    fi

    if grep -qi 'installing the boot loader' "$logfile" 2>/dev/null; then
        [[ "$progress" -lt 93 ]] && progress=93
    fi

    # Let time push progress up to 99 — no artificial freeze at 94
    [[ "$progress" -gt 99 ]] && progress=99

    printf '%s' "$progress"
}

show_install_progress_screen() {
    local percent="$1"
    local status_text="$2"
    local elapsed="$3"
    local logfile="${4:-}"

    show_header "Installing Abora OS" "Writing the system — usually 5–10 min on a fast connection."
    printf '%bProgress%b\n' "$WHITE" "$NC"
    draw_progress_bar "$percent"
    printf '\n'
    printf '  Status:   %s\n' "$status_text"
    printf '  Elapsed:  %s\n' "$(format_elapsed "$elapsed")"

    if [[ -n "$logfile" ]]; then
        printf '\n'
        printf '%bRecent log lines%b\n' "$WHITE" "$NC"
        draw_rule
        print_log_tail "$logfile"
    fi
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
    local display_num=""
    local num_idx=0
    local max_visible=10
    local start=0
    local end=0

    while true; do
        show_header "$prompt" "Arrow keys or number to jump, Enter to confirm, Esc to go back."

        if [[ "${#options[@]}" -le "$max_visible" ]]; then
            start=0
            end=$((${#options[@]} - 1))
        else
            start=$((selected - (max_visible / 2)))
            if [[ "$start" -lt 0 ]]; then
                start=0
            fi

            end=$((start + max_visible - 1))
            if [[ "$end" -ge "${#options[@]}" ]]; then
                end=$((${#options[@]} - 1))
                start=$((end - max_visible + 1))
            fi
        fi

        if [[ "$start" -gt 0 ]]; then
            printf '%b  ↑ more choices above%b\n' "$DIM" "$NC"
        fi

        for ((i = start; i <= end; i++)); do
            if [[ $((i + 1)) -le 9 ]]; then
                display_num="$((i + 1))"
            elif [[ $((i + 1)) -eq 10 ]]; then
                display_num="0"
            else
                display_num=" "
            fi
            if [[ "$i" -eq "$selected" ]]; then
                printf '%b›%b [%s] %b%s%b\n' "$BLUE" "$NC" "$display_num" "$MAGENTA" "${options[$i]}" "$NC"
            else
                printf '%b  [%s]%b %s\n' "$DIM" "$display_num" "$NC" "${options[$i]}"
            fi
        done

        if [[ "$end" -lt $((${#options[@]} - 1)) ]]; then
            printf '%b  ↓ more choices below%b\n' "$DIM" "$NC"
        fi

        printf '\n'
        printf '%b<↑↓> navigate  <1-9> jump  <enter> confirm  <esc> back%b\n' "$DIM" "$NC"

        key="$(read_key)"
        case "$key" in
            $'\033')
                menu_result="__back__"
                return 0
                ;;
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
                num_idx=$((key - 1))
                if [[ "$num_idx" -lt "${#options[@]}" ]]; then
                    menu_result="$num_idx"
                    return 0
                fi
                ;;
            "0")
                num_idx=9
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

prompt_input() {
    local prompt="$1"
    local default_value="${2:-}"
    local subtitle="${3:-Type a value and press Enter. Type /back to return.}"
    local input=""

    while true; do
        show_header "$prompt" "$subtitle"
        if [[ -n "$default_value" ]]; then
            read -r -p "> [${default_value}] " input
            prompt_result="${input:-$default_value}"
        else
            read -r -p "> " input
            prompt_result="$input"
        fi
        if [[ "$prompt_result" == "/back" ]]; then
            prompt_result="__back__"
        fi
        return 0
    done
}

set_step_next() {
    step_action="next"
}

set_step_back() {
    step_action="back"
}

set_step_cancel() {
    step_action="cancel"
}

set_step_install() {
    step_action="install"
}

set_step_stay() {
    step_action="stay"
}

sync_starter_apps_label() {
    case "${starter_apps_bundle,,}" in
        none)
            starter_apps_label="No starter apps"
            ;;
        favorites)
            starter_apps_label="Fan Favorites"
            ;;
        essentials)
            starter_apps_label="Essentials"
            ;;
        social)
            starter_apps_label="Social"
            ;;
        creator)
            starter_apps_label="Creator"
            ;;
        developer)
            starter_apps_label="Developer"
            ;;
        *)
            starter_apps_label="Custom"
            ;;
    esac
}

refresh_github_identity() {
    local login=""

    if ! command -v gh >/dev/null 2>&1; then
        github_identity="GitHub CLI unavailable"
        return 0
    fi

    if gh auth status --hostname github.com >/dev/null 2>&1; then
        login="$(gh api user --jq '.login' 2>/dev/null || true)"
        if [[ -n "$login" ]]; then
            github_identity="Signed in as ${login}"
        else
            github_identity="Signed in"
        fi
    else
        github_identity="Skipped"
    fi
}

auto_detect_timezone() {
    local detected=""
    detected="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    if [[ -n "$detected" ]] && timezone_exists "$detected" 2>/dev/null; then
        timezone_value="$detected"
    fi
}

auto_detect_keyboard() {
    local detected=""
    detected="$(localectl status 2>/dev/null | awk '/VC Keymap:/ { print $3 }' || true)"
    # Only accept values that look like a real keymap name (letters, digits, hyphens).
    # This rejects localectl outputs like "(unset)", "n/a", or empty strings.
    if [[ "$detected" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        keyboard_value="$detected"
        sync_xkb_layout
    fi
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error_msg "This installer must run as root."
        exit 1
    fi
}

resolve_nixpkgs_path() {
    local candidate=""

    for candidate in \
        "${ABORA_NIXPKGS_PATH:-}" \
        /etc/abora/nixpkgs \
        /etc/nix/path/nixpkgs \
        /run/current-system/nixpkgs/nixpkgs \
        /nix/var/nix/profiles/per-user/root/channels/nixos \
        /nix/var/nix/profiles/per-user/root/channels
    do
        if [[ -n "$candidate" && -e "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

load_keyboard_layout() {
    if command -v loadkeys >/dev/null 2>&1; then
        loadkeys "$keyboard_value" >/dev/null 2>&1 || true
    fi
}

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        printf 'UEFI'
    else
        printf 'Legacy BIOS'
    fi
}

system_memory_gib() {
    local mem_kib="0"
    mem_kib="$(awk '/MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || printf '0')"
    awk -v kib="$mem_kib" 'BEGIN { printf "%.1f GiB", kib / 1024 / 1024 }'
}

cpu_summary() {
    lscpu 2>/dev/null | awk -F: '/Model name:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || printf 'Unknown CPU'
}

selected_disk_summary() {
    [[ -n "$disk" ]] || {
        printf 'No disk selected yet'
        return 0
    }

    lsblk -dn -o NAME,SIZE,MODEL,TRAN,RM "$disk" 2>/dev/null | awk '
        {
            model = ($3 == "" ? "Unknown model" : $3)
            tran = ($4 == "" ? "internal" : $4)
            removable = ($5 == "1" ? "removable" : "fixed")
            printf "/dev/%s  %s  %s  [%s, %s]\n", $1, $2, model, tran, removable
        }
    ' || printf '%s\n' "$disk"
}

hardware_summary_text() {
    cat <<EOF
Boot mode:   $(detect_boot_mode)
Memory:      $(system_memory_gib)
CPU:         $(cpu_summary)
Disk target: $(selected_disk_summary)
Desktop:     ${desktop_label}
Apps:        ${starter_apps_label}
GitHub:      ${github_identity}
EOF
}

save_support_report() {
    local report_path=""

    if [[ ! -x /etc/abora/support-report.sh ]]; then
        error_msg "The support report tool is not available in this build."
        pause_prompt
        return 1
    fi

    show_header "Saving support report" "Collecting hardware and log details."
    printf 'Abora is gathering a support report now.\n'
    printf '\n'
    report_path="$(/etc/abora/support-report.sh 2>/dev/null || true)"
    if [[ -n "$report_path" && -f "$report_path" ]]; then
        printf '%s\n' "$report_path" > "$support_report_output"
        success "Support report saved"
        printf '\nReport archive:\n  %s\n' "$report_path"
    else
        error_msg "Support report generation failed."
    fi
    pause_prompt
}

show_hardware_summary() {
    show_header "Hardware summary" "Useful before testing or filing a report."
    hardware_summary_text
    printf '\n'
    printf 'Tip: use "Save support report" to capture hardware details and current logs.\n'
    pause_prompt
}

preflight_warnings_text() {
    local root_device=""
    local root_parent=""

    if root_device="$(findmnt -n -o SOURCE / 2>/dev/null)"; then
        root_parent="$(lsblk -no PKNAME "$root_device" 2>/dev/null || true)"
    fi

    if [[ -n "$root_parent" && "$disk" == "/dev/${root_parent}" ]]; then
        printf '%bWarning:%b the selected disk appears to back the current live system.\n' "$RED" "$NC"
        printf 'Installing to the live USB disk will erase the media you booted from.\n\n'
    fi

    if [[ "$(awk '/MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || printf '0')" -lt 4194304 ]]; then
        printf '%bWarning:%b system memory is under 4 GiB. Expect slower installs and desktop startup.\n\n' "$RED" "$NC"
    fi
}

sync_xkb_layout() {
    case "$keyboard_value" in
        uk)
            xkb_layout_value="gb"
            ;;
        *)
            xkb_layout_value="$keyboard_value"
            ;;
    esac
}

prompt_keyboard_layout() {
    local input=""

    while true; do
        prompt_input "Choose keyboard layout" "$keyboard_value" \
            "Enter a layout code (e.g. us, gb, de, fr, es, it). Type /back to return."
        input="$prompt_result"
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi
        if [[ "$input" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            keyboard_value="$input"
            sync_xkb_layout
            load_keyboard_layout
            set_step_next
            return 0
        fi
        error_msg "Invalid layout code. Use letters, numbers, or hyphens (e.g. us, gb, de, fr)."
        pause_prompt
    done
}

prompt_locale() {
    while true; do
        menu_choose \
            "Locale settings" \
            "Continue" \
            "Timezone: ${timezone_value}" \
            "Keyboard: ${keyboard_value}" \
            "Back"

        case "$menu_result" in
            "__back__"|3)
                set_step_back
                return 0
                ;;
            0)
                set_step_next
                return 0
                ;;
            1)
                prompt_timezone
                if [[ "$step_action" == "back" ]]; then
                    set_step_stay
                fi
                ;;
            2)
                prompt_keyboard_layout
                if [[ "$step_action" == "back" ]]; then
                    set_step_stay
                fi
                ;;
        esac
    done
}

find_zoneinfo_dir() {
    local candidate=""

    for candidate in \
        "${ABORA_ZONEINFO_PATH:-}" \
        /usr/share/zoneinfo \
        /run/current-system/sw/share/zoneinfo \
        /etc/zoneinfo
    do
        if [[ -n "$candidate" && -d "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

collect_timezones() {
    local zoneinfo_dir=""

    zoneinfo_dir="$(find_zoneinfo_dir)" || return 1

    find "$zoneinfo_dir" -type f | sed "s#^${zoneinfo_dir}/##" | grep -Ev \
        '^(posix/|right/|SystemV/|localtime$|posixrules$|leap-seconds.list$|leapseconds$|tzdata.zi$|zone.tab$|zone1970.tab$|iso3166.tab$)' \
        | sort -u
}

timezone_exists() {
    local value="${1:-}"

    [[ -n "$value" ]] || return 1
    collect_timezones | grep -Fxq "$value"
}

show_about_abora() {
    show_header "Welcome to Abora OS" "A simpler path into NixOS."
    printf 'Abora is trying to make NixOS feel more human from the start.\n'
    printf '\n'
    printf 'This installer keeps the advanced NixOS base, but gives you:\n'
    printf '  - a cleaner first-run path\n'
    printf '  - easier desktop selection\n'
    printf '  - optional starter apps before first boot\n'
    printf '  - a system that still updates the NixOS way\n'
    printf '\n'
    printf 'You are still in the live environment right now.\n'
    printf 'Nothing is written to disk until you confirm the install.\n'
    pause_prompt
}

open_live_shell_from_installer() {
    local shell_bin="${SHELL:-/run/current-system/sw/bin/bash}"

    show_header "Live shell" "Exit the shell to return to the installer."
    printf '%bOpening a root shell in the live environment.%b\n' "$DIM" "$NC"
    printf '%bType exit when you want to come back here.%b\n\n' "$DIM" "$NC"
    "$shell_bin" --login || true
}

starter_apps_preview() {
    local app_id=""
    local app_name=""

    if [[ "${starter_apps_bundle,,}" == "none" ]]; then
        printf 'No extra starter apps are selected.\n'
        return 0
    fi

    printf 'Bundle: %s\n' "$starter_apps_label"
    printf '\n'

    while IFS= read -r app_id; do
        [[ -n "$app_id" ]] || continue
        app_name="$(abora_catalog_name "$app_id" 2>/dev/null || printf '%s' "$app_id")"
        printf '  - %s\n' "$app_name"
    done < <(abora_catalog_bundle_ids "$starter_apps_bundle")
}

show_starter_apps_preview() {
    show_header "Starter apps" "These apps will be preinstalled on the new system."
    starter_apps_preview
    pause_prompt
}

pick_starter_apps_bundle() {
    local labels=(
        "No starter apps"
        "Fan Favorites"
        "Essentials"
        "Social"
        "Creator"
        "Developer"
        "Back"
    )
    local values=(
        "none"
        "favorites"
        "essentials"
        "social"
        "creator"
        "developer"
    )

    menu_choose "Choose starter apps" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#values[@]}" ]]; then
        set_step_back
        return 0
    fi

    starter_apps_bundle="${values[$menu_result]}"
    sync_starter_apps_label
    set_step_next
}

sync_anix_label() {
    if [[ "$anix_enabled" == "yes" ]]; then
        printf 'Enabled'
    else
        printf 'Disabled'
    fi
}

prompt_anix_opt_in() {
    while true; do
        show_header "ANIX — NixOS made simple" "Decide how you want to manage your system."
        draw_rule
        printf '\n'
        printf '  %bANIX%b is a lightweight layer that lets you change your desktop,\n' "$WHITE" "$NC"
        printf '  hostname, timezone, and keyboard with simple commands:\n'
        printf '\n'
        printf '  %banix set desktop gnome%b\n' "$CYAN" "$NC"
        printf '  %banix set hostname mypc%b\n' "$CYAN" "$NC"
        printf '  %banix apply%b\n' "$CYAN" "$NC"
        printf '\n'
        printf '  It also keeps local Git snapshots so you can roll back any change.\n'
        printf '\n'
        draw_rule
        printf '  Currently: %b%s%b\n\n' "$CYAN" "$(sync_anix_label)" "$NC"

        menu_choose "ANIX setup" \
            "Enable ANIX (recommended)" \
            "Disable ANIX" \
            "Back"

        case "$menu_result" in
            "__back__"|2)
                set_step_back
                return 0
                ;;
            0)
                anix_enabled="yes"
                set_step_next
                return 0
                ;;
            1)
                anix_enabled="no"
                set_step_next
                return 0
                ;;
        esac
    done
}

_net_signal_bar() {
    local sig="${1:-0}"
    if   [[ "$sig" -ge 80 ]]; then printf '████'
    elif [[ "$sig" -ge 60 ]]; then printf '███░'
    elif [[ "$sig" -ge 40 ]]; then printf '██░░'
    elif [[ "$sig" -ge 20 ]]; then printf '█░░░'
    else                           printf '░░░░'
    fi
}

_net_scan_wifi() {
    local raw line ssid signal security rest
    wifi_ssids=()
    wifi_signals=()
    wifi_security=()

    nmcli device wifi rescan 2>/dev/null || true

    # Parse terse nmcli output robustly:
    # Format:  SSID:SIGNAL:SECURITY   (colons in SSID are escaped as \:)
    # We split from the right: last field = SECURITY, second-to-last = SIGNAL, rest = SSID
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Strip trailing whitespace
        line="${line%"${line##*[![:space:]]}"}"

        # Extract SECURITY (everything after last unescaped colon)
        security="${line##*:}"
        rest="${line%:"$security"}"

        # Extract SIGNAL (everything after last unescaped colon in rest)
        signal="${rest##*:}"
        ssid="${rest%:"$signal"}"

        # Unescape \: in SSID
        ssid="${ssid//\\:/: }"
        ssid="${ssid% }"

        [[ -z "$ssid" || "$ssid" == "--" ]] && continue
        [[ "$signal" =~ ^[0-9]+$ ]] || continue

        # Deduplicate: skip if SSID already seen
        local seen=0
        local j
        for j in "${!wifi_ssids[@]}"; do
            [[ "${wifi_ssids[$j]}" == "$ssid" ]] && seen=1 && break
        done
        [[ "$seen" -eq 1 ]] && continue

        wifi_ssids+=("$ssid")
        wifi_signals+=("$signal")
        wifi_security+=("$security")
    done < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null \
        | sort -t: -k2 -rn 2>/dev/null \
        || true)
}

_net_is_connected() {
    nmcli -t networking connectivity check 2>/dev/null | grep -q "^full$"
}

prompt_network_connect() {
    local wifi_ssids=()
    local wifi_signals=()
    local wifi_security=()
    local connected=0
    local selected=0
    local status_msg=""
    local key=""
    local i=0

    _net_is_connected && connected=1
    _net_scan_wifi

    while true; do
        # ── Draw screen ───────────────────────────────────────────────────────
        show_header "Network" "Choose a network to connect before installing."

        # Ethernet section
        local eth_found=0
        while IFS= read -r iface; do
            [[ -z "$iface" ]] && continue
            eth_found=1
            local state
            state="$(nmcli -t -f GENERAL.STATE device show "$iface" 2>/dev/null \
                | cut -d: -f2 | head -1 || true)"
            if printf '%s' "$state" | grep -qi "connected"; then
                printf '  %b✔  Ethernet (%s) — connected%b\n' "$GREEN" "$iface" "$NC"
                connected=1
            else
                printf '  %b─  Ethernet (%s) — unplugged%b\n' "$DIM" "$iface" "$NC"
            fi
        done < <(nmcli -t -f DEVICE,TYPE device 2>/dev/null \
            | awk -F: '$2=="ethernet"{print $1}' || true)

        printf '\n'

        # WiFi section header
        if [[ "${#wifi_ssids[@]}" -eq 0 ]]; then
            printf '  %bNo wireless networks found.%b\n' "$DIM" "$NC"
        else
            # Total rows = wifi list + divider + Rescan + Continue/Skip
            local total=$(( ${#wifi_ssids[@]} + 2 ))
            local max_wifi=12
            local start=0
            local end=$(( ${#wifi_ssids[@]} - 1 ))

            # Scroll window around selection (wifi items only)
            if [[ "${#wifi_ssids[@]}" -gt "$max_wifi" ]]; then
                start=$(( selected - max_wifi / 2 ))
                [[ "$start" -lt 0 ]] && start=0
                end=$(( start + max_wifi - 1 ))
                [[ "$end" -ge "${#wifi_ssids[@]}" ]] && end=$(( ${#wifi_ssids[@]} - 1 )) && start=$(( end - max_wifi + 1 ))
            fi

            [[ "$start" -gt 0 ]] && printf '  %b↑ more above%b\n' "$DIM" "$NC"

            for (( i = start; i <= end; i++ )); do
                local bar sig sec locked ssid_display
                sig="${wifi_signals[$i]:-0}"
                sec="${wifi_security[$i]:-}"
                bar="$(_net_signal_bar "$sig")"
                [[ -n "$sec" && "$sec" != "--" ]] && locked=" 🔒" || locked=""
                ssid_display="${wifi_ssids[$i]}"

                if [[ "$i" -eq "$selected" ]]; then
                    printf '%b›  %s  %b%s%b%s\n' "$BLUE" "$bar" "$WHITE" "$ssid_display" "$NC" "$locked"
                else
                    printf '   %b%s  %s%b%s\n' "$DIM" "$bar" "$ssid_display" "$NC" "$locked"
                fi
            done

            [[ "$end" -lt $(( ${#wifi_ssids[@]} - 1 )) ]] && printf '  %b↓ more below%b\n' "$DIM" "$NC"
        fi

        printf '\n'
        draw_rule

        # Bottom actions
        local action_rescan="  [ R ] Rescan"
        local action_continue
        if [[ "$connected" -eq 1 ]]; then
            action_continue="  [ C ] Continue  ›  (connected)"
        else
            action_continue="  [ S ] Skip (no internet)"
        fi
        printf '%b%s%b\n' "$DIM" "$action_rescan" "$NC"
        printf '%b%s%b\n' "$DIM" "$action_continue" "$NC"
        printf '\n'

        if [[ -n "$status_msg" ]]; then
            printf '  %s\n\n' "$status_msg"
            status_msg=""
        fi

        printf '%b<↑↓> select  <enter> connect  <R> rescan  <C/S> continue  <esc> back%b\n' "$DIM" "$NC"

        # ── Input ─────────────────────────────────────────────────────────────
        key="$(read_key)"
        case "$key" in
            $'\033')
                set_step_back; return 0
                ;;
            $'\033[A')   # up
                if [[ "${#wifi_ssids[@]}" -gt 0 ]]; then
                    selected=$(( selected - 1 ))
                    [[ "$selected" -lt 0 ]] && selected=$(( ${#wifi_ssids[@]} - 1 ))
                fi
                ;;
            $'\033[B')   # down
                if [[ "${#wifi_ssids[@]}" -gt 0 ]]; then
                    selected=$(( selected + 1 ))
                    [[ "$selected" -ge "${#wifi_ssids[@]}" ]] && selected=0
                fi
                ;;
            r|R)
                status_msg="${DIM}Scanning…${NC}"
                _net_scan_wifi
                selected=0
                _net_is_connected && connected=1
                ;;
            c|C|s|S)
                set_step_next; return 0
                ;;
            "")   # enter — connect to selected network
                if [[ "${#wifi_ssids[@]}" -eq 0 ]]; then
                    status_msg="${DIM}No networks available.${NC}"
                    continue
                fi
                local chosen_ssid="${wifi_ssids[$selected]}"
                local chosen_sec="${wifi_security[$selected]}"
                local password=""

                if [[ -n "$chosen_sec" && "$chosen_sec" != "--" ]]; then
                    prompt_input "Password for ${chosen_ssid}" "" \
                        "Enter WiFi password and press Enter. Type /back to cancel."
                    password="$prompt_result"
                    [[ "$password" == "__back__" ]] && continue
                fi

                show_header "Connecting" "Joining ${chosen_ssid}…"
                local ok=0
                if [[ -z "$password" ]]; then
                    nmcli device wifi connect "$chosen_ssid" 2>/dev/null && ok=1 || true
                else
                    nmcli device wifi connect "$chosen_ssid" password "$password" 2>/dev/null && ok=1 || true
                fi

                if [[ "$ok" -eq 1 ]]; then
                    connected=1
                    status_msg="${GREEN}✔ Connected to ${chosen_ssid}${NC}"
                else
                    status_msg="${RED}✘ Could not connect — check the password and try again${NC}"
                fi
                ;;
        esac
    done
}

show_installer_welcome() {
    while true; do
        menu_choose \
            "Welcome to Abora OS ${version}" \
            "Continue to installer setup" \
            "View hardware summary" \
            "Save support report" \
            "Read about Abora" \
            "Open live shell" \
            "Reboot" \
            "Power off" \
            "Cancel"

        case "$menu_result" in
            "__back__"|7)
                set_step_cancel
                return 0
                ;;
            0)
                set_step_next
                return 0
                ;;
            1)
                show_hardware_summary
                ;;
            2)
                save_support_report
                ;;
            3)
                show_about_abora
                ;;
            4)
                open_live_shell_from_installer
                ;;
            5)
                sync
                reboot
                ;;
            6)
                sync
                poweroff
                ;;
        esac
    done
}

show_extra_packages_setup() {
    while true; do
        menu_choose \
            "Extra packages and setup" \
            "Continue to install review" \
            "Install target: ${disk:-Not selected}" \
            "Desktop environment: ${desktop_label}" \
            "Extra packages: ${starter_apps_label}" \
            "View selected package bundle" \
            "View hardware summary" \
            "Save support report" \
            "Open live shell" \
            "Back" \
            "Cancel"

        case "$menu_result" in
            "__back__"|8)
                set_step_back
                return 0
                ;;
            1)
                prompt_disk || true
                set_step_stay
                ;;
            2)
                pick_desktop_environment
                set_step_stay
                ;;
            3)
                pick_starter_apps_bundle
                set_step_stay
                ;;
            4)
                show_starter_apps_preview
                ;;
            5)
                show_hardware_summary
                ;;
            6)
                save_support_report
                ;;
            7)
                open_live_shell_from_installer
                ;;
            8)
                set_step_back
                return 0
                ;;
            9)
                set_step_cancel
                return 0
                ;;
            0)
                if [[ -z "$disk" ]]; then
                    error_msg "Choose an install target before continuing."
                    pause_prompt
                    set_step_stay
                else
                    set_step_next
                    return 0
                fi
                ;;
        esac
    done
}

prompt_names() {
    while true; do
        prompt_hostname
        if [[ "$step_action" == "back" ]]; then
            set_step_back
            return 0
        fi

        prompt_username
        if [[ "$step_action" == "back" ]]; then
            continue
        fi

        set_step_next
        return 0
    done
}

prompt_github_login() {
    local continue_label=""

    if ! command -v gh >/dev/null 2>&1; then
        github_identity="GitHub CLI unavailable"
        set_step_next
        return 0
    fi

    while true; do
        refresh_github_identity

        if [[ "$github_identity" == "Skipped" ]]; then
            continue_label="Skip GitHub for now"
        else
            continue_label="Use ${github_identity}"
        fi

        menu_choose \
            "GitHub device login (optional)" \
            "$continue_label" \
            "Start device code login" \
            "Back"

        case "$menu_result" in
            "__back__"|2)
                set_step_back
                return 0
                ;;
            0)
                set_step_next
                return 0
                ;;
            1)
                show_header "GitHub device login" "This step is optional and can be skipped."
                printf 'Abora will show a one-time device code in this installer.\n'
                printf '\n'
                printf 'Then you can finish the login from your phone or another computer at:\n'
                printf '  github.com/login/device\n'
                printf '\n'
                printf 'If login succeeds, the GitHub auth config will be copied into the installed user account.\n'
                printf 'If you do not want this, go back and skip the GitHub step.\n'
                printf '\n'
                pause_prompt
                clear_screen
                GH_ACCESSIBLE_PROMPTER=enabled \
                GH_SPINNER_DISABLED=yes \
                GH_BROWSER=/run/current-system/sw/bin/echo \
                gh auth login --web --hostname github.com --git-protocol https || true
                refresh_github_identity
                if [[ "$github_identity" == "Skipped" ]]; then
                    error_msg "GitHub device login did not complete. You can skip it or try again."
                    pause_prompt
                else
                    success "$github_identity"
                    pause_prompt
                    set_step_next
                    return 0
                fi
                ;;
        esac
    done
}

pick_desktop_environment() {
    local labels=(
        "GNOME          - polished, simple, modern"
        "KDE Plasma     - flexible and feature-rich"
        "Hyprland       - Wayland tiling compositor"
        "Sway           - lightweight Wayland tiling"
        "Niri           - scrollable Wayland tiling"
        "River          - Wayland dynamic tiling"
        "XFCE           - fast and familiar"
        "Cinnamon       - traditional with modern polish"
        "MATE           - classic GNOME 2 desktop"
        "Budgie         - clean and focused"
        "LXQt           - lightweight Qt desktop"
        "Pantheon       - elementary OS look and feel"
        "LXDE           - minimal traditional desktop"
        "Enlightenment  - unique EFL-based desktop"
        "i3             - keyboard-driven tiling"
        "AwesomeWM      - highly configurable tiling"
        "Openbox        - very minimal floating WM"
        "Qtile          - Python-configured tiling"
        "BSPWM          - binary space partitioning"
        "Fluxbox        - fast and lightweight"
        "IceWM          - very lightweight, retro feel"
        "Herbstluftwm   - manual tiling WM"
        "Back"
    )
    local values=(
        "gnome"
        "plasma"
        "hyprland"
        "sway"
        "niri"
        "river"
        "xfce"
        "cinnamon"
        "mate"
        "budgie"
        "lxqt"
        "pantheon"
        "enlightenment"
        "i3"
        "awesome"
        "openbox"
        "qtile"
        "bspwm"
        "fluxbox"
        "icewm"
        "herbstluftwm"
    )

    menu_choose "Select desktop environment" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#values[@]}" ]]; then
        set_step_back
        return 0
    fi
    desktop_profile="${values[$menu_result]}"
    abora_sync_desktop_label "$desktop_profile"
    set_step_next
}

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) {
                next
            }
            model = ""
            for (i = 3; i < NF; i++) {
                model = model (model ? " " : "") $i
            }
            if (model == "") {
                model = "Unknown model"
            }
            print $1 "|" $2 "|" model
        }
    '
}

prompt_disk() {
    local entries=()
    local labels=()
    local paths=()
    local choice=""
    local name=""
    local size=""
    local model=""
    local entry=""

    mapfile -t entries < <(collect_disks)
    if [[ "${#entries[@]}" -eq 0 ]]; then
        show_header "Select install target" "No installable disks were found."
        printf '%bNo disks are visible to the installer right now.%b\n' "$RED" "$NC"
        printf '\n'
        menu_choose "Choose what to do next" "Rescan disks" "Back"
        if [[ "$menu_result" == "__back__" || "$menu_result" == "1" ]]; then
            set_step_back
            return 0
        fi
        set_step_stay
        return 0
    fi

    for entry in "${entries[@]}"; do
        IFS='|' read -r name size model <<<"$entry"
        labels+=( "/dev/${name}  ${size}  ${model}" )
        paths+=( "/dev/${name}" )
    done
    labels+=( "Back" )

    menu_choose "Select install target" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#paths[@]}" ]]; then
        set_step_back
        return 0
    fi
    disk="${paths[$menu_result]}"
    set_step_next
}

prompt_hostname() {
    local input=""

    while true; do
        prompt_input "Choose a hostname" "$hostname_value"
        input="$prompt_result"
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi
        if [[ "$input" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
            hostname_value="$input"
            set_step_next
            return
        fi

        error_msg "Hostname must use letters, numbers, or hyphens."
        pause_prompt
    done
}

prompt_username() {
    local input=""

    while true; do
        prompt_input "Choose a username" "$username_value"
        input="$prompt_result"
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi
        if [[ "$input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            username_value="$input"
            set_step_next
            return
        fi

        error_msg "Username must start with a lowercase letter or underscore."
        pause_prompt
    done
}

prompt_timezone() {
    local input=""
    local query=""
    local zoneinfo_matches=()

    menu_choose \
        "Choose timezone method" \
        "Search for a timezone" \
        "Enter timezone directly" \
        "Back"

    if [[ "$menu_result" == "__back__" || "$menu_result" == "2" ]]; then
        set_step_back
        return 0
    fi

    if [[ "$menu_result" == "0" ]]; then
        while true; do
            prompt_input "Search timezone" "$timezone_value"
            query="$prompt_result"
            if [[ "$query" == "__back__" ]]; then
                set_step_back
                return 0
            fi
            mapfile -t zoneinfo_matches < <(collect_timezones | grep -Fi -- "${query:-UTC}" | head -n 30)

            if [[ "${#zoneinfo_matches[@]}" -eq 0 ]]; then
                error_msg "No timezones matched. Try UTC, America, Europe, or Etc."
                pause_prompt
                continue
            fi

            zoneinfo_matches+=( "Back" )
            menu_choose "Select timezone" "${zoneinfo_matches[@]}"
            if [[ "$menu_result" == "__back__" || "$menu_result" == "$((${#zoneinfo_matches[@]} - 1))" ]]; then
                continue
            fi
            timezone_value="${zoneinfo_matches[$menu_result]}"
            set_step_next
            return 0
        done
    fi

    while true; do
        prompt_input "Enter timezone directly" "$timezone_value"
        input="${prompt_result:-$timezone_value}"
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi

        if timezone_exists "$input"; then
            timezone_value="$input"
            set_step_next
            return 0
        fi

        error_msg "Timezone not found. Try UTC, Etc/UTC, or use search."
        pause_prompt
    done
}

prompt_password() {
    local first=""
    local second=""

    while true; do
        show_header "Set password" "Choose a password for ${username_value}. Type /back to return."

        read -r -s -p "Password: " first
        printf '\n'
        if [[ "$first" == "/back" ]]; then
            set_step_back
            return 0
        fi
        read -r -s -p "Confirm password: " second
        printf '\n'

        if [[ -z "$first" ]]; then
            error_msg "Password cannot be empty."
            pause_prompt
            continue
        fi

        if [[ "$first" != "$second" ]]; then
            error_msg "Passwords did not match."
            pause_prompt
            continue
        fi

        if command -v mkpasswd >/dev/null 2>&1; then
            user_password_hash="$(mkpasswd -m yescrypt "$first")"
        elif command -v openssl >/dev/null 2>&1; then
            user_password_hash="$(printf '%s' "$first" | openssl passwd -6 -stdin)"
        else
            error_msg "A password hashing tool is missing. Install mkpasswd or openssl."
            pause_prompt
            continue
        fi

        unset first second
        set_step_next
        return
    done
}

confirm_install() {
    local inner=42

    show_header "Ready to install" "Review your choices before the disk is wiped."

    printf '%b┌' "$BLUE"
    repeat_char '─' $((inner + 2))
    printf '┐%b\n' "$NC"

    printf '%b│%b  %-*s %b│%b\n' "$BLUE" "$WHITE" "$inner" "Install Summary" "$BLUE" "$NC"

    printf '%b├' "$BLUE"
    repeat_char '─' $((inner + 2))
    printf '┤%b\n' "$NC"

    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "Disk:"      "$CYAN" $((inner - 14)) "$(trunc "$disk" $((inner - 14)))"      "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "Desktop:"   "$CYAN" $((inner - 14)) "$(trunc "$desktop_label" $((inner - 14)))"   "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "Apps:"      "$CYAN" $((inner - 14)) "$(trunc "$starter_apps_label" $((inner - 14)))"      "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "GitHub:"    "$CYAN" $((inner - 14)) "$(trunc "$github_identity" $((inner - 14)))"    "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "Hostname:"  "$CYAN" $((inner - 14)) "$(trunc "$hostname_value" $((inner - 14)))"  "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "User:"      "$CYAN" $((inner - 14)) "$(trunc "$username_value" $((inner - 14)))"      "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "Timezone:"  "$CYAN" $((inner - 14)) "$(trunc "$timezone_value" $((inner - 14)))"  "$NC" "$BLUE" "$NC"
    printf '%b│%b  %-12s %b%-*s%b %b│%b\n' "$BLUE" "$NC" "Keyboard:"  "$CYAN" $((inner - 14)) "$(trunc "$keyboard_value" $((inner - 14)))"  "$NC" "$BLUE" "$NC"

    printf '%b└' "$BLUE"
    repeat_char '─' $((inner + 2))
    printf '┘%b\n' "$NC"

    printf '\n'
    preflight_warnings_text
    printf '%bDisk layout that will be created:%b\n' "$WHITE" "$NC"
    printf '  1 MiB BIOS boot  +  512 MiB EFI  +  ext4 root (remaining space)\n'
    printf '\n'
    printf '%bThe selected disk will be completely erased.%b\n' "$RED" "$NC"
    printf '\n'

    menu_choose "Continue with installation?" "Install now" "Back" "Cancel"
    case "$menu_result" in
        "__back__"|1)
            set_step_back
            ;;
        2)
            set_step_cancel
            ;;
        *)
            set_step_install
            ;;
    esac
}

disk_part_suffix() {
    case "$disk" in
        *nvme*|*mmcblk*|*loop*)
            printf 'p'
            ;;
        *)
            printf ''
            ;;
    esac
}

partition_disk() {
    local suffix=""

    info "Partitioning ${disk}"
    umount -R /mnt 2>/dev/null || true
    wipefs -af "$disk" >/dev/null
    parted -s "$disk" mklabel gpt
    parted -s "$disk" unit MiB mkpart BIOSBOOT 1 3
    parted -s "$disk" set 1 bios_grub on
    parted -s "$disk" unit MiB mkpart ESP fat32 3 515
    parted -s "$disk" set 2 esp on
    parted -s "$disk" unit MiB mkpart primary ext4 515 100%
    partprobe "$disk"
    udevadm settle

    suffix="$(disk_part_suffix)"
    efi_part="${disk}${suffix}2"
    root_part="${disk}${suffix}3"

    mkfs.vfat -F 32 -n ABORA_EFI "$efi_part" >/dev/null
    mkfs.ext4 -F -L ABORA_ROOT "$root_part" >/dev/null
    success "Disk prepared"
}

mount_target() {
    info "Mounting target filesystem"
    mkdir -p /mnt
    mount "$root_part" /mnt
    mkdir -p /mnt/boot
    mount "$efi_part" /mnt/boot
    success "Target mounted at /mnt"
}

desktop_config_block() {
    abora_desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value"
}

desktop_package_block() {
    abora_desktop_package_block "$desktop_profile"
}

write_branding_assets() {
    local live_background="/etc/abora/bootloader/background.png"
    local live_limine_background="/etc/abora/bootloader/limine-background.png"
    local live_theme="/etc/abora/bootloader/theme.txt"
    local limine_source=""

    mkdir -p /mnt/etc/nixos/abora/plymouth /mnt/etc/nixos/abora/bootloader /mnt/etc/nixos/abora/wallpapers /mnt/etc/nixos/abora/themes /mnt/etc/nixos/abora/effects
    cp "$title_file" /mnt/etc/nixos/abora/title.txt
    cp /etc/abora/VERSION /mnt/etc/nixos/abora/VERSION
    cp /etc/abora/abora.sh /mnt/etc/nixos/abora/abora.sh
    cp /etc/abora/ui.sh /mnt/etc/nixos/abora/ui.sh
    cp /etc/abora/config.sh /mnt/etc/nixos/abora/config.sh
    cp /etc/abora/desktop.sh /mnt/etc/nixos/abora/desktop.sh
    cp /etc/abora/doctor.sh /mnt/etc/nixos/abora/doctor.sh
    cp /etc/abora/recovery.sh /mnt/etc/nixos/abora/recovery.sh
    cp /etc/abora/welcome.sh /mnt/etc/nixos/abora/welcome.sh
    cp /etc/abora/app-catalog.sh /mnt/etc/nixos/abora/app-catalog.sh
    cp /etc/abora/apps.sh /mnt/etc/nixos/abora/apps.sh
    cp /etc/abora/support-report.sh /mnt/etc/nixos/abora/support-report.sh
    cp /etc/abora/hardware-test.sh /mnt/etc/nixos/abora/hardware-test.sh
    cp /etc/abora/default-wallpaper.png /mnt/etc/nixos/abora/default-wallpaper.png
    cp /etc/abora/fastfetch-logo.txt /mnt/etc/nixos/abora/fastfetch-logo.txt
    cp /etc/abora/fastfetch-config.jsonc /mnt/etc/nixos/abora/fastfetch-config.jsonc
    cp /etc/abora/desktop-profiles.sh /mnt/etc/nixos/abora/desktop-profiles.sh
    cp /etc/abora/installed-base.nix /mnt/etc/nixos/abora/installed-base.nix
    cp /etc/abora/session-setup.sh /mnt/etc/nixos/abora/session-setup.sh
    cp /etc/abora/theme-sync.sh /mnt/etc/nixos/abora/theme-sync.sh
    cp /etc/abora/update.sh /mnt/etc/nixos/abora/update.sh
    [[ -f /etc/abora/effects/v3StartingAbora.mp3 ]] && cp /etc/abora/effects/v3StartingAbora.mp3 /mnt/etc/nixos/abora/effects/v3StartingAbora.mp3 || true
    cp /etc/abora/plymouth/abora.plymouth /mnt/etc/nixos/abora/plymouth/abora.plymouth
    cp /etc/abora/plymouth/abora.script /mnt/etc/nixos/abora/plymouth/abora.script
    if [[ ! -f "$live_background" ]]; then
        show_failure_screen \
            "Missing boot assets" \
            "The live image is missing the bootloader background needed for install." \
            "$config_log"
        return 1
    fi
    if [[ ! -f "$live_theme" ]]; then
        show_failure_screen \
            "Missing boot assets" \
            "The live image is missing the GRUB theme file needed for install." \
            "$config_log"
        return 1
    fi

    limine_source="$live_background"
    if [[ -f "$live_limine_background" ]]; then
        limine_source="$live_limine_background"
    fi

    install -Dm0644 "$live_background" /mnt/etc/nixos/abora/bootloader/background.png
    install -Dm0644 "$limine_source" /mnt/etc/nixos/abora/bootloader/limine-background.png
    install -Dm0644 "$live_theme" /mnt/etc/nixos/abora/bootloader/theme.txt

    if [[ ! -f /mnt/etc/nixos/abora/bootloader/background.png || ! -f /mnt/etc/nixos/abora/bootloader/limine-background.png || ! -f /mnt/etc/nixos/abora/bootloader/theme.txt ]]; then
        show_failure_screen \
            "Missing boot assets" \
            "The installer could not write the bootloader assets onto the target system." \
            "$config_log"
        return 1
    fi

    cp /etc/abora/wallpapers/* /mnt/etc/nixos/abora/wallpapers/
    cp /etc/abora/themes/* /mnt/etc/nixos/abora/themes/
    mkdir -p /mnt/etc/nixos/abora
    : > /mnt/etc/nixos/abora/apps.list
    cat > /mnt/etc/nixos/abora/apps.nix <<'EOF'
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
  ];
}
EOF
    write_starter_apps_list /mnt/etc/nixos/abora/apps.list
    render_apps_module_file /mnt/etc/nixos/abora/apps.nix /mnt/etc/nixos/abora/apps.list

    if [[ ! -s /mnt/etc/nixos/abora/apps.nix ]]; then
        show_failure_screen \
            "Missing app module" \
            "The installer could not create the Abora app module on the target system." \
            "$config_log"
        return 1
    fi
}

write_starter_apps_list() {
    local target_file="$1"

    : > "$target_file"

    if [[ "${starter_apps_bundle,,}" == "none" ]]; then
        return 0
    fi

    abora_catalog_bundle_ids "$starter_apps_bundle" > "$target_file"
}

render_apps_module_file() {
    local target_file="$1"
    local app_list_file="$2"
    local app_id=""
    local app_expr=""

    {
        printf '{ pkgs, ... }:\n'
        printf '{\n'
        printf '  environment.systemPackages = with pkgs; [\n'
        while IFS= read -r app_id; do
            [[ -n "$app_id" ]] || continue
            app_expr="$(abora_catalog_expr "$app_id" 2>/dev/null || true)"
            [[ -n "$app_expr" ]] || continue
            printf '    %s\n' "$app_expr"
        done < "$app_list_file"
        printf '  ];\n'
        printf '}\n'
    } > "$target_file"
}

copy_github_auth_to_target() {
    local root_hosts="/root/.config/gh/hosts.yml"
    local target_dir="/mnt/home/${username_value}/.config/gh"
    local uid="1000"
    local gid="100"

    [[ -f "$root_hosts" ]] || return 0
    [[ "$github_identity" != "Skipped" ]] || return 0

    info "Copying GitHub login into the installed system"
    mkdir -p "$target_dir"
    cp "$root_hosts" "$target_dir/hosts.yml"
    chmod 600 "$target_dir/hosts.yml"

    if command -v nixos-enter >/dev/null 2>&1; then
        uid="$(nixos-enter --root /mnt -c "id -u ${username_value}" 2>/dev/null || printf '1000')"
        gid="$(nixos-enter --root /mnt -c "id -g ${username_value}" 2>/dev/null || printf '100')"
    fi

    chown -R "$uid:$gid" "/mnt/home/${username_value}/.config"
    success "GitHub auth copied for ${username_value}"
}

write_install_assets() {
    write_branding_assets

    [[ -f /etc/abora/anix.sh ]]        && cp /etc/abora/anix.sh        /mnt/etc/nixos/abora/anix.sh        || true
    [[ -f /etc/abora/anix-module.nix ]] && cp /etc/abora/anix-module.nix /mnt/etc/nixos/abora/anix-module.nix || true
    [[ -f /etc/abora/abora-options.nix ]] && cp /etc/abora/abora-options.nix /mnt/etc/nixos/abora/abora-options.nix || true
}

ensure_target_install_files() {
    mkdir -p /mnt/etc/nixos/abora

    if [[ ! -f /mnt/etc/nixos/abora/apps.list ]]; then
        : > /mnt/etc/nixos/abora/apps.list
    fi

    if [[ ! -f /mnt/etc/nixos/abora/apps.nix ]]; then
        cat > /mnt/etc/nixos/abora/apps.nix <<'EOF'
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
  ];
}
EOF
    fi

    if [[ ! -s /mnt/etc/nixos/abora/apps.nix ]]; then
        render_apps_module_file /mnt/etc/nixos/abora/apps.nix /mnt/etc/nixos/abora/apps.list
    fi

    if [[ ! -s /mnt/etc/nixos/abora/apps.nix ]]; then
        error_msg "Target app module is missing: /mnt/etc/nixos/abora/apps.nix"
        return 1
    fi
}

generate_config() {
    local desktop_block=""
    local desktop_packages=""

    info "Generating NixOS configuration"
    info "Writing configuration log to ${config_log}"
    printf '[*] Running nixos-generate-config --root /mnt\n' > "$config_log"
    if ! nixos-generate-config --root /mnt >>"$config_log" 2>&1; then
        show_failure_screen \
            "Configuration failed" \
            "Abora could not generate the base NixOS hardware config." \
            "$config_log"
        return 1
    fi

    write_install_assets
    desktop_block="$(desktop_config_block)"
    desktop_packages="$(desktop_package_block)"

    if [[ "$anix_enabled" == "yes" ]]; then
        cat > /mnt/etc/nixos/anix.nix <<EOF
# ANIX is the simple layer on top of Abora/NixOS.
# Change the values below, save the file, then run: anix apply
{ ... }:
{
  anix.enable = true;

  # Your system name on the network.
  anix.hostname = "${hostname_value}";

  # Timezone example: America/New_York
  anix.timezone = "${timezone_value}";

  # Keyboard layouts for console and desktop sessions.
  anix.keyboard.console = "${keyboard_value}";
  anix.keyboard.xkb = "${xkb_layout_value}";

  # Pick one desktop or use "none" for a console-only system.
  anix.desktop = "${desktop_profile}";

  # Wallpaper filename (Abora OS only).
  anix.wallpaper = "${wallpaper_name}";
}
EOF
    fi

    cat > /mnt/etc/nixos/configuration.nix <<EOF
{ lib, ... }:
let
  appModule = ./abora/apps.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ./abora/installed-base.nix
    ./abora-local.nix
  ] ++ lib.optional (builtins.pathExists appModule) appModule;
}
EOF

    cat > /mnt/etc/nixos/abora-local.nix <<EOF
{ pkgs, lib, ... }:
{
  system.nixos.variantName = "Abora ${version} ${desktop_label} Edition";
  system.nixos.variant_id = "${desktop_variant_id}";

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.limine = {
    enable = true;
    biosSupport = true;
    biosDevice = "${disk}";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "${hostname_value}";
  time.timeZone = "${timezone_value}";
  console.keyMap = "${keyboard_value}";

${desktop_block}
  users.users."${username_value}" = {
    isNormalUser = true;
    description = "Abora User";
    createHome = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "${user_password_hash}";
  };

  security.sudo.wheelNeedsPassword = true;

  environment.systemPackages = with pkgs; [
${desktop_packages}
  ];

  system.stateVersion = "26.05";
}
EOF

    cat > /mnt/etc/nixos/flake.nix <<EOF
{
  description = "Abora installed system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.abora = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        let
          lib       = nixpkgs.lib;
          appModule  = ./abora/apps.nix;
          anixModule = ./abora/anix-module.nix;
          anixLayer  = ./anix.nix;
        in
        [
          ./hardware-configuration.nix
          ./abora/installed-base.nix
          ./abora-local.nix
        ] ++ lib.optional (builtins.pathExists appModule)  appModule
          ++ lib.optional (builtins.pathExists anixModule) anixModule
          ++ lib.optional (builtins.pathExists anixLayer)  anixLayer;
    };
  };
}
EOF
    success "Configuration written"
}

install_system() {
    local nixpkgs_path=""
    local nix_path=""
    local status=0
    local install_pid=""
    local start_time=0
    local elapsed=0
    local progress=45
    local status_text=""

    info "Installing Abora OS"
    info "This usually takes 5-10 minutes depending on network speed."

    # Require at least 15 GB free on the target to avoid out-of-space build failures
    local free_kb
    free_kb="$(df -k /mnt 2>/dev/null | awk 'NR==2{print $4}')"
    if [[ -n "$free_kb" && "$free_kb" -lt 15728640 ]]; then
        local free_gb
        free_gb="$(( free_kb / 1024 / 1024 ))"
        error_msg "Not enough disk space: ${free_gb} GB free, 15 GB required. Partition the disk with a larger root volume."
        return 1
    fi

    ensure_target_install_files || return 1
    nixpkgs_path="$(resolve_nixpkgs_path)" || {
        error_msg "Could not locate nixpkgs for nixos-install."
        return 1
    }
    nix_path="nixpkgs=${nixpkgs_path}:nixos-config=/mnt/etc/nixos/configuration.nix"
    info "Writing install log to ${install_log}"
    printf '[*] Running nixos-install\n' > "$install_log"
    printf '[*] NIX_PATH=%s\n' "$nix_path" >> "$install_log"

    NIX_PATH="$nix_path" timeout 900 nixos-install \
        --root /mnt \
        --no-root-passwd \
        --show-trace \
        --option substituters "https://cache.nixos.org" \
        --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
        --option max-substitution-jobs 32 \
        --option http-connections 128 \
        --option max-jobs auto \
        --option max-silent-time 300 \
        --cores 0 \
        -I "nixpkgs=${nixpkgs_path}" \
        -I "nixos-config=/mnt/etc/nixos/configuration.nix" \
        >>"$install_log" 2>&1 &
    install_pid="$!"
    start_time="$(date +%s)"
    local last_log_size=0
    local last_log_change_time="$start_time"
    local stale_warn=0

    while kill -0 "$install_pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start_time ))
        progress="$(install_progress_percent "$install_log" "$elapsed")"
        status_text="$(install_status_summary "$install_log" "$elapsed")"

        # Detect log staleness: if no new output for 5 min after build completed, warn
        local cur_log_size=0
        [[ -f "$install_log" ]] && cur_log_size="$(wc -c < "$install_log" 2>/dev/null || printf '0')"
        if [[ "$cur_log_size" -ne "$last_log_size" ]]; then
            last_log_size="$cur_log_size"
            last_log_change_time="$(date +%s)"
            stale_warn=0
        else
            local stale_for=$(( $(date +%s) - last_log_change_time ))
            # After build is done (symlinks created), warn if no new log for 5 min
            if [[ "$stale_for" -gt 300 ]] && grep -qi 'symlinks in user environment' "$install_log" 2>/dev/null; then
                stale_warn=1
            fi
        fi

        if [[ "$stale_warn" -eq 1 ]]; then
            status_text="Bootloader install (may take a few minutes)"
        fi

        show_install_progress_screen "$progress" "$status_text" "$elapsed" "$install_log"
        sleep 1
    done

    if wait "$install_pid"; then
        elapsed=$(( $(date +%s) - start_time ))
        show_install_progress_screen 100 "Installation complete" "$elapsed" "$install_log"
        success "Installation complete"
        return 0
    else
        status="$?"
        printf '\n[x] nixos-install exited with status %s\n' "$status" >> "$install_log"
        if [[ -x /etc/abora/support-report.sh ]]; then
            /etc/abora/support-report.sh >/tmp/abora-last-support-report.txt 2>/dev/null || true
        fi
        show_failure_screen \
            "Installation failed" \
            "Abora could not finish writing the system." \
            "$install_log"
        return 1
    fi
}

finish_screen() {
    show_header "Install complete" "Your machine is ready for first boot."

    printf '%b[ok] Abora OS %s is installed successfully.%b\n' "$GREEN" "$version" "$NC"
    printf '\n'
    draw_rule
    printf '%b  Next steps%b\n' "$WHITE" "$NC"
    draw_rule
    printf '  1. Remove the installation media (USB drive or ISO).\n'
    printf '  2. Reboot — your drive will be selected automatically.\n'
    printf '  3. Log in as %b%s%b on the %b%s%b desktop.\n' \
        "$CYAN" "$username_value" "$NC" "$CYAN" "$desktop_label" "$NC"
    draw_rule
    printf '\n'

    menu_choose "What would you like to do?" "Reboot into Abora OS" "Power off"

    case "$menu_result" in
        0)
            sync
            reboot
            ;;
        *)
            sync
            poweroff
            ;;
    esac

    # Should not be reached — reboot/poweroff is async, give it time then exit
    sleep 10
    exit 0
}

cleanup_target() {
    sync
    umount -R /mnt 2>/dev/null || true
}

main() {
    local step=0

    require_root
    sync_starter_apps_label
    refresh_github_identity
    auto_detect_timezone
    auto_detect_keyboard
    if ! command -v mkpasswd >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
        error_msg "Password hashing is unavailable. Install mkpasswd or openssl."
        exit 1
    fi

    while true; do
        set_step_next

        case "$step" in
            0)
                prompt_network_connect
                ;;
            1)
                show_installer_welcome
                ;;
            2)
                prompt_anix_opt_in
                ;;
            3)
                prompt_names
                ;;
            4)
                prompt_locale
                ;;
            5)
                prompt_password
                ;;
            6)
                prompt_github_login
                ;;
            7)
                show_extra_packages_setup
                ;;
            8)
                confirm_install
                ;;
        esac

        case "$step_action" in
            back)
                if [[ "$step" -gt 0 ]]; then
                    step=$((step - 1))
                fi
                ;;
            cancel)
                info "Install cancelled."
                return 0
                ;;
            stay)
                ;;
            install)
                show_install_progress_screen 5 "Preparing the target disk" 0
                partition_disk
                show_install_progress_screen 18 "Mounting the target filesystem" 0
                mount_target
                show_install_progress_screen 32 "Generating the Abora system configuration" 0 "$config_log"
                generate_config || {
                    pause_prompt
                    return 1
                }
                show_install_progress_screen 40 "Starting nixos-install" 0 "$install_log"
                install_system || {
                    pause_prompt
                    return 1
                }
                copy_github_auth_to_target
                cleanup_target
                finish_screen
                exit 0
                ;;
            *)
                if [[ "$step" -lt 8 ]]; then
                    step=$((step + 1))
                fi
                ;;
        esac
    done
}

main "$@"
