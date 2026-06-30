#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script_self="${BASH_SOURCE[0]}"
script_hash_before="$(sha256sum "$script_self" 2>/dev/null | awk '{print $1}' || true)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

# shellcheck source=/dev/null
source "$ui_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
command_name="${ABORA_UPDATE_COMMAND:-$(basename "$0")}"
repo_git_url="${ABORA_REPO_GIT_URL:-https://github.com/AnimatedGTVR/abora-os.git}"
repo_ref="${ABORA_REPO_REF:-main}"
upstream_dir="${ABORA_UPSTREAM_DIR:-$config_dir/.abora-upstream}"
flake_config_name="${ABORA_FLAKE_CONFIG_NAME:-abora}"

# ── Channel helpers ───────────────────────────────────────────────────────────

channel_file() {
    printf '%s/abora/channel' "$config_dir"
}

read_channel() {
    local cf
    cf="$(channel_file)"
    if [[ -f "$cf" ]]; then
        tr -d '[:space:]' < "$cf"
    else
        printf 'stable'
    fi
}

write_channel() {
    local name="$1" cf
    cf="$(channel_file)"
    mkdir -p "$(dirname "$cf")"
    printf '%s\n' "$name" > "$cf"
}

# Resolve the git ref for the current channel.
# For stable: finds the latest v* tag via git ls-remote.
# For unstable: uses main.
resolve_channel_ref() {
    local channel="$1" latest_tag=""

    case "$channel" in
        stable)
            abora_info "Resolving latest stable release tag..." >&2
            latest_tag="$(
                git ls-remote --tags "$repo_git_url" 'refs/tags/v*' 2>/dev/null \
                    | grep -v '\^{}' \
                    | awk '{print $2}' \
                    | sed 's|refs/tags/||' \
                    | grep -E '^v[0-9]+([.][0-9]+)*$' \
                    | sort -V \
                    | tail -n1 \
                    || true
            )"
            if [[ -n "$latest_tag" ]]; then
                printf '%s' "$latest_tag"
            else
                abora_warn "Could not resolve a stable tag — falling back to main." >&2
                printf 'main'
            fi
            ;;
        unstable)
            printf 'main'
            ;;
        *)
            abora_warn "Unknown channel '${channel}' — using main." >&2
            printf 'main'
            ;;
    esac
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    abora_banner "System Update" "Keep your Abora installation up to date."
    printf '  %bCommands%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %bnixos update%b  /  %bupdate%b  /  %babora-update%b\n' \
        "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Sync the latest Abora files and rebuild the system."
    printf '\n'
    printf '  %bnixos rollback%b  /  %brollback%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Roll back to the previous system generation."
    printf '\n'
    printf '  %bnixos channel%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the current update channel."
    printf '\n'
    printf '  %bnixos channel list%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List all available channels."
    printf '\n'
    printf '  %bnixos channel set <stable|unstable>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Switch to a different update channel."
    printf '\n'
}

# ── Channel subcommand ────────────────────────────────────────────────────────

