#!/usr/bin/env bash
# Abora OS Installer — Denali Edition
# Compact Omarchy-inspired TUI: large wordmark, boxed choices, simple prompts.

set -uo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export TERM="${TERM:-linux}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_log="/tmp/abora-config.log"
install_log="/tmp/abora-install.log"

# ── State ──────────────────────────────────────────────────────────────────────
disk=""
efi_part=""
root_part=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
keyboard_value="us"
xkb_layout_value="us"
desktop_profile="gnome"
desktop_label="GNOME"
desktop_variant_id="gnome"
wallpaper_name="oceandusk.png"
starter_apps_bundle="favorites"
starter_apps_label="Fan Favorites"
anix_enabled="yes"
github_identity="Skipped"
user_password_hash=""
root_password_hash=""
root_password_mode="same"
version="${ABORA_VERSION:-}"
reconfig_mode="${ABORA_RECONFIG:-0}"

for arg in "$@"; do
    case "$arg" in
        --reconfig|-r) reconfig_mode=1 ;;
    esac
done

# ── Library loading ────────────────────────────────────────────────────────────
find_lib() {
    local name="$1" extra="${2:-}" candidate
    for candidate in "$extra" "$script_dir/$name" "$script_dir/abora-$name" \
        "/etc/abora/$name" "/etc/abora/abora-$name"; do
        [[ -n "$candidate" && -f "$candidate" ]] && printf '%s\n' "$candidate" && return 0
    done
    return 1
}

desktop_profiles_lib="$(find_lib "desktop-profiles.sh" "${ABORA_DESKTOP_PROFILES_LIB:-}")" \
    || { printf 'abora-installer: desktop-profiles.sh not found\n' >&2; exit 1; }
app_catalog_lib="$(find_lib "app-catalog.sh" "${ABORA_APP_CATALOG_LIB:-}")" \
    || { printf 'abora-installer: app-catalog.sh not found\n' >&2; exit 1; }

# shellcheck source=/dev/null
source "$desktop_profiles_lib"
# shellcheck source=/dev/null
source "$app_catalog_lib"

if [[ -z "$version" && -f /etc/abora/VERSION ]]; then
    version="$(tr -d '\n' < /etc/abora/VERSION)"
fi
[[ -n "$version" ]] || version="dev"

# ── Colors ─────────────────────────────────────────────────────────────────────
R=$'\033[0m'
B=$'\033[1m'
D=$'\033[2m'
CF=$'\033[38;5;108m'   # Muted green  — frame / logo
CI=$'\033[38;5;230m'   # Warm white   — prompts
CS=$'\033[1;97m'       # Snow white   — headings
CG=$'\033[38;5;245m'   # Stone gray   — dim / pending
CP=$'\033[38;5;150m'   # Pale green   — done / logo
CW=$'\033[38;5;39m'    # Dodger blue  — choices
CE=$'\033[38;5;196m'   # Red          — errors
CY=$'\033[38;5;220m'   # Yellow       — warnings
CC=$'\033[38;5;253m'   # Cloud white  — body text

# ── Omarchy-style UI engine ────────────────────────────────────────────────────

_TABS=("Network" "Identity" "Desktop" "Apps" "Options" "Disk" "Confirm")

draw_logo() {
    printf '  %b █████╗ ██████╗  ██████╗ ██████╗  █████╗  ██████╗ ███████╗%b\n' "$CW" "$R"
    printf '  %b██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔═══██╗██╔════╝%b\n' "$CW" "$R"
    printf '  %b███████║██████╔╝██║   ██║██████╔╝███████║██║   ██║███████╗%b\n' "$CW" "$R"
    printf '  %b██╔══██║██╔══██╗██║   ██║██╔══██╗██╔══██║██║   ██║╚════██║%b\n' "$CW" "$R"
    printf '  %b██║  ██║██████╔╝╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████║%b\n' "$CW" "$R"
    printf '  %b╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝%b\n' "${D}${CW}" "$R"
}

rule() {
    printf '  %b──────────────────────────────────────────────────────────%b\n' "$CG" "$R"
}

tab_header() {
    local step="$1"
    local step_name="${_TABS[$((step - 1))]}"

    printf '\033[2J\033[H'   # ANSI clear + cursor home (no full VT reset)
    printf '\n'
    draw_logo
    printf '\n'
    printf '  %bLet'\''s setup your Abora Denali install...%b\n' "$CC" "$R"
    printf '  %bStep %d/%d%b  %b%s%b  %bv%s%b\n' "$CW" "$step" "${#_TABS[@]}" "$R" "${B}${CS}" "$step_name" "$R" "$CG" "$version" "$R"
    rule
    printf '\n'
}

