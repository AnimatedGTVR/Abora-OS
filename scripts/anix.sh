#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

if [[ -f "$ui_lib" ]]; then
    # shellcheck source=/dev/null
    source "$ui_lib"
else
    # Minimal fallback UI — used when running outside Abora OS
    ABORA_DIM=$'\033[38;5;242m'
    ABORA_NC=$'\033[0m'
    ABORA_CYAN=$'\033[38;5;44m'
    ABORA_WHITE=$'\033[1;97m'
    ABORA_GREEN=$'\033[38;5;77m'
    ABORA_RED=$'\033[38;5;203m'
    ABORA_YELLOW=$'\033[38;5;222m'
    ABORA_BLUE=$'\033[38;5;39m'
    abora_banner()   { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_success()  { printf '  \033[38;5;77m✓\033[0m  \033[38;5;77m%s\033[0m\n' "$1"; }
    abora_warn()     { printf '  \033[38;5;222m!\033[0m  \033[38;5;222m%s\033[0m\n' "$1"; }
    abora_error()    { printf '  \033[38;5;203m✗\033[0m  \033[38;5;203m%s\033[0m\n' "$1" >&2; }
    abora_step()     { printf '  \033[38;5;44m▸\033[0m  %s\n' "$1"; }
    abora_dim_line() { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
    abora_card_start() {
        printf '  %b┌─ %s ─%b\n' "$ABORA_BLUE" "${1:-}" "$ABORA_NC"
    }
    abora_card_end() {
        printf '  %b└────────%b\n' "$ABORA_BLUE" "$ABORA_NC"
    }
    abora_kv() {
        printf '  %b│%b  %b%-18s%b  %b%s%b\n' \
            "$ABORA_BLUE" "$ABORA_NC" \
            "$ABORA_DIM" "$1" "$ABORA_NC" \
            "$ABORA_CYAN" "${2:-}" "$ABORA_NC"
    }
fi

config_dir="${ANIX_SYSTEM_CONFIG:-/etc/nixos}"
anix_file="${ANIX_CONFIG_FILE:-$config_dir/anix.nix}"
abora_local_file="${config_dir}/abora-local.nix"
flake_config_name="${ANIX_FLAKE_CONFIG_NAME:-abora}"
wallpaper_dir="${ANIX_WALLPAPER_DIR:-/etc/abora/wallpapers}"
anix_state_dir="${ANIX_STATE_DIR:-$config_dir/.anix}"
anix_tool_config="${ANIX_TOOL_CONFIG:-$anix_state_dir/config}"

valid_desktops=(
    none gnome plasma hyprland sway xfce cinnamon mate budgie lxqt pantheon
    enlightenment i3 awesome openbox niri river qtile bspwm fluxbox
    icewm herbstluftwm dwm
)

default_wallpapers=(
    oceandusk.png
    bluehorizon.png
    astronautwallpaper.png
    glacierreflection.png
)

run_as_root() {
    if is_yes "${ANIX_NO_SUDO:-}"; then
        "$@"
        return
    fi
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

wallpaper_candidates() {
    if [[ -d "$wallpaper_dir" ]]; then
        find "$wallpaper_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
        return 0
    fi

    printf '%s\n' "${default_wallpapers[@]}"
}

validate_wallpaper() {
    local candidate="$1"
    if wallpaper_candidates | grep -Fxq "$candidate"; then
        return 0
    fi

    abora_error "Unknown wallpaper: ${candidate}"
    printf '  %bAvailable wallpapers:%b\n' "$ABORA_DIM" "$ABORA_NC"
    wallpaper_candidates | sed 's/^/    /'
    printf '\n'
    exit 1
}

is_yes() {
    case "${1:-}" in
        1|yes|true|on|y|Y|YES|TRUE|ON) return 0 ;;
        *) return 1 ;;
    esac
}

confirm() {
    local prompt="$1"
    local default="${2:-yes}"
    local answer=""

    if is_yes "${ANIX_ASSUME_YES:-}"; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        [[ "$default" == "yes" ]]
        return
    fi

    if [[ "$default" == "yes" ]]; then
        printf '  %b%s [Y/n]%b ' "$ABORA_YELLOW" "$prompt" "$ABORA_NC"
    else
        printf '  %b%s [y/N]%b ' "$ABORA_YELLOW" "$prompt" "$ABORA_NC"
    fi

    read -r answer
    case "$answer" in
        "") [[ "$default" == "yes" ]] ;;
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

require_command() {
    local command="$1"
    if command -v "$command" >/dev/null 2>&1; then
        return 0
    fi
    abora_error "Missing required command: ${command}"
    exit 1
}

validate_profile_name() {
    local profile="$1"
    if [[ "$profile" =~ ^[A-Za-z0-9._-]+$ ]]; then
        return 0
    fi
    abora_error "Invalid profile name: ${profile}"
    abora_dim_line "Use a flake config name like nix, minimal, stable, creator, or gaming."
    printf '\n'
    exit 1
}

profile_target() {
    local family="$1"
    local profile="${2:-}"

    case "$family" in
        nix) ;;
        *)
            abora_error "Unknown profile family: ${family}"
            abora_dim_line "Use: anix switch nix <profile>"
            printf '\n'
            exit 1
            ;;
    esac

    if [[ -z "$profile" ]]; then
        profile="$flake_config_name"
    fi

    validate_profile_name "$profile"
    printf '%s#%s' "$config_dir" "$profile"
}