handle_channel_command() {
    local sub="${1:-}" channel

    case "$sub" in
        "" | show)
            channel="$(read_channel)"
            abora_banner "Update Channel" "Your system receives updates from this channel."
            printf '  %bChannel%b    %b%s%b\n' "$ABORA_DIM" "$ABORA_NC" "$ABORA_CYAN" "$channel" "$ABORA_NC"
            case "$channel" in
                stable)
                    abora_dim_line "  Tracks tagged Abora releases. Recommended for most users."
                    ;;
                unstable)
                    abora_dim_line "  Tracks the main development branch. May include breaking changes."
                    ;;
            esac
            printf '\n'
            ;;
        list)
            abora_banner "Update Channels" "Choose how your system receives updates."
            channel="$(read_channel)"

            abora_card_start "Available Channels"

            local marker_stable="" marker_unstable=""
            [[ "$channel" == "stable" ]]   && marker_stable=" %b◀ current%b"
            [[ "$channel" == "unstable" ]] && marker_unstable=" %b◀ current%b"

            printf '  %b│%b  %bstable%b' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
            # shellcheck disable=SC2059
            [[ -n "$marker_stable" ]]   && printf "  $marker_stable" "$ABORA_GREEN" "$ABORA_NC"
            printf '\n'
            printf '  %b│%b  %bLatest tagged Abora releases. Recommended for most users.%b\n' \
                "$ABORA_BLUE" "$ABORA_NC" "$ABORA_DIM" "$ABORA_NC"
            printf '\n'

            printf '  %b│%b  %bunstable%b' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
            # shellcheck disable=SC2059
            [[ -n "$marker_unstable" ]] && printf "  $marker_unstable" "$ABORA_GREEN" "$ABORA_NC"
            printf '\n'
            printf '  %b│%b  %bDevelopment builds from the main branch. May include breaking changes.%b\n' \
                "$ABORA_BLUE" "$ABORA_NC" "$ABORA_DIM" "$ABORA_NC"
            printf '  %b│%b\n' "$ABORA_BLUE" "$ABORA_NC"

            abora_card_end

            printf '\n'
            ;;
        set)
            local new_channel="${2:-}"
            case "$new_channel" in
                stable | unstable)
                    run_as_root env \
                        ABORA_SYSTEM_CONFIG="$config_dir" \
                        bash -c '
                            channel_file="'"$config_dir"'/abora/channel"
                            mkdir -p "$(dirname "$channel_file")"
                            printf "%s\n" "'"$new_channel"'" > "$channel_file"
                        '
                    abora_success "Channel set to '${new_channel}'."
                    abora_dim_line "Run 'update' to apply the new channel."
                    printf '\n'
                    ;;
                "")
                    abora_error "Specify a channel: stable or unstable"
                    exit 1
                    ;;
                *)
                    abora_error "Unknown channel: ${new_channel}. Use 'stable' or 'unstable'."
                    exit 1
                    ;;
            esac
            ;;
        *)
            abora_error "Unknown channel subcommand: ${sub}"
            exit 1
            ;;
    esac
}

# ── System helpers ────────────────────────────────────────────────────────────

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return
    fi

    abora_error "This command needs root privileges. Run it as root or install sudo."
    exit 1
}

confirm() {
    local prompt="$1"
    local answer=""
    if [[ ! -t 0 ]]; then
        return 0
    fi
    printf '  %b%s [Y/n]%b ' "$ABORA_YELLOW" "$prompt" "$ABORA_NC"
    read -r answer
    case "$answer" in
        ""|y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

copy_upstream_file() {
    local source="$1"
    local destination="$2"

    if [[ ! -f "$source" ]]; then
        abora_error "Required upstream file is missing: ${source}"
        return 1
    fi

    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
}

copy_first_existing_upstream_file() {
    local destination="$1"
    shift

    local source=""
    for source in "$@"; do
        if [[ -f "$source" ]]; then
            mkdir -p "$(dirname "$destination")"
            cp "$source" "$destination"
            return 0
        fi
    done

    abora_error "None of the expected upstream files were found for ${destination##*/}."
    return 1
}

maybe_reexec_synced_updater() {
    local synced_script="$config_dir/abora/update.sh"
    local script_hash_after=""

    [[ "${ABORA_UPDATE_REEXECED:-0}" != 1 ]] || return 0
    [[ -n "$script_hash_before" && -f "$synced_script" ]] || return 0

    script_hash_after="$(sha256sum "$synced_script" 2>/dev/null | awk '{print $1}' || true)"
    [[ -n "$script_hash_after" && "$script_hash_after" != "$script_hash_before" ]] || return 0

    abora_info "Restarting with the synced updater."
    exec env \
        ABORA_UPDATE_REEXECED=1 \
        ABORA_UPDATE_COMMAND="$command_name" \
        ABORA_SYSTEM_CONFIG="$config_dir" \
        ABORA_REPO_GIT_URL="$repo_git_url" \
        ABORA_REPO_REF="$repo_ref" \
        ABORA_UPSTREAM_DIR="$upstream_dir" \
        ABORA_FLAKE_CONFIG_NAME="$flake_config_name" \
        ABORA_UI_LIB="$ui_lib" \
        bash "$synced_script"
}

# ── GitHub clone fallback ─────────────────────────────────────────────────────

# Called when a git fetch on an existing upstream dir fails.
# Prompts the user, then wipes and re-clones from GitHub if they agree.
try_fresh_clone() {
    local effective_ref="$1"

    abora_warn "The local upstream cache appears to be broken or out of date."
    printf '\n'

    if [[ ! -t 0 ]]; then
        abora_error "Non-interactive session — cannot prompt to re-clone. Run interactively or delete '${upstream_dir}' manually and retry."
        return 1
    fi

    printf '  %bWould you like to re-clone Abora from GitHub and retry?%b\n' "$ABORA_YELLOW" "$ABORA_NC"
    abora_dim_line "  This will delete the local cache at: ${upstream_dir}"
    printf '  %b[Y/n]%b ' "$ABORA_YELLOW" "$ABORA_NC"
    local answer=""
    read -r answer
    case "$answer" in
        ""|y|Y|yes|YES) ;;
        *)
            abora_error "Re-clone declined. Update aborted."
            return 1
            ;;
    esac

    abora_info "Removing broken cache and cloning fresh from GitHub..."
    rm -rf "$upstream_dir"
    if ! git clone --depth=1 --branch "$effective_ref" "$repo_git_url" "$upstream_dir"; then
        abora_error "Fresh clone from ${repo_git_url} also failed."
        abora_error "Check your internet connection, then run 'nixos update' again."
        return 1
    fi
}

