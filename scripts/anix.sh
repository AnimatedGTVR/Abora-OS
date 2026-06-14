#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
anix_version="1.0.5 DEMO"

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
    i3 awesome openbox niri river qtile bspwm fluxbox
    icewm herbstluftwm cosmic mangowm
)

default_wallpapers=(
    Daytime-MNT.jpg
    NightTime-MNT.png
    oceandusk.png
    bluehorizon.png
    astronautwallpaper.png
    glacierreflection.png
)

current_system_link="${ANIX_CURRENT_SYSTEM:-/run/current-system}"
system_profile_link="${ANIX_SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"

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

current_configured_desktop() {
    local value=""
    value="$(read_abora_option "desktop")"
    if [[ -z "$value" ]]; then
        value="$(read_anix_option "desktop")"
    fi
    printf '%s' "${value:-unknown}"
}

write_anix_raw_option() {
    local key="$1"
    local value="$2"
    local escaped_key="${key//./\\.}"

    ensure_anix_file
    if grep -Eq "^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=" "$anix_file"; then
        run_as_root sed -i -E \
            "s|^([[:space:]]*anix\\.${escaped_key}[[:space:]]*=).*$|\\1 ${value};|" \
            "$anix_file"
    else
        run_as_root sed -i -E \
            "/^[[:space:]]*}$/i\\  anix.${key} = ${value};" \
            "$anix_file"
    fi
}

quote_nix_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

explain_nix_failure() {
    local log_file="$1"
    local line=""

    [[ -s "$log_file" ]] || return 0

    printf '\n'
    abora_error "Nix stopped before applying the config."

    if grep -q "The option .* does not exist" "$log_file"; then
        line="$(grep -m1 "The option .* does not exist" "$log_file" || true)"
        abora_warn "Unknown option in your config."
        printf '  %b%s%b\n' "$ABORA_DIM" "$line" "$ABORA_NC"
        if grep -q "The option \`abora'" "$log_file"; then
            abora_dim_line "Use nested options like 'abora.desktop = \"gnome\";', not 'abora = ...'."
        fi
    elif grep -qi "unfree" "$log_file"; then
        abora_warn "This looks like an unfree package block."
        abora_dim_line "ANIX normally sets 'anix.allowUnfree = true;'. Run: anix enable allowUnfree"
        abora_dim_line "Then retry the command. For one TinyPM install: NIXPKGS_ALLOW_UNFREE=1 grab --nix discord"
    elif grep -q "syntax error" "$log_file"; then
        line="$(grep -m1 -B2 -A3 "syntax error" "$log_file" || true)"
        abora_warn "This looks like a Nix syntax error."
        printf '%s\n' "$line" | sed 's/^/    /'
    else
        abora_warn "Last lines from the Nix error:"
        tail -n 14 "$log_file" | sed 's/^/    /'
    fi

    abora_dim_line "Full log: ${log_file}"
    printf '\n'
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
        run_as_root git -C "$config_dir" -c init.defaultBranch=main init >/dev/null
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
    local log_file=""
    local rc=0

    log_file="$(mktemp "${TMPDIR:-/tmp}/anix-${action}.XXXXXX.log")"

    case "$action" in
        dry-build)
            run_as_root nixos-rebuild dry-build --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        switch)
            run_as_root nixos-rebuild switch --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        build)
            run_as_root nixos-rebuild build --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        test)
            run_as_root nixos-rebuild test --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        boot)
            run_as_root nixos-rebuild boot --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        rollback)
            run_as_root nixos-rebuild switch --rollback 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        *)
            abora_error "Unknown rebuild action: ${action}"
            exit 1
            ;;
    esac

    if [[ "$rc" -ne 0 ]]; then
        explain_nix_failure "$log_file"
        return "$rc"
    fi
}

git_branch_name() {
    config_is_git_repo || {
        printf 'none'
        return 0
    }
    git -C "$config_dir" branch --show-current 2>/dev/null | sed 's/^$/detached/' || printf 'unknown'
}

git_snapshot_count() {
    config_is_git_repo || {
        printf '0'
        return 0
    }
    git -C "$config_dir" rev-list --count HEAD 2>/dev/null || printf '0'
}

flake_profile_candidates() {
    local flake_file="$config_dir/flake.nix"
    local profiles=""

    if command -v nix >/dev/null 2>&1 && [[ -f "$flake_file" ]]; then
        profiles="$(nix --extra-experimental-features "nix-command flakes" \
            eval --json "$config_dir#nixosConfigurations" --apply 'builtins.attrNames' 2>/dev/null \
            | tr -d '[]",' \
            | tr ' ' '\n' \
            | sed '/^$/d' \
            || true)"
        if [[ -n "$profiles" ]]; then
            printf '%s\n' "$profiles"
            return 0
        fi
    fi

    if [[ -f "$flake_file" ]]; then
        sed -nE 's|^[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*=[[:space:]]*nixpkgs\.lib\.nixosSystem.*|\1|p' "$flake_file" | sort -u
    fi
}

