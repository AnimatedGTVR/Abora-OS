#!/usr/bin/env bash
# abora-ui.sh — shared terminal UI primitives for Abora OS tools.
# Source this file; do not execute it directly.
#
# All functions are prefixed with abora_ to avoid collisions.
# Palette variables use the ABORA_ prefix.

# ── Version ───────────────────────────────────────────────────────────────────

_abora_ui_resolve_version() {
    if [[ -n "${ABORA_VERSION:-}" ]]; then
        printf '%s' "$ABORA_VERSION"
        return
    fi
    if [[ -f /etc/abora/VERSION ]]; then
        tr -d '[:space:]' < /etc/abora/VERSION
        return
    fi
    printf 'v2.5.0'
}

ABORA_UI_VERSION="$(_abora_ui_resolve_version)"

# ── Palette ───────────────────────────────────────────────────────────────────
# Matches the installer's ocean-themed palette exactly.

ABORA_BLUE='\033[38;5;33m'       # ocean blue   – borders, rules
ABORA_ACCENT='\033[38;5;87m'     # bright aqua  – selected state, highlights
ABORA_CYAN='\033[38;5;44m'       # sea teal     – steps, field values
ABORA_YELLOW='\033[38;5;222m'    # warm amber   – warnings
ABORA_WHITE='\033[1;97m'         # salt white   – titles, headings
ABORA_DIM='\033[38;5;242m'       # mist gray    – secondary text
ABORA_FAINT='\033[38;5;237m'     # abyss gray   – decorations, ultra-dim
ABORA_GREEN='\033[38;5;77m'      # kelp green   – success
ABORA_RED='\033[38;5;203m'       # coral red    – errors
ABORA_MAGENTA='\033[38;5;213m'   # sea rose     – mild highlights
ABORA_NC='\033[0m'               # reset

# ── Terminal helpers ──────────────────────────────────────────────────────────

abora_cols() {
    local cols
    cols="$(tput cols 2>/dev/null || printf '80')"
    printf '%s' "${cols:-80}"
}

_abora_repeat() {
    local char="$1" count="$2" out=""
    while [[ "$count" -gt 0 ]]; do
        out+="$char"
        count=$((count - 1))
    done
    printf '%s' "$out"
}

abora_trunc() {
    local str="$1" max="$2"
    if [[ "${#str}" -gt "$max" ]]; then
        printf '%s...' "${str:0:$((max - 3))}"
    else
        printf '%s' "$str"
    fi
}

# ── Visual primitives ─────────────────────────────────────────────────────────

abora_rule() {
    local cols
    cols="$(abora_cols)"
    printf '  %b' "$ABORA_FAINT"
    _abora_repeat '─' $((cols - 4))
    printf '%b\n' "$ABORA_NC"
}

abora_brand_header() {
    local cols inner left right pad
    cols="$(abora_cols)"
    inner=$((cols - 2))
    [[ $inner -lt 20 ]] && inner=20

    left="  ▸ ABORA OS"
    right="${ABORA_UI_VERSION}  "
    pad=$((inner - ${#left} - ${#right}))
    [[ $pad -lt 1 ]] && pad=1

    printf '%b╭' "$ABORA_BLUE"
    _abora_repeat '─' "$inner"
    printf '╮%b\n' "$ABORA_NC"

    printf '%b│%b%b%s%b' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_WHITE" "$left" "$ABORA_NC"
    printf '%*s' "$pad" ''
    printf '%b%s%b%b│%b\n' "$ABORA_DIM" "$right" "$ABORA_NC" "$ABORA_BLUE" "$ABORA_NC"

    printf '%b╰' "$ABORA_BLUE"
    _abora_repeat '─' "$inner"
    printf '╯%b\n' "$ABORA_NC"
}

# Print a banner without clearing the screen — for non-interactive CLI tools.
abora_banner() {
    local title="${1:-}" subtitle="${2:-}"
    printf '\n'
    abora_brand_header
    if [[ -n "$title" ]]; then
        printf '\n  %b%s%b\n' "$ABORA_WHITE" "$title" "$ABORA_NC"
    fi
    if [[ -n "$subtitle" ]]; then
        printf '  %b%s%b\n' "$ABORA_DIM" "$subtitle" "$ABORA_NC"
    fi
    printf '\n'
    abora_rule
    printf '\n'
}

# ── Log line helpers ──────────────────────────────────────────────────────────

abora_info() {
    printf '  %b·%b  %s\n' "$ABORA_BLUE" "$ABORA_NC" "$1"
}

abora_success() {
    printf '  %b✓%b  %b%s%b\n' "$ABORA_GREEN" "$ABORA_NC" "$ABORA_GREEN" "$1" "$ABORA_NC"
}

abora_warn() {
    printf '  %b!%b  %b%s%b\n' "$ABORA_YELLOW" "$ABORA_NC" "$ABORA_YELLOW" "$1" "$ABORA_NC"
}

abora_error() {
    printf '  %b✗%b  %b%s%b\n' "$ABORA_RED" "$ABORA_NC" "$ABORA_RED" "$1" "$ABORA_NC" >&2
}

abora_step() {
    printf '  %b▸%b  %s\n' "$ABORA_CYAN" "$ABORA_NC" "$1"
}

abora_dim_line() {
    printf '  %b%s%b\n' "$ABORA_DIM" "$1" "$ABORA_NC"
}

# ── Progress bar ──────────────────────────────────────────────────────────────

abora_progress() {
    local percent="$1" cols width filled empty

    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    cols="$(abora_cols)"
    width=$((cols - 12))
    [[ $width -lt 20 ]] && width=20
    [[ $width -gt 60 ]] && width=60

    filled=$((percent * width / 100))
    empty=$((width - filled))

    printf '  %b' "$ABORA_BLUE"
    _abora_repeat '█' "$filled"
    printf '%b' "$ABORA_FAINT"
    _abora_repeat '░' "$empty"
    printf '%b  %b%3d%%%b\n' "$ABORA_NC" "$ABORA_WHITE" "$percent" "$ABORA_NC"
}

abora_format_elapsed() {
    local secs="$1" m=0 h=0
    h=$((secs / 3600))
    m=$(((secs % 3600) / 60))
    secs=$((secs % 60))
    if [[ "$h" -gt 0 ]]; then
        printf '%02dh %02dm %02ds' "$h" "$m" "$secs"
    else
        printf '%02dm %02ds' "$m" "$secs"
    fi
}

# ── Log tail ──────────────────────────────────────────────────────────────────

abora_log_tail() {
    local logfile="$1" cols width line

    cols="$(abora_cols)"
    width=$((cols - 6))
    [[ $width -lt 20 ]] && width=20

    if [[ ! -s "$logfile" ]]; then
        printf '  %bno output captured yet%b\n' "$ABORA_FAINT" "$ABORA_NC"
        return 0
    fi

    while IFS= read -r line; do
        printf '  %b%s%b\n' "$ABORA_FAINT" "$(abora_trunc "$line" "$width")" "$ABORA_NC"
    done < <(tail -n 10 "$logfile")
}
