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
lonis_enabled="false"
user_password_hash=""
efi_part=""
root_part=""
config_log="/tmp/abora-generate-config.log"
install_log="/tmp/abora-install.log"

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

draw_rule() {
    printf '%b' "$DIM"
    printf '────────────────────────────────────────────────────────────\n'
    printf '%b' "$NC"
}

show_header() {
    local title="${1:-Abora OS installer}"
    local subtitle="${2:-Lets set up your machine...}"

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
        show_header "$prompt" "Type a value and press Enter."
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
            if [[ "$lonis_enabled" == "true" ]]; then
                desktop_label="Abora Lonis"
                desktop_variant_id="lonis"
            else
                desktop_label="Hyprland"
                desktop_variant_id="hyprland"
            fi
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
        enlightenment)
            desktop_label="Enlightenment"
            desktop_variant_id="enlightenment"
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
    )
    local values=( "us" "uk" "de" "fr" "es" )
    local choice=""

    menu_choose "Select keyboard layout" "${labels[@]}"
    keyboard_value="${values[$menu_result]}"
    sync_xkb_layout
    load_keyboard_layout
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
        "Pantheon - minimal and elegant"
        "Enlightenment - flashy and lightweight"
        "i3 - keyboard-driven tiling session"
        "Openbox - very minimal floating session"
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
        "pantheon"
        "enlightenment"
        "i3"
        "openbox"
    )

    menu_choose "Select desktop environment" "${labels[@]}"
    desktop_profile="${values[$menu_result]}"
    lonis_enabled="false"
    if [[ "$desktop_profile" == "hyprland" ]]; then
        prompt_hyprland_variant
        return 0
    fi
    sync_desktop_label
}

prompt_hyprland_variant() {
    menu_choose \
        "Choose Hyprland flavor" \
        "Standard Hyprland" \
        "Abora Lonis - a styled Hyprland setup"

    if [[ "$menu_result" == "1" ]]; then
        show_header "About Abora Lonis" "A prettier Hyprland setup from Abora."
        printf 'Lonis is still Hyprland at its core.\n'
        printf 'It adds a calmer Abora look with:\n'
        printf '  - a styled Waybar top bar\n'
        printf '  - themed Kitty, Rofi, and notifications\n'
        printf '  - cleaner defaults for a more polished first boot\n'
        printf '\n'
        printf 'You are agreeing to use the Abora-themed Hyprland variant.\n'
        printf 'If you would rather keep things plain, choose standard Hyprland.\n'
        printf '\n'
        pause_prompt

        menu_choose \
            "Do you agree and want to use Lonis?" \
            "Yes - install Abora Lonis" \
            "No - keep standard Hyprland"

        if [[ "$menu_result" == "0" ]]; then
            lonis_enabled="true"
        fi
    fi

    sync_desktop_label
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
    local query=""
    local zoneinfo_matches=()

    menu_choose \
        "Choose timezone method" \
        "Search for a timezone" \
        "Enter timezone directly"

    if [[ "$menu_result" == "0" ]]; then
        while true; do
            prompt_input "Search timezone" "$timezone_value"
            query="$prompt_result"
            mapfile -t zoneinfo_matches < <(collect_timezones | grep -Fi -- "${query:-UTC}" | head -n 30)

            if [[ "${#zoneinfo_matches[@]}" -eq 0 ]]; then
                error_msg "No timezones matched. Try UTC, America, Europe, or Etc."
                pause_prompt
                continue
            fi

            menu_choose "Select timezone" "${zoneinfo_matches[@]}"
            timezone_value="${zoneinfo_matches[$menu_result]}"
            return 0
        done
    fi

    while true; do
        prompt_input "Enter timezone directly" "$timezone_value"
        input="${prompt_result:-$timezone_value}"

        if timezone_exists "$input"; then
            timezone_value="$input"
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
        show_header "Set password" "Choose a password for ${username_value}."

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

desktop_config_block() {
    case "$desktop_profile" in
        gnome)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };
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
            if [[ "$lonis_enabled" == "true" ]]; then
                cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "hyprland";
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
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  environment.systemPackages = with pkgs; [
    brightnessctl
    dunst
    grim
    kitty
    networkmanagerapplet
    pavucontrol
    rofi-wayland
    slurp
    waybar
    wl-clipboard
  ];
  environment.etc."skel/.config/hypr/hyprland.conf".source = ./abora/lonis/hyprland.conf;
  environment.etc."skel/.config/waybar/config.jsonc".source = ./abora/lonis/waybar-config.jsonc;
  environment.etc."skel/.config/waybar/style.css".source = ./abora/lonis/waybar-style.css;
  environment.etc."skel/.config/kitty/kitty.conf".source = ./abora/lonis/kitty.conf;
  environment.etc."skel/.config/rofi/config.rasi".source = ./abora/lonis/rofi.rasi;
  environment.etc."skel/.config/dunst/dunstrc".source = ./abora/lonis/dunstrc;