# ── File sync ─────────────────────────────────────────────────────────────────

install_mango_config_asset() {
    local abora_dir="$config_dir/abora"
    local dest="$abora_dir/mango/config.conf"
    local candidate

    mkdir -p "$(dirname "$dest")"
    for candidate in \
        "$upstream_dir/assets/mango/config.conf" \
        "$config_dir/.abora-upstream/assets/mango/config.conf" \
        /etc/abora/mango/config.conf \
        "$config_dir/assets/mango/config.conf"; do
        if [[ -f "$candidate" ]]; then
            cp "$candidate" "$dest"
            return 0
        fi
    done

    : > "$dest"
}

rewrite_installed_mango_config_paths() {
    local abora_dir="$config_dir/abora"
    local bad_store='/nix/store'
    bad_store="${bad_store}/assets/mango/config.conf"
    local file

    for file in "$abora_dir/abora-options.nix" "$abora_dir/installed-base.nix"; do
        [[ -f "$file" ]] || continue
        sed -i \
            -e "s|\"${bad_store}\"|./mango/config.conf|g" \
            -e "s|${bad_store}|./mango/config.conf|g" \
            -e 's|../../assets/mango/config\.conf|./mango/config.conf|g' \
            -e 's|../../../assets/mango/config\.conf|./mango/config.conf|g' \
            "$file"
    done

    if [[ -d "$abora_dir/desktops" ]]; then
        while IFS= read -r -d '' file; do
            sed -i \
                -e "s|\"${bad_store}\"|../mango/config.conf|g" \
                -e "s|${bad_store}|../mango/config.conf|g" \
                -e 's|../../assets/mango/config\.conf|../mango/config.conf|g' \
                -e 's|../../../assets/mango/config\.conf|../mango/config.conf|g' \
                "$file"
        done < <(
            grep -RIlZ \
                -e "$bad_store" \
                -e '../../assets/mango/config.conf' \
                -e '../../../assets/mango/config.conf' \
                "$abora_dir/desktops" 2>/dev/null || true
        )
    fi
}