# Numbered menu — NO screen clear (caller uses tab_header first).
# Each item: "Label|short description"  (description truncated to fit 80 cols)
# Sets MENU_RESULT (0-indexed).
MENU_RESULT=0
menu() {
    local title="$1"; shift
    local -a items=("$@")
    local count=${#items[@]}

    [[ -n "$title" ]] && printf '  %b%s%b\n' "${B}${CS}" "$title" "$R"
    printf '  %b┌────────────────────────────────────────────────────────────┐%b\n' "$CG" "$R"

    local i label desc
    for ((i = 0; i < count; i++)); do
        label="${items[$i]%%|*}"
        desc="${items[$i]#*|}"
        [[ "$desc" == "${items[$i]}" ]] && desc=""

        if [[ -n "$desc" && ${#desc} -gt 33 ]]; then
            desc="${desc:0:32}…"
        fi

        printf '  %b│%b %b%-2d%b %-20.20s %b%-33.33s%b %b│%b\n' \
            "$CG" "$R" "$CW" "$((i+1))" "$R" "$label" "${D}${CG}" "$desc" "$R" "$CG" "$R"
    done
    printf '  %b└────────────────────────────────────────────────────────────┘%b\n' "$CG" "$R"

    printf '\n'
    while true; do
        printf '  %bchoose:%b ' "$CW" "$R"
        local choice
        read -r choice </dev/tty || choice=""
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            MENU_RESULT=$(( choice - 1 ))
            return 0
        fi
        printf '  %b⚠%b  Enter a number from 1 to %d.\n' "$CY" "$R" "$count"
    done
}

# prompt_field — send prompt text to stderr so $(prompt_field ...) captures only value
prompt_field() {
    local prompt="$1" default="$2"
    printf '  %b%-14s%b %b│%b %s %b>%b ' "$CI" "$prompt" "$R" "$CG" "$R" "$default" "$CW" "$R" >&2
    local val
    read -r val </dev/tty || val=""
    printf '%s\n' "${val:-$default}"
}

prompt_password() {
    local prompt="$1"
    printf '  %b%-14s%b %b│%b %b>%b ' "$CI" "$prompt" "$R" "$CG" "$R" "$CW" "$R" >&2
    local val
    read -rs val </dev/tty || val=""
    printf '\n' >&2
    printf '%s\n' "$val"
}

ok()   { printf '  %b✓%b  %s\n' "$CP" "$R" "$1"; }
warn() { printf '  %b⚠%b  %s\n' "$CY" "$R" "$1"; }
err()  { printf '  %b✕%b  %s\n' "$CE" "$R" "$1"; }
msg()  { printf '  %b·%b  %s\n' "$CI" "$R" "$1"; }

die() {
    err "$*"
    printf '\n  %bLog: %s%b\n\n' "${D}${CG}" "$install_log" "$R"
    exit 1
}

# ── Utility ───────────────────────────────────────────────────────────────────

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || { err "Run the installer as root."; exit 1; }
}

safe_identifier() { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]; }
safe_hostname()   { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]]; }

sync_xkb_layout() {
    case "$keyboard_value" in
        us) xkb_layout_value="us" ;;
        uk) xkb_layout_value="gb" ;;
        de) xkb_layout_value="de" ;;
        fr) xkb_layout_value="fr" ;;
        es) xkb_layout_value="es" ;;
        it) xkb_layout_value="it" ;;
        pt) xkb_layout_value="pt" ;;
        ru) xkb_layout_value="ru" ;;
        *)  xkb_layout_value="$keyboard_value" ;;
    esac
}

detect_defaults() {
    local d
    d="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    [[ -n "$d" ]] && timezone_value="$d"
    d="$(localectl status 2>/dev/null | awk '/VC Keymap:/{print $3;exit}' || true)"
    if [[ "$d" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        keyboard_value="$d"; sync_xkb_layout
    fi
}

refresh_github_identity() {
    command -v gh >/dev/null 2>&1 || { github_identity="gh CLI unavailable"; return 0; }
    if gh auth status --hostname github.com >/dev/null 2>&1; then
        local login; login="$(gh api user --jq '.login' 2>/dev/null || true)"
        github_identity="${login:+Signed in as ${login}}"
        [[ -n "$github_identity" ]] || github_identity="Signed in"
    else
        github_identity="Skipped"
    fi
}

net_connected() {
    if command -v nmcli >/dev/null 2>&1; then
        nmcli -t networking connectivity check 2>/dev/null \
            | grep -Eq '^(full|limited)$' && return 0
        nmcli -t -f DEVICE,STATE device status 2>/dev/null \
            | grep -Eq ':(connected)$' && return 0
    fi
    ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && return 0
    curl -fsI --connect-timeout 5 https://cache.nixos.org >/dev/null 2>&1 && return 0
    return 1
}

start_nm() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl daemon-reload         >/dev/null 2>&1 || true
    systemctl unmask NetworkManager >/dev/null 2>&1 || true
    systemctl enable --now NetworkManager >/dev/null 2>&1 \
        || systemctl start NetworkManager >/dev/null 2>&1 \
        || return 1
}

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) next
            model = ""
            for (i = 3; i < NF; i++) model = model (model ? " " : "") $i
            if (model == "") model = "Unknown model"
            print "/dev/" $1 "|" $2 "  " model
        }'
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PAGES
# ═══════════════════════════════════════════════════════════════════════════════

