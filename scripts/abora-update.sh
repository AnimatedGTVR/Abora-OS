#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
desktop_profiles_lib="${ABORA_DESKTOP_PROFILES_LIB:-$script_dir/abora-desktop-profiles.sh}"

if [[ ! -f "$desktop_profiles_lib" && -f /etc/abora/desktop-profiles.sh ]]; then
    desktop_profiles_lib="/etc/abora/desktop-profiles.sh"
fi

# shellcheck source=/dev/null
source "$desktop_profiles_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
command_name="${ABORA_UPDATE_COMMAND:-$(basename "$0")}"
repo_git_url="${ABORA_REPO_GIT_URL:-https://github.com/AnimatedGTVR/abora-os.git}"
repo_ref="${ABORA_REPO_REF:-main}"
upstream_dir="${ABORA_UPSTREAM_DIR:-$config_dir/.abora-upstream}"
flake_config_name="${ABORA_FLAKE_CONFIG_NAME:-abora}"

info() {
    printf '[*] %s\n' "$1"
}

error_msg() {
    printf '[x] %s\n' "$1" >&2
}

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return
    fi

    error_msg "This command needs root privileges. Run it as root or install sudo."
    exit 1
}

usage() {
    cat <<EOF
Usage:
  nixos update
  nixos upgrade
  nixos rollback
  update
  upgrade
  rollback
  abora-update
EOF
}

system_string() {
    case "$(uname -m)" in
        x86_64) printf 'x86_64-linux\n' ;;
        aarch64 | arm64) printf 'aarch64-linux\n' ;;
        *) printf '%s-linux\n' "$(uname -m)" ;;
    esac
}

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

    cat > "$target" <<EOF
{
  description = "Abora installed system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.${flake_config_name} = nixpkgs.lib.nixosSystem {
      system = "${nix_system}";
      modules =
        let
          appModule = ./abora/apps.nix;
        in
        [
          ./hardware-configuration.nix
          ./abora/installed-base.nix
          ./abora-local.nix
        ] ++ nixpkgs.lib.optional (builtins.pathExists appModule) appModule;
    };
  };
}
EOF
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
    local desktop_block=""
    local desktop_packages=""
    local desktop_label=""
    local desktop_variant_id=""

    abora_sync_desktop_label "$desktop_profile"
    desktop_block="$(desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value")"
    desktop_packages="$(desktop_package_block "$desktop_profile")"

    cat > "$target" <<EOF
{ pkgs, lib, ... }:
{
  system.nixos.variantName = "Abora ${desktop_label} Edition";
  system.nixos.variant_id = "${desktop_variant_id}";

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.limine = {
    enable = true;
    biosSupport = true;
    biosDevice = "${disk_value}";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "${hostname_value}";
  time.timeZone = "${timezone_value}";
  console.keyMap = "${keyboard_value}";

${desktop_block}
  users.users."${username_value}" = {
    isNormalUser = true;
    description = "Abora User";
    createHome = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "${user_password_hash}";
  };

  security.sudo.wheelNeedsPassword = true;

  environment.systemPackages = with pkgs; [
${desktop_packages}
  ];

  system.stateVersion = "${state_version}";
}
EOF
}

extract_setting() {
    local file="$1"
    local expression="$2"

    sed -nE "$expression" "$file" | head -n1
}

