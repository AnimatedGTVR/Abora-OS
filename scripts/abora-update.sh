#!/usr/bin/env bash
set -euo pipefail

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
  update
  upgrade
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

sync_desktop_label() {
    case "$1" in
        gnome)
            desktop_label="GNOME"
            desktop_variant_id="gnome"
            ;;
        plasma)
            desktop_label="Plasma"
            desktop_variant_id="plasma"
            ;;
        hyprland)
            desktop_label="Hyprland"
            desktop_variant_id="hyprland"
            ;;
        xfce)
            desktop_label="XFCE"
            desktop_variant_id="xfce"
            ;;
        cinnamon)
            desktop_label="Cinnamon"
            desktop_variant_id="cinnamon"
            ;;
        mate)
            desktop_label="MATE"
            desktop_variant_id="mate"
            ;;
        budgie)
            desktop_label="Budgie"
            desktop_variant_id="budgie"
            ;;
        lxqt)
            desktop_label="LXQt"
            desktop_variant_id="lxqt"
            ;;
        pantheon)
            desktop_label="Pantheon"
            desktop_variant_id="pantheon"
            ;;
        i3)
            desktop_label="i3"
            desktop_variant_id="i3"
            ;;
        openbox)
            desktop_label="Openbox"
            desktop_variant_id="openbox"
            ;;
        *)
            desktop_label="GNOME"
            desktop_variant_id="gnome"
            ;;
    esac
}

detect_desktop_profile() {
    local file="$1"

    if grep -q 'programs\.hyprland = {' "$file" || grep -q 'defaultSession = "hyprland-uwsm";' "$file"; then
        printf 'hyprland\n'
    elif grep -q 'services\.desktopManager\.plasma6\.enable = true;' "$file"; then
        printf 'plasma\n'
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
    elif grep -q 'windowManager\.i3\.enable = true;' "$file"; then
        printf 'i3\n'
    elif grep -q 'windowManager\.openbox\.enable = true;' "$file"; then
        printf 'openbox\n'
    else
        printf 'gnome\n'
    fi
}

desktop_config_block() {
    local desktop_profile="$1"
    local xkb_layout_value="$2"
    local username_value="$3"

    case "$desktop_profile" in
        gnome)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "${username_value}";
  services.displayManager.defaultSession = "gnome";
  services.gnome.gnome-keyring.enable = true;
EOF
            ;;
        plasma)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "plasma";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
EOF
            ;;
        hyprland)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "hyprland-uwsm";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
EOF
            ;;
        xfce)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.xfce.enable = true;
  };
  services.displayManager = {
    defaultSession = "xfce";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        cinnamon)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.cinnamon.enable = true;
  };
  services.displayManager = {
    defaultSession = "cinnamon";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        mate)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.mate.enable = true;
  };
  services.displayManager = {
    defaultSession = "mate";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        budgie)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.budgie.enable = true;
  };
  services.displayManager = {
    defaultSession = "budgie-desktop";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        lxqt)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.lxqt.enable = true;
  };
  services.displayManager = {
    defaultSession = "lxqt";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm.enable = true;
EOF
            ;;
        pantheon)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "pantheon-wayland";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.pantheon.enable = true;
EOF
            ;;
        i3)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.i3.enable = true;
  };
  services.displayManager = {
    defaultSession = "none+i3";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        openbox)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.openbox.enable = true;
  };
  services.displayManager = {
    defaultSession = "none+openbox";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
    esac
}

desktop_package_block() {
    case "$1" in
        hyprland)
            cat <<EOF
    kitty
EOF
            ;;
    esac
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
      modules = [
        ./hardware-configuration.nix
        ./abora/installed-base.nix
        ./abora-local.nix
      ];
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

    sync_desktop_label "$desktop_profile"
    desktop_block="$(desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value")"
    desktop_packages="$(desktop_package_block "$desktop_profile")"

    cat > "$target" <<EOF
{ pkgs, ... }:
{
  system.nixos.variantName = "Abora ${desktop_label} Edition";
  system.nixos.variant_id = "${desktop_variant_id}";

  boot.loader.grub = {
    enable = true;
    devices = [ "${disk_value}" ];
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
    cp "$upstream_dir/nix/modules/installed-base.nix" "$abora_dir/installed-base.nix"
    cp "$upstream_dir/scripts/abora-update.sh" "$abora_dir/update.sh"
    cp "$upstream_dir/assets/abora-title.txt" "$abora_dir/title.txt"
    cp "$upstream_dir/assets/fastfetch-logo.txt" "$abora_dir/fastfetch-logo.txt"
    cp "$upstream_dir/assets/fastfetch-config.jsonc" "$abora_dir/fastfetch-config.jsonc"
    cp "$upstream_dir/assets/plymouth/abora.plymouth" "$abora_dir/plymouth/abora.plymouth"
    cp "$upstream_dir/assets/plymouth/abora.script" "$abora_dir/plymouth/abora.script"
    cp "$upstream_dir/assets/bootloader/"* "$abora_dir/bootloader/"
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
        desktop_profile="$(detect_desktop_profile "$legacy_config")"

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
