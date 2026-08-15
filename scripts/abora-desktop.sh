#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
profiles_lib="${ABORA_DESKTOP_PROFILES_LIB:-$script_dir/abora-desktop-profiles.sh}"

[[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]] && ui_lib="/etc/abora/ui.sh"
[[ ! -f "$profiles_lib" && -f /etc/abora/desktop-profiles.sh ]] && profiles_lib="/etc/abora/desktop-profiles.sh"

if [[ -f "$ui_lib" ]]; then
    # shellcheck source=/dev/null
    source "$ui_lib"
else
    # Minimal fallback UI -- used when abora-ui.sh isn't available (e.g. a
    # bare checkout before install, or a corrupted /etc/abora).
    ABORA_DIM=$'\033[38;5;242m'
    ABORA_NC=$'\033[0m'
    ABORA_WHITE=$'\033[1;97m'
    ABORA_BLUE=$'\033[38;5;33m'
    ABORA_CYAN=$'\033[38;5;44m'
    abora_banner()     { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_error()      { printf '  \033[38;5;203m✗\033[0m  \033[38;5;203m%s\033[0m\n' "$1" >&2; }
    abora_dim_line()   { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
    abora_card_start() { printf '  %b┌─ %s ─%b\n' "$ABORA_BLUE" "${1:-}" "$ABORA_NC"; }
    abora_card_end()   { printf '  %b└────────%b\n' "$ABORA_BLUE" "$ABORA_NC"; }
fi
# shellcheck source=/dev/null
source "$profiles_lib"

run_config() {
    if command -v abora-config >/dev/null 2>&1; then
        abora-config "$@"
    else
        ABORA_UI_LIB="$ui_lib" bash "$script_dir/abora-config.sh" "$@"
    fi
}

usage() {
    abora_banner "Desktop" "View or switch Abora desktop profiles."
    printf '  %babora desktop%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show current desktop setting."
    printf '\n'
    printf '  %babora desktop list%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List supported desktop profiles."
    printf '\n'
    printf '  %babora desktop set <profile>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Change the desktop profile; rebuild with 'abora config apply'."
    printf '\n'
}

case "${1:-show}" in
    show|"")
        run_config
        ;;
    list)
        abora_banner "Desktop Profiles" "These names work with 'abora desktop set <profile>'."
        abora_card_start "Supported Profiles"
        abora_supported_desktop_profiles | while IFS= read -r profile; do
            abora_sync_desktop_label "$profile"
            printf '  %b│%b  %b%-16s%b %b%s%b\n' \
                "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$profile" "$ABORA_NC" "$ABORA_DIM" "$desktop_label" "$ABORA_NC"
        done
        abora_card_end
        printf '\n'
        ;;
    set)
        profile="${2:-}"
        if [[ -z "$profile" ]]; then
            abora_error "Usage: abora desktop set <profile>"
            exit 1
        fi
        if ! abora_supported_desktop_profiles | grep -Fxq "$profile"; then
            abora_error "Unknown desktop profile: $profile"
            exit 1
        fi
        run_config set desktop "$profile"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        abora_error "Unknown desktop command: $1"
        usage
        exit 1
        ;;
esac
