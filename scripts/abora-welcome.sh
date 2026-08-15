#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
[[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]] && ui_lib="/etc/abora/ui.sh"

if [[ -f "$ui_lib" ]]; then
    # shellcheck source=/dev/null
    source "$ui_lib"
else
    # Minimal fallback UI -- used when abora-ui.sh isn't available (e.g. a
    # bare checkout before install, or a corrupted /etc/abora).
    ABORA_DIM=$'\033[38;5;242m'
    ABORA_NC=$'\033[0m'
    ABORA_CYAN=$'\033[38;5;44m'
    ABORA_WHITE=$'\033[1;97m'
    ABORA_BLUE=$'\033[38;5;33m'
    abora_banner()     { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_success()    { printf '  \033[38;5;77m✓\033[0m  \033[38;5;77m%s\033[0m\n' "$1"; }
    abora_warn()       { printf '  \033[38;5;222m!\033[0m  \033[38;5;222m%s\033[0m\n' "$1"; }
    abora_error()      { printf '  \033[38;5;203m✗\033[0m  \033[38;5;203m%s\033[0m\n' "$1" >&2; }
    abora_dim_line()   { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
    abora_kv()         { printf '  %b%-18s%b  %b%s%b\n' "$ABORA_DIM" "$1" "$ABORA_NC" "$ABORA_CYAN" "${2:-}" "$ABORA_NC"; }
    abora_card_start() { printf '  %b┌─ %s ─%b\n' "$ABORA_BLUE" "${1:-}" "$ABORA_NC"; }
    abora_card_end()   { printf '  %b└────────%b\n' "$ABORA_BLUE" "$ABORA_NC"; }
fi

welcome_config="${XDG_CONFIG_HOME:-$HOME/.config}/abora/welcome.conf"
welcome_marker="$HOME/.cache/abora/welcome-seen"

# These two files are also read directly by profile.d/abora-welcome.sh (shell
# login banner) and the abora-welcome-gui.desktop autostart entry
# (installed-base.nix) -- welcome_config's show_on_startup=false is the
# permanent "don't show again" opt-out, while welcome_marker just tracks
# whether this particular session has already shown it once.
set_startup() {
    local value="$1"
    mkdir -p "$(dirname "$welcome_config")" "$(dirname "$welcome_marker")"
    case "$value" in
        on|true|yes|1)
            printf 'show_on_startup=true\n' > "$welcome_config"
            rm -f "$welcome_marker"
            abora_success "Abora Welcome will show on startup."
            ;;
        off|false|no|0)
            printf 'show_on_startup=false\n' > "$welcome_config"
            touch "$welcome_marker"
            abora_success "Abora Welcome will not show on startup."
            ;;
        *)
            abora_error "Usage: abora welcome startup <on|off>"
            exit 1
            ;;
    esac
}

read_setting() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    local file="${ABORA_SYSTEM_CONFIG:-/etc/nixos}/abora-local.nix"
    [[ -f "$file" ]] || return 0
    sed -nE "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\\1|p" "$file" | head -n1
}

read_bool_setting() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    local file="${ABORA_SYSTEM_CONFIG:-/etc/nixos}/abora-local.nix"
    [[ -f "$file" ]] || return 0
    sed -nE "s@^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*(true|false);?.*@\\1@p" "$file" | head -n1
}

show_status() {
    local desktop wallpaper channel flathub anix_state gaming_state
    desktop="$(read_setting desktop)"
    wallpaper="$(read_setting wallpaper)"
    gaming_state="$(read_bool_setting gaming.enable)"
    [[ "$gaming_state" == "true" ]] && gaming_state="enabled" || gaming_state="off"
    channel="${ABORA_DEFAULT_CHANNEL:-unstable}"
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
    abora_kv "Gaming" "$gaming_state"
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
    printf '  %b3%b  Open gaming setup\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b4%b  Create first ANIX snapshot\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b5%b  Switch desktop\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b6%b  Open recovery tools\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %bq%b  Quit\n\n' "$ABORA_DIM" "$ABORA_NC"
}

usage() {
    abora_banner "Welcome" "First-run status and quick actions."
    printf '  %babora welcome%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Open the interactive welcome menu."
    printf '\n'
    printf '  %babora welcome status%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show desktop, wallpaper, gaming, update, Flathub, and ANIX status."
    printf '\n'
    printf '  %babora welcome startup on%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show Abora Welcome automatically after login."
    printf '\n'
    printf '  %babora welcome startup off%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Stop showing Abora Welcome automatically."
    printf '\n'
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
                1) abora doctor ;;
                2) abora apps ;;
                3) abora gaming status ;;
                4) anix save "anix: first Abora snapshot" ;;
                5) abora desktop list ;;
                6) abora recovery ;;
                q|Q) exit 0 ;;
                *) abora_warn "Unknown choice: $choice" ;;
            esac
            printf '\n'
            read -r -p "  Press Enter to continue..." _
        done
        ;;
    help|--help|-h)
        usage
        ;;
    startup)
        set_startup "${2:-}"
        ;;
    *)
        abora_error "Unknown welcome command: $1"
        usage >&2
        exit 1
        ;;
esac