page_welcome() {
    printf '\033[2J\033[H'
    printf '\n'
    draw_logo
    printf '\n'
    printf '  %bLet'\''s setup your Abora Denali install...%b\n' "${D}${CC}" "$R"
    printf '  %bSmall choices first. Big rebuild later.%b\n' "${D}${CG}" "$R"
    printf '\n'
    printf '  %b┌────────────────────────────────────────────────────────────┐%b\n' "$CG" "$R"
    printf '  %b│%b File          %b│%b %-43s %b│%b\n' "$CG" "$R" "$CG" "$R" "Abora Denali" "$CG" "$R"
    printf '  %b│%b Version       %b│%b %-43s %b│%b\n' "$CG" "$R" "$CG" "$R" "$version" "$CG" "$R"
    printf '  %b│%b Goal          %b│%b Install NixOS without NixOS sadness      %b│%b\n' "$CG" "$R" "$CG" "$R" "$CG" "$R"
    printf '  %b└────────────────────────────────────────────────────────────┘%b\n' "$CG" "$R"
    printf '\n'
    printf '  %bPress Enter to begin installation%b\n' "$CW" "$R"
    printf '\n'
    read -rs _ </dev/tty || true
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — NETWORK
# ═══════════════════════════════════════════════════════════════════════════════

step_network() {
    start_nm 2>/dev/null || true
    local ok=0
    if net_connected; then ok=1; fi

    while true; do
        tab_header 1
        printf '  %bNetwork Setup%b\n\n' "${B}${CS}" "$R"

        if (( ok )); then
            ok "Connected — internet available"
        else
            warn "No internet connection detected"
        fi
        printf '\n'

        menu "" \
            "Open nmtui|Wi-Fi setup, hidden SSIDs, VPNs" \
            "Quick Wi-Fi connect|Scan and connect from terminal" \
            "Re-check connection|Test connectivity again" \
            "Continue|Proceed with current state"

        case "$MENU_RESULT" in
            0)
                nmtui 2>/dev/null || true
                start_nm 2>/dev/null || true
                ;;
            1)
                nmcli radio wifi on >/dev/null 2>&1 || true
                nmcli device wifi rescan >/dev/null 2>&1 || true
                printf '\n'
                nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || true
                printf '\n'
                printf '  %bSSID:%b ' "$CI" "$R"
                local _ssid; read -r _ssid </dev/tty || _ssid=""
                if [[ -n "${_ssid:-}" ]]; then
                    local _sec
                    _sec="$(nmcli -t -f SSID,SECURITY device wifi list 2>/dev/null \
                        | awk -F: -v s="$_ssid" '$1==s{print $2;exit}')"
                    if [[ -n "${_sec:-}" && "$_sec" != "--" ]]; then
                        printf '  %bPassword:%b ' "$CI" "$R"
                        local _pw; read -rs _pw </dev/tty || _pw=""
                        printf '\n'
                        nmcli device wifi connect "$_ssid" password "$_pw" 2>/dev/null || true
                    else
                        nmcli device wifi connect "$_ssid" 2>/dev/null || true
                    fi
                fi
                ;;
            2)
                if net_connected; then ok=1; ok "Connected!"
                else ok=0; warn "Still no connection."; fi
                printf '\n'
                printf '  %bPress Enter to continue%b' "${D}${CG}" "$R"
                read -rs _ </dev/tty || true
                ;;
            3)
                if (( ok )); then return 0; fi
                warn "No internet — install may fail without it."
                printf '\n'
                menu "Continue without internet?" \
                    "Go back|Return to network options" \
                    "Skip — continue anyway|Install without internet"
                if [[ "$MENU_RESULT" -eq 1 ]]; then return 0; fi
                ;;
        esac
        if net_connected; then ok=1; else ok=0; fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════

step_identity() {
    tab_header 2
    printf '  %bIdentity & Locale%b\n\n' "${B}${CS}" "$R"

    # Hostname
    while true; do
        local v; v="$(prompt_field "Hostname" "$hostname_value")"
        [[ -n "$v" ]] && hostname_value="$v"
        if safe_hostname "$hostname_value"; then break; fi
        warn "Letters, numbers, hyphens only. Must start with a letter/digit."
    done

    # Username
    while true; do
        local v; v="$(prompt_field "Username" "$username_value")"
        [[ -n "$v" ]] && username_value="$v"
        if safe_identifier "$username_value"; then break; fi
        warn "Lowercase letters, numbers, hyphens. Must start with a letter."
    done

    local v
    v="$(prompt_field "Timezone" "$timezone_value")"
    [[ -n "$v" ]] && timezone_value="$v"

    v="$(prompt_field "Console keymap" "$keyboard_value")"
    [[ -n "$v" ]] && keyboard_value="$v"
    sync_xkb_layout

    v="$(prompt_field "XKB layout (X11)" "$xkb_layout_value")"
    [[ -n "$v" ]] && xkb_layout_value="$v"

    printf '\n'

    # Password
    while true; do
        local p1; p1="$(prompt_password "Password")"
        local p2; p2="$(prompt_password "Confirm password")"
        [[ -z "$p1" ]] && { warn "Password cannot be empty."; continue; }
        [[ "$p1" != "$p2" ]] && { warn "Passwords do not match."; continue; }
        user_password_hash="$(openssl passwd -6 "$p1")"
        ok "Password set."
        break
    done

    printf '\n'
    menu "Root Account" \
        "Same password as user|Root inherits the user password" \
        "Lock root account|Disable root login — use sudo only" \
        "Set separate root password|Choose a separate root password"
    case "$MENU_RESULT" in
        0) root_password_mode="same"; root_password_hash="$user_password_hash" ;;
        1) root_password_mode="locked"; root_password_hash="" ;;
        2)
            root_password_mode="custom"
            while true; do
                local p1; p1="$(prompt_password "Root password")"
                local p2; p2="$(prompt_password "Confirm root password")"
                [[ -z "$p1" ]] && { warn "Password cannot be empty."; continue; }
                [[ "$p1" != "$p2" ]] && { warn "Passwords do not match."; continue; }
                root_password_hash="$(openssl passwd -6 "$p1")"
                ok "Root password set."
                break
            done
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 3 — DESKTOP
# ═══════════════════════════════════════════════════════════════════════════════

