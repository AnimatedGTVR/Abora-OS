#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
desktop_profiles_lib="${ABORA_DESKTOP_PROFILES_LIB:-$script_dir/abora-desktop-profiles.sh}"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$desktop_profiles_lib" && -f /etc/abora/desktop-profiles.sh ]]; then
    desktop_profiles_lib="/etc/abora/desktop-profiles.sh"
fi

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

# shellcheck source=/dev/null
source "$desktop_profiles_lib"
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

system_string() {
    case "$(uname -m)" in
        x86_64) printf 'x86_64-linux\n' ;;
        aarch64 | arm64) printf 'aarch64-linux\n' ;;
        *) printf '%s-linux\n' "$(uname -m)" ;;
    esac
}

# ── Config writers ────────────────────────────────────────────────────────────

desktop_config_block() {
    local desktop_profile="$1"
    local xkb_layout_value="$2"
    local username_value="$3"

    abora_desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value"
}

desktop_package_block() {
    abora_desktop_package_block "$1"
}

write_flake_file() {
    local target="$1"
    local nix_system="$2"

    cat > "$target" <<'EOF'
{
  description = "Abora installed system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      system = "__ABORA_NIX_SYSTEM__";
      baseModules =
        let
          appModule = ./abora/apps.nix;
          anixLayer = ./anix.nix;
        in
        [
          ./hardware-configuration.nix
          ./abora/installed-base.nix
          ./abora/abora-options.nix
          ./abora/anix-module.nix
          ./abora-local.nix
        ] ++ lib.optional (builtins.pathExists appModule) appModule
          ++ lib.optional (builtins.pathExists anixLayer) anixLayer;
      mkProfile = name: extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = baseModules ++ extraModules ++ [
          { system.nixos.variantName = lib.mkOverride 800 "Abora ${name} Profile"; }
        ];
      };
    in {
    nixosConfigurations.__ABORA_FLAKE_CONFIG_NAME__ = mkProfile "Stable" [];
    nixosConfigurations.stable = mkProfile "Stable" [];
    nixosConfigurations.minimal = mkProfile "Minimal" [
      { abora.desktop = lib.mkForce "none"; }
    ];
    nixosConfigurations.gaming = mkProfile "Gaming" [
      ({ pkgs, ... }: {
        abora.desktop = lib.mkForce "gnome";
        environment.systemPackages = with pkgs; [ mangohud prismlauncher lutris ];
        programs.steam.enable = lib.mkDefault true;
      })
    ];
    nixosConfigurations.creator = mkProfile "Creator" [
      ({ pkgs, ... }: {
        abora.desktop = lib.mkForce "gnome";
        environment.systemPackages = with pkgs; [ blender gimp inkscape krita obs-studio audacity ];
      })
    ];
    nixosConfigurations.developer = mkProfile "Developer" [
      ({ pkgs, ... }: {
        abora.desktop = lib.mkForce "gnome";
        environment.systemPackages = with pkgs; [ git gh vscode direnv nixfmt-rfc-style shellcheck ];
      })
    ];
  };
}
EOF

    sed -i \
        -e "s|__ABORA_NIX_SYSTEM__|${nix_system}|g" \
        -e "s|__ABORA_FLAKE_CONFIG_NAME__|${flake_config_name}|g" \
        "$target"
}

write_local_module() {
    local target="$1"
    local hostname_value="$2"
    local timezone_value="$3"
    local keyboard_value="$4"
    local xkb_layout_value="$5"
    local username_value="$6"
    local user_password_hash="$7"
    local disk_value="$8"
    local state_version="$9"
    local desktop_profile="${10}"

    cat > "$target" <<EOF
# ── Abora OS — system configuration ──────────────────────────────────────────
# Edit these values to personalise your system, then run 'update' to apply.
# Do not change abora.disk or abora.stateVersion after the first install.
{ ... }:
{
  # ── Identity ──────────────────────────────────────────────────────────────
  abora.hostname         = "${hostname_value}";
  abora.timezone         = "${timezone_value}";  # e.g. America/New_York, Europe/London
  abora.keyboard.console = "${keyboard_value}";  # TTY keymap
  abora.keyboard.xkb     = "${xkb_layout_value}"; # graphical keyboard layout

  # ── User ──────────────────────────────────────────────────────────────────
  abora.user.name           = "${username_value}";
  abora.user.hashedPassword = "${user_password_hash}"; # generate with: mkpasswd

  # ── Desktop ───────────────────────────────────────────────────────────────
  # Options: none gnome plasma hyprland sway niri xfce cinnamon mate budgie
  #          lxqt pantheon lxde i3 awesome openbox
  #          river qtile bspwm fluxbox icewm herbstluftwm cosmic
  abora.desktop = "${desktop_profile}";

  # ── Hardware ──────────────────────────────────────────────────────────────
  abora.disk         = "${disk_value}";    # install disk for the bootloader
  abora.stateVersion = "${state_version}"; # set at install time — do not change
}
EOF
}

