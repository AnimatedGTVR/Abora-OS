#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="${ABORA_DIR:-/etc/abora}"

if [[ ! -f "$ui_lib" && -f "$abora_dir/ui.sh" ]]; then
    ui_lib="$abora_dir/ui.sh"
fi

# shellcheck source=/dev/null
source "$ui_lib"

warnings=0
failures=0

ok() {
    abora_success "$1"
}

warn() {
    warnings=$((warnings + 1))
    abora_warn "$1"
}

fail() {
    failures=$((failures + 1))
    abora_error "$1"
}

check_file() {
    local file="$1"
    local label="$2"
    if [[ -e "$file" ]]; then
        ok "$label"
    else
        fail "$label missing: $file"
    fi
}

read_abora_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    local file="$config_dir/abora-local.nix"
    [[ -f "$file" ]] || return 0
    sed -nE "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\\1|p" "$file" | head -n1
}

read_local_assignment() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    local file="$config_dir/abora-local.nix"
    [[ -f "$file" ]] || return 0
    sed -nE "s|^[[:space:]]*${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\\1|p" "$file" | head -n1
}

detect_desktop_from_local_config() {
    local file="$config_dir/abora-local.nix"
    [[ -f "$file" ]] || return 0

    if grep -q 'services\.desktopManager\.gnome\.enable = true;' "$file"; then
        printf 'gnome\n'
    elif grep -q 'services\.desktopManager\.plasma6\.enable = true;' "$file"; then
        printf 'plasma\n'
    elif grep -q 'programs\.hyprland' "$file"; then
        printf 'hyprland\n'
    elif grep -q 'programs\.sway\.enable = true;' "$file"; then
        printf 'sway\n'
    elif grep -q 'desktopManager\.xfce\.enable = true;' "$file"; then
        printf 'xfce\n'
    elif grep -q 'desktopManager\.cinnamon\.enable = true;' "$file"; then
        printf 'cinnamon\n'
    elif grep -q 'desktopManager\.mate\.enable = true;' "$file"; then
        printf 'mate\n'
    elif grep -q 'desktopManager\.budgie\.enable = true;' "$file"; then
        printf 'budgie\n'
    elif grep -q 'desktopManager\.lxqt\.enable = true;' "$file"; then
        printf 'lxqt\n'
    elif grep -q 'desktopManager\.pantheon\.enable = true;' "$file"; then
        printf 'pantheon\n'
    elif grep -q 'desktopManager\.cosmic\.enable = true;' "$file"; then
        printf 'cosmic\n'
    elif grep -q 'desktopManager\.enlightenment\.enable = true;' "$file"; then
        printf 'enlightenment\n'
    elif grep -q 'windowManager\.i3\.enable = true;' "$file"; then
        printf 'i3\n'
    elif grep -q 'windowManager\.awesome\.enable = true;' "$file"; then
        printf 'awesome\n'
    elif grep -q 'windowManager\.openbox\.enable = true;' "$file"; then
        printf 'openbox\n'
    elif grep -q 'programs\.niri\.enable = true;' "$file"; then
        printf 'niri\n'
    elif grep -q 'programs\.river\.enable = true;' "$file"; then
        printf 'river\n'
    elif grep -q 'windowManager\.qtile\.enable = true;' "$file"; then
        printf 'qtile\n'
    elif grep -q 'windowManager\.bspwm\.enable = true;' "$file"; then
        printf 'bspwm\n'
    elif grep -q 'windowManager\.fluxbox\.enable = true;' "$file"; then
        printf 'fluxbox\n'
    elif grep -q 'windowManager\.icewm\.enable = true;' "$file"; then
        printf 'icewm\n'
    elif grep -q 'windowManager\.herbstluftwm\.enable = true;' "$file"; then
        printf 'herbstluftwm\n'
    fi
}

check_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        warn "flatpak command is not installed"
        return
    fi

    if flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -Fxq flathub; then
        ok "Flathub system remote is configured"
    else
        warn "Flathub system remote is not configured yet"
    fi
}

check_channel() {
    local channel_file="$config_dir/abora/channel"
    local channel="stable"
    [[ -f "$channel_file" ]] && channel="$(tr -d '[:space:]' < "$channel_file")"
    case "$channel" in
        stable|unstable) ok "update channel: $channel" ;;
        *) warn "unknown update channel: $channel" ;;
    esac
}

check_desktop() {
    local desktop=""
    desktop="$(read_abora_option "desktop")"
    [[ -n "$desktop" ]] || desktop="$(read_local_assignment "system.nixos.variant_id")"
    [[ -n "$desktop" ]] || desktop="$(detect_desktop_from_local_config)"
    if [[ -z "$desktop" ]]; then
        warn "desktop setting was not found in abora-local.nix"
        return
    fi

    if [[ -f "$abora_dir/desktop-profiles.sh" ]] \
        && bash -c "source '$abora_dir/desktop-profiles.sh'; abora_supported_desktop_profiles" | grep -Fxq "$desktop"; then
        ok "desktop profile is valid: $desktop"
    else
        warn "desktop profile may be invalid: $desktop"
    fi
}

check_anix() {
    if command -v anix >/dev/null 2>&1; then
        ok "ANIX command is installed"
        if anix doctor >/tmp/abora-anix-doctor.log 2>&1; then
            ok "ANIX doctor completed"
        else
            warn "ANIX doctor reported issues; see /tmp/abora-anix-doctor.log"
        fi
    else
        warn "ANIX command is not installed"
    fi
}

main() {
    abora_banner "Abora Doctor" "Checking installed-system health."

    check_file "$config_dir/flake.nix" "flake.nix exists"
    check_file "$config_dir/abora-local.nix" "abora-local.nix exists"
    check_file "$abora_dir/update.sh" "Abora update tool exists"
    check_file "$abora_dir/theme-sync.sh" "Abora theme sync exists"
    check_file "$abora_dir/support-report.sh" "Abora support report exists"
    check_file "$abora_dir/anix.sh" "ANIX script exists"
    check_file "$abora_dir/bootloader/theme.txt" "bootloader theme exists"
    check_file "$abora_dir/plymouth/abora.plymouth" "Plymouth theme exists"

    check_flatpak
    check_channel
    check_desktop
    check_anix

    printf '\n'
    if [[ "$failures" -gt 0 ]]; then
        abora_error "Abora doctor found ${failures} problem(s) and ${warnings} warning(s)."
        exit 1
    fi
    if [[ "$warnings" -gt 0 ]]; then
        abora_warn "Abora doctor found ${warnings} warning(s)."
    else
        abora_success "Abora doctor found no problems."
    fi
    printf '\n'
}

main "$@"