generation_lines() {
    if command -v nix-env >/dev/null 2>&1 && [[ -e "$system_profile_link" || -e "${system_profile_link}-1-link" ]]; then
        nix-env --list-generations --profile "$system_profile_link" 2>/dev/null || true
        return 0
    fi

    local generation
    { compgen -G "${system_profile_link}-*-link" 2>/dev/null || true; } | sort -V | while IFS= read -r generation; do
        printf '%s\n' "$(basename "$generation")"
    done
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
    wallpaper="$(seed_value "wallpaper" "Daytime-MNT.jpg")"

    cat <<EOF
## ANIX is the simple layer on top of Abora/NixOS.
## Change values here, save the file, then run: anix apply
{ pkgs, ... }:
{
  ## Turns ANIX on.
  anix.enable = true;

  ## Your system name on the network.
  ## Command: anix set hostname <name>
  anix.hostname = "${hostname}";

  ## Timezone example: America/New_York
  ## Command: anix set timezone America/New_York
  anix.timezone = "${timezone}";

  ## Keyboard layouts for console and desktop sessions.
  ## Commands: anix set keyboard us ; anix set keyboard.xkb us
  anix.keyboard.console = "${keyboard_console}";
  anix.keyboard.xkb = "${keyboard_xkb}";

  ## Pick one desktop or use "none" for a console-only system.
  ## Command: anix set desktop gnome
  anix.desktop = "${desktop}";

  ## Wallpaper filename (Abora OS only).
  ## Command: anix set wallpaper Daytime-MNT.jpg
  anix.wallpaper = "${wallpaper}";

  ## Allow unfree apps like Discord and Steam.
  ## Command: anix enable allowUnfree
  anix.allowUnfree = true;

  ## Modern Nix CLI and flakes.
  ## Command: anix enable experimentalNix
  anix.experimentalNix = true;

  ## Default shell for normal users: "bash", "zsh", or "fish".
  ## Command: anix set shell zsh
  anix.shell = "zsh";

  ## TinyPM installs per-user on first login (grab, search, term, start, supdate).
  ## Command: anix tinypm install
  anix.tinypm.enable = true;

  ## System services.
  ## Commands: anix enable bluetooth ; anix disable openssh
  anix.services.bluetooth = true;
  anix.services.printing = true;
  anix.services.flatpak = true;
  anix.services.audio = true;
  anix.services.openssh = false;

  ## Laptop and power helpers.
  ## Commands: anix enable thermald ; anix enable tlp
  anix.power.thermald = true;
  anix.power.tlp = false;

  ## Extra packages and fonts.
  ## Commands: anix package add vim ; anix package remove vim
  anix.packages = with pkgs; [ ];
  anix.fonts = with pkgs; [ inter nerd-fonts.jetbrains-mono ];

  ## Trusted Nix users and scheduled cleanup.
  ## Commands: anix enable garbageCollect ; anix set gc.days 14d
  anix.trustedUsers = [ "root" "@wheel" ];
  anix.garbageCollect.enable = true;
  anix.garbageCollect.dates = "weekly";
  anix.garbageCollect.options = "--delete-older-than 14d";
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
    local allow_unfree tinypm bluetooth flatpak audio openssh gc shell
    hostname="$(read_anix_option "hostname")"
    timezone="$(read_anix_option "timezone")"
    kb_console="$(read_anix_option "keyboard.console")"
    kb_xkb="$(read_anix_option "keyboard.xkb")"
    desktop="$(read_anix_option "desktop")"
    wallpaper="$(read_anix_option "wallpaper")"
    shell="$(read_anix_option "shell")"
    allow_unfree="$(sed -nE 's|^[[:space:]]*anix\.allowUnfree[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    tinypm="$(sed -nE 's|^[[:space:]]*anix\.tinypm\.enable[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    bluetooth="$(sed -nE 's|^[[:space:]]*anix\.services\.bluetooth[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    flatpak="$(sed -nE 's|^[[:space:]]*anix\.services\.flatpak[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    audio="$(sed -nE 's|^[[:space:]]*anix\.services\.audio[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    openssh="$(sed -nE 's|^[[:space:]]*anix\.services\.openssh[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    gc="$(sed -nE 's|^[[:space:]]*anix\.garbageCollect\.enable[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"

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
    abora_kv "shell"       "${shell:-—}"
    abora_kv "allowUnfree" "${allow_unfree:-—}"

    abora_card_end

    abora_card_start "Services"
    abora_kv "TinyPM"      "${tinypm:-—}"
    abora_kv "Bluetooth"   "${bluetooth:-—}"
    abora_kv "Flatpak"     "${flatpak:-—}"
    abora_kv "Audio"       "${audio:-—}"
    abora_kv "OpenSSH"     "${openssh:-—}"
    abora_kv "GC"          "${gc:-—}"
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
        shell)
            case "$value" in bash|zsh|fish) ;; *) abora_error "Shell must be bash, zsh, or fish."; exit 1 ;; esac
            ;;
        gc.days)
            key="garbageCollect.options"
            value="--delete-older-than ${value}"
            ;;
        garbageCollect.dates|gc.dates)
            key="garbageCollect.dates"
            ;;
        *)
            abora_error "Unknown key: ${key}"
            printf '  %bSettable keys:%b hostname timezone keyboard keyboard.xkb desktop wallpaper shell gc.days gc.dates\n\n' "$ABORA_DIM" "$ABORA_NC"
            exit 1
            ;;
    esac

    if [[ "$key" == "desktop" ]]; then
        local current=""
        current="$(current_configured_desktop)"
        if [[ "$current" != "unknown" && "$current" != "$value" ]]; then
            abora_warn "Desktop change: ${current} -> ${value}"
            abora_dim_line "This can download a large desktop stack and boot into ${value} after apply."
            if ! confirm "Keep this desktop change?" "no"; then
                abora_warn "Desktop change cancelled."
                printf '\n'
                return 0
            fi
        fi
    fi

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

do_toggle() {
    local wanted="$1"
    local name="${2:-}"
    local key=""

    if [[ -z "$name" ]]; then
        abora_error "Usage: anix enable <feature> OR anix disable <feature>"
        exit 1
    fi

    case "$name" in
        allowUnfree|unfree) key="allowUnfree" ;;
        experimentalNix|flakes) key="experimentalNix" ;;
        bluetooth) key="services.bluetooth" ;;
        printing|printers) key="services.printing" ;;
        flatpak) key="services.flatpak" ;;
        audio|sound) key="services.audio" ;;
        openssh|ssh) key="services.openssh" ;;
        thermald) key="power.thermald" ;;
        tlp) key="power.tlp" ;;
        tinypm) key="tinypm.enable" ;;
        garbageCollect|gc) key="garbageCollect.enable" ;;
        *)
            abora_error "Unknown feature: ${name}"
            abora_dim_line "Known: allowUnfree experimentalNix bluetooth printing flatpak audio openssh thermald tlp tinypm garbageCollect"
            exit 1
            ;;
    esac

    write_anix_raw_option "$key" "$wanted"
    abora_success "'anix.${key}' set to '${wanted}'"
    abora_dim_line "Run 'anix apply' to rebuild."
    printf '\n'
}

do_package() {
    local action="${1:-}"
    local pkg="${2:-}"
    local file=""

    if [[ -z "$action" || -z "$pkg" ]]; then
        abora_error "Usage: anix package add <pkg> OR anix package remove <pkg>"
        exit 1
    fi
    if [[ ! "$pkg" =~ ^[A-Za-z0-9._+-]+$ ]]; then
        abora_error "Invalid package name: ${pkg}"
        exit 1
    fi

    ensure_anix_file
    file="$anix_file"
    case "$action" in
        add)
            if grep -Eq "anix\\.packages = with pkgs; \\[[^]]*(^|[[:space:]])${pkg}($|[[:space:]])" "$file"; then
                abora_warn "${pkg} is already in anix.packages"
            elif grep -Eq "^[[:space:]]*anix\\.packages[[:space:]]*=[[:space:]]*with pkgs; \\[" "$file"; then
                run_as_root sed -i -E "s|^([[:space:]]*anix\\.packages[[:space:]]*=[[:space:]]*with pkgs; \\[)(.*)(\\];)|\\1\\2 ${pkg} \\3|" "$file"
            else
                write_anix_raw_option "packages" "with pkgs; [ ${pkg} ]"
            fi
            abora_success "Added package: ${pkg}"
            ;;
        remove|rm)
            run_as_root sed -i -E "s|([[:space:][])${pkg}([[:space:]]|\\])|\\1\\2|g; s|[[:space:]]+\\]| \\]|g" "$file"
            abora_success "Removed package if present: ${pkg}"
            ;;
        *)
            abora_error "Usage: anix package add <pkg> OR anix package remove <pkg>"
            exit 1
            ;;
    esac
    abora_dim_line "Run 'anix apply' to rebuild."
    printf '\n'
}

