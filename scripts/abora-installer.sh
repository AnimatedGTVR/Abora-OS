#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
desktop_profiles_lib="${ABORA_DESKTOP_PROFILES_LIB:-$script_dir/abora-desktop-profiles.sh}"
app_catalog_lib="${ABORA_APP_CATALOG_LIB:-$script_dir/abora-app-catalog.sh}"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$desktop_profiles_lib" && -f /etc/abora/desktop-profiles.sh ]]; then
    desktop_profiles_lib="/etc/abora/desktop-profiles.sh"
fi

if [[ ! -f "$app_catalog_lib" && -f /etc/abora/app-catalog.sh ]]; then
    app_catalog_lib="/etc/abora/app-catalog.sh"
fi

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

# shellcheck source=/dev/null
source "$desktop_profiles_lib"
# shellcheck source=/dev/null
source "$app_catalog_lib"
# shellcheck source=/dev/null
source "$ui_lib"

disk=""
hostname_value="abora"
username_value="abora"
language_value="en_US.UTF-8"
timezone_value="UTC"
keyboard_value="us"
xkb_layout_value="us"
desktop_profile="gnome"
desktop_label="GNOME"
desktop_variant_id="gnome"
wallpaper_name="oceandusk.png"
wallpaper_label="Ocean Dusk"
starter_apps_bundle="favorites"
starter_apps_label="Fan Favorites"
github_identity="Skipped"
user_password_hash=""
efi_part=""
root_part=""
anix_enabled="yes"
anix_info_compact="no"
config_log="/tmp/abora-generate-config.log"
install_log="/tmp/abora-install.log"
support_report_output="/tmp/abora-last-support-report.txt"

title_file="/etc/abora/title.txt"
version="${ABORA_VERSION:-v2.5.0}"
product_name="${ABORA_PRODUCT_NAME:-Abora OS}"
product_short="${ABORA_PRODUCT_SHORT:-Abora}"
product_tagline="${ABORA_PRODUCT_TAGLINE:-A simpler path into NixOS.}"
product_notice="${ABORA_PRODUCT_NOTICE:-}"
ABORA_UI_VERSION="$version"   # keep brand header in sync with installer version

# ── Palette aliases (delegates to abora-ui.sh) ───────────────────────────────
BLUE="$ABORA_BLUE"
ACCENT="$ABORA_ACCENT"
CYAN="$ABORA_CYAN"
YELLOW="$ABORA_YELLOW"
WHITE="$ABORA_WHITE"
DIM="$ABORA_DIM"
FAINT="$ABORA_FAINT"
GREEN="$ABORA_GREEN"
RED="$ABORA_RED"
MAGENTA="$ABORA_MAGENTA"
NC="$ABORA_NC"

menu_result=""
prompt_result=""
step_action="next"

# ── Core helper aliases ───────────────────────────────────────────────────────

clear_screen()      { clear || printf '\033c'; }
terminal_cols()     { abora_cols; }
terminal_rows()     { local r; r="$(tput lines 2>/dev/null || printf '24')"; printf '%s' "${r:-24}"; }
repeat_char()       { _abora_repeat "$@"; }
trunc()             { abora_trunc "$@"; }
draw_rule()         { abora_rule; }
draw_brand_header() { abora_brand_header; }
info()              { abora_info "$@"; }
success()           { abora_success "$@"; }
error_msg()         { abora_error "$@"; }

show_header() {
    local title="${1:-${product_name} ${version} installer}"
    local subtitle="${2:-Set up your machine.}"
    local step_num="${3:-}"
    local step_total="${4:-}"

    clear_screen
    printf '\n'
    draw_brand_header
    printf '\n'

    # Step indicator if provided
    if [[ -n "$step_num" && -n "$step_total" ]]; then
        printf '  %bstep %d of %d%b\n' "$ABORA_DIM" "$((step_num + 1))" "$step_total" "$ABORA_NC"
        printf '\n'
    fi

    printf '  %b%s%b\n' "$ABORA_WHITE" "$title" "$ABORA_NC"
    printf '  %b%s%b\n' "$ABORA_DIM" "$subtitle" "$ABORA_NC"
    printf '\n'
    draw_rule
    printf '\n'
}

# Welcome header with ASCII logo (only on wide terminals).
show_welcome_header() {
    local cols
    cols="$(terminal_cols)"

    clear_screen
    printf '\n'

    if [[ "$cols" -ge 78 ]]; then
        abora_ascii_header "$version"
    else
        draw_brand_header
    fi

    printf '\n'
    draw_rule
    printf '\n'
    printf '  %b%s%b\n' "$ABORA_WHITE" "Welcome to ${product_name}" "$ABORA_NC"
    printf '  %b%s%b\n' "$ABORA_DIM" "$product_tagline" "$ABORA_NC"
    printf '\n'
    draw_rule
    printf '\n'
}

pause_prompt() {
    printf '\n'
    printf '  %bpress enter to continue...%b' "$FAINT" "$NC"
    read -r
    printf '\n'
}

# ── Log display ───────────────────────────────────────────────────────────────

print_log_tail() {
    local logfile="$1"
    local cols max_lines=10 width line

    cols="$(terminal_cols)"
    width=$((cols - 6))
    [[ $width -lt 20 ]] && width=20

    if [[ ! -s "$logfile" ]]; then
        printf '  %bno output captured yet%b\n' "$FAINT" "$NC"
        return 0
    fi

    while IFS= read -r line; do
        if [[ "${#line}" -gt "$width" ]]; then
            printf '  %b%s...%b\n' "$FAINT" "${line:0:$((width - 3))}" "$NC"
        else
            printf '  %b%s%b\n' "$FAINT" "$line" "$NC"
        fi
    done < <(tail -n "$max_lines" "$logfile")
}

show_failure_screen() {
    local title="$1"
    local subtitle="$2"
    local logfile="$3"
    local report_path=""

    show_header "$title" "$subtitle"

    abora_card_start "Recent output"
    print_log_tail "$logfile"
    abora_card_end

    printf '\n'
    printf '  %bfull log:%b  %s\n' "$FAINT" "$DIM" "$logfile"

    if [[ -f "$support_report_output" ]]; then
        report_path="$(cat "$support_report_output" 2>/dev/null || true)"
        if [[ -n "$report_path" ]]; then
            printf '  %bsupport report:%b  %s\n' "$FAINT" "$DIM" "$report_path"
        fi
    fi
}

# ── Progress ──────────────────────────────────────────────────────────────────

