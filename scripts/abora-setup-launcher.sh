#!/usr/bin/env bash
# Abora OS Setup Launcher
# Launched from the desktop app menu. The live ISO uses the MINT-powered TUI
# installer. On an installed system it opens the TUI reconfiguration flow.

set -euo pipefail

INSTALLER="${ABORA_INSTALLER:-/etc/abora/installer.sh}"
MODE="${ABORA_SETUP_MODE:-auto}"

# Fall back to well-known install paths if the env var isn't set
if [[ ! -f "$INSTALLER" ]]; then
    for candidate in \
        /etc/abora/abora-installer.sh \
        /run/current-system/sw/bin/abora-installer \
        "$(dirname "$0")/abora-installer.sh"; do
        [[ -f "$candidate" ]] && INSTALLER="$candidate" && break
    done
fi

[[ -f "$INSTALLER" ]] || {
    printf 'abora-setup: installer not found\n' >&2
    exit 1
}

# ── Privilege escalation ──────────────────────────────────────────────────────
# The installer needs root. If we're already root (e.g. launched by pkexec),
# run directly. Otherwise use sudo inside the chosen terminal.

already_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

# Three independent signals, any one of which is enough: the NixOS ISO
# image marker files, the live-image README text this repo's own live.nix
# ships, and (as a last resort) simply not having an installed
# /etc/nixos/configuration.nix at all -- which is true on every live boot
# and false on every real install.
is_live_iso() {
    [[ -f /iso-image/iso-info || -e /run/current-system/iso-image ]] && return 0
    grep -qi 'live image' /etc/abora/README 2>/dev/null && return 0
    [[ ! -f /etc/nixos/configuration.nix ]] && return 0
    return 1
}

installer_args() {
    case "$MODE" in
        install|live)
            return 0
            ;;
        reconfig|installed)
            printf '%s\n' --reconfig
            return 0
            ;;
        auto|"")
            if is_live_iso; then
                return 0
            fi
            printf '%s\n' --reconfig
            return 0
            ;;
        *)
            printf 'abora-setup: unknown ABORA_SETUP_MODE: %s\n' "$MODE" >&2
            exit 1
            ;;
    esac
}

sudo_cmd() {
    if [[ -x /run/wrappers/bin/sudo ]]; then
        printf '%s\n' /run/wrappers/bin/sudo
        return 0
    fi
    command -v sudo 2>/dev/null
}

# ── Terminal detection (ordered by preference) ────────────────────────────────
# Each entry: "command|launch args that run a program"
TERMINALS=(
    "konsole|konsole -e"
    "kgx|kgx --"
    "gnome-terminal|gnome-terminal --"
    "ptyxis|ptyxis --"
    "xfce4-terminal|xfce4-terminal -x"
    "alacritty|alacritty -e"
    "kitty|kitty"
    "foot|foot"
    "wezterm|wezterm start --"
    "tilix|tilix -e"
    "xterm|xterm -e"
)

find_terminal() {
    local entry cmd args
    for entry in "${TERMINALS[@]}"; do
        cmd="${entry%%|*}"
        args="${entry#*|}"
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '%s\n' "$args"
            return 0
        fi
    done
    return 1
}

run_tui_installer() {
    local terminal_spec=""
    local terminal_cmd=()

    if terminal_spec="$(find_terminal 2>/dev/null)"; then
        # shellcheck disable=SC2206
        terminal_cmd=( $terminal_spec )
        exec "${terminal_cmd[@]}" "${RUNNER[@]}"
    fi

    exec "${RUNNER[@]}"
}

# ── Build the command to run inside the terminal ──────────────────────────────

RUNNER=()
mapfile -t INSTALLER_ARGS < <(installer_args)
INSTALLER_ENV=(
    "TERM=${TERM:-linux}"
    "ABORA_DESKTOP_PROFILES_LIB=${ABORA_DESKTOP_PROFILES_LIB:-/etc/abora/desktop-profiles.sh}"
    "ABORA_APP_CATALOG_LIB=${ABORA_APP_CATALOG_LIB:-/etc/abora/app-catalog.sh}"
    "ABORA_ZONEINFO_PATH=${ABORA_ZONEINFO_PATH:-/run/current-system/sw/share/zoneinfo}"
)

if already_root; then
    RUNNER=(env "${INSTALLER_ENV[@]}" bash "$INSTALLER" "${INSTALLER_ARGS[@]}")
else
    sudo_bin="$(sudo_cmd || true)"
    if [[ -n "$sudo_bin" ]]; then
        RUNNER=("$sudo_bin" env "${INSTALLER_ENV[@]}" bash "$INSTALLER" "${INSTALLER_ARGS[@]}")
    elif command -v pkexec >/dev/null 2>&1; then
        RUNNER=(pkexec env "${INSTALLER_ENV[@]}" bash "$INSTALLER" "${INSTALLER_ARGS[@]}")
    else
        printf 'abora-setup: neither sudo nor pkexec found\n' >&2
        exit 1
    fi
fi

run_tui_installer
