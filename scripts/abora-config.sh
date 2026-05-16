#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

# shellcheck source=/dev/null
source "$ui_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
local_module="${config_dir}/abora-local.nix"
wallpaper_dir="${ABORA_WALLPAPER_DIR:-/etc/abora/wallpapers}"

# ── Helpers ───────────────────────────────────────────────────────────────────

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"; return
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"; return
    fi
    abora_error "This command needs root privileges."
    exit 1
}

is_options_format() {
    [[ -f "$local_module" ]] && grep -q 'abora\.user\.name' "$local_module" 2>/dev/null
}

require_options_format() {
    if ! is_options_format; then
        abora_error "abora-local.nix uses the legacy format."
        abora_warn  "Reinstall or migrate to the v2.5 config format to use this command."
        printf '\n'
        exit 1
    fi
}

require_local_module() {
    if [[ ! -f "$local_module" ]]; then
        abora_error "No abora-local.nix found at ${local_module}."
        abora_warn  "This command only works on an installed Abora system."
        printf '\n'
        exit 1
    fi
}

# Read a single abora.* value from abora-local.nix.
# Usage: read_option "hostname"  or  read_option "keyboard.console"
read_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    sed -nE "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*|\1|p" \
        "$local_module" | head -n1
}

# Replace a single abora.* value in abora-local.nix.
# Usage: write_option "hostname" "new-value"
write_option() {
    local key="$1" value="$2"
    local escaped_key="${key//./\\.}"
    sed -i -E \
        "s|^([[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*)\"[^\"]*\";|\1\"${value}\";|" \
        "$local_module"
}

# ── Display ───────────────────────────────────────────────────────────────────

show_config() {
    require_local_module

    local hostname timezone kb_console kb_xkb user_name desktop wallpaper disk state_ver
    hostname="$(read_option "hostname")"
    timezone="$(read_option "timezone")"
    kb_console="$(read_option "keyboard.console")"
    kb_xkb="$(read_option "keyboard.xkb")"
    user_name="$(read_option "user.name")"
    desktop="$(read_option "desktop")"
    wallpaper="$(read_option "wallpaper")"
    disk="$(read_option "disk")"
    state_ver="$(read_option "stateVersion")"

    if ! is_options_format; then
        abora_banner "System Configuration" "Legacy format — upgrade to v2.5 to use abora config set."
        abora_warn "This system uses the pre-v2.5 configuration format."
        abora_dim_line "Reinstall from the latest Abora ISO to get the new format."
        printf '\n'
        return 0
    fi

    abora_banner "System Configuration" "${local_module}"

    abora_card_start "Current Settings"

    abora_kv "hostname"      "${hostname:-—}"
    abora_kv "timezone"      "${timezone:-—}"
    printf '  %b│%b  %b%-18s%b  %b%s%b  /  %b%s%b\n' \
        "$ABORA_BLUE" "$ABORA_NC" \
        "$ABORA_DIM" "keyboard" "$ABORA_NC" \
        "$ABORA_CYAN" "${kb_console:-—}" "$ABORA_NC" \
        "$ABORA_DIM" "${kb_xkb:-—}" "$ABORA_NC"
    abora_kv "desktop"       "${desktop:-—}"
    abora_kv "wallpaper"     "${wallpaper:-—}"
    abora_kv "user"          "${user_name:-—}"
    abora_kv_faint "disk"    "${disk:-—}"
    abora_kv_faint "state version" "${state_ver:-—}"

    abora_card_end

    printf '\n'
    abora_dim_line "Run 'abora config set <key> <value>' to change a setting."
    abora_dim_line "Run 'abora config apply' to rebuild after changes."
    printf '\n'
}

# ── Set ───────────────────────────────────────────────────────────────────────

valid_desktops=(
    none gnome plasma hyprland sway xfce cinnamon mate budgie lxqt pantheon
    enlightenment i3 awesome openbox niri river qtile bspwm fluxbox
    icewm herbstluftwm
)

wallpaper_candidates() {
    if [[ -d "$wallpaper_dir" ]]; then
        find "$wallpaper_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
        return 0
    fi

    printf '%s\n' \
        oceandusk.png \
        bluehorizon.png \
        astronautwallpaper.png \
        glacierreflection.png
}