anix_config_get() {
    local key="$1"
    local fallback="${2:-}"
    [[ -f "$anix_tool_config" ]] || {
        printf '%s' "$fallback"
        return 0
    }
    sed -nE "s|^[[:space:]]*${key//./\\.}[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$|\\1|p" "$anix_tool_config" | head -n1
}

anix_config_set() {
    local key="$1"
    local value="$2"
    run_as_root mkdir -p "$anix_state_dir"
    if [[ -f "$anix_tool_config" ]] && grep -Eq "^[[:space:]]*${key//./\\.}[[:space:]]*=" "$anix_tool_config"; then
        run_as_root sed -i -E "s|^([[:space:]]*${key//./\\.}[[:space:]]*=[[:space:]]*).*$|\\1${value}|" "$anix_tool_config"
    else
        run_as_root bash -c "$(printf 'printf '"'"'%%s\\n'"'"' %q >> %q' "${key}=${value}" "$anix_tool_config")"
    fi
}

git_available_for_config() {
    command -v git >/dev/null 2>&1 && [[ -d "$config_dir" ]]
}

config_is_git_repo() {
    git_available_for_config && git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

config_is_dirty() {
    config_is_git_repo || return 1
    [[ -n "$(git -C "$config_dir" status --porcelain 2>/dev/null)" ]]
}

warn_possible_secrets() {
    [[ -d "$config_dir" ]] || return 0

    local matches=""
    matches="$(
        grep -RInE \
            --exclude-dir=.git \
            --exclude-dir=.anix \
            --exclude='*.lock' \
            '(api[_-]?key|token|secret|password|passwd)[[:space:]]*[:=]' \
            "$config_dir" 2>/dev/null | head -n 8 || true
    )"

    [[ -n "$matches" ]] || return 0

    abora_warn "Possible secret found in your Nix config."
    abora_dim_line "Move real secrets to sops-nix or agenix before saving snapshots."
    printf '%s\n' "$matches" | sed 's/^/    /'
    printf '\n'

    confirm "Continue with the local snapshot anyway?" "no"
}

ensure_config_git_repo() {
    require_command git
    [[ -d "$config_dir" ]] || run_as_root mkdir -p "$config_dir"
    if config_is_git_repo; then
        return 0
    fi
    abora_warn "${config_dir} is not a Git repo yet."
    if confirm "Initialize a local Git repo for ANIX snapshots?" "yes"; then
        run_as_root git -C "$config_dir" init >/dev/null
    else
        abora_error "Snapshot cancelled."
        exit 1
    fi
}