extract_setting() {
    local file="$1"
    local expression="$2"

    sed -nE "$expression" "$file" | head -n1
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

# ── File sync ─────────────────────────────────────────────────────────────────

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
        if ! git -C "$upstream_dir" fetch --depth=1 origin "$effective_ref"; then
            abora_error "Failed to fetch ${effective_ref} from ${repo_git_url}."
            return 1
        fi
        if ! git -C "$upstream_dir" reset --hard FETCH_HEAD >/dev/null; then
            abora_error "Failed to reset the upstream checkout to ${effective_ref}."
            return 1
        fi
    else
        abora_info "Cloning Abora files (${effective_ref})"
        rm -rf "$upstream_dir"
        if ! git clone --depth=1 --branch "$effective_ref" "$repo_git_url" "$upstream_dir"; then
            abora_error "Failed to clone ${repo_git_url} at ${effective_ref}."
            return 1
        fi
    fi

    mkdir -p "$abora_dir/plymouth" "$abora_dir/bootloader" "$abora_dir/effects"
    copy_upstream_file "$upstream_dir/VERSION" "$abora_dir/VERSION"
    copy_upstream_file "$upstream_dir/nix/modules/abora-options.nix" "$abora_dir/abora-options.nix"
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
    mkdir -p "$abora_dir/wallpapers" "$abora_dir/themes"
    cp "$upstream_dir/assets/wallpapers/collection/"* "$abora_dir/wallpapers/"
    cp "$upstream_dir/assets/wallpaper-themes/"* "$abora_dir/themes/"

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

# ── Legacy migration ──────────────────────────────────────────────────────────

bootstrap_legacy_flake() {
    local legacy_config="$config_dir/configuration.nix"
    local local_module="$config_dir/abora-local.nix"
    local flake_file="$config_dir/flake.nix"
    local hostname_value="" timezone_value="" keyboard_value="" xkb_layout_value=""
    local username_value="" user_password_hash="" disk_value="" state_version=""
    local desktop_profile=""

    if [[ ! -f "$legacy_config" && ! -f "$flake_file" ]]; then
        abora_error "No flake.nix or configuration.nix found in $config_dir."
        return 1
    fi

    if [[ ! -f "$local_module" ]]; then
        hostname_value="$(extract_setting "$legacy_config" 's/^[[:space:]]*networking\.hostName = "([^"]+)";/\1/p')"
        timezone_value="$(extract_setting "$legacy_config" 's/^[[:space:]]*time\.timeZone = "([^"]+)";/\1/p')"
        keyboard_value="$(extract_setting "$legacy_config" 's/^[[:space:]]*console\.keyMap = "([^"]+)";/\1/p')"
        xkb_layout_value="$(extract_setting "$legacy_config" 's/^[[:space:]]*xkb\.layout = "([^"]+)";/\1/p')"
        username_value="$(extract_setting "$legacy_config" 's/^[[:space:]]*users\.users\."([^"]+)".*/\1/p')"
        user_password_hash="$(extract_setting "$legacy_config" 's/^[[:space:]]*hashedPassword = "([^"]+)";/\1/p')"
        disk_value="$(extract_setting "$legacy_config" 's/^[[:space:]]*devices = \[ "([^"]+)" \];/\1/p')"
        state_version="$(extract_setting "$legacy_config" 's/^[[:space:]]*system\.stateVersion = "([^"]+)";/\1/p')"
        desktop_profile="$(abora_detect_desktop_profile "$legacy_config")"

        hostname_value="${hostname_value:-$(hostname)}"
        timezone_value="${timezone_value:-UTC}"
        keyboard_value="${keyboard_value:-us}"
        xkb_layout_value="${xkb_layout_value:-$keyboard_value}"
        state_version="${state_version:-26.05}"

        if [[ -z "$username_value" || -z "$user_password_hash" || -z "$disk_value" ]]; then
            abora_error "Could not migrate the legacy Abora install automatically."
            abora_error "Missing values: user=${username_value:-missing} passwordHash=${user_password_hash:+set}${user_password_hash:-missing} disk=${disk_value:-missing}"
            return 1
        fi

        abora_info "Migrating legacy Abora install to flake layout"
        cp -f "$legacy_config" "$config_dir/configuration.legacy.nix"
        write_local_module \
            "$local_module" \
            "$hostname_value" \
            "$timezone_value" \
            "$keyboard_value" \
            "$xkb_layout_value" \
            "$username_value" \
            "$user_password_hash" \
            "$disk_value" \
            "$state_version" \
            "$desktop_profile"
        abora_info "Created $local_module"
    fi

    write_flake_file "$flake_file" "$(system_string)"
    abora_info "Wrote $flake_file"
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
        bash "$0" "$@"
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

bootstrap_legacy_flake || {
    abora_error "Abora could not prepare a flake-based system update."
    abora_error "Reinstall from the latest Abora ISO if this system predates the flake update path."
    exit 1
}

abora_step "Updating flake inputs"
printf '\n'
nix --extra-experimental-features "nix-command flakes" flake update --flake "$config_dir"
printf '\n'

abora_step "Rebuilding Abora from $config_dir"
printf '\n'
nixos-rebuild switch --flake "$config_dir#${flake_config_name}"
printf '\n'

abora_success "Abora is up to date."
printf '\n'