validate_wallpaper() {
    local candidate="$1"
    if wallpaper_candidates | grep -Fxq "$candidate"; then
        return 0
    fi

    abora_error "Unknown wallpaper: '${candidate}'"
    printf '  %bAvailable wallpapers:%b\n' "$ABORA_DIM" "$ABORA_NC"
    wallpaper_candidates | sed 's/^/    /'
    printf '\n'
    exit 1
}

validate_desktop() {
    local d="$1"
    for valid in "${valid_desktops[@]}"; do
        [[ "$d" == "$valid" ]] && return 0
    done
    abora_error "Unknown desktop: '${d}'"
    printf '  %bValid options:%b %s\n\n' "$ABORA_DIM" "$ABORA_NC" "${valid_desktops[*]}"
    exit 1
}

do_set() {
    local key="$1" value="$2"

    require_local_module
    require_options_format

    # Validate and normalise the key.
    case "$key" in
        hostname)
            if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
                abora_error "Invalid hostname '${value}' — use letters, numbers, and hyphens only."
                exit 1
            fi
            ;;
        timezone) ;;
        keyboard | keyboard.console)
            key="keyboard.console"
            ;;
        keyboard.xkb) ;;
        desktop)
            validate_desktop "$value"
            ;;
        wallpaper)
            validate_wallpaper "$value"
            ;;
        *)
            abora_error "Unknown key: '${key}'"
            printf '  %bSettable keys:%b  hostname  timezone  keyboard  keyboard.xkb  desktop  wallpaper\n\n' \
                "$ABORA_DIM" "$ABORA_NC"
            exit 1
            ;;
    esac

    # Write the new value — one sed pass, works for all keys.
    local escaped_key="${key//./\\.}"
    run_as_root sed -i -E \
        "s|^([[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*)\"[^\"]*\";|\\1\"${value}\";|" \
        "$local_module"

    abora_success "'abora.${key}' set to '${value}'"
    abora_dim_line "Run 'abora config apply' to rebuild the system."
    printf '\n'
}

# ── Apply ─────────────────────────────────────────────────────────────────────

do_apply() {
    local flake_target="${ABORA_FLAKE_CONFIG_NAME:-abora}"

    require_local_module

    abora_banner "Apply Configuration" "Rebuilding Abora from ${local_module}"
    abora_step "Running nixos-rebuild switch"
    printf '\n'

    run_as_root nixos-rebuild switch --flake "${config_dir}#${flake_target}"

    printf '\n'
    abora_success "Done. Your changes are now active."
    printf '\n'
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    abora_banner "Config" "View and edit your Abora system settings."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"

    printf '  %babora config%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show all current settings."
    printf '\n'

    printf '  %babora config set hostname   <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %babora config set timezone   <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %babora config set keyboard   <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %babora config set desktop    <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %babora config set wallpaper  <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Update a setting in abora-local.nix."
    printf '\n'

    printf '  %babora config apply%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Rebuild the system to apply pending changes."
    printf '\n'

    printf '  %bSettable keys%b\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '\n'
    abora_dim_line "  hostname       Machine hostname (e.g. my-pc)"
    abora_dim_line "  timezone       System timezone (e.g. America/New_York)"
    abora_dim_line "  keyboard       Console keymap (e.g. us, de, fr)"
    abora_dim_line "  keyboard.xkb   Graphical keyboard layout"
    abora_dim_line "  desktop        Desktop environment (e.g. gnome, hyprland, plasma)"
    abora_dim_line "  wallpaper      Shipped Abora wallpaper filename"
    printf '\n'
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local command="${1:-}"

    case "$command" in
        "" | show)
            show_config
            ;;
        set)
            if [[ "${2:-}" == "" || "${3:-}" == "" ]]; then
                abora_error "Usage: abora config set <key> <value>"
                printf '\n'
                exit 1
            fi
            do_set "$2" "$3"
            ;;
        apply)
            do_apply
            ;;
        help | --help | -h)
            usage
            ;;
        *)
            abora_error "Unknown command: ${command}"
            printf '\n'
            usage
            exit 1
            ;;
    esac
}

main "$@"