do_service() {
    local action="${1:-status}"
    local service="${2:-}"

    if [[ -z "$service" ]]; then
        abora_error "Usage: anix service <start|stop|restart|status|enable|disable> <unit>"
        exit 1
    fi

    case "$action" in
        start|stop|restart|status)
            run_as_root systemctl "$action" "$service"
            ;;
        enable|disable)
            run_as_root systemctl "$action" --now "$service"
            ;;
        *)
            abora_error "Unknown service action: ${action}"
            exit 1
            ;;
    esac
}

do_ringtone() {
    local action="${1:-start}"
    local sound="/etc/abora/effects/v3StartingAbora.mp3"

    case "$action" in
        start|play)
            if command -v mpg123 >/dev/null 2>&1 && [[ -f "$sound" ]]; then
                mpg123 -q "$sound" &
                abora_success "Played Abora start sound."
            elif systemctl --user list-unit-files abora-ringtone.service >/dev/null 2>&1; then
                systemctl --user start abora-ringtone.service
            else
                abora_warn "No ringtone/start sound player was found."
            fi
            ;;
        stop)
            pkill -f "mpg123 .*v3StartingAbora.mp3" 2>/dev/null || true
            systemctl --user stop abora-ringtone.service 2>/dev/null || true
            ;;
        status)
            pgrep -af "mpg123 .*v3StartingAbora.mp3" || systemctl --user status abora-ringtone.service
            ;;
        *)
            abora_error "Usage: anix ringtone [start|stop|status]"
            exit 1
            ;;
    esac
}

preflight_anix_config() {
    local prompt_desktop="${1:-yes}"
    local failures=0
    local bad_line=""
    local desktop=""
    local current=""

    [[ -f "$anix_file" ]] || return 0

    bad_line="$(grep -nE '^[[:space:]]*abora[[:space:]]*=' "$anix_file" | head -1 || true)"
    if [[ -n "$bad_line" ]]; then
        abora_error "ANIX config has a top-level 'abora =' assignment."
        abora_dim_line "Line ${bad_line%%:*}: use 'abora.desktop = \"gnome\";' or ANIX options instead."
        failures=$((failures + 1))
    fi

    if grep -nE '^[[:space:]]*anix\.[A-Za-z0-9_.-]+[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*$' "$anix_file" >/dev/null; then
        abora_warn "Some ANIX lines may be missing a semicolon."
        grep -nE '^[[:space:]]*anix\.[A-Za-z0-9_.-]+[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*$' "$anix_file" | head -4 | sed 's/^/    /'
        failures=$((failures + 1))
    fi

    desktop="$(read_anix_option "desktop")"
    if [[ -n "$desktop" ]]; then
        local valid=""
        local known="false"
        for valid in "${valid_desktops[@]}"; do
            [[ "$desktop" == "$valid" ]] && known="true"
        done
        if [[ "$known" != "true" ]]; then
            abora_error "Invalid desktop in ANIX config: ${desktop}"
            abora_dim_line "Valid desktops: ${valid_desktops[*]}"
            failures=$((failures + 1))
        fi
        current="$(read_abora_option "desktop")"
        if [[ -n "$current" && "$current" != "$desktop" ]]; then
            abora_warn "ANIX desktop differs from installed Abora desktop: ${current} -> ${desktop}"
            abora_dim_line "This can download a large DE and make ${desktop} the next desktop."
            if [[ "$prompt_desktop" != "yes" ]]; then
                return 1
            fi
            if ! confirm "Apply this desktop change?" "no"; then
                abora_warn "Apply cancelled."
                printf '\n'
                return 1
            fi
        fi
    fi

    [[ "$failures" -eq 0 ]]
}

do_apply() {
    ensure_anix_file

    abora_banner "ANIX Apply" "Rebuilding with ${anix_file}"
    if ! preflight_anix_config yes; then
        abora_error "Fix the ANIX config before applying."
        printf '\n'
        exit 1
    fi
    abora_step "Running nixos-rebuild switch"
    printf '\n'

    run_as_root nixos-rebuild switch --flake "${config_dir}#${flake_config_name}"

    printf '\n'
    abora_success "Done. The ANIX layer is now active."
    printf '\n'
}

do_version() {
    abora_banner "ANIX v${anix_version}" "Abora/NixOS profile manager."
    abora_card_start "Runtime"
    abora_kv "config_dir" "$config_dir"
    abora_kv "config" "$anix_file"
    abora_kv "flake_config" "$flake_config_name"
    abora_kv "git_branch" "$(git_branch_name)"
    abora_kv "snapshots" "$(git_snapshot_count)"
    abora_card_end
    printf '\n'
}

do_status() {
    local dirty="no"
    local flake="missing"
    local generation="unknown"

    config_is_dirty && dirty="yes"
    [[ -f "$config_dir/flake.nix" ]] && flake="present"
    if [[ -e "$current_system_link" ]]; then
        generation="$(readlink "$current_system_link" 2>/dev/null || printf 'active')"
    fi

    abora_banner "ANIX Status" "What ANIX sees right now."
    abora_card_start "System"
    abora_kv "version" "$anix_version"
    abora_kv "config_dir" "$config_dir"
    abora_kv "anix_config" "$([[ -f "$anix_file" ]] && printf present || printf missing)"
    abora_kv "flake" "$flake"
    abora_kv "default_profile" "$flake_config_name"
    abora_kv "generation" "$generation"
    abora_card_end

    abora_card_start "Snapshots"
    abora_kv "git_repo" "$(config_is_git_repo && printf yes || printf no)"
    abora_kv "branch" "$(git_branch_name)"
    abora_kv "dirty" "$dirty"
    abora_kv "commits" "$(git_snapshot_count)"
    abora_kv "push" "$(anix_config_get "snapshots.push" "false")"
    abora_card_end

    abora_card_start "TinyPM"
    if tinypm_installed; then
        abora_kv "installed" "yes"
        local _ver=""
        _ver="$("${HOME}/.tinypm/bin/version" 2>/dev/null | head -1 || true)"
        abora_kv "version" "${_ver:-unknown}"
    else
        abora_kv "installed" "no — run: anix tinypm install"
    fi
    abora_card_end
    printf '\n'
}

tinypm_stamp() {
    printf '%s' "${XDG_STATE_HOME:-${HOME}/.local/state}/tinypm/anix-init-done"
}

tinypm_installed() {
    [[ -f "$(tinypm_stamp)" ]] && [[ -d "${HOME}/.tinypm/bin" ]]
}