sync_abora_files() {
    local effective_ref="$1"
    local abora_dir="$config_dir/abora"
    local upstream_background="$upstream_dir/assets/bootloader/background.png"
    local upstream_limine_background="$upstream_dir/assets/bootloader/limine-background.png"
    local upstream_theme="$upstream_dir/assets/bootloader/theme.txt"
    local limine_source=""

    if ! command -v git >/dev/null 2>&1; then
        abora_error "The git command is required to fetch the latest Abora files."
        return 1
    fi

    if [[ -d "$upstream_dir/.git" ]]; then
        abora_info "Fetching latest Abora files (${effective_ref})"
        if ! git -C "$upstream_dir" fetch --depth=1 origin "$effective_ref" 2>/dev/null; then
            abora_warn "Fetch from origin failed."
            try_fresh_clone "$effective_ref" || return 1
        else
            if ! git -C "$upstream_dir" reset --hard FETCH_HEAD >/dev/null; then
                abora_warn "Reset to FETCH_HEAD failed — upstream cache may be corrupt."
                try_fresh_clone "$effective_ref" || return 1
            fi
        fi
    else
        abora_info "Cloning Abora files (${effective_ref})"
        rm -rf "$upstream_dir"
        if ! git clone --depth=1 --branch "$effective_ref" "$repo_git_url" "$upstream_dir"; then
            abora_error "Failed to clone ${repo_git_url} at ${effective_ref}."
            abora_error "Check your internet connection and try again."
            return 1
        fi
    fi

    mkdir -p "$abora_dir/plymouth" "$abora_dir/bootloader" "$abora_dir/effects" "$abora_dir/mango"
    copy_upstream_file "$upstream_dir/VERSION" "$abora_dir/VERSION"
    copy_upstream_file "$upstream_dir/nix/modules/abora-options.nix" "$abora_dir/abora-options.nix"
    rm -rf "$abora_dir/desktops"
    cp -R "$upstream_dir/nix/modules/desktops" "$abora_dir/desktops"
    copy_upstream_file "$upstream_dir/nix/modules/anix.nix" "$abora_dir/anix-module.nix"
    copy_upstream_file "$upstream_dir/scripts/abora-ui.sh" "$abora_dir/ui.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-config.sh" "$abora_dir/config.sh"
    copy_upstream_file "$upstream_dir/scripts/abora.sh" "$abora_dir/abora.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-desktop.sh" "$abora_dir/desktop.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-doctor.sh" "$abora_dir/doctor.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-recovery.sh" "$abora_dir/recovery.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-welcome.sh" "$abora_dir/welcome.sh"
    copy_upstream_file "$upstream_dir/scripts/anix.sh" "$abora_dir/anix.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-app-catalog.sh" "$abora_dir/app-catalog.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-apps.sh" "$abora_dir/apps.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-support-report.sh" "$abora_dir/support-report.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-hardware-test.sh" "$abora_dir/hardware-test.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-repair-flake-purity.sh" "$abora_dir/repair-flake-purity.sh"
    copy_first_existing_upstream_file \
        "$abora_dir/default-wallpaper.png" \
        "$upstream_dir/assets/wallpapers/collection/Daytime-MNT.jpg" \
        "$upstream_dir/assets/wallpapers/collection/bluehorizon.png" \
        "$upstream_dir/assets/wallpapers/collection/astronautwallpaper.png"
    copy_upstream_file "$upstream_dir/scripts/abora-desktop-profiles.sh" "$abora_dir/desktop-profiles.sh"
    copy_upstream_file "$upstream_dir/nix/modules/installed-base.nix" "$abora_dir/installed-base.nix"
    copy_upstream_file "$upstream_dir/scripts/abora-session-setup.sh" "$abora_dir/session-setup.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-theme-sync.sh" "$abora_dir/theme-sync.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-update.sh" "$abora_dir/update.sh"
    copy_upstream_file "$upstream_dir/assets/abora-title.txt" "$abora_dir/title.txt"
    copy_upstream_file "$upstream_dir/assets/fastfetch-logo.txt" "$abora_dir/fastfetch-logo.txt"
    copy_upstream_file "$upstream_dir/assets/fastfetch-config.jsonc" "$abora_dir/fastfetch-config.jsonc"
    copy_first_existing_upstream_file \
        "$abora_dir/effects/v3StartingAbora.mp3" \
        "$upstream_dir/assets/Effects/v3StartingAbora.mp3" \
        "$upstream_dir/assets/Effects/LaunchingAbora.mp3"
    copy_upstream_file "$upstream_dir/assets/plymouth/abora.plymouth" "$abora_dir/plymouth/abora.plymouth"
    copy_upstream_file "$upstream_dir/assets/plymouth/abora.script" "$abora_dir/plymouth/abora.script"
    install_mango_config_asset
    rewrite_installed_mango_config_paths

    if [[ ! -f "$upstream_background" || ! -f "$upstream_theme" ]]; then
        abora_error "The latest Abora bootloader assets are incomplete."
        return 1
    fi

    limine_source="$upstream_background"
    if [[ -f "$upstream_limine_background" ]]; then
        limine_source="$upstream_limine_background"
    fi

    install -Dm0644 "$upstream_background" "$abora_dir/bootloader/background.png"
    install -Dm0644 "$limine_source" "$abora_dir/bootloader/limine-background.png"
    install -Dm0644 "$upstream_theme" "$abora_dir/bootloader/theme.txt"
    mkdir -p "$abora_dir/wallpapers" "$abora_dir/themes" "$abora_dir/pkgs"
    cp "$upstream_dir/assets/wallpapers/collection/"* "$abora_dir/wallpapers/"
    cp "$upstream_dir/assets/wallpaper-themes/"* "$abora_dir/themes/"
    copy_upstream_file "$upstream_dir/nix/pkgs/mango.nix" "$abora_dir/pkgs/mango.nix"
    copy_upstream_file "$upstream_dir/nix/pkgs/modularity.nix" "$abora_dir/pkgs/modularity.nix"

    if [[ ! -f "$abora_dir/apps.list" ]]; then
        : > "$abora_dir/apps.list"
    fi

    if [[ ! -f "$abora_dir/apps.nix" ]]; then
        cat > "$abora_dir/apps.nix" <<'EOF'
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
  ];
}
EOF
    fi
}

