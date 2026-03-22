#!/usr/bin/env bash
set -euo pipefail

disk=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
user_password_hash=""
efi_part=""
root_part=""

clear_screen() {
    clear || printf '\033c'
}

show_header() {
    clear_screen

    if [[ -f /etc/abora/fastfetch-logo.txt ]]; then
        cat /etc/abora/fastfetch-logo.txt
    fi

    printf '\n'
    printf 'Abora OS Installer\n'
    printf 'Minimal boot-first install flow\n'
    printf '\n'
}

info() {
    printf '[*] %s\n' "$1"
}

success() {
    printf '[ok] %s\n' "$1"
}

error_msg() {
    printf '[x] %s\n' "$1" >&2
}

pause_prompt() {
    printf '\n'
    read -r -p "Press ENTER to continue..."
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error_msg "This installer must run as root."
        exit 1
    fi
}

list_disks() {
    lsblk -d -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '$4 == "disk" { printf "  /dev/%s  %s  %s\n", $1, $2, substr($0, index($0, $3)) }'
}

prompt_disk() {
    local input=""

    while true; do
        show_header
        info "Available disks"
        printf '\n'
        list_disks
        printf '\n'
        read -r -p "Install target disk (example: sda or /dev/nvme0n1): " input
        [[ -n "$input" ]] || continue

        if [[ "$input" != /dev/* ]]; then
            input="/dev/$input"
        fi

        if [[ -b "$input" ]]; then
            disk="$input"
            return
        fi

        error_msg "Disk not found: $input"
        pause_prompt
    done
}

prompt_hostname() {
    local input=""

    while true; do
        show_header
        read -r -p "Hostname [${hostname_value}]: " input
        input="${input:-$hostname_value}"

        if [[ "$input" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
            hostname_value="$input"
            return
        fi

        error_msg "Hostname must use letters, numbers, or hyphens."
        pause_prompt
    done
}

prompt_username() {
    local input=""

    while true; do
        show_header
        read -r -p "Username [${username_value}]: " input
        input="${input:-$username_value}"

        if [[ "$input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            username_value="$input"
            return
        fi

        error_msg "Username must start with a lowercase letter or underscore."
        pause_prompt
    done
}

prompt_timezone() {
    local input=""

    while true; do
        show_header
        read -r -p "Timezone [${timezone_value}]: " input
        input="${input:-$timezone_value}"

        if [[ -n "$input" ]]; then
            timezone_value="$input"
            return
        fi
    done
}

prompt_password() {
    local first=""
    local second=""

    while true; do
        show_header
        printf 'Set password for %s\n\n' "$username_value"

        read -r -s -p "Password: " first
        printf '\n'
        read -r -s -p "Confirm password: " second
        printf '\n'

        if [[ -z "$first" ]]; then
            error_msg "Password cannot be empty."
            pause_prompt
            continue
        fi

        if [[ "$first" != "$second" ]]; then
            error_msg "Passwords did not match."
            pause_prompt
            continue
        fi

        user_password_hash="$(mkpasswd -m yescrypt "$first")"
        unset first second
        return
    done
}

confirm_install() {
    local input=""

    show_header
    printf 'Install summary\n\n'
    printf '  Disk:      %s\n' "$disk"
    printf '  Hostname:  %s\n' "$hostname_value"
    printf '  User:      %s\n' "$username_value"
    printf '  Timezone:  %s\n' "$timezone_value"
    printf '\n'
    printf 'The installer will wipe the selected disk and create:\n'
    printf '  - 1 MiB BIOS boot partition\n'
    printf '  - 512 MiB EFI system partition\n'
    printf '  - ext4 root partition using the rest of the disk\n'
    printf '\n'
    read -r -p "Type WIPE to continue, or anything else to cancel: " input
    [[ "$input" == "WIPE" ]]
}

disk_part_suffix() {
    case "$disk" in
        *nvme*|*mmcblk*|*loop*)
            printf 'p'
            ;;
        *)
            printf ''
            ;;
    esac
}

partition_disk() {
    local suffix=""

    info "Partitioning ${disk}"
    umount -R /mnt 2>/dev/null || true
    wipefs -af "$disk" >/dev/null
    parted -s "$disk" mklabel gpt
    parted -s "$disk" unit MiB mkpart BIOSBOOT 1 3
    parted -s "$disk" set 1 bios_grub on
    parted -s "$disk" unit MiB mkpart ESP fat32 3 515
    parted -s "$disk" set 2 esp on
    parted -s "$disk" unit MiB mkpart primary ext4 515 100%
    partprobe "$disk"
    udevadm settle

    suffix="$(disk_part_suffix)"
    efi_part="${disk}${suffix}2"
    root_part="${disk}${suffix}3"

    mkfs.vfat -F 32 -n ABORA_EFI "$efi_part" >/dev/null
    mkfs.ext4 -F -L ABORA_ROOT "$root_part" >/dev/null
    success "Disk prepared"
}

mount_target() {
    info "Mounting target filesystem"
    mkdir -p /mnt
    mount "$root_part" /mnt
    mkdir -p /mnt/boot
    mount "$efi_part" /mnt/boot
    success "Target mounted at /mnt"
}

generate_config() {
    info "Generating NixOS configuration"
    nixos-generate-config --root /mnt >/dev/null

    cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.grub = {
    enable = true;
    devices = [ "${disk}" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "${hostname_value}";
  networking.networkmanager.enable = true;

  time.timeZone = "${timezone_value}";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users."${username_value}" = {
    isNormalUser = true;
    description = "Abora User";
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "${user_password_hash}";
  };

  security.sudo.wheelNeedsPassword = true;

  environment.systemPackages = with pkgs; [
    curl
    fastfetch
    git
    htop
    wget
  ];

  services.openssh.enable = true;

  system.stateVersion = "24.11";
}
EOF
    success "Configuration written"
}

install_system() {
    info "Installing Abora OS"
    nixos-install --root /mnt --no-root-passwd
    success "Installation complete"
}

finish_screen() {
    show_header
    success "Abora OS is installed."
    printf '\n'
    printf 'What to do next:\n'
    printf '  1. Remove the ISO from the VM or USB boot order.\n'
    printf '  2. Reboot the machine.\n'
    printf '\n'
    read -r -p "Press ENTER to return to the boot menu..."
}

main() {
    require_root
    command -v mkpasswd >/dev/null 2>&1 || {
        error_msg "mkpasswd is required but missing."
        exit 1
    }

    prompt_disk
    prompt_hostname
    prompt_username
    prompt_timezone
    prompt_password

    if ! confirm_install; then
        info "Install cancelled."
        return 0
    fi

    show_header
    partition_disk
    mount_target
    generate_config
    install_system
    finish_screen
}

main "$@"