step_desktop() {
    tab_header 3

    local -a profiles=()
    local profile
    while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        abora_sync_desktop_label "$profile"
        profiles+=("${desktop_label}|${profile}")
    done < <(abora_supported_desktop_profiles)

    menu "Choose Your Desktop Environment" "${profiles[@]}"
    desktop_profile="${profiles[$MENU_RESULT]#*|}"
    abora_sync_desktop_label "$desktop_profile"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — APPS
# ═══════════════════════════════════════════════════════════════════════════════

step_apps() {
    tab_header 4

    menu "Choose a Starter App Bundle" \
        "Fan Favorites|Our curated pick — great for most users" \
        "Essentials|Browsers, office, media, everyday utilities" \
        "Social|Chat, video calls, messaging apps" \
        "Creator|Design, audio, video, creative tools" \
        "Developer|IDEs, containers, terminal tools, Git" \
        "Gaming|Steam, Lutris, Wine, gaming helpers" \
        "System Tools|Monitoring, backup, system management" \
        "None|Start clean — add apps later with grab"
    case "$MENU_RESULT" in
        0) starter_apps_bundle="favorites";  starter_apps_label="Fan Favorites" ;;
        1) starter_apps_bundle="essentials"; starter_apps_label="Essentials" ;;
        2) starter_apps_bundle="social";     starter_apps_label="Social" ;;
        3) starter_apps_bundle="creator";    starter_apps_label="Creator" ;;
        4) starter_apps_bundle="developer";  starter_apps_label="Developer" ;;
        5) starter_apps_bundle="gaming";     starter_apps_label="Gaming" ;;
        6) starter_apps_bundle="system";     starter_apps_label="System Tools" ;;
        7) starter_apps_bundle="none";       starter_apps_label="None" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 5 — OPTIONS
# ═══════════════════════════════════════════════════════════════════════════════