do_save() {
    local message="${1:-anix: local config snapshot}"
    ensure_config_git_repo

    if ! warn_possible_secrets; then
        abora_error "Snapshot cancelled."
        exit 1
    fi

    run_as_root git -C "$config_dir" add -A
    if run_as_root git -C "$config_dir" diff --cached --quiet; then
        abora_warn "No config changes to snapshot."
        printf '\n'
        return 0
    fi

    run_as_root git -C "$config_dir" \
        -c user.name="${ANIX_GIT_USER_NAME:-ANIX}" \
        -c user.email="${ANIX_GIT_USER_EMAIL:-anix@localhost}" \
        commit -m "$message" >/dev/null

    abora_success "Saved local snapshot: ${message}"

    if is_yes "$(anix_config_get "snapshots.push" "false")"; then
        abora_step "Pushing snapshot because snapshots.push is true"
        run_as_root git -C "$config_dir" push
    else
        abora_dim_line "Snapshot stayed local. Enable pushing with: anix config set snapshots.push true"
    fi
    printf '\n'
}

maybe_snapshot_dirty_config() {
    local message="$1"

    if ! config_is_git_repo; then
        [[ -d "$config_dir" ]] || return 0
        abora_warn "No local snapshot history exists for ${config_dir}."
        if confirm "Create a snapshot before switching?" "yes"; then
            do_save "$message"
        else
            abora_warn "Continuing without a snapshot."
            printf '\n'
        fi
        return 0
    fi

    if ! config_is_dirty; then
        return 0
    fi

    abora_warn "You have unsaved local changes."
    if confirm "Save snapshot before switching?" "yes"; then
        do_save "$message"
    else
        abora_warn "Continuing without a snapshot."
        printf '\n'
    fi
}

run_rebuild() {
    local action="$1"
    local target="${2:-}"

    case "$action" in
        dry-build)
            run_as_root nixos-rebuild dry-build --flake "$target"
            ;;
        switch)
            run_as_root nixos-rebuild switch --flake "$target"
            ;;
        build)
            run_as_root nixos-rebuild build --flake "$target"
            ;;
        rollback)
            run_as_root nixos-rebuild switch --rollback
            ;;
        *)
            abora_error "Unknown rebuild action: ${action}"
            exit 1
            ;;
    esac
}