draw_progress_bar() {
    local percent="$1"
    local cols width filled empty

    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    cols="$(terminal_cols)"
    width=$((cols - 12))
    [[ $width -lt 20 ]] && width=20
    [[ $width -gt 60 ]] && width=60

    filled=$((percent * width / 100))
    empty=$((width - filled))

    printf '  %b' "$BLUE"
    repeat_char '█' "$filled"
    printf '%b' "$FAINT"
    repeat_char '░' "$empty"
    printf '%b  %b%3d%%%b\n' "$NC" "$WHITE" "$percent" "$NC"
}

format_elapsed() {
    local seconds="$1"
    local minutes=0 hours=0

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

    if [[ ! -s "$logfile" ]]; then
        printf 'Preparing the install environment'
        return 0
    fi

    if grep -qi 'installing the boot loader' "$logfile"; then
        printf 'Installing the bootloader'
    elif grep -qi 'activating the configuration' "$logfile"; then
        printf 'Activating the new system'
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
    local line_count=0 progress=45

    if [[ -f "$logfile" ]]; then
        line_count="$(wc -l < "$logfile")"
    fi

    progress=$((45 + line_count / 6 + elapsed / 4))

    if grep -qi 'building the configuration' "$logfile" 2>/dev/null; then
        [[ $progress -lt 60 ]] && progress=60
    fi
    if grep -qi "copying path '/nix/store" "$logfile" 2>/dev/null; then
        [[ $progress -lt 72 ]] && progress=72
    fi
    if grep -qi 'installing the boot loader' "$logfile" 2>/dev/null; then
        [[ $progress -lt 88 ]] && progress=88
    fi
    [[ $progress -gt 94 ]] && progress=94

    printf '%s' "$progress"
}

show_install_progress_screen() {
    local percent="$1"
    local status_text="$2"
    local elapsed="$3"
    local logfile="${4:-}"

    show_header "Installing ${product_name}" "Applying partitions and writing the system."

    printf '  %b%s%b\n' "$ABORA_WHITE" "$status_text" "$NC"
    printf '\n'
    abora_progress_smooth "$percent"
    printf '  %b%s elapsed%b\n' "$FAINT" "$(format_elapsed "$elapsed")" "$NC"

    if [[ -n "$logfile" ]]; then
        printf '\n'
        draw_rule
        printf '  %brecent output%b\n' "$FAINT" "$NC"
        printf '\n'
        print_log_tail "$logfile"
    fi
}