step_options() {
    tab_header 5

    menu "ANIX Helper Layer" \
        "Enable ANIX|Friendly NixOS commands — recommended" \
        "Disable ANIX|Bare Abora/NixOS — for plain nix users"
    if [[ "$MENU_RESULT" -eq 0 ]]; then anix_enabled="yes"; else anix_enabled="no"; fi

    printf '\n'
    menu "GitHub CLI" \
        "Skip for now|Sign in later with: gh auth login" \
        "Sign in now|Run gh auth login and copy credentials"
    if [[ "$MENU_RESULT" -eq 1 ]]; then
        gh auth login 2>/dev/null || true
        refresh_github_identity
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 6 — DISK
# ═══════════════════════════════════════════════════════════════════════════════

step_disk() {
    tab_header 6
    warn "All data on the selected disk will be permanently erased!"
    printf '\n'

    local -a disks=() row
    while IFS= read -r row; do
        [[ -n "$row" ]] && disks+=("$row")
    done < <(collect_disks)
    [[ ${#disks[@]} -eq 0 ]] && die "No installable disks found."

    menu "Choose Installation Disk" "${disks[@]}"
    disk="${disks[$MENU_RESULT]%%|*}"

    printf '\n'
    warn "This will erase ALL data on: ${disk}"
    printf '\n'
    menu "Are you sure?" \
        "Yes — erase ${disk} and install|I understand all data will be lost" \
        "No — go back|Choose a different disk"
    if [[ "$MENU_RESULT" -eq 1 ]]; then
        step_disk
        return
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 7 — CONFIRM
# ═══════════════════════════════════════════════════════════════════════════════

_print_summary() {
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Disk:"     "$R" "${disk}  ← will be erased"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Hostname:" "$R" "$hostname_value"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Username:" "$R" "$username_value"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Timezone:" "$R" "$timezone_value"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Keyboard:" "$R" "${keyboard_value} / ${xkb_layout_value}"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Desktop:"  "$R" "${desktop_label} (${desktop_profile})"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:"     "$R" "$starter_apps_label"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "ANIX:"     "$R" "$anix_enabled"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Root:"     "$R" "$root_password_mode"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "GitHub:"   "$R" "$github_identity"
    printf '\n'
}

step_confirm() {
    while true; do
        tab_header 7
        printf '  %bInstallation Summary%b\n\n' "${B}${CS}" "$R"
        _print_summary

        menu "Ready to install?" \
            "Install now|Erase ${disk} and install Abora OS Denali" \
            "Change password|Reset user password before installing" \
            "Cancel|Abort and return to the live shell"

        case "$MENU_RESULT" in
            0) return 0 ;;
            1)
                printf '\n'
                while true; do
                    local p1; p1="$(prompt_password "New password")"
                    local p2; p2="$(prompt_password "Confirm password")"
                    [[ -z "$p1" ]] && { warn "Password cannot be empty."; continue; }
                    [[ "$p1" != "$p2" ]] && { warn "Passwords do not match."; continue; }
                    user_password_hash="$(openssl passwd -6 "$p1")"
                    [[ "$root_password_mode" == "same" ]] && root_password_hash="$user_password_hash"
                    ok "Password updated."
                    break
                done
                ;;
            2)
                printf '\nInstall cancelled.\n\n'
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  INSTALL ENGINE  (unchanged from working version)
# ═══════════════════════════════════════════════════════════════════════════════

disk_part_suffix() {
    case "$disk" in *nvme*|*mmcblk*|*loop*) printf 'p' ;; *) printf '' ;; esac
}

partition_disk() {
    umount -R /mnt >/dev/null 2>&1 || true
    wipefs -af "$disk" >>"$install_log" 2>&1
    parted -s "$disk" mklabel gpt >>"$install_log" 2>&1
    parted -s "$disk" unit MiB mkpart BIOSBOOT 1 3 >>"$install_log" 2>&1
    parted -s "$disk" set 1 bios_grub on >>"$install_log" 2>&1
    parted -s "$disk" unit MiB mkpart ESP fat32 3 515 >>"$install_log" 2>&1
    parted -s "$disk" set 2 esp on >>"$install_log" 2>&1
    parted -s "$disk" unit MiB mkpart primary ext4 515 100% >>"$install_log" 2>&1
    partprobe "$disk" >>"$install_log" 2>&1 || true
    udevadm settle >>"$install_log" 2>&1 || true

    local sfx; sfx="$(disk_part_suffix)"
    efi_part="${disk}${sfx}2"
    root_part="${disk}${sfx}3"

    mkfs.vfat -F 32 -n ABORA_EFI "$efi_part" >>"$install_log" 2>&1
    mkfs.ext4 -F -L ABORA_ROOT "$root_part" >>"$install_log" 2>&1
}

mount_target() {
    mkdir -p /mnt
    mount "$root_part" /mnt >>"$install_log" 2>&1
    mkdir -p /mnt/boot
    mount "$efi_part" /mnt/boot >>"$install_log" 2>&1
}

cp_required() {
    [[ -f "$1" ]] || { printf 'Required file missing: %s\n' "$1" >&2; return 1; }
    cp "$1" "$2"
}

write_starter_apps_list() {
    local target="$1" id expr
    : > "$target"
    [[ "$starter_apps_bundle" == "none" ]] && return 0
    while IFS= read -r id; do
        expr="$(abora_catalog_expr "$id" 2>/dev/null || true)"
        [[ -n "$expr" ]] && printf '%s\n' "$expr" >> "$target"
    done < <(abora_catalog_bundle_ids "$starter_apps_bundle" 2>/dev/null || true)
}

render_apps_nix() {
    local nix="$1" lst="$2" extra="${3:-}"
    {
        printf '{ pkgs, ... }:\n{\n  environment.systemPackages = with pkgs; [\n'
        if [[ -s "$lst" ]]; then
            while IFS= read -r expr; do
                [[ -n "$expr" ]] && printf '    %s\n' "$expr"
            done < "$lst"
        fi
        if [[ -n "$extra" ]]; then
            printf '%s\n' "$extra"
        fi
        printf '  ];\n}\n'
    } > "$nix"
}

write_branding_assets() {
    local root="${1:-/mnt}"
    mkdir -p "${root}/etc/nixos/abora/plymouth" \
             "${root}/etc/nixos/abora/bootloader" \
             "${root}/etc/nixos/abora/wallpapers" \
             "${root}/etc/nixos/abora/themes" \
             "${root}/etc/nixos/abora/effects"

    local f
    for f in VERSION title.txt abora.sh ui.sh config.sh desktop.sh doctor.sh \
              recovery.sh welcome.sh app-catalog.sh apps.sh support-report.sh \
              hardware-test.sh default-wallpaper.png fastfetch-logo.txt \
              fastfetch-config.jsonc desktop-profiles.sh installed-base.nix \
              installer.sh setup-launcher.sh setup.desktop \
              session-setup.sh theme-sync.sh update.sh; do
        cp_required "/etc/abora/${f}" "${root}/etc/nixos/abora/${f}"
    done
    cp_required /etc/abora/plymouth/abora.plymouth "${root}/etc/nixos/abora/plymouth/abora.plymouth"
    cp_required /etc/abora/plymouth/abora.script   "${root}/etc/nixos/abora/plymouth/abora.script"

    [[ -f /etc/abora/anix.sh           ]] && cp /etc/abora/anix.sh            "${root}/etc/nixos/abora/anix.sh"
    [[ -f /etc/abora/anix-module.nix   ]] && cp /etc/abora/anix-module.nix    "${root}/etc/nixos/abora/anix-module.nix"
    [[ -f /etc/abora/abora-options.nix ]] && cp /etc/abora/abora-options.nix  "${root}/etc/nixos/abora/abora-options.nix"
    [[ -f /etc/abora/effects/v3StartingAbora.mp3 ]] && \
        cp /etc/abora/effects/v3StartingAbora.mp3 "${root}/etc/nixos/abora/effects/v3StartingAbora.mp3"

    if [[ -e /etc/abora/tinypm ]]; then
        mkdir -p "${root}/etc/nixos/abora/tinypm"
        cp -rL /etc/abora/tinypm/. "${root}/etc/nixos/abora/tinypm/"
    fi

    local bg="/etc/abora/bootloader/background.png"
    local lm="/etc/abora/bootloader/limine-background.png"
    local th="/etc/abora/bootloader/theme.txt"
    cp_required "$bg" "${root}/etc/nixos/abora/bootloader/background.png"
    cp_required "$th" "${root}/etc/nixos/abora/bootloader/theme.txt"
    if [[ -f "$lm" ]]; then
        cp "$lm" "${root}/etc/nixos/abora/bootloader/limine-background.png"
    else
        cp "$bg" "${root}/etc/nixos/abora/bootloader/limine-background.png"
    fi

    find /etc/abora/wallpapers -maxdepth 1 -type f \
        -exec cp {} "${root}/etc/nixos/abora/wallpapers/" \; 2>/dev/null || true
    find /etc/abora/themes -maxdepth 1 -type f \
        -exec cp {} "${root}/etc/nixos/abora/themes/" \; 2>/dev/null || true

}

generate_nixos_config() {
    local root="${1:-/mnt}"
    local cfgdir="${root}/etc/nixos"

    printf '[*] nixos-generate-config\n' > "$config_log"
    nixos-generate-config --root "$root" >> "$config_log" 2>&1
    write_branding_assets "$root"

    local desktop_block desktop_pkgs root_pw_line
    desktop_block="$(abora_desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value")"
    desktop_pkgs="$(abora_desktop_package_block "$desktop_profile")"
    [[ -n "$desktop_block" ]] || die "Empty desktop block for $desktop_profile."

    # Write apps.nix here, after desktop_pkgs is known, so desktop packages
    # are included alongside the user's chosen starter bundle.
    write_starter_apps_list "${root}/etc/nixos/abora/apps.list"
    render_apps_nix "${root}/etc/nixos/abora/apps.nix" \
        "${root}/etc/nixos/abora/apps.list" \
        "$desktop_pkgs"
    [[ -n "$user_password_hash" ]] || die "User password hash is empty."

    if [[ -n "$root_password_hash" ]]; then
        root_pw_line="  users.users.root.hashedPassword = \"${root_password_hash}\";"
    else
        root_pw_line="  users.users.root.hashedPassword = \"!\";"
    fi

    if [[ "$anix_enabled" == "yes" ]]; then
        cat > "${cfgdir}/anix.nix" <<EOF
{ ... }:
{
  anix.enable = true;
  anix.hostname = "${hostname_value}";
  anix.timezone = "${timezone_value}";
  anix.keyboard.console = "${keyboard_value}";
  anix.keyboard.xkb = "${xkb_layout_value}";
  anix.desktop = "${desktop_profile}";
  anix.wallpaper = "${wallpaper_name}";
}
EOF
    else
        rm -f "${cfgdir}/anix.nix"
    fi

    cat > "${cfgdir}/configuration.nix" <<'NIXEOF'
{ lib, ... }:
let appModule = ./abora/apps.nix; in
{
  imports = [
    ./hardware-configuration.nix
    ./abora/installed-base.nix
    ./abora-local.nix
  ] ++ lib.optional (builtins.pathExists appModule) appModule;
}
NIXEOF

    cat > "${cfgdir}/abora-local.nix" <<EOF
{ pkgs, lib, ... }:
{
  system.nixos.variantName = "Abora ${version#v} ${desktop_label} Edition";
  system.nixos.variant_id = "${desktop_variant_id}";

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.efiSysMountPoint = "/boot";
  boot.loader.limine = {
    enable = true;
    biosSupport = true;
    biosDevice = "${disk}";
    partitionIndex = 1;
    force = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "${hostname_value}";
  networking.networkmanager.enable = lib.mkForce true;
  time.timeZone = "${timezone_value}";
  console.keyMap = "${keyboard_value}";

${desktop_block}

  users.users."${username_value}" = {
    isNormalUser = true;
    description = "${username_value}";
    createHome = true;
    shell = pkgs.bash;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "${user_password_hash}";
  };

${root_pw_line}

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "26.05";
}
EOF

    cat > "${cfgdir}/flake.nix" <<'NIXEOF'
{
  description = "Abora installed system";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.abora = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        let
          lib = nixpkgs.lib;
          appModule   = ./abora/apps.nix;
          anixModule  = ./abora/anix-module.nix;
          anixLayer   = ./anix.nix;
        in [
          ./hardware-configuration.nix
          ./abora/installed-base.nix
          ./abora-local.nix
        ]
        ++ lib.optional (builtins.pathExists appModule)  appModule
        ++ lib.optional (builtins.pathExists anixModule) anixModule
        ++ lib.optional (builtins.pathExists anixLayer)  anixLayer;
    };
  };
}
NIXEOF
}

