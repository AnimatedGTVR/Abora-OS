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

config_dir="${ANIX_SYSTEM_CONFIG:-/etc/nixos}"
anix_file="${ANIX_CONFIG_FILE:-$config_dir/anix.nix}"
abora_local_file="${config_dir}/abora-local.nix"
flake_config_name="${ANIX_FLAKE_CONFIG_NAME:-abora}"

valid_desktops=(
    none gnome plasma hyprland sway xfce cinnamon mate budgie lxqt pantheon
    lxde enlightenment i3 awesome openbox niri river qtile bspwm fluxbox
    icewm herbstluftwm dwm
)

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return
    fi
    abora_error "This command needs root privileges."
    exit 1
}

read_anix_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    [[ -f "$anix_file" ]] || return 0
    sed -nE "s|^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\1|p" "$anix_file" | head -n1
}

read_abora_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    [[ -f "$abora_local_file" ]] || return 0
    sed -nE "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\1|p" "$abora_local_file" | head -n1
}

validate_desktop() {
    local candidate="$1"
    local valid=""

    for valid in "${valid_desktops[@]}"; do
        [[ "$candidate" == "$valid" ]] && return 0
    done

    abora_error "Unknown desktop: ${candidate}"
    printf '  %bValid options:%b %s\n\n' "$ABORA_DIM" "$ABORA_NC" "${valid_desktops[*]}"
    exit 1
}

seed_value() {
    local key="$1"
    local fallback="$2"
    local value=""

    value="$(read_abora_option "$key")"
    if [[ -n "$value" ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

render_template() {
    local hostname timezone keyboard_console keyboard_xkb desktop

    hostname="$(seed_value "hostname" "abora")"
    timezone="$(seed_value "timezone" "UTC")"
    keyboard_console="$(seed_value "keyboard.console" "us")"
    keyboard_xkb="$(seed_value "keyboard.xkb" "$keyboard_console")"
    desktop="$(seed_value "desktop" "gnome")"

    cat <<EOF
# ANIX is a simple layer on top of Abora/NixOS.
# Keep the settings here easy to read, then run 'anix apply'.
{ ... }:
{
  anix.enable = true;

  anix.hostname = "${hostname}";
  anix.timezone = "${timezone}";
  anix.keyboard.console = "${keyboard_console}";
  anix.keyboard.xkb = "${keyboard_xkb}";
  anix.desktop = "${desktop}";
}
EOF
}

ensure_anix_file() {
    if [[ -f "$anix_file" ]]; then
        return 0
    fi

    run_as_root mkdir -p "$config_dir"
    run_as_root bash -c "$(printf 'cat > %q <<'"'"'EOF'"'"'\n%s\nEOF' "$anix_file" "$(render_template)")"
}

show_config() {
    if [[ ! -f "$anix_file" ]]; then
        abora_banner "ANIX" "No ANIX config exists yet."
        abora_dim_line "Run 'anix init' to create ${anix_file}."
        printf '\n'
        return 0
    fi

    local hostname timezone kb_console kb_xkb desktop
    hostname="$(read_anix_option "hostname")"
    timezone="$(read_anix_option "timezone")"
    kb_console="$(read_anix_option "keyboard.console")"
    kb_xkb="$(read_anix_option "keyboard.xkb")"
    desktop="$(read_anix_option "desktop")"

    abora_banner "ANIX" "${anix_file}"
    printf '  %b%-18s%b  %b%s%b\n' "$ABORA_DIM" "hostname" "$ABORA_NC" "$ABORA_CYAN" "${hostname:-—}" "$ABORA_NC"
    printf '  %b%-18s%b  %b%s%b\n' "$ABORA_DIM" "timezone" "$ABORA_NC" "$ABORA_CYAN" "${timezone:-—}" "$ABORA_NC"
    printf '  %b%-18s%b  %b%s%b / %b%s%b\n' \
        "$ABORA_DIM" "keyboard" "$ABORA_NC" \
        "$ABORA_CYAN" "${kb_console:-—}" "$ABORA_NC" \
        "$ABORA_DIM" "${kb_xkb:-—}" "$ABORA_NC"
    printf '  %b%-18s%b  %b%s%b\n' "$ABORA_DIM" "desktop" "$ABORA_NC" "$ABORA_CYAN" "${desktop:-—}" "$ABORA_NC"
    printf '\n'
    abora_dim_line "Run 'anix set <key> <value>' to change a setting."
    abora_dim_line "Run 'anix apply' to rebuild with the ANIX layer."
    printf '\n'
}

do_init() {
    if [[ -f "$anix_file" ]]; then
        abora_warn "ANIX config already exists at ${anix_file}."
        abora_dim_line "Use 'anix show' or edit the file directly."
        printf '\n'
        return 0
    fi

    run_as_root mkdir -p "$config_dir"
    run_as_root bash -c "$(printf 'cat > %q <<'"'"'EOF'"'"'\n%s\nEOF' "$anix_file" "$(render_template)")"
    abora_success "Created ${anix_file}"
    abora_dim_line "Run 'anix apply' when you are ready."
    printf '\n'
}

do_set() {
    local key="${1:-}"
    local value="${2:-}"
    local escaped_key=""

    if [[ -z "$key" || -z "$value" ]]; then
        abora_error "Usage: anix set <key> <value>"
        printf '\n'
        exit 1
    fi

    ensure_anix_file

    case "$key" in
        hostname)
            if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
                abora_error "Invalid hostname '${value}'."
                exit 1
            fi
            ;;
        timezone) ;;
        keyboard|keyboard.console)
            key="keyboard.console"
            ;;
        keyboard.xkb) ;;
        desktop)
            validate_desktop "$value"
            ;;
        *)
            abora_error "Unknown key: ${key}"
            printf '  %bSettable keys:%b hostname timezone keyboard keyboard.xkb desktop\n\n' "$ABORA_DIM" "$ABORA_NC"
            exit 1
            ;;
    esac

    escaped_key="${key//./\\.}"
    run_as_root sed -i -E \
        "s|^([[:space:]]*anix\\.${escaped_key}[[:space:]]*=[[:space:]]*)\"[^\"]*\";|\\1\"${value}\";|" \
        "$anix_file"

    abora_success "'anix.${key}' set to '${value}'"
    abora_dim_line "Run 'anix apply' to rebuild with the ANIX layer."
    printf '\n'
}

do_apply() {
    ensure_anix_file

    abora_banner "ANIX Apply" "Rebuilding with ${anix_file}"
    abora_step "Running nixos-rebuild switch"
    printf '\n'

    run_as_root nixos-rebuild switch --flake "${config_dir}#${flake_config_name}"

    printf '\n'
    abora_success "Done. The ANIX layer is now active."
    printf '\n'
}

usage() {
    abora_banner "ANIX" "A simple layer on top of Abora/NixOS."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %banix init%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create /etc/nixos/anix.nix using your current Abora settings as a base."
    printf '\n'
    printf '  %banix show%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the current ANIX settings."
    printf '\n'
    printf '  %banix set hostname <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set timezone <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard.xkb <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set desktop <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Update a simple ANIX setting."
    printf '\n'
    printf '  %banix apply%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Rebuild the system using the ANIX layer."
    printf '\n'
}

main() {
    local command="${1:-show}"

    case "$command" in
        init) shift; do_init "$@" ;;
        show|"") shift; show_config "$@" ;;
        set) shift; do_set "$@" ;;
        apply) shift; do_apply "$@" ;;
        help|--help|-h) usage ;;
        *)
            abora_error "Unknown ANIX command: ${command}"
            printf '\n'
            usage
            exit 1
            ;;
    esac
}

main "$@"