show_package_changes() {
    local target="$1"
    local tmp_dir=""

    if ! command -v nix >/dev/null 2>&1; then
        abora_warn "Cannot show package changes because nix is unavailable."
        return 0
    fi

    if [[ ! -e /run/current-system ]]; then
        abora_warn "Cannot compare package changes because /run/current-system is missing."
        return 0
    fi

    tmp_dir="$(mktemp -d)"
    abora_step "Building ${target} for package comparison"

    if (
        cd "$tmp_dir"
        run_rebuild build "$target" >/dev/null
    ); then
        if [[ -e "$tmp_dir/result" ]]; then
            abora_step "Package changes"
            nix store diff-closures /run/current-system "$tmp_dir/result" || true
        else
            abora_warn "Build finished, but no result link was created."
        fi
    else
        abora_warn "Package comparison build failed; dry-build output is still shown above."
    fi

    run_as_root rm -rf "$tmp_dir"
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
    local hostname timezone keyboard_console keyboard_xkb desktop wallpaper

    hostname="$(seed_value "hostname" "abora")"
    timezone="$(seed_value "timezone" "UTC")"
    keyboard_console="$(seed_value "keyboard.console" "us")"
    keyboard_xkb="$(seed_value "keyboard.xkb" "$keyboard_console")"
    desktop="$(seed_value "desktop" "gnome")"
    wallpaper="$(seed_value "wallpaper" "oceandusk.png")"

    cat <<EOF
# ANIX is the simple layer on top of Abora/NixOS.
# Change the values below, save the file, then run: anix apply
{ ... }:
{
  anix.enable = true;

  # Your system name on the network.
  anix.hostname = "${hostname}";

  # Timezone example: America/New_York
  anix.timezone = "${timezone}";

  # Keyboard layouts for console and desktop sessions.
  anix.keyboard.console = "${keyboard_console}";
  anix.keyboard.xkb = "${keyboard_xkb}";

  # Pick one desktop or use "none" for a console-only system.
  anix.desktop = "${desktop}";

  # Wallpaper filename (Abora OS only).
  anix.wallpaper = "${wallpaper}";
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

    local hostname timezone kb_console kb_xkb desktop wallpaper
    hostname="$(read_anix_option "hostname")"
    timezone="$(read_anix_option "timezone")"
    kb_console="$(read_anix_option "keyboard.console")"
    kb_xkb="$(read_anix_option "keyboard.xkb")"
    desktop="$(read_anix_option "desktop")"
    wallpaper="$(read_anix_option "wallpaper")"

    abora_banner "ANIX" "${anix_file}"

    abora_card_start "Current Settings"

    abora_kv "hostname"    "${hostname:-—}"
    abora_kv "timezone"    "${timezone:-—}"
    printf '  %b│%b  %b%-18s%b  %b%s%b / %b%s%b\n' \
        "$ABORA_BLUE" "$ABORA_NC" \
        "$ABORA_DIM" "keyboard" "$ABORA_NC" \
        "$ABORA_CYAN" "${kb_console:-—}" "$ABORA_NC" \
        "$ABORA_DIM" "${kb_xkb:-—}" "$ABORA_NC"
    abora_kv "desktop"     "${desktop:-—}"
    abora_kv "wallpaper"   "${wallpaper:-—}"

    abora_card_end

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
        wallpaper)
            validate_wallpaper "$value"
            ;;
        *)
            abora_error "Unknown key: ${key}"
            printf '  %bSettable keys:%b hostname timezone keyboard keyboard.xkb desktop wallpaper\n\n' "$ABORA_DIM" "$ABORA_NC"
            exit 1
            ;;
    esac

    escaped_key="${key//./\\.}"
    if grep -Eq "^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=" "$anix_file"; then
        run_as_root sed -i -E \
            "s|^([[:space:]]*anix\\.${escaped_key}[[:space:]]*=[[:space:]]*)\"[^\"]*\";|\\1\"${value}\";|" \
            "$anix_file"
    else
        run_as_root sed -i -E \
            "/^[[:space:]]*}$/i\\  anix.${key} = \"${value}\";" \
            "$anix_file"
    fi

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

do_switch() {
    local family="${1:-}"
    local profile="${2:-}"
    local now="false"
    local target=""

    shift 2 2>/dev/null || true
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --now) now="true" ;;
            *)
                abora_error "Unknown switch option: $1"
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "$family" || -z "$profile" ]]; then
        abora_error "Usage: anix switch nix <profile> [--now]"
        printf '\n'
        exit 1
    fi

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Switch" "${family}/${profile}"

    maybe_snapshot_dirty_config "anix: snapshot before switching to ${profile}"

    if [[ "$now" != "true" ]]; then
        abora_step "Checking ${target}"
        run_rebuild dry-build "$target"
        printf '\n'
        if ! confirm "Switch to ${profile} now?" "yes"; then
            abora_warn "Switch cancelled."
            printf '\n'
            return 0
        fi
    fi

    abora_step "Switching to ${target}"
    run_rebuild switch "$target"
    printf '\n'
    abora_success "Now running profile: ${profile}"
    printf '\n'
}