do_tinypm() {
    local sub="${1:-status}"
    shift 2>/dev/null || true

    case "$sub" in
        status)
            abora_banner "TinyPM" "Abora Package Manager"
            abora_card_start "Status"
            if tinypm_installed; then
                abora_kv "installed"  "yes (${HOME}/.tinypm)"
                local ver=""
                ver="$("${HOME}/.tinypm/bin/version" 2>/dev/null | head -1 || true)"
                abora_kv "version"    "${ver:-unknown}"
                abora_kv "commands"   "grab  search  term  start  supdate"
            else
                abora_kv "installed"  "no"
                abora_kv "stamp"      "$(tinypm_stamp)"
            fi
            abora_kv "system src" "/etc/abora/tinypm"
            abora_card_end
            printf '\n'
            if ! tinypm_installed; then
                abora_dim_line "Run 'anix tinypm install' to set up TinyPM now."
                printf '\n'
            fi
            ;;
        install|setup|reinstall)
            local src="/etc/abora/tinypm"
            if [[ ! -f "${src}/install.sh" ]]; then
                abora_error "TinyPM source not found at ${src}/install.sh"
                exit 1
            fi
            if tinypm_installed && [[ "$sub" != "reinstall" ]]; then
                abora_warn "TinyPM is already installed at ${HOME}/.tinypm"
                abora_dim_line "Use 'anix tinypm reinstall' to force a fresh install."
                printf '\n'
                return 0
            fi
            abora_step "Installing TinyPM (flavor: abora)…"
            TINYPM_FLAVOR=abora bash "${src}/install.sh" \
                --flavor abora --yes --native nix
            local stamp_dir
            stamp_dir="$(dirname "$(tinypm_stamp)")"
            mkdir -p "${stamp_dir}"
            touch "$(tinypm_stamp)"
            printf '\n'
            abora_success "TinyPM installed. Open a new shell or run: hash -r"
            printf '\n'
            ;;
        *)
            abora_error "Usage: anix tinypm [status|install|reinstall]"
            exit 1
            ;;
    esac
}

do_docs() {
    abora_banner "ANIX Docs" "Local documentation for the Abora toolchain."
    abora_card_start "Docs"
    abora_kv "ANIX" "/etc/abora/docs/wiki/ANIX-V1.md"
    abora_kv "TinyPM" "/etc/abora/docs/wiki/TinyPM-V4.md"
    abora_kv "Abora tools" "/etc/abora/docs/wiki/Abora-Tools.md"
    abora_kv "Recovery" "/etc/abora/docs/wiki/Recovery.md"
    abora_card_end
    printf '\n'
    abora_dim_line "Source tree copies live under docs/wiki/ when developing Abora."
    printf '\n'
}

gui_available() {
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v zenity >/dev/null 2>&1
}

gui_show_file() {
    local title="$1"
    local file="$2"

    if gui_available; then
        zenity --text-info --width=820 --height=560 --title="$title" --filename="$file" 2>/dev/null || true
    else
        printf '\n%s\n' "$title"
        sed -n '1,220p' "$file"
    fi
}

gui_capture() {
    local title="$1"
    shift
    local tmp rc

    tmp="$(mktemp)"
    if "$@" >"$tmp" 2>&1; then
        rc=0
    else
        rc=$?
    fi

    gui_show_file "$title" "$tmp"
    rm -f "$tmp"
    return "$rc"
}

gui_pick_profile() {
    local profiles profile
    profiles="$(flake_profile_candidates)"
    [[ -n "$profiles" ]] || profiles="$flake_config_name"

    if gui_available; then
        profile="$(printf '%s\n' "$profiles" \
            | zenity --list --width=360 --height=320 --title="ANIX Profiles" \
                --column="Profile" 2>/dev/null || true)"
        printf '%s\n' "${profile:-$flake_config_name}"
        return 0
    fi

    printf '\nAvailable profiles:\n'
    printf '%s\n' "$profiles" | sed 's/^/  /'
    printf 'Profile [%s]: ' "$flake_config_name"
    read -r profile || profile=""
    printf '%s\n' "${profile:-$flake_config_name}"
}

gui_choose_action() {
    local title="$1"
    local text="$2"
    shift 2

    zenity --list --width=760 --height=500 \
        --title="$title" \
        --text="$text" \
        --column="Action" \
        --column="What it does" \
        "$@" 2>/dev/null || true
}

gui_prompt_text() {
    local title="$1"
    local text="$2"
    local current="${3:-}"

    zenity --entry --width=460 \
        --title="$title" \
        --text="$text" \
        --entry-text="$current" 2>/dev/null || true
}

gui_confirm_action() {
    local title="$1"
    local text="$2"
    zenity --question --width=460 --title="$title" --text="$text" 2>/dev/null
}

gui_pick_setting_key() {
    gui_choose_action "ANIX Settings" "Choose a setting to change." \
        "show" "Show the current ANIX config summary" \
        "hostname" "Set the machine hostname" \
        "timezone" "Set the system timezone" \
        "keyboard.console" "Set the TTY keyboard layout" \
        "keyboard.xkb" "Set the desktop keyboard layout" \
        "desktop" "Pick a desktop profile" \
        "wallpaper" "Pick an Abora wallpaper" \
        "shell" "Choose bash, zsh, or fish" \
        "back" "Return to the main menu"
}

gui_pick_setting_value() {
    local key="$1"
    local current="$2"
    local value=""

    case "$key" in
        desktop)
            value="$(
                printf '%s\n' "${valid_desktops[@]}" \
                    | zenity --list --width=420 --height=420 \
                        --title="Choose Desktop" \
                        --text="Select the desktop profile ANIX should manage." \
                        --column="Desktop" 2>/dev/null || true
            )"
            ;;
        wallpaper)
            value="$(
                wallpaper_candidates \
                    | zenity --list --width=480 --height=420 \
                        --title="Choose Wallpaper" \
                        --text="Select the wallpaper file stored in ${wallpaper_dir}." \
                        --column="Wallpaper" 2>/dev/null || true
            )"
            ;;
        shell)
            value="$(
                printf '%s\n' bash zsh fish \
                    | zenity --list --width=360 --height=280 \
                        --title="Choose Shell" \
                        --text="Select the default shell for normal users." \
                        --column="Shell" 2>/dev/null || true
            )"
            ;;
        hostname)
            value="$(gui_prompt_text "Set Hostname" "Machine hostname" "$current")"
            ;;
        timezone)
            value="$(gui_prompt_text "Set Timezone" "Timezone, for example America/New_York" "$current")"
            ;;
        keyboard.console)
            value="$(gui_prompt_text "Set Console Keyboard" "Console keyboard layout, for example us" "$current")"
            ;;
        keyboard.xkb)
            value="$(gui_prompt_text "Set Desktop Keyboard" "Desktop keyboard layout, for example us" "$current")"
            ;;
    esac

    printf '%s\n' "$value"
}

