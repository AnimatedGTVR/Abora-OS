#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

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
    abora_step()       { printf '  \033[38;5;44m▸\033[0m  %s\n' "$1"; }
    abora_dim_line()   { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
    abora_kv()         { printf '  %b%-18s%b  %b%s%b\n' "$ABORA_DIM" "$1" "$ABORA_NC" "$ABORA_CYAN" "${2:-}" "$ABORA_NC"; }
    abora_kv_faint()   { printf '  %b%-18s%b  %b%s%b\n' "$ABORA_DIM" "$1" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_card_start() { printf '  %b┌─ %s ─%b\n' "$ABORA_BLUE" "${1:-}" "$ABORA_NC"; }
    abora_card_end()   { printf '  %b└────────%b\n' "$ABORA_BLUE" "$ABORA_NC"; }
fi

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
local_module="${config_dir}/abora-local.nix"
wallpaper_dir="${ABORA_WALLPAPER_DIR:-/etc/abora/wallpapers}"

# ── Helpers ───────────────────────────────────────────────────────────────────

run_as_root() {
    if [[ "${ABORA_NO_SUDO:-0}" == "1" ]]; then
        "$@"; return
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"; return
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"; return
    fi
    abora_error "This command needs root privileges."
    exit 1
}

stage_config_for_flake() {
    if command -v git >/dev/null 2>&1 \
        && [[ -d "$config_dir" ]] \
        && run_as_root git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        run_as_root git -C "$config_dir" add -A >/dev/null 2>&1 || true
    fi
}

is_options_format() {
    [[ -f "$local_module" ]] && grep -q 'abora\.user\.name' "$local_module" 2>/dev/null
}

read_legacy_string() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    sed -nE "s|^[[:space:]]*${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*|\\1|p" \
        "$local_module" | head -n1
}

detect_legacy_desktop() {
    if grep -q 'services\.desktopManager\.gnome\.enable[[:space:]]*=[[:space:]]*true' "$local_module"; then
        printf 'gnome\n'
    elif grep -q 'services\.desktopManager\.plasma6\.enable[[:space:]]*=[[:space:]]*true' "$local_module"; then
        printf 'plasma\n'
    elif grep -q 'services\.desktopManager\.cosmic\.enable[[:space:]]*=[[:space:]]*true' "$local_module"; then
        printf 'cosmic\n'
    elif grep -q 'programs\.hyprland\.enable[[:space:]]*=[[:space:]]*true' "$local_module"; then
        printf 'hyprland\n'
    else
        read_legacy_string "system.nixos.variant_id"
    fi
}

detect_legacy_gpu() {
    if grep -q 'services\.xserver\.videoDrivers[[:space:]]*=[^;]*"nvidia"' "$local_module"; then
        if grep -q 'open[[:space:]]*=[[:space:]]*true' "$local_module"; then
            printf 'nvidia-open\n'
        else
            printf 'nvidia\n'
        fi
    elif grep -q 'services\.xserver\.videoDrivers[[:space:]]*=[^;]*"nouveau"' "$local_module"; then
        printf 'nouveau\n'
    elif grep -q 'services\.xserver\.videoDrivers[[:space:]]*=[^;]*"amdgpu"' "$local_module"; then
        printf 'amdgpu\n'
    elif grep -q 'services\.xserver\.videoDrivers[[:space:]]*=[^;]*"modesetting"' "$local_module"; then
        printf 'intel\n'
    else
        printf 'none\n'
    fi
}

# One-time upgrade path: older installs wrote abora-local.nix as raw NixOS
# options (networking.hostName, services.desktopManager.gnome.enable, ...)
# instead of the abora.* options module used since. is_options_format()
# detects which form is on disk (presence of abora.user.name), and this
# reads the old raw values back out via grep/sed (detect_legacy_desktop/
# detect_legacy_gpu reverse-engineer desktop/GPU the same way
# abora_detect_desktop_profile does), then rewrites abora-local.nix in the
# new form -- backing up the original alongside it first.
migrate_legacy_config() {
    require_local_module
    is_options_format && return 0

    if [[ "$(id -u)" -ne 0 && "${ABORA_NO_SUDO:-0}" != "1" ]]; then
        run_as_root env ABORA_SYSTEM_CONFIG="$config_dir" ABORA_UI_LIB="$ui_lib" "$0" migrate
        return 0
    fi

    local hostname timezone locale kb_console kb_xkb user_name user_hash desktop disk gpu state_ver wallpaper tmp backup
    hostname="$(read_legacy_string "networking.hostName")"
    timezone="$(read_legacy_string "time.timeZone")"
    locale="$(read_legacy_string "i18n.defaultLocale")"
    kb_console="$(read_legacy_string "console.keyMap")"
    kb_xkb="$(read_legacy_string "services.xserver.xkb.layout")"
    user_name="$(sed -nE 's|^[[:space:]]*users\.users\."?([^".{[:space:]]+)"?[[:space:]]*=[[:space:]]*\{.*|\1|p' "$local_module" | head -n1)"
    user_hash="$(sed -nE 's|^[[:space:]]*hashedPassword[[:space:]]*=[[:space:]]*"([^"]*)".*|\1|p' "$local_module" | head -n1)"
    desktop="$(detect_legacy_desktop)"
    disk="$(read_legacy_string "boot.loader.limine.biosDevice")"
    gpu="$(detect_legacy_gpu)"
    state_ver="$(read_legacy_string "system.stateVersion")"
    wallpaper="titlis-alps.jpg"

    hostname="${hostname:-abora}"
    timezone="${timezone:-UTC}"
    locale="${locale:-en_US.UTF-8}"
    kb_console="${kb_console:-us}"
    kb_xkb="${kb_xkb:-$kb_console}"
    user_name="${user_name:-abora}"
    desktop="${desktop:-cosmic}"
    disk="${disk:-}"
    gpu="${gpu:-none}"
    state_ver="${state_ver:-26.05}"

    backup="${local_module}.legacy.$(date +%Y%m%d%H%M%S)"
    tmp="$(mktemp "${local_module}.tmp.XXXXXX")"
    cp "$local_module" "$backup"
    cat >"$tmp" <<EOF
{ config, ... }:
{
  abora.hostname = "${hostname}";
  abora.locale = "${locale}";
  abora.timezone = "${timezone}";
  abora.keyboard.console = "${kb_console}";
  abora.keyboard.xkb = "${kb_xkb}";
  abora.desktop = "${desktop}";
  abora.wallpaper = "${wallpaper}";
  abora.gpu = "${gpu}";
  abora.stateVersion = "${state_ver}";
  abora.gaming.enable = false;
  abora.gaming.bigPictureShortcut = true;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = true;
  abora.gaming.vulkanTools = true;
  abora.extras.diagnostics = false;
  abora.extras.virtualizationGuests = false;
  abora.extras.mobileBroadband = false;
  abora.user.name = "${user_name}";
  abora.user.hashedPassword = "${user_hash}";
EOF
    if [[ -n "$disk" ]]; then
        printf '  abora.disk = "%s";\n' "$disk" >>"$tmp"
    else
        printf '  abora.disk = null;\n' >>"$tmp"
    fi
    cat >>"$tmp" <<'EOF'

  networking.networkmanager.enable = true;
  i18n.supportedLocales = [
    "${config.abora.locale}/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  users.users.root.hashedPassword = "!";
}
EOF
    mv "$tmp" "$local_module"
    chmod 0644 "$local_module"
    abora_warn "Migrated abora-local.nix to the current format."
    abora_dim_line "Backup saved at ${backup}"
}

require_options_format() {
    if ! is_options_format; then
        migrate_legacy_config
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

read_bool_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    sed -nE "s#^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*(true|false).*#\\1#p" \
        "$local_module" | head -n1
}

normalize_bool() {
    case "${1,,}" in
        true|yes|y|on|1|enable|enabled) printf 'true' ;;
        false|no|n|off|0|disable|disabled) printf 'false' ;;
        *)
            abora_error "Invalid boolean '${1}' — use true/false, yes/no, on/off, or 1/0."
            exit 1
            ;;
    esac
}

write_bool_option() {
    local key="$1" value="$2" escaped_key tmp
    local escaped_key="${key//./\\.}"
    if grep -Eq "^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=" "$local_module"; then
        run_as_root sed -i -E \
            "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=.*|  abora.${key} = ${value};|" \
            "$local_module"
        return 0
    fi

    tmp="$(mktemp)"
    awk -v line="  abora.${key} = ${value};" '
        /^[[:space:]]*}[[:space:]]*$/ && !done { print line; done=1 }
        { print }
        END { if (!done) print line }
    ' "$local_module" > "$tmp"
    run_as_root cp "$tmp" "$local_module"
    rm -f "$tmp"
}

# ── Display ───────────────────────────────────────────────────────────────────

show_config() {
    require_local_module

    local hostname timezone kb_console kb_xkb user_name desktop wallpaper disk gpu state_ver gaming gaming_big_picture gaming_autostart gaming_gamescope gaming_vulkan extras_diagnostics extras_vm extras_mobile
    hostname="$(read_option "hostname")"
    timezone="$(read_option "timezone")"
    kb_console="$(read_option "keyboard.console")"
    kb_xkb="$(read_option "keyboard.xkb")"
    user_name="$(read_option "user.name")"
    desktop="$(read_option "desktop")"
    wallpaper="$(read_option "wallpaper")"
    disk="$(read_option "disk")"
    gpu="$(read_option "gpu")"
    state_ver="$(read_option "stateVersion")"
    gaming="$(read_bool_option "gaming.enable")"
    gaming_big_picture="$(read_bool_option "gaming.bigPictureShortcut")"
    gaming_autostart="$(read_bool_option "gaming.bigPictureAutostart")"
    gaming_gamescope="$(read_bool_option "gaming.gamescopeSession")"
    gaming_vulkan="$(read_bool_option "gaming.vulkanTools")"
    extras_diagnostics="$(read_bool_option "extras.diagnostics")"
    extras_vm="$(read_bool_option "extras.virtualizationGuests")"
    extras_mobile="$(read_bool_option "extras.mobileBroadband")"

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
    abora_kv "gpu"           "${gpu:-—}"
    abora_kv "gaming"        "${gaming:-false}"
    abora_kv "big picture"   "${gaming_big_picture:-true}"
    abora_kv "gamescope"     "${gaming_gamescope:-true}"
    abora_kv "vulkan tools"  "${gaming_vulkan:-true}"
    abora_kv "gaming autostart" "${gaming_autostart:-false}"
    abora_kv "diagnostics extras" "${extras_diagnostics:-false}"
    abora_kv "VM guest extras" "${extras_vm:-false}"
    abora_kv "mobile broadband" "${extras_mobile:-false}"
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
    i3 awesome openbox niri river qtile bspwm fluxbox
    icewm herbstluftwm cosmic mangowm
)

wallpaper_candidates() {
    if [[ -d "$wallpaper_dir" ]]; then
        find "$wallpaper_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
        return 0
    fi

    printf '%s\n' \
        alpine-glacier.jpg \
        tannheimer-mountains.jpg \
        titlis-alps.jpg \
        aurora-lofoten.jpg
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

valid_gpus=(nouveau nvidia nvidia-open amdgpu intel none)

# Detect the primary GPU vendor via lspci and resolve it to a concrete
# abora.gpu value. Never resolves to the proprietary "nvidia" driver on its
# own — NVIDIA hardware resolves to "nouveau" (open-source, no license to
# accept) unless the caller explicitly asks for "nvidia" or "nvidia-open".
detect_gpu() {
    local gpu_line=""
    if command -v lspci >/dev/null 2>&1; then
        gpu_line="$(lspci 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' | head -n1)"
    fi

    case "$gpu_line" in
        *NVIDIA*|*nvidia*) printf 'nouveau\n' ;;
        *AMD*|*ATI*|*amd*) printf 'amdgpu\n' ;;
        *Intel*|*intel*)   printf 'intel\n' ;;
        *)                 printf 'none\n' ;;
    esac
}