do_rollback() {
    local family="${1:-nix}"
    local profile=""
    local now="false"
    local target=""

    if [[ "$family" == "--now" ]]; then
        family="nix"
        now="true"
        shift
    else
        shift 1 2>/dev/null || true
    fi

    if [[ "${1:-}" != --* ]]; then
        profile="${1:-}"
    fi

    if [[ -n "$profile" ]]; then
        shift 1 2>/dev/null || true
    fi

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --now) now="true" ;;
            *)
                abora_error "Unknown rollback option: $1"
                exit 1
                ;;
        esac
        shift
    done

    if [[ "$family" != "nix" ]]; then
        abora_error "Unknown rollback family: ${family}"
        abora_dim_line "Use: anix rollback nix [profile] [--now]"
        printf '\n'
        exit 1
    fi

    if [[ -z "$profile" ]]; then
        abora_banner "ANIX Rollback" "Using the previous NixOS generation"
        if [[ "$now" != "true" ]] && ! confirm "Rollback to the previous generation?" "yes"; then
            abora_warn "Rollback cancelled."
            printf '\n'
            return 0
        fi
        run_rebuild rollback
        printf '\n'
        abora_success "Rollback complete."
        printf '\n'
        return 0
    fi

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Rollback" "${family}/${profile}"
    maybe_snapshot_dirty_config "anix: snapshot before rollback to ${profile}"

    if [[ "$now" != "true" ]]; then
        abora_step "Dry-building ${target}"
        run_rebuild dry-build "$target"
        printf '\n'
        show_package_changes "$target"
        printf '\n'
        abora_dim_line "Review the package and activation changes above."
        if ! confirm "Rollback/switch to ${profile} now?" "yes"; then
            abora_warn "Rollback cancelled."
            printf '\n'
            return 0
        fi
    fi

    abora_step "Rebuilding ${target}"
    run_rebuild switch "$target"
    printf '\n'
    abora_success "Profile rollback complete: ${profile}"
    printf '\n'
}

do_tool_config() {
    local command="${1:-show}"
    local key="${2:-}"
    local value="${3:-}"

    case "$command" in
        show|"")
            abora_banner "ANIX Config" "${anix_tool_config}"
            abora_card_start "Tool Settings"
            abora_kv "snapshots.push" "$(anix_config_get "snapshots.push" "false")"
            abora_card_end
            printf '\n'
            ;;
        set)
            if [[ -z "$key" || -z "$value" ]]; then
                abora_error "Usage: anix config set <key> <value>"
                exit 1
            fi
            case "$key" in
                snapshots.push)
                    if ! is_yes "$value" && [[ "$value" != "false" && "$value" != "no" && "$value" != "off" && "$value" != "0" ]]; then
                        abora_error "snapshots.push must be true or false."
                        exit 1
                    fi
                    if is_yes "$value"; then
                        value="true"
                    else
                        value="false"
                    fi
                    ;;
                *)
                    abora_error "Unknown ANIX config key: ${key}"
                    abora_dim_line "Known keys: snapshots.push"
                    exit 1
                    ;;
            esac
            anix_config_set "$key" "$value"
            abora_success "'${key}' set to '${value}'"
            printf '\n'
            ;;
        *)
            abora_error "Unknown config command: ${command}"
            exit 1
            ;;
    esac
}

doctor_check() {
    local status="$1"
    local label="$2"
    case "$status" in
        ok) abora_success "$label" ;;
        warn) abora_warn "$label" ;;
        fail) abora_error "$label" ;;
    esac
}