EOF
            else
                cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "hyprland";
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
            fi
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
    defaultSession = "pantheon";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.pantheon.enable = true;
EOF
            ;;
        enlightenment)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.enlightenment.enable = true;
  };
  services.displayManager = {
    defaultSession = "enlightenment";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
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

write_branding_assets() {
    mkdir -p /mnt/etc/nixos/abora
    cp "$title_file" /mnt/etc/nixos/abora/title.txt
    cp /etc/abora/fastfetch-config.jsonc /mnt/etc/nixos/abora/fastfetch-config.jsonc
}

write_lonis_assets() {
    mkdir -p /mnt/etc/nixos/abora/lonis
    sed "s/__ABORA_KB_LAYOUT__/${xkb_layout_value}/g" /etc/abora/lonis/hyprland.conf > /mnt/etc/nixos/abora/lonis/hyprland.conf
    cp /etc/abora/lonis/waybar-config.jsonc /mnt/etc/nixos/abora/lonis/waybar-config.jsonc
    cp /etc/abora/lonis/waybar-style.css /mnt/etc/nixos/abora/lonis/waybar-style.css
    cp /etc/abora/lonis/kitty.conf /mnt/etc/nixos/abora/lonis/kitty.conf
    cp /etc/abora/lonis/rofi.rasi /mnt/etc/nixos/abora/lonis/rofi.rasi
    cp /etc/abora/lonis/dunstrc /mnt/etc/nixos/abora/lonis/dunstrc
}

write_install_assets() {
    write_branding_assets

    if [[ "$lonis_enabled" == "true" ]]; then
        write_lonis_assets
    fi
}

generate_config() {
    local desktop_block=""

    info "Generating NixOS configuration"
    info "Writing configuration log to ${config_log}"
    if ! nixos-generate-config --root /mnt >"$config_log" 2>&1; then
        show_failure_screen \
            "Configuration failed" \
            "Abora could not generate the base NixOS hardware config." \
            "$config_log"
        return 1
    fi

    write_install_assets
    desktop_block="$(desktop_config_block)"

    cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  system.nixos = {
    distroId = "abora";
    distroName = "Abora OS";
    vendorId = "abora";
    vendorName = "Abora OS";
    variantName = "${desktop_label} Edition";
    variant_id = "${desktop_variant_id}";
  };

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
  security.polkit.enable = true;
  services.udisks2.enable = true;
  environment.etc."abora/title.txt".source = ./abora/title.txt;
  environment.etc."xdg/fastfetch/config.jsonc".source = ./abora/fastfetch-config.jsonc;
  environment.etc."skel/.config/fastfetch/config.jsonc".source = ./abora/fastfetch-config.jsonc;
  environment.etc."issue".text = ''
    Abora OS
  '';
  environment.etc."issue.net".text = ''
    Abora OS
  '';
  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";
${desktop_block}
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users."${username_value}" = {
    isNormalUser = true;
    description = "Abora User";
    createHome = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
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
    local nixpkgs_path=""
    local nix_path=""

    info "Installing Abora OS"
    info "This can take a few minutes."
    nixpkgs_path="$(resolve_nixpkgs_path)" || {
        error_msg "Could not locate nixpkgs for nixos-install."
        return 1
    }
    nix_path="nixpkgs=${nixpkgs_path}:nixos-config=/mnt/etc/nixos/configuration.nix"
    : > "$install_log"
    info "Writing install log to ${install_log}"

    if ! NIX_PATH="$nix_path" nixos-install \
        --root /mnt \
        --no-root-passwd \
        -I "nixpkgs=${nixpkgs_path}" \
        -I "nixos-config=/mnt/etc/nixos/configuration.nix"
        >"$install_log" 2>&1
    then
        show_failure_screen \
            "Installation failed" \
            "Abora could not finish writing the system." \
            "$install_log"
        return 1
    fi
    success "Installation complete"
}

finish_screen() {
    show_header "Install complete" "Your machine is ready for first boot."
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
    if ! command -v mkpasswd >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
        error_msg "Password hashing is unavailable. Install mkpasswd or openssl."
        exit 1
    fi

    pick_keyboard_layout
    pick_desktop_environment
    prompt_disk || return 1
    prompt_hostname
    prompt_username
    prompt_timezone
    prompt_password

    if ! confirm_install; then
        info "Install cancelled."
        return 0
    fi

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
    finish_screen
}

main "$@"
