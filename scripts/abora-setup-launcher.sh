#!/usr/bin/env bash
# Abora OS Setup Launcher
# Launched from the desktop app menu — opens the installer TUI in the best
# available terminal emulator, running in --reconfig mode so it reconfigures
# the installed system without touching the bootloader or partitions.

set -euo pipefail

INSTALLER="${ABORA_INSTALLER:-/etc/abora/installer.sh}"

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

# ── Terminal detection (ordered by preference) ────────────────────────────────
# Each entry: "command|launch args that run a program"
TERMINALS=(
    "kgx|kgx --"
    "gnome-terminal|gnome-terminal --"
    "ptyxis|ptyxis --"
    "konsole|konsole -e"
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
if already_root; then
    RUNNER=(bash "$INSTALLER" --reconfig)
else
    if command -v sudo >/dev/null 2>&1; then
        RUNNER=(sudo bash "$INSTALLER" --reconfig)
    elif command -v pkexec >/dev/null 2>&1; then
        RUNNER=(pkexec bash "$INSTALLER" --reconfig)
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