gui_pick_feature_action() {
    gui_choose_action "ANIX Features" "Toggle higher-level ANIX feature flags." \
        "allowUnfree:on" "Allow unfree packages and apps" \
        "allowUnfree:off" "Disable unfree packages" \
        "experimentalNix:on" "Enable flakes and the modern Nix CLI" \
        "experimentalNix:off" "Disable flakes and the modern Nix CLI" \
        "bluetooth:on" "Enable Bluetooth support" \
        "bluetooth:off" "Disable Bluetooth support" \
        "printing:on" "Enable printer support" \
        "printing:off" "Disable printer support" \
        "flatpak:on" "Enable Flatpak integration" \
        "flatpak:off" "Disable Flatpak integration" \
        "audio:on" "Enable desktop audio services" \
        "audio:off" "Disable desktop audio services" \
        "openssh:on" "Enable SSH service" \
        "openssh:off" "Disable SSH service" \
        "thermald:on" "Enable laptop thermal management" \
        "thermald:off" "Disable thermald" \
        "tlp:on" "Enable TLP power management" \
        "tlp:off" "Disable TLP" \
        "tinypm:on" "Turn on TinyPM bootstrap" \
        "tinypm:off" "Turn off TinyPM bootstrap" \
        "garbageCollect:on" "Enable scheduled garbage collection" \
        "garbageCollect:off" "Disable scheduled garbage collection" \
        "back" "Return to the main menu"
}

gui_pick_doc_file() {
    gui_choose_action "ANIX Docs" "Choose a local document to view." \
        "/etc/abora/docs/wiki/ANIX-V1.md" "ANIX guide" \
        "/etc/abora/docs/wiki/TinyPM-V4.md" "TinyPM guide" \
        "/etc/abora/docs/wiki/Abora-Tools.md" "Abora tools guide" \
        "/etc/abora/docs/wiki/Recovery.md" "Recovery guide" \
        "back" "Return to the main menu"
}

gui_show_doc() {
    local doc="$1"
    [[ "$doc" == "back" || -z "$doc" ]] && return 0
    if [[ -f "$doc" ]]; then
        gui_show_file "ANIX Docs" "$doc"
    else
        zenity --warning --width=420 --title="Missing document" \
            --text="This local doc was not found:\n${doc}" 2>/dev/null || true
    fi
}

gui_settings_menu() {
    local action current value

    while true; do
        action="$(gui_pick_setting_key)"
        case "$action" in
            show) gui_capture "ANIX Settings" show_config ;;
            hostname|timezone|keyboard.console|keyboard.xkb|desktop|wallpaper|shell)
                current="$(read_anix_option "$action")"
                [[ -n "$current" ]] || current="$(read_abora_option "$action")"
                value="$(gui_pick_setting_value "$action" "$current")"
                [[ -n "$value" ]] || continue
                gui_capture "ANIX Set ${action}" do_set "$action" "$value"
                ;;
            back|"") return 0 ;;
        esac
    done
}

gui_features_menu() {
    local action feature state wanted

    while true; do
        action="$(gui_pick_feature_action)"
        case "$action" in
            back|"") return 0 ;;
            *)
                feature="${action%%:*}"
                state="${action##*:}"
                wanted="true"
                [[ "$state" == "off" ]] && wanted="false"
                gui_capture "ANIX Feature ${feature}" do_toggle "$wanted" "$feature"
                ;;
        esac
    done
}

gui_profiles_menu() {
    local action profile target

    while true; do
        action="$(gui_choose_action "ANIX Profiles" "Inspect, validate, or switch profiles." \
            "profiles" "List detected flake profiles" \
            "generations" "Show recent system generations" \
            "diff" "Dry-build a profile and compare package changes" \
            "build" "Build a profile without switching to it" \
            "test" "Test-activate a profile for this boot" \
            "boot" "Set a profile for next boot" \
            "switch" "Switch to a profile now" \
            "rollback" "Rollback to the previous generation" \
            "back" "Return to the main menu")"

        case "$action" in
            profiles) gui_capture "ANIX Profiles" do_profiles ;;
            generations) gui_capture "ANIX Generations" do_generations ;;
            diff)
                profile="$(gui_pick_profile)"
                gui_capture "ANIX Diff ${profile}" do_diff nix "$profile"
                ;;
            build)
                profile="$(gui_pick_profile)"
                target="$(profile_target nix "$profile")"
                gui_capture "ANIX Build ${profile}" do_build_profile nix "$profile" "$target"
                ;;
            test)
                profile="$(gui_pick_profile)"
                gui_capture "ANIX Test ${profile}" do_test nix "$profile"
                ;;
            boot)
                profile="$(gui_pick_profile)"
                gui_capture "ANIX Boot ${profile}" do_boot nix "$profile"
                ;;
            switch)
                profile="$(gui_pick_profile)"
                if gui_confirm_action "Switch profile" "Switch to profile '${profile}' now?\n\nThis runs nixos-rebuild switch."; then
                    gui_capture "ANIX Switch ${profile}" do_switch nix "$profile" --now
                fi
                ;;
            rollback)
                if gui_confirm_action "Rollback generation" "Rollback to the previous generation now?"; then
                    gui_capture "ANIX Rollback" do_rollback --now
                fi
                ;;
            back|"") return 0 ;;
        esac
    done
}

gui_snapshots_menu() {
    local action current next

    while true; do
        current="$(anix_config_get "snapshots.push" "false")"
        action="$(gui_choose_action "ANIX Snapshots" "Manage local config history and push behavior." \
            "status" "Show ANIX status with snapshot state" \
            "save" "Create a local config snapshot now" \
            "push" "Toggle snapshots.push (currently ${current})" \
            "config" "Show ANIX tool config" \
            "back" "Return to the main menu")"

        case "$action" in
            status) gui_capture "ANIX Status" do_status ;;
            save)
                local message=""
                message="$(gui_prompt_text "Save Snapshot" "Commit message for this local snapshot" "anix: local config snapshot")"
                [[ -n "$message" ]] || continue
                gui_capture "ANIX Snapshot" do_save "$message"
                ;;
            push)
                next="true"
                if is_yes "$current"; then
                    next="false"
                fi
                gui_capture "ANIX Config" do_tool_config set snapshots.push "$next"
                ;;
            config) gui_capture "ANIX Config" do_tool_config show ;;
            back|"") return 0 ;;
        esac
    done
}