# ── Interactive menus ─────────────────────────────────────────────────────────

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
    local key="" i="" display_num="" num_idx=0
    local max_visible=10 start=0 end=0

    while true; do
        show_header "$prompt" "arrow keys or number to jump · enter to select · esc to go back"

        if [[ "${#options[@]}" -le "$max_visible" ]]; then
            start=0
            end=$((${#options[@]} - 1))
        else
            start=$((selected - (max_visible / 2)))
            [[ $start -lt 0 ]] && start=0
            end=$((start + max_visible - 1))
            if [[ $end -ge "${#options[@]}" ]]; then
                end=$((${#options[@]} - 1))
                start=$((end - max_visible + 1))
            fi
        fi

        if [[ "$start" -gt 0 ]]; then
            printf '  %b  ↑ more above%b\n' "$FAINT" "$NC"
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
                printf '  %b▸%b %b%s%b %b%s%b\n' \
                    "$ACCENT" "$NC" \
                    "$FAINT" "$display_num" "$NC" \
                    "$ABORA_WHITE" "${options[$i]}" "$NC"
            else
                printf '  %b%s%b %b%s%b\n' \
                    "$FAINT" "$display_num" "$NC" \
                    "$DIM" "${options[$i]}" "$NC"
            fi
        done

        if [[ "$end" -lt $((${#options[@]} - 1)) ]]; then
            printf '  %b  ↓ more below%b\n' "$FAINT" "$NC"
        fi

        printf '\n'
        draw_rule
        printf '  %b↑↓ navigate  ·  1-9 jump  ·  enter select  ·  esc back%b\n' "$FAINT" "$NC"

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
            printf '  %b›%b  %b[%s]%b  ' "$CYAN" "$NC" "$FAINT" "$default_value" "$NC"
            read -r input
            prompt_result="${input:-$default_value}"
        else
            printf '  %b›%b  ' "$CYAN" "$NC"
            read -r input
            prompt_result="$input"
        fi
        if [[ "$prompt_result" == "/back" ]]; then
            prompt_result="__back__"
        fi
        return 0
    done
}

# ── Step state helpers ────────────────────────────────────────────────────────

set_step_next()    { step_action="next"; }
set_step_back()    { step_action="back"; }
set_step_cancel()  { step_action="cancel"; }
set_step_install() { step_action="install"; }
set_step_stay()    { step_action="stay"; }

sync_anix_label() {
    if [[ "${anix_enabled}" == "yes" ]]; then
        printf 'Enabled'
    else
        printf 'Disabled'
    fi
}

sync_wallpaper_label() {
    abora_sync_wallpaper_label "$wallpaper_name"
}

# ── App bundle helpers ────────────────────────────────────────────────────────

sync_starter_apps_label() {
    case "${starter_apps_bundle,,}" in
        none)        starter_apps_label="No starter apps" ;;
        favorites)   starter_apps_label="Fan Favorites" ;;
        essentials)  starter_apps_label="Essentials" ;;
        social)      starter_apps_label="Social" ;;
        creator)     starter_apps_label="Creator" ;;
        developer)   starter_apps_label="Developer" ;;
        *)           starter_apps_label="Custom" ;;
    esac
}

# ── GitHub helpers ────────────────────────────────────────────────────────────

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

# ── Auto-detect ───────────────────────────────────────────────────────────────

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

# ── Nix path helpers ──────────────────────────────────────────────────────────

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

# ── Keyboard / timezone helpers ───────────────────────────────────────────────

load_keyboard_layout() {
    if command -v loadkeys >/dev/null 2>&1; then
        loadkeys "$keyboard_value" >/dev/null 2>&1 || true
    fi
}

sync_xkb_layout() {
    case "$keyboard_value" in
        uk) xkb_layout_value="gb" ;;
        *)  xkb_layout_value="$keyboard_value" ;;
    esac
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
    lscpu 2>/dev/null | awk -F: '/Model name:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' \
        || printf 'Unknown CPU'
}

selected_disk_summary() {
    [[ -n "$disk" ]] || { printf 'No disk selected yet'; return 0; }

    lsblk -dn -o NAME,SIZE,MODEL,TRAN,RM "$disk" 2>/dev/null | awk '
        {
            model = ($3 == "" ? "Unknown model" : $3)
            tran  = ($4 == "" ? "internal" : $4)
            removable = ($5 == "1" ? "removable" : "fixed")
            printf "/dev/%s  %s  %s  [%s, %s]\n", $1, $2, model, tran, removable
        }
    ' || printf '%s\n' "$disk"
}

hardware_summary_text() {
    cat <<EOF
  Boot mode   $(detect_boot_mode)
  Memory      $(system_memory_gib)
  CPU         $(cpu_summary)
  Disk        $(selected_disk_summary)
  Desktop     ${desktop_label}
  Wallpaper   ${wallpaper_label}
  Apps        ${starter_apps_label}
  ANIX        $(sync_anix_label)
  GitHub      ${github_identity}
EOF
}

# ── Support report ────────────────────────────────────────────────────────────

save_support_report() {
    local report_path=""

    if [[ ! -x /etc/abora/support-report.sh ]]; then
        error_msg "The support report tool is not available in this build."
        pause_prompt
        return 1
    fi

    show_header "Saving support report" "Collecting hardware and log details."
    printf '  Gathering report...\n'
    printf '\n'
    report_path="$(/etc/abora/support-report.sh 2>/dev/null || true)"
    if [[ -n "$report_path" && -f "$report_path" ]]; then
        printf '%s\n' "$report_path" > "$support_report_output"
        success "Support report saved"
        printf '\n  %barchive:%b  %s\n' "$FAINT" "$DIM" "$report_path"
    else
        error_msg "Support report generation failed."
    fi
    pause_prompt
}

show_hardware_summary() {
    show_header "Hardware summary" "Your current machine at a glance."
    draw_rule
    printf '\n'
    hardware_summary_text
    printf '\n'
    draw_rule
    printf '  %bTip: use "Save support report" to capture these details and logs.%b\n' "$FAINT" "$NC"
    printf '\n'
    pause_prompt
}

preflight_warnings_text() {
    local root_device="" root_parent=""

    if root_device="$(findmnt -n -o SOURCE / 2>/dev/null)"; then
        root_parent="$(lsblk -no PKNAME "$root_device" 2>/dev/null || true)"
    fi

    if [[ -n "$root_parent" && "$disk" == "/dev/${root_parent}" ]]; then
        printf '  %b!%b  %bThe selected disk appears to back the current live system.%b\n' \
            "$YELLOW" "$NC" "$YELLOW" "$NC"
        printf '     Installing here will erase the media you booted from.\n\n'
    fi

    if [[ "$(awk '/MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || printf '0')" -lt 4194304 ]]; then
        printf '  %b!%b  %bSystem memory is under 4 GiB — expect slower installs.%b\n\n' \
            "$YELLOW" "$NC" "$YELLOW" "$NC"
    fi
}

# ── About screen ──────────────────────────────────────────────────────────────

show_about_abora() {
    show_header "Welcome to ${product_name}" "$product_tagline"
    draw_rule
    printf '\n'
    printf '  %s is trying to make NixOS feel more human from the start.\n' "$product_short"
    printf '\n'
    printf '  This installer gives you:\n'
    printf '\n'
    printf '  %b·%b  a cleaner first-run path\n'            "$BLUE" "$NC"
    printf '  %b·%b  easier desktop selection\n'            "$BLUE" "$NC"
    printf '  %b·%b  optional starter apps before first boot\n' "$BLUE" "$NC"
    printf '  %b·%b  a system that still updates the NixOS way\n' "$BLUE" "$NC"
    printf '\n'
    draw_rule
    printf '  %bNothing is written to disk until you confirm the install.%b\n' "$FAINT" "$NC"
    if [[ -n "$product_notice" ]]; then
        printf '\n'
        printf '  %b%s%b\n' "$CYAN" "$product_notice" "$NC"
    fi
    printf '\n'
    pause_prompt
}

show_product_notice() {
    [[ -n "$product_notice" ]] || return 0

    show_header "${product_name} setup notice" "Optional setup should feel clear before you continue."
    draw_rule
    printf '\n'
    printf '  %b%s%b\n' "$CYAN" "$product_notice" "$NC"
    printf '\n'
    draw_rule
    printf '  %bYou can skip the optional setup choices and continue with a plain NixOS-style base.%b\n' "$FAINT" "$NC"
    printf '\n'
    pause_prompt
}

open_live_shell_from_installer() {
    local shell_bin="${SHELL:-/run/current-system/sw/bin/bash}"

    show_header "Live shell" "Exit the shell to return to the installer."
    printf '  %bOpening a root shell. Type exit when you are done.%b\n\n' "$FAINT" "$NC"
    "$shell_bin" --login || true
}

# ── Starter apps ──────────────────────────────────────────────────────────────

starter_apps_preview() {
    local app_id="" app_name=""

    if [[ "${starter_apps_bundle,,}" == "none" ]]; then
        printf '  No extra starter apps selected.\n'
        return 0
    fi

    printf '  %bBundle:%b  %s\n' "$FAINT" "$NC" "$starter_apps_label"
    printf '\n'

    while IFS= read -r app_id; do
        [[ -n "$app_id" ]] || continue
        app_name="$(abora_catalog_name "$app_id" 2>/dev/null || printf '%s' "$app_id")"
        printf '  %b·%b  %s\n' "$BLUE" "$NC" "$app_name"
    done < <(abora_catalog_bundle_ids "$starter_apps_bundle")
}

show_starter_apps_preview() {
    show_header "Starter apps" "These apps will be preinstalled on the new system."
    draw_rule
    printf '\n'
    starter_apps_preview
    printf '\n'
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

# ── Welcome screen ────────────────────────────────────────────────────────────

show_installer_welcome() {
    while true; do
        show_welcome_header

        printf '  %s is trying to make NixOS feel more human from the start.\n' "$product_short"
        printf '\n'
        printf '  %bThis installer gives you:%b\n' "$ABORA_WHITE" "$NC"
        printf '\n'
        printf '  %b·%b  a cleaner first-run path\n'            "$BLUE" "$NC"
        printf '  %b·%b  easier desktop selection\n'            "$BLUE" "$NC"
        printf '  %b·%b  optional starter apps before first boot\n' "$BLUE" "$NC"
        printf '  %b·%b  a system that still updates the NixOS way\n' "$BLUE" "$NC"
        printf '\n'
        draw_rule
        printf '  %bNothing is written to disk until you confirm the install.%b\n' "$FAINT" "$NC"
        if [[ -n "$product_notice" ]]; then
            printf '\n'
            printf '  %b%s%b\n' "$CYAN" "$product_notice" "$NC"
        fi
        printf '\n'

        menu_choose \
            "What would you like to do?" \
            "Begin installation" \
            "View hardware summary" \
            "Save support report" \
            "Open live shell" \
            "Reboot" \
            "Power off" \
            "Cancel"

        case "$menu_result" in
            "__back__"|6)
                set_step_cancel
                return 0
                ;;
            0)
                show_product_notice
                set_step_next
                return 0
                ;;
            1)  show_hardware_summary ;;
            2)  save_support_report ;;
            3)  open_live_shell_from_installer ;;
            4)  sync; reboot ;;
            5)  sync; poweroff ;;
        esac
    done
}