validate_gpu() {
    local candidate="$1"
    for valid in "${valid_gpus[@]}"; do
        [[ "$candidate" == "$valid" ]] && return 0
    done
    abora_error "Unknown gpu: '${candidate}'"
    printf '  %bValid options:%b %s auto\n\n' "$ABORA_DIM" "$ABORA_NC" "${valid_gpus[*]}"
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

safe_timezone() {
    [[ "$1" =~ ^[A-Za-z0-9_+./-]+$ && "$1" != *..* && "$1" != /* ]]
}

safe_xkb_code() {
    [[ "$1" =~ ^[a-z]{2,3}(,[a-z]{2,3})*$ ]]
}

do_set() {
    local key="$1" value="$2"

    require_local_module
    require_options_format

    # Belt-and-suspenders: no settable value may contain characters that could
    # break out of the Nix double-quoted string it gets written into ('"' ends
    # the string; '\' starts an escape; '${' begins Nix antiquotation), no
    # matter which key-specific check below runs.
    if [[ "$value" == *'"'* || "$value" == *'\'* || "$value" == *'${'* ]]; then
        abora_error "Invalid value '${value}' — it cannot contain '\"', '\\', or '\${'."
        exit 1
    fi

    # Validate and normalise the key.
    case "$key" in
        hostname)
            if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
                abora_error "Invalid hostname '${value}' — use letters, numbers, and hyphens only."
                exit 1
            fi
            ;;
        timezone)
            if ! safe_timezone "$value"; then
                abora_error "Invalid timezone '${value}' — expected a zoneinfo-style name (e.g. 'America/New_York')."
                exit 1
            fi
            ;;
        keyboard | keyboard.console)
            key="keyboard.console"
            ;;
        keyboard.xkb)
            if ! safe_xkb_code "$value"; then
                abora_error "Invalid keyboard layout '${value}' — expected a layout code (e.g. 'us' or 'us,de')."
                exit 1
            fi
            ;;
        desktop)
            validate_desktop "$value"
            ;;
        wallpaper)
            validate_wallpaper "$value"
            ;;
        gpu)
            if [[ "$value" == "auto" ]]; then
                value="$(detect_gpu)"
                abora_dim_line "Detected GPU vendor → resolved to '${value}'."
            fi
            validate_gpu "$value"
            ;;
        gaming | gaming.enable)
            key="gaming.enable"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        gaming.big-picture | gaming.bigPictureShortcut)
            key="gaming.bigPictureShortcut"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        gaming.autostart | gaming.bigPictureAutostart)
            key="gaming.bigPictureAutostart"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        gaming.gamescope | gaming.gamescopeSession)
            key="gaming.gamescopeSession"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        gaming.vulkan | gaming.vulkanTools)
            key="gaming.vulkanTools"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        extras.diagnostics | diagnostics)
            key="extras.diagnostics"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        extras.virtualizationGuests | virtualization-guests | vm-guests)
            key="extras.virtualizationGuests"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        extras.mobileBroadband | mobile-broadband | modemmanager)
            key="extras.mobileBroadband"
            value="$(normalize_bool "$value")"
            write_bool_option "$key" "$value"
            abora_success "'abora.${key}' set to '${value}'"
            abora_dim_line "Run 'abora config apply' to rebuild the system."
            printf '\n'
            return 0
            ;;
        *)
            abora_error "Unknown key: '${key}'"
            printf '  %bSettable keys:%b  hostname  timezone  keyboard  keyboard.xkb  desktop  wallpaper  gpu  gaming  gaming.big-picture  gaming.autostart  gaming.gamescope  gaming.vulkan  diagnostics  vm-guests  mobile-broadband\n\n' \
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
    require_options_format

    abora_banner "Apply Configuration" "Rebuilding Abora from ${local_module}"
    abora_step "Running nixos-rebuild switch"
    printf '\n'

    stage_config_for_flake
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
    printf '  %babora config set gpu        <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %babora config set gaming     <true|false>%b\n' "$ABORA_CYAN" "$ABORA_NC"
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
    abora_dim_line "  gpu            GPU driver: nouveau, nvidia, nvidia-open, amdgpu, intel, none, or auto"
    abora_dim_line "  gaming         Enable Steam, 32-bit graphics, GameMode, and gaming helpers"
    abora_dim_line "  gaming.big-picture  Add the Steam Big Picture launcher"
    abora_dim_line "  gaming.autostart    Start Steam Big Picture on desktop login"
    abora_dim_line "  gaming.gamescope    Add the Big Picture Gamescope session"
    abora_dim_line "  gaming.vulkan       Add Vulkan diagnostic tools"
    abora_dim_line "  diagnostics         Add dmidecode, ethtool, htop, and smartmontools"
    abora_dim_line "  vm-guests           Enable VM guest agents for QEMU/SPICE/VMware/VirtualBox/Hyper-V"
    abora_dim_line "  mobile-broadband    Enable ModemManager for cellular devices"
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
        migrate)
            migrate_legacy_config
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
