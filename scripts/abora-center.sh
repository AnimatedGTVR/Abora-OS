#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

version="${ABORA_VERSION:-v1.0.1}"
APP_TITLE="Abora Center ${version}"
APP_WIDTH="${ABORA_CENTER_WIDTH:-980}"
APP_HEIGHT="${ABORA_CENTER_HEIGHT:-640}"
installer_script="/etc/abora/installer.sh"
welcome_cmd="${ABORA_WELCOME_CMD:-abora-welcome}"
gui_launcher="${ABORA_GUI_WRAPPER:-/etc/abora/launch-gui.sh}"

require_graphics() {
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        if [[ -x "$gui_launcher" ]]; then
            exec "$gui_launcher" "abora-center"
        fi
        printf '%s requires a graphical session.\n' "$APP_TITLE" >&2
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    local label="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    zenity --error \
        --title="$APP_TITLE" \
        --width=420 \
        --text="${label} is not available in this build."
    return 1
}

show_text_window() {
    local title="$1"
    local body="$2"
    local tmp=""

    tmp="$(mktemp)"
    printf '%s\n' "$body" >"$tmp"
    zenity --text-info \
        --title="$title" \
        --width="$APP_WIDTH" \
        --height="$APP_HEIGHT" \
        --font="Monospace 11" \
        --filename="$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp"
}

system_overview_text() {
    cat <<EOF
Abora live environment

Hostname: $(hostname)
Kernel: $(uname -r)
Architecture: $(uname -m)
Uptime: $(uptime -p 2>/dev/null || uptime)
Shell: ${SHELL:-bash}
User: $(id -un)

Memory
$(free -h 2>/dev/null || printf 'free is unavailable')

Fastfetch
$(fastfetch -c /etc/xdg/fastfetch/config.jsonc --pipe false 2>/dev/null || printf 'fastfetch is unavailable')
EOF
}

network_text() {
    cat <<EOF
Network overview

$(ip -br link 2>/dev/null || printf 'ip link data is unavailable')

Addresses
$(ip -br addr 2>/dev/null || printf 'ip address data is unavailable')

Routes
$(ip route 2>/dev/null || printf 'ip route data is unavailable')
EOF
}

storage_text() {
    cat <<EOF
Storage overview

$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL 2>/dev/null || printf 'lsblk is unavailable')

Filesystems
$(df -h 2>/dev/null || printf 'df is unavailable')
EOF
}

logs_text() {
    journalctl -b -n 120 --no-pager 2>/dev/null || printf 'journalctl is unavailable\n'
}

launch_terminal_command() {
    local title="$1"
    shift

    require_command xterm "xterm" || return 1
    xterm -fa "Monospace" -fs 11 -geometry 132x36 -T "$title" -e "$@" >/dev/null 2>&1 &
}

launch_installer() {
    if [[ ! -x "$installer_script" ]]; then
        zenity --error \
            --title="$APP_TITLE" \
            --width=420 \
            --text="The installer is not available in this environment."
        return 1
    fi

    launch_terminal_command "Abora Installer" "$installer_script"
}

show_power_menu() {
    local choice=""

    choice="$(
        zenity --list \
            --title="Power" \
            --text="Choose a power action." \
            --width=520 \
            --height=260 \
            --ok-label="Run" \
            --cancel-label="Back" \
            --column="Action" \
            --column="Description" \
            "Reboot" "Restart this machine" \
            "Power off" "Shut this machine down" \
            2>/dev/null
    )" || return 0

    case "$choice" in
        Reboot*)
            systemctl reboot
            ;;
        Power\ off*)
            systemctl poweroff
            ;;
    esac
}

main_menu() {
    zenity --list \
        --title="$APP_TITLE" \
        --text="A live-session control hub for install, diagnostics, and recovery in Abora OS ${version}." \
        --width="$APP_WIDTH" \
        --height="$APP_HEIGHT" \
        --ok-label="Open" \
        --cancel-label="Close" \
        --extra-button="Welcome" \
        --column="Action" \
        --column="Description" \
        "Install Abora OS" "Launch the graphical install workflow in a dedicated terminal window" \
        "System Overview" "See hardware, uptime, and live-session details" \
        "Network" "Inspect interfaces, addresses, and routes" \
        "Storage" "See disks, partitions, and mounted filesystems" \
        "Logs" "Read recent journal output from this boot" \
        "Shell" "Open a root shell in a separate terminal" \
        "Power" "Reboot or power off" \
        2>/dev/null
}

main() {
    local choice=""

    require_graphics
    require_command zenity "Zenity" || exit 1

    while true; do
        choice="$(main_menu)" || exit 0

        case "$choice" in
            "Install Abora OS"*)
                launch_installer
                ;;
            "System Overview"*)
                show_text_window "System Overview" "$(system_overview_text)"
                ;;
            "Network"*)
                show_text_window "Network Overview" "$(network_text)"
                ;;
            "Storage"*)
                show_text_window "Storage Overview" "$(storage_text)"
                ;;
            "Logs"*)
                show_text_window "Recent Logs" "$(logs_text)"
                ;;
            "Shell"*)
                launch_terminal_command "Abora Shell" "${SHELL:-/bin/bash}" --login
                ;;
            "Power"*)
                show_power_menu
                ;;
            Welcome)
                "$welcome_cmd" >/dev/null 2>&1 || true
                ;;
        esac
    done
}

main "$@"