prompt_anix_opt_in() {
    local selected=0
    local key=""
    local toggle_label=""
    local options=()

    while true; do
        show_header "Do you want ANIX?" "ANIX is optional — a simpler front layer for NixOS settings." 1 8
        draw_rule
        printf '\n'

        if [[ "$anix_info_compact" == "yes" ]]; then
            printf '  ANIX is a simple layer on top of NixOS and Abora.\n'
            printf '  You do not need it. If you skip it, you will just be using NixOS.\n'
            toggle_label="Show more"
        else
            printf '  ANIX is an easier front layer for common NixOS-style settings.\n'
            printf '\n'
            printf '  It helps with things like:\n'
            printf '  %b·%b  changing the wallpaper more easily\n' "$BLUE" "$NC"
            printf '  %b·%b  switching desktop/session defaults\n' "$BLUE" "$NC"
            printf '  %b·%b  editing hostname, timezone, and keyboard settings\n' "$BLUE" "$NC"
            printf '  %b·%b  rebuilding with simpler commands for first-time Nix users\n' "$BLUE" "$NC"
            printf '\n'
            printf '  You do not have to install ANIX. It just makes NixOS easier.\n'
            toggle_label="Show less"
        fi

        printf '\n'
        draw_rule
        printf '\n'

        # Show current choice
        printf '  %bCurrent choice:%b\n' "$ABORA_WHITE" "$NC"
        printf '\n'
        if [[ "$anix_enabled" == "yes" ]]; then
            abora_checkbox "Yes — install the ANIX helper layer" "yes"
            abora_checkbox "No — keep the install plain" "no"
        else
            abora_checkbox "Yes — install the ANIX helper layer" "no"
            abora_checkbox "No — keep the install plain" "yes"
        fi

        printf '\n'
        draw_rule
        printf '  %b%s%b\n' "$ABORA_DIM" "$toggle_label" "$ABORA_NC"
        printf '\n'

        if [[ "$anix_enabled" == "yes" ]]; then
            options=("Keep ANIX enabled" "Skip ANIX" "$toggle_label" "Back")
        else
            options=("Install ANIX" "Keep install plain" "$toggle_label" "Back")
        fi

        for i in "${!options[@]}"; do
            if [[ "$i" -eq "$selected" ]]; then
                printf '  %b▸%b  %b%s%b\n' "$ACCENT" "$NC" "$ABORA_WHITE" "${options[$i]}" "$NC"
            else
                printf '  %b  %b%s%b\n' "$FAINT" "$NC" "$DIM" "${options[$i]}" "$NC"
            fi
        done

        printf '\n'
        draw_rule
        printf '  %b↑↓ navigate  ·  enter select  ·  esc back%b\n' "$FAINT" "$NC"

        key="$(read_key)"
        case "$key" in
            $'\033')
                set_step_back
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
            "")
                case "$selected" in
                    0)
                        anix_enabled="yes"
                        ;;
                    1)
                        anix_enabled="no"
                        ;;
                    2)
                        if [[ "$anix_info_compact" == "yes" ]]; then
                            anix_info_compact="no"
                        else
                            anix_info_compact="yes"
                        fi
                        ;;
                    *)
                        set_step_back
                        return 0
                        ;;
                esac
                ;;
        esac
    done
}

# ── Extra packages screen ─────────────────────────────────────────────────────

show_extra_packages_setup() {
    while true; do
        menu_choose \
            "Extra packages and setup" \
            "Continue to install review" \
            "ANIX: $(sync_anix_label)" \
            "Install target: ${disk:-Not selected}" \
            "Desktop environment: ${desktop_label}" \
            "Wallpaper: ${wallpaper_label}" \
            "Extra packages: ${starter_apps_label}" \
            "View selected package bundle" \
            "View hardware summary" \
            "Save support report" \
            "Open live shell" \
            "Back" \
            "Cancel"

        case "$menu_result" in
            "__back__"|10)
                set_step_back
                return 0
                ;;
            1)
                prompt_anix_opt_in
                set_step_stay
                ;;
            2)
                prompt_disk || true
                set_step_stay
                ;;
            3)
                pick_desktop_environment
                set_step_stay
                ;;
            4)
                pick_wallpaper
                set_step_stay
                ;;
            5)
                pick_starter_apps_bundle
                set_step_stay
                ;;
            6)  show_starter_apps_preview ;;
            7)  show_hardware_summary ;;
            8)  save_support_report ;;
            9)  open_live_shell_from_installer ;;
            11)
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

# ── Names ─────────────────────────────────────────────────────────────────────

prompt_names() {
    while true; do
        prompt_hostname
        [[ "$step_action" == "back" ]] && { set_step_back; return 0; }

        prompt_username
        [[ "$step_action" == "back" ]] && continue

        set_step_next
        return 0
    done
}

# ── GitHub login ──────────────────────────────────────────────────────────────

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
                draw_rule
                printf '\n'
                printf '  %s will show a one-time device code in this installer.\n' "$product_short"
                printf '\n'
                printf '  Finish the login from your phone or another machine:\n'
                printf '  %b  github.com/login/device%b\n' "$CYAN" "$NC"
                printf '\n'
                printf '  If login succeeds, your GitHub auth config will be copied\n'
                printf '  into the installed user account.\n'
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

# ── Desktop picker ────────────────────────────────────────────────────────────