gui_packages_menu() {
    local action pkg

    while true; do
        action="$(gui_choose_action "ANIX Packages" "Manage TinyPM bootstrap and simple package edits." \
            "tinypm-status" "Show TinyPM status" \
            "tinypm-install" "Install or repair TinyPM for this user" \
            "package-add" "Add a package to anix.packages" \
            "package-remove" "Remove a package from anix.packages" \
            "back" "Return to the main menu")"

        case "$action" in
            tinypm-status) gui_capture "TinyPM Status" do_tinypm status ;;
            tinypm-install) gui_capture "TinyPM Install" do_tinypm install ;;
            package-add)
                pkg="$(gui_prompt_text "Add Package" "Package name to add to anix.packages")"
                [[ -n "$pkg" ]] || continue
                gui_capture "ANIX Package Add" do_package add "$pkg"
                ;;
            package-remove)
                pkg="$(gui_prompt_text "Remove Package" "Package name to remove from anix.packages")"
                [[ -n "$pkg" ]] || continue
                gui_capture "ANIX Package Remove" do_package remove "$pkg"
                ;;
            back|"") return 0 ;;
        esac
    done
}

gui_maintenance_menu() {
    local action

    while true; do
        action="$(gui_choose_action "ANIX Maintenance" "Run larger system checks and apply changes." \
            "quickstart" "Create ANIX config and prepare snapshot history" \
            "doctor" "Check the ANIX and NixOS management layer" \
            "doctor-fix" "Create missing safe basics automatically" \
            "apply" "Rebuild and switch using the ANIX layer" \
            "docs" "Show local docs paths" \
            "back" "Return to the main menu")"

        case "$action" in
            quickstart) gui_capture "ANIX Quickstart" do_quickstart ;;
            doctor) gui_capture "ANIX Doctor" do_doctor ;;
            doctor-fix) gui_capture "ANIX Doctor Repair" do_doctor --fix ;;
            apply)
                if gui_confirm_action "Apply ANIX config" "Apply the current ANIX config now?\n\nThis runs nixos-rebuild switch."; then
                    gui_capture "ANIX Apply" do_apply
                fi
                ;;
            docs) gui_capture "ANIX Docs" do_docs ;;
            back|"") return 0 ;;
        esac
    done
}

terminal_prompt_setting_key() {
    printf '\nSettings\n'
    printf '  1  Show current config\n'
    printf '  2  Hostname\n'
    printf '  3  Timezone\n'
    printf '  4  Console keyboard\n'
    printf '  5  Desktop keyboard\n'
    printf '  6  Desktop\n'
    printf '  7  Wallpaper\n'
    printf '  8  Shell\n'
    printf '  0  Back\n\n'
    printf '  Select: '
}

terminal_prompt_feature_action() {
    printf '\nFeatures\n'
    printf '  1  Allow unfree\n'
    printf '  2  Experimental Nix / flakes\n'
    printf '  3  Bluetooth\n'
    printf '  4  Printing\n'
    printf '  5  Flatpak\n'
    printf '  6  Audio\n'
    printf '  7  OpenSSH\n'
    printf '  8  Thermald\n'
    printf '  9  TLP\n'
    printf '  10 TinyPM bootstrap\n'
    printf '  11 Garbage collect\n'
    printf '  0  Back\n\n'
    printf '  Select: '
}

terminal_prompt_feature_state() {
    printf '  State [on/off]: '
}

terminal_settings_menu() {
    local choice key current value

    while true; do
        abora_banner "ANIX Settings" "Change common ANIX values."
        terminal_prompt_setting_key
        read -r choice || choice="0"
        case "$choice" in
            1) show_config ;;
            2) key="hostname" ;;
            3) key="timezone" ;;
            4) key="keyboard.console" ;;
            5) key="keyboard.xkb" ;;
            6) key="desktop" ;;
            7) key="wallpaper" ;;
            8) key="shell" ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac

        if [[ "$choice" == "1" ]]; then
            printf '\nPress Enter to return to settings.'
            read -r _ || true
            continue
        fi

        current="$(read_anix_option "$key")"
        [[ -n "$current" ]] || current="$(read_abora_option "$key")"
        printf '  Current [%s]: ' "${current:-unset}"
        read -r value || value=""
        [[ -n "$value" ]] || continue
        do_set "$key" "$value"
        printf '\nPress Enter to return to settings.'
        read -r _ || true
    done
}

terminal_features_menu() {
    local choice feature wanted state

    while true; do
        abora_banner "ANIX Features" "Toggle ANIX feature flags."
        terminal_prompt_feature_action
        read -r choice || choice="0"
        case "$choice" in
            1) feature="allowUnfree" ;;
            2) feature="experimentalNix" ;;
            3) feature="bluetooth" ;;
            4) feature="printing" ;;
            5) feature="flatpak" ;;
            6) feature="audio" ;;
            7) feature="openssh" ;;
            8) feature="thermald" ;;
            9) feature="tlp" ;;
            10) feature="tinypm" ;;
            11) feature="garbageCollect" ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac

        terminal_prompt_feature_state
        read -r state || state=""
        case "$state" in
            on|enable|enabled|true|yes|y) wanted="true" ;;
            off|disable|disabled|false|no|n) wanted="false" ;;
            *) abora_warn "Type on or off."; printf '\n'; continue ;;
        esac
        do_toggle "$wanted" "$feature"
        printf '\nPress Enter to return to features.'
        read -r _ || true
    done
}

terminal_profiles_menu() {
    local choice profile

    while true; do
        abora_banner "ANIX Profiles" "Inspect, build, and switch profiles."
        printf '  1  List profiles\n'
        printf '  2  Show generations\n'
        printf '  3  Diff profile\n'
        printf '  4  Build profile\n'
        printf '  5  Test profile\n'
        printf '  6  Boot profile\n'
        printf '  7  Switch profile\n'
        printf '  8  Rollback previous generation\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) do_profiles ;;
            2) do_generations ;;
            3) profile="$(gui_pick_profile)"; do_diff nix "$profile" ;;
            4) profile="$(gui_pick_profile)"; do_build_profile nix "$profile" ;;
            5) profile="$(gui_pick_profile)"; do_test nix "$profile" ;;
            6) profile="$(gui_pick_profile)"; do_boot nix "$profile" ;;
            7) profile="$(gui_pick_profile)"; do_switch nix "$profile" ;;
            8) do_rollback ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to profiles.'
        read -r _ || true
    done
}

terminal_snapshots_menu() {
    local choice message current

    while true; do
        current="$(anix_config_get "snapshots.push" "false")"
        abora_banner "ANIX Snapshots" "Manage local config history."
        printf '  1  Status\n'
        printf '  2  Save snapshot\n'
        printf '  3  Toggle snapshots.push (current: %s)\n' "$current"
        printf '  4  Show ANIX tool config\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) do_status ;;
            2)
                printf '  Message [anix: local config snapshot]: '
                read -r message || message=""
                do_save "${message:-anix: local config snapshot}"
                ;;
            3)
                if is_yes "$current"; then
                    do_tool_config set snapshots.push false
                else
                    do_tool_config set snapshots.push true
                fi
                ;;
            4) do_tool_config show ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to snapshots.'
        read -r _ || true
    done
}