copy_github_auth() {
    local root="${1:-/mnt}"
    local src="/root/.config/gh/hosts.yml"
    [[ -f "$src" && "$github_identity" != "Skipped" ]] || return 0
    local dst="${root}/home/${username_value}/.config/gh"
    mkdir -p "$dst"
    cp "$src" "$dst/hosts.yml"
    chmod 600 "$dst/hosts.yml"
    chown -R 1000:100 "$dst" 2>/dev/null || true
}

resolve_nixpkgs() {
    local c
    for c in "${ABORA_NIXPKGS_PATH:-}" /etc/abora/nixpkgs /etc/nix/path/nixpkgs; do
        [[ -n "$c" && -d "$c" ]] && printf '%s\n' "$c" && return 0
    done
    return 1
}

validate_boot() {
    [[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]] && return 0
    find /mnt/boot -maxdepth 3 \
        \( -iname '*limine*.efi' -o -iname 'limine-bios.sys' \) 2>/dev/null \
        | grep -q . && return 0
    die "Bootloader not found after nixos-install. See ${install_log}."
}

validate_generated_config() {
    local root="${1:-/mnt}"
    local nixpkgs="$2"

    command -v nix-instantiate >/dev/null 2>&1 || return 0
    NIX_PATH="nixpkgs=${nixpkgs}:nixos-config=${root}/etc/nixos/configuration.nix" \
        nix-instantiate '<nixpkgs/nixos>' \
            -A config.system.nixos.variantName \
            --eval --strict >>"$config_log" 2>&1
}