pick_desktop_environment() {
    local labels=(
        "No desktop     - console-only NixOS system"
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
        "Enlightenment  - unique EFL-based desktop"
        "i3             - keyboard-driven tiling"
        "AwesomeWM      - highly configurable tiling"
        "Openbox        - very minimal floating WM"
        "Qtile          - Python-configured tiling"
        "BSPWM          - binary space partitioning"
        "Fluxbox        - fast and lightweight"
        "IceWM          - very lightweight, retro feel"
        "Herbstluftwm   - manual tiling WM"
        "DWM            - suckless dynamic WM"
        "Back"
    )
    local values=(
        "none" "gnome" "plasma" "hyprland" "sway" "niri" "river"
        "xfce" "cinnamon" "mate" "budgie" "lxqt" "pantheon"
        "enlightenment" "i3" "awesome" "openbox"
        "qtile" "bspwm" "fluxbox" "icewm" "herbstluftwm" "dwm"
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

pick_wallpaper() {
    local labels=(
        "Ocean Dusk           - the current Abora default"
        "Blue Horizon         - bright blue and clean"
        "Astronaut Wallpaper  - darker and more dramatic"
        "Glacier Reflection   - colder and calmer"
        "Back"
    )
    local values=(
        "oceandusk.png"
        "bluehorizon.png"
        "astronautwallpaper.png"
        "glacierreflection.png"
    )

    menu_choose "Select default wallpaper" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#values[@]}" ]]; then
        set_step_back
        return 0
    fi

    wallpaper_name="${values[$menu_result]}"
    sync_wallpaper_label
    set_step_next
}

# ── Disk picker ───────────────────────────────────────────────────────────────

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) next
            model = ""
            for (i = 3; i < NF; i++) {
                model = model (model ? " " : "") $i
            }
            if (model == "") model = "Unknown model"
            print $1 "|" $2 "|" model
        }
    '
}