terminal_packages_menu() {
    local choice pkg

    while true; do
        abora_banner "ANIX Packages" "Manage TinyPM and anix.packages."
        printf '  1  TinyPM status\n'
        printf '  2  Install TinyPM\n'
        printf '  3  Add package\n'
        printf '  4  Remove package\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) do_tinypm status ;;
            2) do_tinypm install ;;
            3)
                printf '  Package to add: '
                read -r pkg || pkg=""
                [[ -n "$pkg" ]] && do_package add "$pkg"
                ;;
            4)
                printf '  Package to remove: '
                read -r pkg || pkg=""
                [[ -n "$pkg" ]] && do_package remove "$pkg"
                ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to packages.'
        read -r _ || true
    done
}

terminal_maintenance_menu() {
    local choice

    while true; do
        abora_banner "ANIX Maintenance" "Prepare, repair, and apply the ANIX layer."
        printf '  1  Quickstart\n'
        printf '  2  Doctor\n'
        printf '  3  Doctor repair\n'
        printf '  4  Apply\n'
        printf '  5  Docs\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) do_quickstart ;;
            2) do_doctor ;;
            3) do_doctor --fix ;;
            4) do_apply ;;
            5) do_docs ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to maintenance.'
        read -r _ || true
    done
}

terminal_docs_menu() {
    local choice

    while true; do
        abora_banner "ANIX Docs" "Open local documentation in terminal mode."
        printf '  1  ANIX guide\n'
        printf '  2  TinyPM guide\n'
        printf '  3  Abora tools guide\n'
        printf '  4  Recovery guide\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) gui_show_doc "/etc/abora/docs/wiki/ANIX-V1.md" ;;
            2) gui_show_doc "/etc/abora/docs/wiki/TinyPM-V4.md" ;;
            3) gui_show_doc "/etc/abora/docs/wiki/Abora-Tools.md" ;;
            4) gui_show_doc "/etc/abora/docs/wiki/Recovery.md" ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to docs.'
        read -r _ || true
    done
}

do_gui_terminal() {
    local choice

    while true; do
        abora_banner "ANIX Control Center" "Graphical toolkit unavailable; using grouped terminal mode."
        printf '  1  Overview\n'
        printf '  2  Settings\n'
        printf '  3  Features\n'
        printf '  4  Profiles\n'
        printf '  5  Snapshots\n'
        printf '  6  Packages\n'
        printf '  7  Maintenance\n'
        printf '  8  Docs\n'
        printf '  0  Exit\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) do_status; printf '\nPress Enter to return to overview.'; read -r _ || true ;;
            2) terminal_settings_menu ;;
            3) terminal_features_menu ;;
            4) terminal_profiles_menu ;;
            5) terminal_snapshots_menu ;;
            6) terminal_packages_menu ;;
            7) terminal_maintenance_menu ;;
            8) terminal_docs_menu ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number." ;;
        esac
    done
}

do_gui() {
    local action doc

    if ! gui_available; then
        do_gui_terminal
        return
    fi

    while true; do
        action="$(gui_choose_action "ANIX v${anix_version}" "Choose an ANIX workspace." \
            "overview" "Show status, config, flake, and snapshot state" \
            "settings" "Change hostname, timezone, desktop, wallpaper, shell, and more" \
            "features" "Toggle Bluetooth, Flatpak, TinyPM, GC, and other feature flags" \
            "profiles" "Inspect, build, test, boot, switch, or rollback profiles" \
            "snapshots" "Save local config snapshots and control push behavior" \
            "packages" "Install TinyPM and edit anix.packages" \
            "maintenance" "Run quickstart, doctor, repair, and apply flows" \
            "docs" "Read local ANIX and Abora documentation" \
            "exit" "Close ANIX GUI")"

        case "$action" in
            overview) gui_capture "ANIX Status" do_status ;;
            settings) gui_settings_menu ;;
            features) gui_features_menu ;;
            profiles) gui_profiles_menu ;;
            snapshots) gui_snapshots_menu ;;
            packages) gui_packages_menu ;;
            maintenance) gui_maintenance_menu ;;
            docs)
                doc="$(gui_pick_doc_file)"
                gui_show_doc "$doc"
                ;;
            exit|"") return 0 ;;
        esac
    done
}

do_quickstart() {
    abora_banner "ANIX Quickstart" "Prepare the friendly NixOS layer."

    ensure_anix_file
    abora_success "ANIX config is present: ${anix_file}"

    if config_is_git_repo; then
        abora_success "Snapshot repo is ready: ${config_dir}"
    else
        abora_warn "Snapshot repo is not initialized."
        if confirm "Initialize local snapshot history now?" "yes"; then
            ensure_config_git_repo
            abora_success "Snapshot repo is ready."
        fi
    fi

    printf '\n'
    do_status
    abora_dim_line "Next: run 'anix diff nix ${flake_config_name}' or 'anix switch nix ${flake_config_name}'."
    printf '\n'
}

do_profiles() {
    local profiles=""

    profiles="$(flake_profile_candidates)"
    abora_banner "ANIX Profiles" "${config_dir}/flake.nix"

    if [[ -z "$profiles" ]]; then
        abora_warn "No flake profiles were discovered."
        abora_dim_line "Expected outputs under nixosConfigurations."
        printf '\n'
        return 0
    fi

    abora_card_start "Available Profiles"
    printf '%s\n' "$profiles" | while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        printf '  %b│%b  %b%s%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$profile" "$ABORA_NC"
    done
    abora_card_end
    printf '\n'
}

do_generations() {
    local lines=""

    lines="$(generation_lines)"
    abora_banner "ANIX Generations" "$system_profile_link"
    if [[ -z "$lines" ]]; then
        abora_warn "No system generations were found."
        printf '\n'
        return 0
    fi

    abora_card_start "System Generations"
    printf '%s\n' "$lines" | tail -n "${ANIX_GENERATION_LIMIT:-12}" | while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        printf '  %b│%b  %b%s%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$line" "$ABORA_NC"
    done
    abora_card_end
    printf '\n'
}

do_diff() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target=""

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Diff" "${family}/${profile}"
    run_rebuild dry-build "$target"
    printf '\n'
    show_package_changes "$target"
    printf '\n'
}

do_build_profile() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target="${3:-}"

    [[ -n "$target" ]] || target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Build" "${family}/${profile}"
    run_rebuild build "$target"
    printf '\n'
    abora_success "Build finished for ${profile}."
    printf '\n'
}

do_test() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target=""

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Test" "${family}/${profile}"
    maybe_snapshot_dirty_config "anix: snapshot before testing ${profile}"
    run_rebuild test "$target"
    printf '\n'
    abora_success "Test activation finished for ${profile}."
    printf '\n'
}