# ── Flake layout check ────────────────────────────────────────────────────────

write_installed_flake() {
    local flake_file="$config_dir/flake.nix"

    cat > "$flake_file" <<EOF
{
  description = "Abora installed system";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations = {
      "${flake_config_name}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
        ];
      };
    };
  };
}
EOF
}

repair_flake_layout_if_needed() {
    local flake_file="$config_dir/flake.nix"
    local abora_dir="$config_dir/abora"
    local needs_repair=0

    if [[ ! -f "$flake_file" ]]; then
        return 0
    fi

    if grep -Eq '(/nix/store|../../nix|../../../nix|nix/pkgs/mango\.nix|nix/pkgs/modularity\.nix)' "$flake_file"; then
        needs_repair=1
    elif [[ -d "$abora_dir" ]] && grep -RIEq '(/nix/store|(\.\./){2,}assets/mango/config\.conf|(\.\./){2,}nix/|nix/(pkgs|modules)/(mango|modularity)\.nix)' "$abora_dir"; then
        needs_repair=1
    elif ! nix --extra-experimental-features "nix-command flakes" \
        eval --no-write-lock-file "$config_dir#nixosConfigurations.${flake_config_name}.config.system.name" \
        >/dev/null 2>&1; then
        needs_repair=1
    fi

    if [[ "$needs_repair" -eq 1 ]]; then
        abora_warn "Repairing the installed flake/module layout for pure evaluation."
        cp -f "$flake_file" "${flake_file}.abora-backup" 2>/dev/null || true
        write_installed_flake
    fi
}