sync_abora_files() {
    local abora_dir="$config_dir/abora"
    local upstream_background="$upstream_dir/assets/bootloader/background.png"
    local upstream_limine_background="$upstream_dir/assets/bootloader/limine-background.png"
    local upstream_theme="$upstream_dir/assets/bootloader/theme.txt"
    local limine_source=""

    if ! command -v git >/dev/null 2>&1; then
        error_msg "The git command is required to fetch the latest Abora files."
        return 1
    fi

    if [[ -d "$upstream_dir/.git" ]]; then
        info "Fetching latest Abora project files"
        git -C "$upstream_dir" fetch --depth=1 origin "$repo_ref" >/dev/null 2>&1
        git -C "$upstream_dir" reset --hard FETCH_HEAD >/dev/null 2>&1
    else
        info "Cloning latest Abora project files"
        rm -rf "$upstream_dir"
        git clone --depth=1 --branch "$repo_ref" "$repo_git_url" "$upstream_dir" >/dev/null 2>&1
    fi

    mkdir -p "$abora_dir/plymouth" "$abora_dir/bootloader"
    cp "$upstream_dir/VERSION" "$abora_dir/VERSION"
    cp "$upstream_dir/scripts/abora-app-catalog.sh" "$abora_dir/app-catalog.sh"
    cp "$upstream_dir/scripts/abora-apps.sh" "$abora_dir/apps.sh"
    cp "$upstream_dir/scripts/abora-support-report.sh" "$abora_dir/support-report.sh"
    cp "$upstream_dir/scripts/abora-hardware-test.sh" "$abora_dir/hardware-test.sh"
    cp "$upstream_dir/assets/wallpapers/collection/oceandusk.png" "$abora_dir/default-wallpaper.png"
    cp "$upstream_dir/scripts/abora-desktop-profiles.sh" "$abora_dir/desktop-profiles.sh"
    cp "$upstream_dir/nix/modules/installed-base.nix" "$abora_dir/installed-base.nix"
    cp "$upstream_dir/scripts/abora-session-setup.sh" "$abora_dir/session-setup.sh"
    cp "$upstream_dir/scripts/abora-theme-sync.sh" "$abora_dir/theme-sync.sh"
    cp "$upstream_dir/scripts/abora-update.sh" "$abora_dir/update.sh"
    cp "$upstream_dir/assets/abora-title.txt" "$abora_dir/title.txt"
    cp "$upstream_dir/assets/fastfetch-logo.txt" "$abora_dir/fastfetch-logo.txt"
    cp "$upstream_dir/assets/fastfetch-config.jsonc" "$abora_dir/fastfetch-config.jsonc"
    cp "$upstream_dir/assets/plymouth/abora.plymouth" "$abora_dir/plymouth/abora.plymouth"
    cp "$upstream_dir/assets/plymouth/abora.script" "$abora_dir/plymouth/abora.script"
    if [[ ! -f "$upstream_background" || ! -f "$upstream_theme" ]]; then
        error_msg "The latest Abora bootloader assets are incomplete."
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

bootstrap_legacy_flake() {
    local legacy_config="$config_dir/configuration.nix"
    local local_module="$config_dir/abora-local.nix"
    local flake_file="$config_dir/flake.nix"
    local hostname_value=""
    local timezone_value=""
    local keyboard_value=""
    local xkb_layout_value=""
    local username_value=""
    local user_password_hash=""
    local disk_value=""
    local state_version=""
    local desktop_profile=""

    if [[ ! -f "$legacy_config" && ! -f "$flake_file" ]]; then
        error_msg "No flake.nix or configuration.nix found in $config_dir."
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
            error_msg "Could not migrate the legacy Abora install automatically."
            error_msg "Missing values: user=${username_value:-missing} passwordHash=${user_password_hash:+set}${user_password_hash:-missing} disk=${disk_value:-missing}"
            return 1
        fi

        info "Migrating legacy Abora install to flake layout"
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
        info "Created $local_module"
    fi

    write_flake_file "$flake_file" "$(system_string)"
    info "Wrote $flake_file"
}

if ! command -v nix >/dev/null 2>&1; then
    error_msg "The nix command is not available on this system."
    exit 1
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
    error_msg "The nixos-rebuild command is not available on this system."
    exit 1
fi

if [[ ! -d "$config_dir" ]]; then
    error_msg "NixOS config directory not found: $config_dir"
    exit 1
fi

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
            "" | help | -h | --help)
                usage
                exit 0
                ;;
            *)
                error_msg "Unknown nixos command: $1"
                usage >&2
                exit 1
                ;;
        esac
        ;;
esac

if [[ "$#" -gt 0 ]]; then
    error_msg "This command does not take extra arguments yet."
    usage >&2
    exit 1
fi

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

if [[ "$command_name" == "rollback" ]]; then
    info "Rolling Abora back to the previous system generation"
    nixos-rebuild switch --rollback
    exit 0
fi

sync_abora_files || {
    error_msg "Abora could not fetch the latest project files."
    exit 1
}

bootstrap_legacy_flake || {
    error_msg "Abora could not prepare a flake-based system update."
    error_msg "Reinstall from the latest Abora ISO if this system predates the flake update path."
    exit 1
}

info "Updating Abora from the latest local flake"
nix --extra-experimental-features "nix-command flakes" flake update --flake "$config_dir"

info "Rebuilding Abora from $config_dir"
nixos-rebuild switch --flake "$config_dir#${flake_config_name}"
