#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

version="${ABORA_VERSION:-v1.0.1}"
APP_TITLE="Abora Welcome ${version}"
APP_WIDTH="${ABORA_WELCOME_WIDTH:-900}"
APP_HEIGHT="${ABORA_WELCOME_HEIGHT:-560}"
center_cmd="${ABORA_CENTER_CMD:-abora-center}"
installer_script="/etc/abora/installer.sh"
gui_launcher="${ABORA_GUI_WRAPPER:-/etc/abora/launch-gui.sh}"

require_graphics() {
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        if [[ -x "$gui_launcher" ]]; then
            exec "$gui_launcher" "abora-welcome"
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

launch_terminal_command() {
    local title="$1"
    shift

    require_command xterm "xterm" || return 1
    xterm -fa "Monospace" -fs 11 -geometry 132x36 -T "$title" -e "$@" >/dev/null 2>&1 &
}

start_installer() {
    if [[ ! -x "$installer_script" ]]; then
        zenity --error \
            --title="$APP_TITLE" \
            --width=420 \
            --text="The installer is not available in this environment."
        return 1
    fi

    launch_terminal_command "Abora Installer" "$installer_script"
}

show_about() {
    zenity --info \
        --title="$APP_TITLE" \
        --width=520 \
        --height=260 \
        --text="Abora OS ${version}

Welcome is the quick entry point for the live build.

Open Abora Center for the full control hub, launch the installer, or drop into a shell when you need it."
}

show_main_dialog() {
    zenity --list \
        --title="$APP_TITLE" \
        --text="Welcome to Abora OS ${version}. Pick where you want to start." \
        --width="$APP_WIDTH" \
        --height="$APP_HEIGHT" \
        --ok-label="Open" \
        --cancel-label="Close" \
        --extra-button="About" \
        --column="Action" \
        --column="Description" \
        "Open Abora Center" "Launch the main live-session control app" \
        "Start Installer" "Open the installer in a dedicated terminal window" \
        "Open Shell" "Get a root shell for advanced work" \
        2>/dev/null
}

main() {
    local choice=""

    require_graphics
    require_command zenity "Zenity" || exit 1

    while true; do
        choice="$(show_main_dialog)" || exit 0

        case "$choice" in
            "Open Abora Center"*)
                "$center_cmd" >/dev/null 2>&1 || true
                ;;
            "Start Installer"*)
                start_installer
                ;;
            "Open Shell"*)
                launch_terminal_command "Abora Shell" "${SHELL:-/bin/bash}" --login
                ;;
            About)
                show_about
                ;;
        esac
    done
}

main "$@"
