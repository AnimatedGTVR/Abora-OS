#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
profiles_lib="${ABORA_DESKTOP_PROFILES_LIB:-$script_dir/abora-desktop-profiles.sh}"

[[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]] && ui_lib="/etc/abora/ui.sh"
[[ ! -f "$profiles_lib" && -f /etc/abora/desktop-profiles.sh ]] && profiles_lib="/etc/abora/desktop-profiles.sh"

# shellcheck source=/dev/null
source "$ui_lib"
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