cleanup_target() {
    sync || true
    umount -R /mnt >/dev/null 2>&1 || true
}

eject_media() {
    command -v eject >/dev/null 2>&1 || return 0
    local d
    for d in /dev/sr0 /dev/cdrom /dev/disk/by-label/ABORA*; do
        [[ -e "$d" ]] && eject "$d" >/dev/null 2>&1 && return 0
    done
}

progress_line() {
    local percent="$1" label="$2" width=32 filled empty
    filled=$(( percent * width / 100 ))
    empty=$(( width - filled ))
    printf '  %b[%b' "$CF" "$R"
    printf '%*s' "$filled" '' | tr ' ' '#'
    printf '%*s' "$empty" '' | tr ' ' '-'
    printf '%b]%b %3d%%  %s\n' "$CF" "$R" "$percent" "$label"
}

run_install() {
    printf '\033[2J\033[H'
    printf '\n'
    draw_logo
    printf '\n'
    printf '  %bInstalling Abora Denali...%b\n' "${D}${CC}" "$R"
    printf '  %bLog: %s%b\n' "${D}${CG}" "$install_log" "$R"
    rule
    printf '\n'

    : > "$install_log"

    progress_line 5 "Starting"
    msg "Preparing target disk…"
    if ! partition_disk; then die "Partitioning failed. See ${install_log}."; fi
    progress_line 20 "Disk ready"
    ok "Disk partitioned"

    msg "Mounting target system…"
    if ! mount_target; then die "Mounting failed. See ${install_log}."; fi
    progress_line 32 "Target mounted"
    ok "Mounted"

    msg "Generating NixOS configuration…"
    if ! generate_nixos_config "/mnt"; then die "Config generation failed. See ${config_log}."; fi
    progress_line 45 "Configuration written"
    ok "Configuration written"

    local nixpkgs
    nixpkgs="$(resolve_nixpkgs || true)"
    [[ -n "$nixpkgs" ]] || die "Cannot resolve nixpkgs path."

    msg "Validating generated configuration…"
    if ! validate_generated_config "/mnt" "$nixpkgs"; then
        die "Generated NixOS configuration failed validation. See ${config_log}."
    fi
    progress_line 55 "Configuration validated"
    ok "Configuration validated"

    msg "Running nixos-install…  (grab a coffee, this takes a few minutes)"
    if ! NIX_PATH="nixpkgs=${nixpkgs}:nixos-config=/mnt/etc/nixos/configuration.nix" \
        nixos-install --root /mnt --no-root-passwd >>"$install_log" 2>&1; then
        die "nixos-install failed. See ${install_log}."
    fi
    progress_line 90 "System installed"

    validate_boot

    msg "Copying credentials…"
    copy_github_auth "/mnt"
    progress_line 100 "Complete"
    ok "Done! Abora OS is installed."
    printf '\n'
}

# ═══════════════════════════════════════════════════════════════════════════════
#  FINISH SCREENS
# ═══════════════════════════════════════════════════════════════════════════════

