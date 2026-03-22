#!/usr/bin/env bash
set -euo pipefail

disk=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
keyboard_value="us"
user_password_hash=""
efi_part=""
root_part=""

title_file="/etc/abora/title.txt"

BLUE='\033[38;5;33m'
MAGENTA='\033[38;5;207m'
WHITE='\033[1;37m'
DIM='\033[38;5;245m'
GREEN='\033[38;5;84m'
RED='\033[38;5;203m'
NC='\033[0m'
menu_result=""
prompt_result=""

clear_screen() {
    clear || printf '\033c'
}

show_header() {
    clear_screen

    if [[ -f "$title_file" ]]; then
        printf '%b' "$WHITE"
        cat "$title_file"
        printf '%b' "$NC"
    fi

    printf '\n'
    printf '%bAbora OS installer%b\n' "$WHITE" "$NC"
    printf '%bLet'\''s set up your machine...%b\n' "$DIM" "$NC"
    printf '\n'
}

info() {
    printf '%b[*] %s%b\n' "$BLUE" "$1" "$NC"
}

success() {
    printf '%b[ok] %s%b\n' "$GREEN" "$1" "$NC"
}

error_msg() {
    printf '%b[x] %s%b\n' "$RED" "$1" "$NC" >&2
}

pause_prompt() {
    printf '\n'
    read -r -p "Press ENTER to continue..."
}

read_key() {
    local key=""
    IFS= read -rsn1 key || true
    if [[ "$key" == $'\033' ]]; then
        local rest=""
        IFS= read -rsn2 -t 0.05 rest || true
        key+="$rest"
    fi
    printf '%s' "$key"
}

menu_choose() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local key=""
    local i=""

    while true; do
        show_header
        printf '%b%s%b\n' "$BLUE" "$prompt" "$NC"
        printf '\n'

        for i in "${!options[@]}"; do
            if [[ "$i" -eq "$selected" ]]; then
                printf '%b› %s%b\n' "$MAGENTA" "${options[$i]}" "$NC"
            else
                printf '  %s\n' "${options[$i]}"
            fi
        done

        printf '\n'
        printf '%b<↑↓> navigate • enter submit%b\n' "$DIM" "$NC"

        key="$(read_key)"
        case "$key" in
            $'\033[A')
                if [[ "$selected" -gt 0 ]]; then
                    selected=$((selected - 1))
                else
                    selected=$((${#options[@]} - 1))
                fi
                ;;
            $'\033[B')
                if [[ "$selected" -lt $((${#options[@]} - 1)) ]]; then
                    selected=$((selected + 1))
                else
                    selected=0
                fi
                ;;
            "")
                menu_result="$selected"
                return 0
                ;;
        esac
    done
}

prompt_input() {
    local prompt="$1"
    local default_value="${2:-}"
    local input=""

    while true; do
        show_header
        printf '%b%s%b\n\n' "$BLUE" "$prompt" "$NC"
        if [[ -n "$default_value" ]]; then
            read -r -p "> [${default_value}] " input
            prompt_result="${input:-$default_value}"
        else
            read -r -p "> " input
            prompt_result="$input"
        fi
        return 0
    done
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error_msg "This installer must run as root."
        exit 1
    fi
}

load_keyboard_layout() {
    if command -v loadkeys >/dev/null 2>&1; then
        loadkeys "$keyboard_value" >/dev/null 2>&1 || true
    fi
}

pick_keyboard_layout() {
    local labels=(
        "English (US)"
        "English (UK)"
        "German"
        "French"
        "Spanish"
    )
    local values=( "us" "uk" "de" "fr" "es" )
    local choice=""

    menu_choose "Select keyboard layout" "${labels[@]}"
    keyboard_value="${values[$menu_result]}"
    load_keyboard_layout
}

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            model = ""
            for (i = 3; i < NF; i++) {
                model = model (model ? " " : "") $i
            }
            if (model == "") {
                model = "Unknown model"
            }
            print $1 "|" $2 "|" model
        }
    '
}

prompt_disk() {
    local entries=()
    local labels=()
    local paths=()
    local choice=""
    local name=""
    local size=""
    local model=""
    local entry=""

    mapfile -t entries < <(collect_disks)
    if [[ "${#entries[@]}" -eq 0 ]]; then
        error_msg "No installable disks were found."
        return 1
    fi

    for entry in "${entries[@]}"; do
        IFS='|' read -r name size model <<<"$entry"
        labels+=( "/dev/${name}  ${size}  ${model}" )
        paths+=( "/dev/${name}" )
    done

    menu_choose "Select install target" "${labels[@]}"
    disk="${paths[$menu_result]}"
}

prompt_hostname() {
    local input=""

    while true; do
        prompt_input "Choose a hostname" "$hostname_value"
        input="$prompt_result"
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
        prompt_input "Choose a username" "$username_value"
        input="$prompt_result"
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
    prompt_input "Choose a timezone" "$timezone_value"
    input="$prompt_result"
    timezone_value="${input:-$timezone_value}"
}

prompt_password() {
    local first=""
    local second=""

    while true; do
        show_header
        printf '%bSet password for %s%b\n\n' "$BLUE" "$username_value" "$NC"

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
    local choice=""

    show_header
    printf '%bInstall summary%b\n\n' "$BLUE" "$NC"
    printf '  Disk:      %s\n' "$disk"
    printf '  Keyboard:  %s\n' "$keyboard_value"
    printf '  Hostname:  %s\n' "$hostname_value"
    printf '  User:      %s\n' "$username_value"
    printf '  Timezone:  %s\n' "$timezone_value"
    printf '\n'
    printf 'The installer will wipe the selected disk and create:\n'
    printf '  - 1 MiB BIOS boot partition\n'
    printf '  - 512 MiB EFI system partition\n'
    printf '  - ext4 root partition using the rest of the disk\n'
    printf '\n'

    menu_choose "Continue with installation?" "Install now" "Cancel"
    [[ "$menu_result" == "0" ]]
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
  boot.loader.efi.canTouchEfiVariables = false;

  networking.hostName = "${hostname_value}";
  networking.networkmanager.enable = true;

  time.timeZone = "${timezone_value}";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "${keyboard_value}";

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
    if ! nixos-install --root /mnt --no-root-passwd; then
        error_msg "Installation failed. Review the output above."
        return 1
    fi
    success "Installation complete"
}

finish_screen() {
    show_header
    success "Abora OS is installed."
    printf '\n'
    printf 'Next:\n'
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

    pick_keyboard_layout
    prompt_disk || return 1
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
    install_system || {
        pause_prompt
        return 1
    }
    finish_screen
}

main "$@"
