#!/usr/bin/env bash
# Abora OS Setup Launcher
# Launched from the desktop app menu. On the live ISO it starts the installer;
# on an installed system it opens the reconfiguration flow.

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

# ── Build the command to run inside the terminal ──────────────────────────────

RUNNER=()
mapfile -t INSTALLER_ARGS < <(installer_args)
if already_root; then
    RUNNER=(bash "$INSTALLER" "${INSTALLER_ARGS[@]}")
else
    sudo_bin="$(sudo_cmd || true)"
    if [[ -n "$sudo_bin" ]]; then
        RUNNER=("$sudo_bin" bash "$INSTALLER" "${INSTALLER_ARGS[@]}")
    elif command -v pkexec >/dev/null 2>&1; then
        RUNNER=(pkexec bash "$INSTALLER" "${INSTALLER_ARGS[@]}")
    else
        printf 'abora-setup: neither sudo nor pkexec found\n' >&2
        exit 1
    fi
fi

# ── Launch ───────────────────────────────────────────────────────────────────

# If we already have a terminal (stdin is a tty and DISPLAY/WAYLAND_DISPLAY not set)
# just run directly — useful for testing from a shell.
if [[ -t 0 && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    exec "${RUNNER[@]}"
fi

# Otherwise, open a terminal window.
term_args="$(find_terminal 2>/dev/null || true)"
if [[ -z "$term_args" ]]; then
    printf 'abora-setup: no supported terminal emulator found.\n' >&2
    printf 'Install one of: kgx gnome-terminal alacritty kitty konsole xterm\n' >&2
    exit 1
fi

# shellcheck disable=SC2086
exec $term_args "${RUNNER[@]}"
