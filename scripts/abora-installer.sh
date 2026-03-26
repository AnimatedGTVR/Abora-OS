#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

disk=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
keyboard_value="us"
xkb_layout_value="us"
desktop_profile="gnome"
desktop_label="GNOME"
desktop_variant_id="gnome"
user_password_hash=""
efi_part=""
root_part=""
config_log="/tmp/abora-generate-config.log"
install_log="/tmp/abora-install.log"

title_file="/etc/abora/title.txt"
version="${ABORA_VERSION:-v1.0.1}"

BLUE='\033[38;5;33m'
MAGENTA='\033[38;5;207m'
WHITE='\033[1;37m'
DIM='\033[38;5;245m'
GREEN='\033[38;5;84m'
RED='\033[38;5;203m'
NC='\033[0m'
menu_result=""
prompt_result=""
step_action="next"

clear_screen() {
    clear || printf '\033c'
}

draw_rule() {
    printf '%b' "$DIM"
    printf '────────────────────────────────────────────────────────────\n'
    printf '%b' "$NC"
}

show_header() {
    local title="${1:-Abora OS ${version} installer}"
    local subtitle="${2:-Set up your machine.}"

    clear_screen

    if [[ -f "$title_file" ]]; then
        printf '%b' "$WHITE"
        cat "$title_file"
        printf '%b' "$NC"
    fi

    printf '\n'
    printf '%b%s%b\n' "$WHITE" "$title" "$NC"
    printf '%b%s%b\n' "$DIM" "$subtitle" "$NC"
    draw_rule
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

terminal_cols() {
    local cols=""
    cols="$(tput cols 2>/dev/null || printf '80')"
    printf '%s' "${cols:-80}"
}

terminal_rows() {
    local rows=""
    rows="$(tput lines 2>/dev/null || printf '24')"
    printf '%s' "${rows:-24}"
}

print_log_tail() {
    local logfile="$1"
    local cols=""
    local rows=""
    local max_lines=0
    local width=0
    local line=""

    cols="$(terminal_cols)"
    rows="$(terminal_rows)"
    width=$((cols - 4))
    max_lines=$((rows - 16))

    if [[ "$width" -lt 20 ]]; then
        width=20
    fi

    if [[ "$max_lines" -lt 6 ]]; then
        max_lines=6
    fi

    if [[ ! -s "$logfile" ]]; then
        printf '%bNo log output was captured.%b\n' "$DIM" "$NC"
        return 0
    fi

    while IFS= read -r line; do
        if [[ "${#line}" -gt "$width" ]]; then
            printf '%s...\n' "${line:0:$((width - 3))}"
        else
            printf '%s\n' "$line"
        fi
    done < <(tail -n "$max_lines" "$logfile")
}

show_failure_screen() {
    local title="$1"
    local subtitle="$2"
    local logfile="$3"

    show_header "$title" "$subtitle"
    printf '%bRecent log lines%b\n' "$WHITE" "$NC"
    draw_rule
    print_log_tail "$logfile"
    printf '\n'
    printf '%bFull log:%b %s\n' "$DIM" "$NC" "$logfile"
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
    local max_visible=8
    local start=0
    local end=0

    while true; do
        show_header "$prompt" "Use the arrow keys, then press Enter."

        if [[ "${#options[@]}" -le "$max_visible" ]]; then
            start=0
            end=$((${#options[@]} - 1))
        else
            start=$((selected - (max_visible / 2)))
            if [[ "$start" -lt 0 ]]; then
                start=0
            fi

            end=$((start + max_visible - 1))
            if [[ "$end" -ge "${#options[@]}" ]]; then
                end=$((${#options[@]} - 1))
                start=$((end - max_visible + 1))
            fi
        fi

        if [[ "$start" -gt 0 ]]; then
            printf '%b  ↑ more choices above%b\n' "$DIM" "$NC"
        fi

        for ((i = start; i <= end; i++)); do
            if [[ "$i" -eq "$selected" ]]; then
                printf '%b› %s%b\n' "$MAGENTA" "${options[$i]}" "$NC"
            else
                printf '  %s\n' "${options[$i]}"
            fi
        done

        if [[ "$end" -lt $((${#options[@]} - 1)) ]]; then
            printf '%b  ↓ more choices below%b\n' "$DIM" "$NC"
        fi

        printf '\n'
        printf '%b<↑↓> navigate • enter submit • esc back%b\n' "$DIM" "$NC"

        key="$(read_key)"
        case "$key" in
            $'\033')
                menu_result="__back__"
                return 0
                ;;
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
    local subtitle="${3:-Type a value and press Enter. Type /back to return.}"
    local input=""

    while true; do
        show_header "$prompt" "$subtitle"
        if [[ -n "$default_value" ]]; then
            read -r -p "> [${default_value}] " input
            prompt_result="${input:-$default_value}"
        else
            read -r -p "> " input
            prompt_result="$input"
        fi
        if [[ "$prompt_result" == "/back" ]]; then
            prompt_result="__back__"
        fi
        return 0
    done
}

set_step_next() {
    step_action="next"
}

set_step_back() {
    step_action="back"
}

set_step_cancel() {
    step_action="cancel"
}

set_step_install() {
    step_action="install"
}

set_step_stay() {
    step_action="stay"
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error_msg "This installer must run as root."
        exit 1
    fi
}

resolve_nixpkgs_path() {
    local candidate=""

    for candidate in \
        "${ABORA_NIXPKGS_PATH:-}" \
        /etc/abora/nixpkgs \
        /etc/nix/path/nixpkgs \
        /run/current-system/nixpkgs/nixpkgs \
        /nix/var/nix/profiles/per-user/root/channels/nixos \
        /nix/var/nix/profiles/per-user/root/channels
    do
        if [[ -n "$candidate" && -e "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

load_keyboard_layout() {
    if command -v loadkeys >/dev/null 2>&1; then
        loadkeys "$keyboard_value" >/dev/null 2>&1 || true
    fi
}

sync_xkb_layout() {
    case "$keyboard_value" in
        uk)
            xkb_layout_value="gb"
            ;;
        *)
            xkb_layout_value="$keyboard_value"
            ;;
    esac
}

find_zoneinfo_dir() {
    local candidate=""

    for candidate in \
        "${ABORA_ZONEINFO_PATH:-}" \
        /usr/share/zoneinfo \
        /run/current-system/sw/share/zoneinfo \
        /etc/zoneinfo
    do
        if [[ -n "$candidate" && -d "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

collect_timezones() {
    local zoneinfo_dir=""

    zoneinfo_dir="$(find_zoneinfo_dir)" || return 1

    find "$zoneinfo_dir" -type f | sed "s#^${zoneinfo_dir}/##" | grep -Ev \
        '^(posix/|right/|SystemV/|localtime$|posixrules$|leap-seconds.list$|leapseconds$|tzdata.zi$|zone.tab$|zone1970.tab$|iso3166.tab$)' \
        | sort -u
}

timezone_exists() {
    local value="${1:-}"

    [[ -n "$value" ]] || return 1
    collect_timezones | grep -Fxq "$value"
}

sync_desktop_label() {
    case "$desktop_profile" in
        gnome)
            desktop_label="GNOME"
            desktop_variant_id="gnome"
            ;;
        plasma)
            desktop_label="KDE Plasma"
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
        i3)
            desktop_label="i3"
            desktop_variant_id="i3"
            ;;
        openbox)
            desktop_label="Openbox"
            desktop_variant_id="openbox"
            ;;
    esac
}

pick_keyboard_layout() {
    local labels=(
        "English (US)"
        "English (UK)"
        "German"
        "French"
        "Spanish"
        "Back"
    )
    local values=( "us" "uk" "de" "fr" "es" )

    menu_choose "Select keyboard layout" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#values[@]}" ]]; then
        set_step_back
        return 0
    fi
    keyboard_value="${values[$menu_result]}"
    sync_xkb_layout
    load_keyboard_layout
    set_step_next
}

pick_desktop_environment() {
    local labels=(
        "GNOME - polished and simple"
        "KDE Plasma - flexible and full featured"
        "Hyprland - tiling Wayland desktop"
        "XFCE - light and familiar"
        "Cinnamon - traditional with modern polish"
        "MATE - classic desktop feel"
        "Budgie - clean and focused"
        "LXQt - extra lightweight desktop"
        "i3 - keyboard-driven tiling session"
        "Openbox - very minimal floating session"
        "Back"
    )
    local values=(
        "gnome"
        "plasma"
        "hyprland"
        "xfce"
        "cinnamon"
        "mate"
        "budgie"
        "lxqt"
        "i3"
        "openbox"
    )

    menu_choose "Select desktop environment" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#values[@]}" ]]; then
        set_step_back
        return 0
    fi
    desktop_profile="${values[$menu_result]}"
    sync_desktop_label
    set_step_next
}

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) {
                next
            }
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
        show_header "Select install target" "No installable disks were found."
        printf '%bNo disks are visible to the installer right now.%b\n' "$RED" "$NC"
        printf '\n'
        menu_choose "Choose what to do next" "Rescan disks" "Back"
        if [[ "$menu_result" == "__back__" || "$menu_result" == "1" ]]; then
            set_step_back
            return 0
        fi
        set_step_stay
        return 0
    fi

    for entry in "${entries[@]}"; do
        IFS='|' read -r name size model <<<"$entry"
        labels+=( "/dev/${name}  ${size}  ${model}" )
        paths+=( "/dev/${name}" )
    done
    labels+=( "Back" )

    menu_choose "Select install target" "${labels[@]}"
    if [[ "$menu_result" == "__back__" || "$menu_result" == "${#paths[@]}" ]]; then
        set_step_back
        return 0
    fi
    disk="${paths[$menu_result]}"
    set_step_next
}

prompt_hostname() {
    local input=""

    while true; do
        prompt_input "Choose a hostname" "$hostname_value"
        input="$prompt_result"
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi
        if [[ "$input" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
            hostname_value="$input"
            set_step_next
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
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi
        if [[ "$input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            username_value="$input"
            set_step_next
            return
        fi

        error_msg "Username must start with a lowercase letter or underscore."
        pause_prompt
    done
}

prompt_timezone() {
    local input=""
    local query=""
    local zoneinfo_matches=()

    menu_choose \
        "Choose timezone method" \
        "Search for a timezone" \
        "Enter timezone directly" \
        "Back"

    if [[ "$menu_result" == "__back__" || "$menu_result" == "2" ]]; then
        set_step_back
        return 0
    fi

    if [[ "$menu_result" == "0" ]]; then
        while true; do
            prompt_input "Search timezone" "$timezone_value"
            query="$prompt_result"
            if [[ "$query" == "__back__" ]]; then
                set_step_back
                return 0
            fi
            mapfile -t zoneinfo_matches < <(collect_timezones | grep -Fi -- "${query:-UTC}" | head -n 30)

            if [[ "${#zoneinfo_matches[@]}" -eq 0 ]]; then
                error_msg "No timezones matched. Try UTC, America, Europe, or Etc."
                pause_prompt
                continue
            fi

            zoneinfo_matches+=( "Back" )
            menu_choose "Select timezone" "${zoneinfo_matches[@]}"
            if [[ "$menu_result" == "__back__" || "$menu_result" == "$((${#zoneinfo_matches[@]} - 1))" ]]; then
                continue
            fi
            timezone_value="${zoneinfo_matches[$menu_result]}"
            set_step_next
            return 0
        done
    fi

    while true; do
        prompt_input "Enter timezone directly" "$timezone_value"
        input="${prompt_result:-$timezone_value}"
        if [[ "$input" == "__back__" ]]; then
            set_step_back
            return 0
        fi

        if timezone_exists "$input"; then
            timezone_value="$input"
            set_step_next
            return 0
        fi

        error_msg "Timezone not found. Try UTC, Etc/UTC, or use search."
        pause_prompt
    done
}

prompt_password() {
    local first=""
    local second=""

    while true; do
        show_header "Set password" "Choose a password for ${username_value}. Type /back to return."

        read -r -s -p "Password: " first
        printf '\n'
        if [[ "$first" == "/back" ]]; then
            set_step_back
            return 0
        fi
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

        if command -v mkpasswd >/dev/null 2>&1; then
            user_password_hash="$(mkpasswd -m yescrypt "$first")"
        elif command -v openssl >/dev/null 2>&1; then
            user_password_hash="$(printf '%s' "$first" | openssl passwd -6 -stdin)"
        else
            error_msg "A password hashing tool is missing. Install mkpasswd or openssl."
            pause_prompt
            continue
        fi

        unset first second
        set_step_next
        return
    done
}

confirm_install() {
    show_header "Ready to install" "Review your choices before the disk is wiped."
    printf '  Disk:      %s\n' "$disk"
    printf '  Keyboard:  %s\n' "$keyboard_value"
    printf '  Desktop:   %s\n' "$desktop_label"
    printf '  Hostname:  %s\n' "$hostname_value"
    printf '  User:      %s\n' "$username_value"
    printf '  Timezone:  %s\n' "$timezone_value"
    printf '\n'
    printf 'The installer will wipe the selected disk and create:\n'
    printf '  - 1 MiB BIOS boot partition\n'
    printf '  - 512 MiB EFI system partition\n'
    printf '  - ext4 root partition using the rest of the disk\n'
    printf '\n'

    menu_choose "Continue with installation?" "Install now" "Back" "Cancel"
    case "$menu_result" in
        "__back__"|1)
            set_step_back
            ;;
        2)
            set_step_cancel
            ;;
        *)
            set_step_install
            ;;
    esac
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

desktop_config_block() {
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
    case "$desktop_profile" in
        hyprland)
            cat <<EOF
    kitty
EOF
            ;;
    esac
}

write_branding_assets() {
    mkdir -p /mnt/etc/nixos/abora/plymouth /mnt/etc/nixos/abora/bootloader
    cp "$title_file" /mnt/etc/nixos/abora/title.txt
    cp /etc/abora/VERSION /mnt/etc/nixos/abora/VERSION
    cp /etc/abora/fastfetch-logo.txt /mnt/etc/nixos/abora/fastfetch-logo.txt
    cp /etc/abora/fastfetch-config.jsonc /mnt/etc/nixos/abora/fastfetch-config.jsonc
    cp /etc/abora/installed-base.nix /mnt/etc/nixos/abora/installed-base.nix
    cp /etc/abora/update.sh /mnt/etc/nixos/abora/update.sh
    cp /etc/abora/plymouth/abora.plymouth /mnt/etc/nixos/abora/plymouth/abora.plymouth
    cp /etc/abora/plymouth/abora.script /mnt/etc/nixos/abora/plymouth/abora.script
    cp /etc/abora/bootloader/* /mnt/etc/nixos/abora/bootloader/
}

write_install_assets() {
    write_branding_assets
}

generate_config() {
    local desktop_block=""
    local desktop_packages=""

    info "Generating NixOS configuration"
    info "Writing configuration log to ${config_log}"
    printf '[*] Running nixos-generate-config --root /mnt\n' > "$config_log"
    if ! nixos-generate-config --root /mnt >>"$config_log" 2>&1; then
        show_failure_screen \
            "Configuration failed" \
            "Abora could not generate the base NixOS hardware config." \
            "$config_log"
        return 1
    fi

    write_install_assets
    desktop_block="$(desktop_config_block)"
    desktop_packages="$(desktop_package_block)"

    cat > /mnt/etc/nixos/configuration.nix <<EOF
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./abora/installed-base.nix
    ./abora-local.nix
  ];
}
EOF

    cat > /mnt/etc/nixos/abora-local.nix <<EOF
{ pkgs, ... }:
{
  system.nixos.variantName = "Abora ${version} ${desktop_label} Edition";
  system.nixos.variant_id = "${desktop_variant_id}";

  boot.loader.grub = {
    enable = true;
    devices = [ "${disk}" ];
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

  system.stateVersion = "26.05";
}
EOF

    cat > /mnt/etc/nixos/flake.nix <<EOF
{
  description = "Abora installed system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.abora = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./abora/installed-base.nix
        ./abora-local.nix
      ];
    };
  };
}
EOF
    success "Configuration written"
}

install_system() {
    local nixpkgs_path=""
    local nix_path=""
    local status=0

    info "Installing Abora OS"
    info "This can take a few minutes."
    nixpkgs_path="$(resolve_nixpkgs_path)" || {
        error_msg "Could not locate nixpkgs for nixos-install."
        return 1
    }
    nix_path="nixpkgs=${nixpkgs_path}:nixos-config=/mnt/etc/nixos/configuration.nix"
    info "Writing install log to ${install_log}"
    printf '[*] Running nixos-install\n' > "$install_log"
    printf '[*] NIX_PATH=%s\n' "$nix_path" >> "$install_log"

    if NIX_PATH="$nix_path" nixos-install \
        --root /mnt \
        --no-root-passwd \
        -I "nixpkgs=${nixpkgs_path}" \
        -I "nixos-config=/mnt/etc/nixos/configuration.nix" \
        >>"$install_log" 2>&1
    then
        success "Installation complete"
        return 0
    else
        status="$?"
        printf '\n[x] nixos-install exited with status %s\n' "$status" >> "$install_log"
        show_failure_screen \
            "Installation failed" \
            "Abora could not finish writing the system." \
            "$install_log"
        return 1
    fi
}

finish_screen() {
    show_header "Install complete" "Your machine is ready for first boot."
    success "Abora OS ${version} is installed."
    printf '\n'
    printf 'Next:\n'
    printf '  1. Remove the ISO from the VM or USB boot order.\n'
    printf '  2. Reboot the machine.\n'
    printf '\n'
    menu_choose "What would you like to do now?" "Reboot into Abora OS" "Power off"

    case "$menu_result" in
        0)
            sync
            reboot
            ;;
        *)
            sync
            poweroff
            ;;
    esac
}

cleanup_target() {
    sync
    umount -R /mnt 2>/dev/null || true
}

main() {
    local step=0

    require_root
    if ! command -v mkpasswd >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
        error_msg "Password hashing is unavailable. Install mkpasswd or openssl."
        exit 1
    fi

    while true; do
        set_step_next

        case "$step" in
            0)
                pick_keyboard_layout
                ;;
            1)
                pick_desktop_environment
                ;;
            2)
                prompt_disk || return 1
                ;;
            3)
                prompt_hostname
                ;;
            4)
                prompt_username
                ;;
            5)
                prompt_timezone
                ;;
            6)
                prompt_password
                ;;
            7)
                confirm_install
                ;;
        esac

        case "$step_action" in
            back)
                if [[ "$step" -gt 0 ]]; then
                    step=$((step - 1))
                fi
                ;;
            cancel)
                info "Install cancelled."
                return 0
                ;;
            stay)
                ;;
            install)
                show_header "Installing Abora OS" "Applying partitions and writing the system."
                partition_disk
                mount_target
                generate_config || {
                    pause_prompt
                    return 1
                }
                install_system || {
                    pause_prompt
                    return 1
                }
                cleanup_target
                finish_screen
                return 0
                ;;
            *)
                if [[ "$step" -lt 7 ]]; then
                    step=$((step + 1))
                fi
                ;;
        esac
    done
}

main "$@"