page_done() {
    printf '\033[2J\033[H'
    printf '\n'
    printf '  %b◈  ABORA OS%b  —  Denali Edition\n' "${B}${CS}" "$R"
    printf '\n'
    printf '  %b✓%b  Installation complete!\n' "$CP" "$R"
    printf '\n'
    printf '  %bLogs:%b\n' "${D}${CG}" "$R"
    printf '    config:   %s\n' "$config_log"
    printf '    install:  %s\n' "$install_log"
    printf '\n'

    menu "What would you like to do?" \
        "Reboot into Abora OS|Boot your freshly installed system" \
        "Power off|Shut down the machine" \
        "Stay in live shell|Remain in the live environment"

    case "$MENU_RESULT" in
        0) cleanup_target; eject_media; sync || true; systemctl reboot 2>/dev/null || reboot ;;
        1) cleanup_target; eject_media; sync || true; systemctl poweroff 2>/dev/null || poweroff ;;
        2)
            printf '\nRemaining in live shell.\n'
            printf '  config:  %s\n' "$config_log"
            printf '  install: %s\n\n' "$install_log"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  RECONFIG MODE
# ═══════════════════════════════════════════════════════════════════════════════

read_current_config() {
    local f="/etc/nixos/abora-local.nix"
    [[ -f "$f" ]] || return 0
    local v
    v="$(sed -nE 's/^[[:space:]]*networking\.hostName *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && hostname_value="$v"
    v="$(sed -nE 's/^[[:space:]]*time\.timeZone *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && timezone_value="$v"
    v="$(sed -nE 's/^[[:space:]]*console\.keyMap *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && keyboard_value="$v"
}

read_anix_config() {
    local f="/etc/nixos/anix.nix"
    [[ -f "$f" ]] || return 0
    local v
    v="$(sed -nE 's/^[[:space:]]*anix\.desktop *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && desktop_profile="$v"
    v="$(sed -nE 's/^[[:space:]]*anix\.hostname *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && hostname_value="$v"
}

run_reconfig() {
    printf '\033[2J\033[H'
    printf '\n'
    printf '  %b◈  ABORA OS%b  —  Reconfiguration\n\n' "${B}${CS}" "$R"

    local cfgdir="/etc/nixos"

    msg "Updating app list…"
    write_starter_apps_list "${cfgdir}/abora/apps.list"
    render_apps_nix "${cfgdir}/abora/apps.nix" "${cfgdir}/abora/apps.list"
    ok "App list updated"

    if [[ "$anix_enabled" == "yes" && -f "${cfgdir}/anix.nix" ]]; then
        msg "Updating anix.nix…"
        sed -i \
            -e "s|anix\.hostname *= *\"[^\"]*\"|anix.hostname = \"${hostname_value}\"|" \
            -e "s|anix\.timezone *= *\"[^\"]*\"|anix.timezone = \"${timezone_value}\"|" \
            -e "s|anix\.desktop *= *\"[^\"]*\"|anix.desktop = \"${desktop_profile}\"|" \
            "${cfgdir}/anix.nix" 2>/dev/null || true
        ok "anix.nix updated"
    fi

    local abora_local="${cfgdir}/abora-local.nix"
    if [[ -f "$abora_local" ]]; then
        msg "Updating abora-local.nix…"
        sed -i \
            -e "s|networking\.hostName *= *\"[^\"]*\"|networking.hostName = \"${hostname_value}\"|" \
            -e "s|time\.timeZone *= *\"[^\"]*\"|time.timeZone = \"${timezone_value}\"|" \
            -e "s|console\.keyMap *= *\"[^\"]*\"|console.keyMap = \"${keyboard_value}\"|" \
            "$abora_local" 2>/dev/null || true
        ok "abora-local.nix updated"
    fi

    msg "Running nixos-rebuild switch…"
    if ! nixos-rebuild switch >>"$install_log" 2>&1; then
        die "nixos-rebuild switch failed. See ${install_log}."
    fi
    ok "Reconfiguration applied!"
    printf '\n'
}

page_done_reconfig() {
    printf '\n'
    printf '  %b✓%b  Your changes are live.\n' "$CP" "$R"
    printf '  %bSome changes may need a re-login or reboot.%b\n\n' "${D}${CI}" "$R"

    menu "What next?" \
        "Close|Exit the setup tool" \
        "Reboot|Restart to fully apply all changes"
    case "$MENU_RESULT" in
        0) : ;;
        1) systemctl reboot 2>/dev/null || reboot ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    require_root
    trap 'if [[ "${reconfig_mode:-0}" != "1" ]]; then cleanup_target; fi' EXIT
    detect_defaults
    refresh_github_identity

    page_welcome

    if [[ "${reconfig_mode:-0}" == "1" ]]; then
        read_current_config
        read_anix_config

        step_identity
        step_desktop
        step_apps
        step_options

        tab_header 7
        printf '  %bReconfiguration Summary%b\n\n' "${B}${CS}" "$R"
        _print_summary

        menu "Apply reconfiguration?" \
            "Apply now|Write config and run nixos-rebuild switch" \
            "Cancel|Discard changes and exit"
        if [[ "$MENU_RESULT" -eq 1 ]]; then exit 0; fi

        run_reconfig
        page_done_reconfig
    else
        step_network
        step_identity
        step_desktop
        step_apps
        step_options
        step_disk
        step_confirm
        run_install
        page_done
    fi
}

main "$@"