do_doctor() {
    local failures=0
    local warnings=0
    local desktop=""

    abora_banner "ANIX Doctor" "Checking the Nix/Abora management layer."

    if command -v nix >/dev/null 2>&1; then
        doctor_check ok "nix command is available"
    else
        doctor_check fail "nix command is missing"
        failures=$((failures + 1))
    fi

    if command -v nixos-rebuild >/dev/null 2>&1; then
        doctor_check ok "nixos-rebuild is available"
    else
        doctor_check fail "nixos-rebuild is missing"
        failures=$((failures + 1))
    fi

    if [[ -d "$config_dir" ]]; then
        doctor_check ok "config directory exists: ${config_dir}"
    else
        doctor_check fail "config directory is missing: ${config_dir}"
        failures=$((failures + 1))
    fi

    if [[ -f "$config_dir/flake.nix" ]]; then
        doctor_check ok "flake.nix exists"
        if command -v nix >/dev/null 2>&1 \
            && nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file "$config_dir" >/dev/null 2>&1; then
            doctor_check ok "flake outputs evaluate"
        else
            doctor_check fail "flake outputs do not evaluate"
            failures=$((failures + 1))
        fi
    else
        doctor_check warn "no flake.nix found in ${config_dir}"
        warnings=$((warnings + 1))
    fi

    if config_is_git_repo; then
        doctor_check ok "config directory is a Git repo"
        if config_is_dirty; then
            doctor_check warn "config repo has unsaved changes"
            warnings=$((warnings + 1))
        else
            doctor_check ok "config repo is clean"
        fi
    else
        doctor_check warn "config directory is not a Git repo; snapshots will initialize one"
        warnings=$((warnings + 1))
    fi

    if [[ -f "$anix_file" ]]; then
        doctor_check ok "ANIX config exists: ${anix_file}"
        desktop="$(read_anix_option "desktop")"
        if [[ -n "$desktop" ]]; then
            local valid=""
            local known="false"
            for valid in "${valid_desktops[@]}"; do
                [[ "$desktop" == "$valid" ]] && known="true"
            done
            if [[ "$known" == "true" ]]; then
                doctor_check ok "ANIX desktop is valid: ${desktop}"
            else
                doctor_check fail "ANIX desktop is invalid: ${desktop}"
                failures=$((failures + 1))
            fi
        fi
    else
        doctor_check warn "ANIX config does not exist yet; run 'anix init'"
        warnings=$((warnings + 1))
    fi

    if [[ -e /nix/var/nix/profiles/system ]]; then
        doctor_check ok "system generation profile exists"
    else
        doctor_check warn "system generation profile was not found"
        warnings=$((warnings + 1))
    fi

    printf '\n'
    if [[ "$failures" -gt 0 ]]; then
        abora_error "Doctor found ${failures} problem(s) and ${warnings} warning(s)."
        exit 1
    fi
    if [[ "$warnings" -gt 0 ]]; then
        abora_warn "Doctor found ${warnings} warning(s)."
    else
        abora_success "Doctor found no problems."
    fi
    printf '\n'
}

usage() {
    abora_banner "ANIX" "Nix without the homework."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %banix switch nix <profile>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Safely switch to a named flake config."
    printf '\n'
    printf '  %banix rollback nix [profile] [--now]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Roll back to the previous generation or a named profile."
    printf '\n'
    printf '  %banix save%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Save a local Git snapshot of ${config_dir}."
    printf '\n'
    printf '  %banix doctor%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Check flakes, Git state, generations, and ANIX settings."
    printf '\n'
    printf '  %banix init%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create ${anix_file} with sensible defaults."
    printf '\n'
    printf '  %banix show%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the current ANIX settings."
    printf '\n'
    printf '  %banix set hostname <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set timezone <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard.xkb <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set desktop <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set wallpaper <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Update a simple ANIX setting."
    printf '\n'
    printf '  %banix wallpapers%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List the wallpapers you can switch to."
    printf '\n'
    printf '  %banix config set snapshots.push true%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Opt in to pushing snapshots after local commits."
    printf '\n'
    printf '  %banix apply%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Rebuild the system using the ANIX layer."
    printf '\n'
}

show_wallpapers() {
    abora_banner "ANIX Wallpapers" "These names work with 'anix set wallpaper <name>'."

    abora_card_start "Available Wallpapers"

    wallpaper_candidates | while IFS= read -r name; do
        printf '  %b│%b  %b%s%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$name" "$ABORA_NC"
    done

    abora_card_end

    printf '\n'
}

main() {
    local command="${1:-show}"

    case "$command" in
        init) shift; do_init "$@" ;;
        show|"") shift; show_config "$@" ;;
        wallpapers) shift; show_wallpapers "$@" ;;
        set) shift; do_set "$@" ;;
        apply) shift; do_apply "$@" ;;
        switch) shift; do_switch "$@" ;;
        rollback) shift; do_rollback "$@" ;;
        save) shift; do_save "$@" ;;
        config) shift; do_tool_config "$@" ;;
        doctor) shift; do_doctor "$@" ;;
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