ensure_flake_layout() {
    local flake_file="$config_dir/flake.nix"
    local repair_script="$config_dir/abora/repair-flake-purity.sh"

    if [[ ! -f "$flake_file" ]]; then
        abora_warn "No flake.nix found in $config_dir — creating a flake-native Abora layout."
        write_installed_flake
    fi

    if [[ ! -f "$config_dir/abora-local.nix" ]]; then
        abora_error "Missing $config_dir/abora-local.nix."
        abora_error "Reinstall from the current Abora ISO or restore the flake-native local module."
        return 1
    fi

    if [[ -f "$repair_script" ]]; then
        bash "$repair_script" || {
            abora_error "Abora could not repair known flake-purity issues."
            return 1
        }
    fi

    repair_flake_layout_if_needed
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────

if ! command -v nix >/dev/null 2>&1; then
    abora_error "The nix command is not available on this system."
    exit 1
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
    abora_error "The nixos-rebuild command is not available on this system."
    exit 1
fi

if [[ ! -d "$config_dir" ]]; then
    abora_error "NixOS config directory not found: $config_dir"
    exit 1
fi

# ── Command routing ───────────────────────────────────────────────────────────

case "$command_name" in
    nixos)
        case "${1:-}" in
            update | upgrade)
                command_name="update"
                shift
                ;;
            rollback)
                command_name="rollback"
                shift
                ;;
            channel)
                shift
                handle_channel_command "$@"
                exit 0
                ;;
            "" | help | -h | --help)
                usage
                exit 0
                ;;
            *)
                abora_error "Unknown nixos command: $1"
                usage >&2
                exit 1
                ;;
        esac
        ;;
esac

if [[ "$#" -gt 0 ]]; then
    abora_error "This command does not take extra arguments yet."
    usage >&2
    exit 1
fi

# Re-exec as root, forwarding channel env vars too.
if [[ "$(id -u)" -ne 0 ]]; then
    run_as_root env \
        ABORA_UPDATE_COMMAND="$command_name" \
        ABORA_SYSTEM_CONFIG="$config_dir" \
        ABORA_REPO_GIT_URL="$repo_git_url" \
        ABORA_REPO_REF="$repo_ref" \
        ABORA_UPSTREAM_DIR="$upstream_dir" \
        ABORA_FLAKE_CONFIG_NAME="$flake_config_name" \
        ABORA_UI_LIB="$ui_lib" \
        bash "$script_self" "$@"
    exit 0
fi

# ── Rollback ──────────────────────────────────────────────────────────────────

if [[ "$command_name" == "rollback" ]]; then
    abora_banner "System Rollback" "Reverting to the previous system generation."
    abora_step "Rolling back to the previous generation"
    printf '\n'
    nixos-rebuild switch --rollback
    printf '\n'
    abora_success "Rollback complete."
    printf '\n'
    exit 0
fi

# ── Update ────────────────────────────────────────────────────────────────────

channel="$(read_channel)"
effective_ref="$(resolve_channel_ref "$channel")"

abora_banner "System Update" "Channel: ${channel}  ·  Ref: ${effective_ref}"

if [[ -x "$config_dir/abora/anix.sh" ]]; then
    if confirm "Save a local ANIX snapshot before updating?"; then
        env ANIX_SYSTEM_CONFIG="$config_dir" ANIX_FLAKE_CONFIG_NAME="$flake_config_name" bash "$config_dir/abora/anix.sh" save "anix: snapshot before Abora update" || {
            abora_warn "Snapshot failed or was cancelled; continuing with update."
            printf '\n'
        }
    fi
fi

sync_abora_files "$effective_ref" || {
    abora_error "Abora could not fetch the latest project files."
    exit 1
}
abora_success "Abora files synced."
printf '\n'

maybe_reexec_synced_updater

ensure_flake_layout || {
    abora_error "Abora could not prepare a flake-native system update."
    exit 1
}

abora_step "Updating flake inputs"
printf '\n'
nix --extra-experimental-features "nix-command flakes" flake update --flake "$config_dir"
printf '\n'

if git -C "$config_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$config_dir" add \
        abora/mango/config.conf \
        abora/abora-options.nix \
        abora/installed-base.nix \
        abora/desktops/mangowm.nix \
        abora/ \
        2>/dev/null || true
fi

abora_step "Rebuilding Abora from $config_dir"
printf '\n'
nixos-rebuild switch --flake "$config_dir#${flake_config_name}"
printf '\n'

abora_success "Abora is up to date."
printf '\n'