do_boot() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target=""

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Boot" "${family}/${profile}"
    maybe_snapshot_dirty_config "anix: snapshot before boot profile ${profile}"
    run_rebuild boot "$target"
    printf '\n'
    abora_success "Boot profile prepared for ${profile}. Reboot when ready."
    printf '\n'
}

do_edit() {
    local editor="${EDITOR:-${VISUAL:-nano}}"

    ensure_anix_file
    if ! command -v "$editor" >/dev/null 2>&1; then
        abora_error "Editor not found: ${editor}"
        abora_dim_line "Set EDITOR or VISUAL, then run anix edit again."
        printf '\n'
        exit 1
    fi
    "$editor" "$anix_file"
}

do_gc() {
    local mode="${1:-old}"

    require_command nix-collect-garbage
    case "$mode" in
        old)
            if ! confirm "Delete old Nix generations and garbage collect?" "no"; then
                abora_warn "Garbage collection cancelled."
                printf '\n'
                return 0
            fi
            run_as_root nix-collect-garbage -d
            ;;
        user)
            nix-collect-garbage
            ;;
        *)
            abora_error "Usage: anix gc [old|user]"
            exit 1
            ;;
    esac

    printf '\n'
    abora_success "Garbage collection complete."
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
    local fix="false"
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --fix|--repair)
                fix="true"
                ;;
            *)
                abora_error "Unknown doctor option: $1"
                exit 1
                ;;
        esac
        shift
    done

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
        if [[ "$fix" == "true" ]]; then
            run_as_root mkdir -p "$config_dir"
            doctor_check ok "created config directory: ${config_dir}"
        else
            doctor_check fail "config directory is missing: ${config_dir}"
            failures=$((failures + 1))
        fi
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
        if [[ "$fix" == "true" ]]; then
            ensure_config_git_repo
            doctor_check ok "initialized config Git repo"
        else
            doctor_check warn "config directory is not a Git repo; snapshots will initialize one"
            warnings=$((warnings + 1))
        fi
    fi

    if [[ -f "$anix_file" ]]; then
        doctor_check ok "ANIX config exists: ${anix_file}"
        if preflight_anix_config no; then
            doctor_check ok "ANIX config preflight passed"
        else
            doctor_check fail "ANIX config preflight failed"
            failures=$((failures + 1))
        fi
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
        if [[ "$fix" == "true" ]]; then
            ensure_anix_file
            doctor_check ok "created ANIX config: ${anix_file}"
        else
            doctor_check warn "ANIX config does not exist yet; run 'anix init'"
            warnings=$((warnings + 1))
        fi
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
    abora_banner "ANIX v${anix_version}" "Nix without the homework."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %banix status%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show profile, generation, flake, Git, and snapshot state."
    printf '\n'
    printf '  %banix quickstart%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create the ANIX config and prepare local snapshots."
    printf '\n'
    printf '  %banix docs%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show local docs paths for ANIX, TinyPM, and Abora."
    printf '\n'
    printf '  %banix profiles%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List flake profiles under nixosConfigurations."
    printf '\n'
    printf '  %banix generations%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show recent NixOS system generations."
    printf '\n'
    printf '  %banix switch nix <profile>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Safely switch to a named flake config."
    printf '\n'
    printf '  %banix test nix [profile]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Test-activate a profile without making it the boot default."
    printf '\n'
    printf '  %banix boot nix [profile]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Build a profile for the next boot without switching now."
    printf '\n'
    printf '  %banix diff nix [profile]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Dry-build and compare package closure changes."
    printf '\n'
    printf '  %banix rollback nix [profile] [--now]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Roll back to the previous generation or a named profile."
    printf '\n'
    printf '  %banix save%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Save a local Git snapshot of ${config_dir}."
    printf '\n'
    printf '  %banix doctor%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Check flakes, Git state, generations, and ANIX settings."
    printf '  %banix doctor --fix%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create missing config and snapshot basics where safe."
    printf '\n'
    printf '  %banix init%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create ${anix_file} with sensible defaults."
    printf '\n'
    printf '  %banix show%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the current ANIX settings."
    printf '\n'
    printf '  %banix edit%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Open the ANIX config in your editor."
    printf '\n'
    printf '  %banix set hostname <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set timezone <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard.xkb <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set desktop <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set wallpaper <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Update a simple ANIX setting."
    printf '\n'
    printf '  %banix enable <feature>%b / %banix disable <feature>%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Toggle bluetooth, flatpak, audio, openssh, allowUnfree, tinypm, gc, and power helpers."
    printf '\n'
    printf '  %banix package add <pkg>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix package remove <pkg>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Add or remove Nix packages from the ANIX system package list."
    printf '\n'
    printf '  %banix service restart <unit>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Control a systemd service through ANIX."
    printf '\n'
    printf '  %banix ringtone start%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Play the Abora start sound when available."
    printf '\n'
    printf '  %banix wallpapers%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List the wallpapers you can switch to."
    printf '\n'
    printf '  %banix config set snapshots.push true%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Opt in to pushing snapshots after local commits."
    printf '\n'
    printf '  %banix gc old%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Remove old generations after confirmation."
    printf '\n'
    printf '  %banix apply%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Rebuild the system using the ANIX layer."
    printf '\n'
    printf '  %banix tinypm [status|install|reinstall]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Manage the TinyPM per-user installation."
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
        version|--version|-v) shift || true; do_version "$@" ;;
        --gui|gui) shift || true; do_gui "$@" ;;
        status) shift || true; do_status "$@" ;;
        quickstart|start) shift || true; do_quickstart "$@" ;;
        docs|doc) shift || true; do_docs "$@" ;;
        profiles|profile|ls) shift || true; do_profiles "$@" ;;
        generations|gens) shift || true; do_generations "$@" ;;
        init) shift || true; do_init "$@" ;;
        show|"") shift || true; show_config "$@" ;;
        edit) shift || true; do_edit "$@" ;;
        wallpapers) shift || true; show_wallpapers "$@" ;;
        set) shift || true; do_set "$@" ;;
        enable) shift || true; do_toggle true "$@" ;;
        disable) shift || true; do_toggle false "$@" ;;
        package|pkg) shift || true; do_package "$@" ;;
        service) shift || true; do_service "$@" ;;
        ringtone) shift || true; do_ringtone "$@" ;;
        apply) shift || true; do_apply "$@" ;;
        test) shift || true; do_test "$@" ;;
        boot) shift || true; do_boot "$@" ;;
        diff) shift || true; do_diff "$@" ;;
        switch) shift || true; do_switch "$@" ;;
        rollback) shift || true; do_rollback "$@" ;;
        save) shift || true; do_save "$@" ;;
        config) shift || true; do_tool_config "$@" ;;
        gc|clean) shift || true; do_gc "$@" ;;
        doctor) shift || true; do_doctor "$@" ;;
        tinypm) shift || true; do_tinypm "$@" ;;
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