prompt_disk() {
    local entries=() labels=() paths=()
    local choice="" name="" size="" model="" entry=""

    mapfile -t entries < <(collect_disks)
    if [[ "${#entries[@]}" -eq 0 ]]; then
        show_header "Select install target" "No installable disks were found."
        printf '  %bNo disks are visible to the installer right now.%b\n' "$RED" "$NC"
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

# ── Individual prompts ────────────────────────────────────────────────────────

prompt_hostname() {
    local input=""

    while true; do
        prompt_input "Choose a hostname" "$hostname_value"
        input="$prompt_result"
        [[ "$input" == "__back__" ]] && { set_step_back; return 0; }
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
        [[ "$input" == "__back__" ]] && { set_step_back; return 0; }
        if [[ "$input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            username_value="$input"
            set_step_next
            return
        fi
        error_msg "Username must start with a lowercase letter or underscore."
        pause_prompt
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

prompt_timezone() {
    local input="" query="" zoneinfo_matches=()

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
            [[ "$query" == "__back__" ]] && { set_step_back; return 0; }
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
        [[ "$input" == "__back__" ]] && { set_step_back; return 0; }

        if timezone_exists "$input"; then
            timezone_value="$input"
            set_step_next
            return 0
        fi

        error_msg "Timezone not found. Try UTC, Etc/UTC, or use search."
        pause_prompt
    done
}

prompt_keyboard_layout() {
    local input=""

    while true; do
        prompt_input "Choose keyboard layout" "$keyboard_value" \
            "Enter a layout code (e.g. us, gb, de, fr, es, it). Type /back to return."
        input="$prompt_result"
        [[ "$input" == "__back__" ]] && { set_step_back; return 0; }
        if [[ "$input" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            keyboard_value="$input"
            sync_xkb_layout
            load_keyboard_layout
            set_step_next
            return 0
        fi
        error_msg "Invalid layout code. Use letters, numbers, or hyphens (e.g. us, gb, de)."
        pause_prompt
    done
}

prompt_language() {
    local lang_labels=(
        "English (US)             en_US.UTF-8"
        "English (UK)             en_GB.UTF-8"
        "German / Deutsch         de_DE.UTF-8"
        "French / Français        fr_FR.UTF-8"
        "Spanish / Español        es_ES.UTF-8"
        "Portuguese (Brazil)      pt_BR.UTF-8"
        "Portuguese (Portugal)    pt_PT.UTF-8"
        "Italian / Italiano       it_IT.UTF-8"
        "Dutch / Nederlands       nl_NL.UTF-8"
        "Polish / Polski          pl_PL.UTF-8"
        "Russian / Русский        ru_RU.UTF-8"
        "Ukrainian / Українська   uk_UA.UTF-8"
        "Czech / Čeština          cs_CZ.UTF-8"
        "Hungarian / Magyar       hu_HU.UTF-8"
        "Romanian / Română        ro_RO.UTF-8"
        "Turkish / Türkçe         tr_TR.UTF-8"
        "Swedish / Svenska        sv_SE.UTF-8"
        "Norwegian / Norsk        nb_NO.UTF-8"
        "Danish / Dansk           da_DK.UTF-8"
        "Finnish / Suomi          fi_FI.UTF-8"
        "Greek / Ελληνικά         el_GR.UTF-8"
        "Arabic / العربية         ar_SA.UTF-8"
        "Hebrew / עברית           he_IL.UTF-8"
        "Hindi / हिन्दी            hi_IN.UTF-8"
        "Chinese (Simplified)     zh_CN.UTF-8"
        "Chinese (Traditional)    zh_TW.UTF-8"
        "Japanese / 日本語         ja_JP.UTF-8"
        "Korean / 한국어            ko_KR.UTF-8"
        "Indonesian / Bahasa      id_ID.UTF-8"
        "Vietnamese / Tiếng Việt  vi_VN.UTF-8"
        "Back"
    )
    local lang_codes=(
        "en_US.UTF-8" "en_GB.UTF-8" "de_DE.UTF-8" "fr_FR.UTF-8"
        "es_ES.UTF-8" "pt_BR.UTF-8" "pt_PT.UTF-8" "it_IT.UTF-8"
        "nl_NL.UTF-8" "pl_PL.UTF-8" "ru_RU.UTF-8" "uk_UA.UTF-8"
        "cs_CZ.UTF-8" "hu_HU.UTF-8" "ro_RO.UTF-8" "tr_TR.UTF-8"
        "sv_SE.UTF-8" "nb_NO.UTF-8" "da_DK.UTF-8" "fi_FI.UTF-8"
        "el_GR.UTF-8" "ar_SA.UTF-8" "he_IL.UTF-8" "hi_IN.UTF-8"
        "zh_CN.UTF-8" "zh_TW.UTF-8" "ja_JP.UTF-8" "ko_KR.UTF-8"
        "id_ID.UTF-8" "vi_VN.UTF-8"
    )

    menu_choose "Choose language" "${lang_labels[@]}"
    local idx="$menu_result"

    if [[ "$idx" == "__back__" || "$idx" -eq $((${#lang_labels[@]} - 1)) ]]; then
        set_step_back
        return 0
    fi

    language_value="${lang_codes[$idx]}"
    set_step_stay
    return 0
}

prompt_locale() {
    while true; do
        menu_choose \
            "Locale settings" \
            "Continue" \
            "Language: ${language_value}" \
            "Timezone: ${timezone_value}" \
            "Keyboard: ${keyboard_value}" \
            "Back"

        case "$menu_result" in
            "__back__"|4)
                set_step_back
                return 0
                ;;
            0)
                set_step_next
                return 0
                ;;
            1)
                prompt_language
                [[ "$step_action" == "back" ]] && set_step_stay
                ;;
            2)
                prompt_timezone
                [[ "$step_action" == "back" ]] && set_step_stay
                ;;
            3)
                prompt_keyboard_layout
                [[ "$step_action" == "back" ]] && set_step_stay
                ;;
        esac
    done
}

prompt_password() {
    local first="" second=""

    while true; do
        show_header "Set password" "Choose a password for ${username_value}."
        draw_rule
        printf '\n'

        printf '  %b›%b  Password:         ' "$CYAN" "$NC"
        read -r -s first
        printf '\n'
        if [[ "$first" == "/back" ]]; then
            set_step_back
            return 0
        fi
        printf '  %b›%b  Confirm password: ' "$CYAN" "$NC"
        read -r -s second
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

        success "Password set for ${username_value}"
        unset first second
        set_step_next
        return
    done
}

# ── Confirm screen ────────────────────────────────────────────────────────────

confirm_install() {
    local cols inner

    cols="$(terminal_cols)"
    inner=$((cols - 6))
    [[ $inner -lt 30 ]] && inner=30
    [[ $inner -gt 60 ]] && inner=60

    local key_w=10
    local val_w=$((inner - key_w - 5))

    show_header "Ready to install" "Review your choices before the disk is wiped."

    # Summary card
    abora_card_start "Install Summary"

    printf '  %b│%b\n' "$BLUE" "$NC"

    _row() {
        local label="$1" value="$2"
        printf '  %b│%b  %b%-*s%b  %b%-*s%b  %b│%b\n' \
            "$BLUE" "$NC" \
            "$DIM"  "$key_w" "$label" "$NC" \
            "$CYAN" "$val_w" "$(trunc "$value" "$val_w")" "$NC" \
            "$BLUE" "$NC"
    }

    _row "Disk"      "$disk"
    _row "Desktop"   "$desktop_label"
    _row "Wallpaper" "$wallpaper_label"
    _row "ANIX"      "$(sync_anix_label)"
    _row "Apps"      "$starter_apps_label"
    _row "GitHub"    "$github_identity"
    _row "Hostname"  "$hostname_value"
    _row "User"      "$username_value"
    _row "Timezone"  "$timezone_value"
    _row "Keyboard"  "$keyboard_value"

    printf '  %b│%b\n' "$BLUE" "$NC"
    abora_card_end

    printf '\n'
    preflight_warnings_text
    printf '  %bDisk layout:%b  1 MiB BIOS boot  ·  512 MiB EFI  ·  ext4 root (remaining)\n' \
        "$FAINT" "$NC"
    printf '\n'
    printf '  %b!  The selected disk will be completely erased.%b\n' "$RED" "$NC"
    printf '\n'

    menu_choose "Continue with installation?" "Install now" "Back" "Cancel"
    case "$menu_result" in
        "__back__"|1) set_step_back ;;
        2)            set_step_cancel ;;
        *)            set_step_install ;;
    esac
}

# ── Disk partitioning ─────────────────────────────────────────────────────────

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

# ── Config generation ─────────────────────────────────────────────────────────

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

    mkdir -p /mnt/etc/nixos/abora/plymouth \
             /mnt/etc/nixos/abora/bootloader \
             /mnt/etc/nixos/abora/effects \
             /mnt/etc/nixos/abora/wallpapers \
             /mnt/etc/nixos/abora/themes

    cp "$title_file"                           /mnt/etc/nixos/abora/title.txt
    cp /etc/abora/VERSION                      /mnt/etc/nixos/abora/VERSION
    cp /etc/abora/app-catalog.sh               /mnt/etc/nixos/abora/app-catalog.sh
    cp /etc/abora/apps.sh                      /mnt/etc/nixos/abora/apps.sh
    cp /etc/abora/support-report.sh            /mnt/etc/nixos/abora/support-report.sh
    cp /etc/abora/hardware-test.sh             /mnt/etc/nixos/abora/hardware-test.sh
    cp /etc/abora/default-wallpaper.png        /mnt/etc/nixos/abora/default-wallpaper.png
    cp /etc/abora/fastfetch-logo.txt           /mnt/etc/nixos/abora/fastfetch-logo.txt
    cp /etc/abora/fastfetch-config.jsonc       /mnt/etc/nixos/abora/fastfetch-config.jsonc
    cp /etc/abora/effects/LaunchingAbora.mp3   /mnt/etc/nixos/abora/effects/LaunchingAbora.mp3
    cp /etc/abora/desktop-profiles.sh          /mnt/etc/nixos/abora/desktop-profiles.sh
    cp /etc/abora/installed-base.nix  /mnt/etc/nixos/abora/installed-base.nix
    cp /etc/abora/abora-options.nix   /mnt/etc/nixos/abora/abora-options.nix
    cp /etc/abora/anix-module.nix     /mnt/etc/nixos/abora/anix-module.nix
    cp /etc/abora/ui.sh               /mnt/etc/nixos/abora/ui.sh
    cp /etc/abora/config.sh           /mnt/etc/nixos/abora/config.sh
    cp /etc/abora/abora.sh            /mnt/etc/nixos/abora/abora.sh
    cp /etc/abora/desktop.sh          /mnt/etc/nixos/abora/desktop.sh
    cp /etc/abora/doctor.sh           /mnt/etc/nixos/abora/doctor.sh
    cp /etc/abora/recovery.sh         /mnt/etc/nixos/abora/recovery.sh
    cp /etc/abora/welcome.sh          /mnt/etc/nixos/abora/welcome.sh
    cp /etc/abora/anix.sh             /mnt/etc/nixos/abora/anix.sh
    cp /etc/abora/session-setup.sh             /mnt/etc/nixos/abora/session-setup.sh
    cp /etc/abora/theme-sync.sh                /mnt/etc/nixos/abora/theme-sync.sh
    cp /etc/abora/update.sh                    /mnt/etc/nixos/abora/update.sh
    cp /etc/abora/plymouth/abora.plymouth      /mnt/etc/nixos/abora/plymouth/abora.plymouth
    cp /etc/abora/plymouth/abora.script        /mnt/etc/nixos/abora/plymouth/abora.script

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
    [[ -f "$live_limine_background" ]] && limine_source="$live_limine_background"

    install -Dm0644 "$live_background"  /mnt/etc/nixos/abora/bootloader/background.png
    install -Dm0644 "$limine_source"    /mnt/etc/nixos/abora/bootloader/limine-background.png
    install -Dm0644 "$live_theme"       /mnt/etc/nixos/abora/bootloader/theme.txt

    if [[ ! -f /mnt/etc/nixos/abora/bootloader/background.png \
       || ! -f /mnt/etc/nixos/abora/bootloader/limine-background.png \
       || ! -f /mnt/etc/nixos/abora/bootloader/theme.txt ]]; then
        show_failure_screen \
            "Missing boot assets" \
            "The installer could not write the bootloader assets onto the target system." \
            "$config_log"
        return 1
    fi

    cp /etc/abora/wallpapers/* /mnt/etc/nixos/abora/wallpapers/
    cp /etc/abora/themes/*     /mnt/etc/nixos/abora/themes/
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
    [[ "${starter_apps_bundle,,}" == "none" ]] && return 0
    abora_catalog_bundle_ids "$starter_apps_bundle" > "$target_file"
}

render_apps_module_file() {
    local target_file="$1"
    local app_list_file="$2"
    local app_id="" app_expr=""

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
    local uid="1000" gid="100"

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
}

ensure_target_install_files() {
    mkdir -p /mnt/etc/nixos/abora

    if [[ ! -f /mnt/etc/nixos/abora/apps.list ]]; then
        : > /mnt/etc/nixos/abora/apps.list
    fi

    if [[ "${anix_enabled}" == "yes" && ! -f /mnt/etc/nixos/anix.nix ]]; then
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

  # Pick one of the shipped Abora wallpapers.
  anix.wallpaper = "${wallpaper_name}";
}
EOF
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
    info "Generating NixOS configuration"
    info "Writing configuration log to ${config_log}"
    printf '[*] Running nixos-generate-config --root /mnt\n' > "$config_log"
    if ! nixos-generate-config --root /mnt >>"$config_log" 2>&1; then
        show_failure_screen \
            "Configuration failed" \
            "${product_short} could not generate the base NixOS hardware config." \
            "$config_log"
        return 1
    fi

    write_install_assets

    cat > /mnt/etc/nixos/configuration.nix <<EOF
{ lib, ... }:
let
  appModule = ./abora/apps.nix;
  anixLayer = ./anix.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ./abora/installed-base.nix
    ./abora/abora-options.nix
    ./abora/anix-module.nix
    ./abora-local.nix
  ] ++ lib.optional (builtins.pathExists appModule) appModule
    ++ lib.optional (builtins.pathExists anixLayer) anixLayer;
}
EOF

    cat > /mnt/etc/nixos/abora-local.nix <<EOF
# ── Abora OS — system configuration ──────────────────────────────────────────
# Edit these values to personalise your system, then run 'update' to apply.
# Do not change abora.disk or abora.stateVersion after the first install.
{ ... }:
{
  # ── Identity ──────────────────────────────────────────────────────────────
  abora.hostname         = "${hostname_value}";
  abora.locale           = "${language_value}";  # e.g. de_DE.UTF-8, fr_FR.UTF-8
  abora.timezone         = "${timezone_value}";  # e.g. America/New_York, Europe/London
  abora.keyboard.console = "${keyboard_value}";  # TTY keymap
  abora.keyboard.xkb     = "${xkb_layout_value}"; # graphical keyboard layout

  # ── User ──────────────────────────────────────────────────────────────────
  abora.user.name           = "${username_value}";
  abora.user.hashedPassword = "${user_password_hash}"; # generate with: mkpasswd

  # ── Desktop ───────────────────────────────────────────────────────────────
  # Options: none gnome plasma hyprland sway niri xfce cinnamon mate budgie
  #          lxqt pantheon enlightenment i3 awesome openbox
  #          river qtile bspwm fluxbox icewm herbstluftwm dwm
  abora.desktop = "${desktop_profile}";

  # ── Look and feel ────────────────────────────────────────────────────────
  # Pick one of the shipped Abora wallpapers.
  abora.wallpaper = "${wallpaper_name}";

  # ── Hardware ──────────────────────────────────────────────────────────────
  abora.disk         = "${disk}";      # install disk for the bootloader
  abora.stateVersion = "26.05";        # set at install time — do not change
}
EOF

    cat > /mnt/etc/nixos/flake.nix <<EOF
{
  description = "Abora installed system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      baseModules =
        let
          appModule = ./abora/apps.nix;
          anixLayer = ./anix.nix;
        in
        [
          ./hardware-configuration.nix
          ./abora/installed-base.nix
          ./abora/abora-options.nix
          ./abora/anix-module.nix
          ./abora-local.nix
        ] ++ lib.optional (builtins.pathExists appModule) appModule
          ++ lib.optional (builtins.pathExists anixLayer) anixLayer;
      mkProfile = name: extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = baseModules ++ extraModules ++ [
          { system.nixos.variantName = lib.mkOverride 800 "Abora ${name} Profile"; }
        ];
      };
    in {
    nixosConfigurations.abora = mkProfile "Stable" [];
    nixosConfigurations.stable = mkProfile "Stable" [];
    nixosConfigurations.minimal = mkProfile "Minimal" [
      { abora.desktop = lib.mkForce "none"; }
    ];
    nixosConfigurations.gaming = mkProfile "Gaming" [
      { pkgs, ... }: {
        abora.desktop = lib.mkForce "gnome";
        environment.systemPackages = with pkgs; [ mangohud prismlauncher lutris ];
        programs.steam.enable = lib.mkDefault true;
      }
    ];
    nixosConfigurations.creator = mkProfile "Creator" [
      { pkgs, ... }: {
        abora.desktop = lib.mkForce "gnome";
        environment.systemPackages = with pkgs; [ blender gimp inkscape krita obs-studio audacity ];
      }
    ];
    nixosConfigurations.developer = mkProfile "Developer" [
      { pkgs, ... }: {
        abora.desktop = lib.mkForce "gnome";
        environment.systemPackages = with pkgs; [ git gh vscode direnv nixfmt-rfc-style shellcheck ];
      }
    ];
  };
}
EOF
    success "Configuration written"
}

install_system() {
    local nixpkgs_path="" nix_path="" status=0
    local install_pid="" start_time=0 elapsed=0
    local progress=45 status_text=""

    info "Installing ${product_name}"
    info "This can take a few minutes."
    ensure_target_install_files || return 1
    nixpkgs_path="$(resolve_nixpkgs_path)" || {
        error_msg "Could not locate nixpkgs for nixos-install."
        return 1
    }
    nix_path="nixpkgs=${nixpkgs_path}:nixos-config=/mnt/etc/nixos/configuration.nix"
    info "Writing install log to ${install_log}"
    printf '[*] Running nixos-install\n' > "$install_log"
    printf '[*] NIX_PATH=%s\n' "$nix_path" >> "$install_log"

    NIX_PATH="$nix_path" nixos-install \
        --root /mnt \
        --no-root-passwd \
        -I "nixpkgs=${nixpkgs_path}" \
        -I "nixos-config=/mnt/etc/nixos/configuration.nix" \
        >>"$install_log" 2>&1 &
    install_pid="$!"
    start_time="$(date +%s)"

    while kill -0 "$install_pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start_time ))
        progress="$(install_progress_percent "$install_log" "$elapsed")"
        status_text="$(install_status_summary "$install_log")"
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
            "${product_short} could not finish writing the system." \
            "$install_log"
        return 1
    fi
}

# ── Finish screen ─────────────────────────────────────────────────────────────

finish_screen() {
    show_header "Install complete" "Your machine is ready for first boot."

    abora_card_start "Success"
    printf '  %b│%b\n' "$BLUE" "$NC"
    printf '  %b│%b  %b✓%b  %b%s %s installed successfully.%b\n' \
        "$BLUE" "$NC" "$GREEN" "$NC" "$GREEN" "$product_name" "$version" "$NC"
    printf '  %b│%b\n' "$BLUE" "$NC"
    printf '  %b│%b  %bNext steps%b\n' "$BLUE" "$NC" "$WHITE" "$NC"
    printf '  %b│%b\n' "$BLUE" "$NC"
    printf '  %b│%b  %b1%b  Remove the installation media (USB drive or ISO).\n' \
        "$BLUE" "$NC" "$DIM" "$NC"
    printf '  %b│%b  %b2%b  Reboot — your drive will be selected automatically.\n' \
        "$BLUE" "$NC" "$DIM" "$NC"
    if [[ "$desktop_profile" == "none" ]]; then
        printf '  %b│%b  %b3%b  Log in as  %b%s%b  on the local console.\n' \
            "$BLUE" "$NC" "$DIM" "$NC" "$CYAN" "$username_value" "$NC"
    else
        printf '  %b│%b  %b3%b  Log in as  %b%s%b  on the  %b%s%b  desktop.\n' \
            "$BLUE" "$NC" "$DIM" "$NC" "$CYAN" "$username_value" "$NC" "$CYAN" "$desktop_label" "$NC"
    fi
    printf '  %b│%b\n' "$BLUE" "$NC"
    abora_card_end

    printf '\n'

    menu_choose "What would you like to do?" "Reboot into ${product_name}" "Power off"

    case "$menu_result" in
        0)  sync; reboot ;;
        *)  sync; poweroff ;;
    esac
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

cleanup_target() {
    sync
    umount -R /mnt 2>/dev/null || true
}

show_installer_loading() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local phases=(
        "Checking system requirements"
        "Detecting hardware configuration"
        "Loading desktop profiles"
        "Preparing installer modules"
        "Starting the installer"
    )
    local total_phases=${#phases[@]}
    local i=0 idx=0 elapsed=0

    clear_screen
    printf '\n'
    draw_brand_header
    printf '\n'

    local cols width
    cols="$(terminal_cols)"
    width=$((cols - 12))
    [[ $width -lt 20 ]] && width=20
    [[ $width -gt 60 ]] && width=60

    printf '  %bInitializing%b\n' "$ABORA_WHITE" "$NC"
    printf '\n'

    while [[ $elapsed -lt 4 ]]; do
        idx=$((elapsed % ${#frames[@]}))
        i=$((elapsed * total_phases / 4))
        [[ $i -ge $total_phases ]] && i=$((total_phases - 1))

        printf '\r  %b%s%b  %b%s%b  %b%ds%b' \
            "$ACCENT" "${frames[$idx]}" "$NC" \
            "$ABORA_WHITE" "${phases[$i]}" "$NC" \
            "$FAINT" "$((4 - elapsed))" "$NC"

        sleep 0.25
        elapsed=$((elapsed + 1))
    done

    printf '\n\n'
    success "System ready"
    printf '\n'
}

# ── Main loop ─────────────────────────────────────────────────────────────────

main() {
    local step=0

    require_root
    sync_wallpaper_label
    sync_starter_apps_label
    refresh_github_identity
    auto_detect_timezone
    auto_detect_keyboard
    if ! command -v mkpasswd >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
        error_msg "Password hashing is unavailable. Install mkpasswd or openssl."
        exit 1
    fi

    if [[ "${ABORA_SKIP_INSTALLER_LOADING:-0}" != "1" ]]; then
        show_installer_loading
    fi

    while true; do
        set_step_next

        case "$step" in
            0) show_installer_welcome ;;
            1) prompt_anix_opt_in ;;
            2) prompt_names ;;
            3) prompt_locale ;;
            4) prompt_password ;;
            5) prompt_github_login ;;
            6) show_extra_packages_setup ;;
            7) confirm_install ;;
        esac

        case "$step_action" in
            back)
                [[ "$step" -gt 0 ]] && step=$((step - 1))
                ;;
            cancel)
                info "Install cancelled."
                return 0
                ;;
            stay)
                ;;
            install)
                show_install_progress_screen 5  "Preparing the target disk"               0
                partition_disk
                show_install_progress_screen 18 "Mounting the target filesystem"          0
                mount_target
                show_install_progress_screen 32 "Generating the Abora system configuration" 0 "$config_log"
                generate_config || { pause_prompt; return 1; }
                show_install_progress_screen 40 "Starting nixos-install"                  0 "$install_log"
                install_system  || { pause_prompt; return 1; }
                copy_github_auth_to_target
                cleanup_target
                finish_screen
                return 0
                ;;
            *)
                if [[ "$step" -lt 7 ]]; then
                    step=$((step + 1))
                fi
                ;;
        esac
    done
}

main "$@"
