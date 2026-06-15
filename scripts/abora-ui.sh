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
    printf '3.1.4'
}

ABORA_UI_VERSION="$(_abora_ui_resolve_version)"

# ── Palette ───────────────────────────────────────────────────────────────────
# Ocean-themed palette — consistent across all Abora terminal tools.

ABORA_BLUE=$'\033[38;5;33m'       # ocean blue   – borders, rules
ABORA_ACCENT=$'\033[38;5;87m'     # bright aqua  – selected state, highlights
ABORA_CYAN=$'\033[38;5;44m'       # sea teal     – steps, field values
ABORA_YELLOW=$'\033[38;5;222m'    # warm amber   – warnings
ABORA_WHITE=$'\033[1;97m'         # salt white   – titles, headings
ABORA_DIM=$'\033[38;5;242m'       # mist gray    – secondary text
ABORA_FAINT=$'\033[38;5;237m'     # abyss gray   – decorations, ultra-dim
ABORA_GREEN=$'\033[38;5;77m'      # kelp green   – success
ABORA_RED=$'\033[38;5;203m'       # coral red    – errors
ABORA_MAGENTA=$'\033[38;5;213m'   # sea rose     – mild highlights
ABORA_NC=$'\033[0m'               # reset

# ── Terminal helpers ──────────────────────────────────────────────────────────

abora_cols() {
    local cols
    cols="$(tput cols 2>/dev/null || printf '80')"
    printf '%s' "${cols:-80}"
}

abora_rows() {
    local rows
    rows="$(tput lines 2>/dev/null || printf '24')"
    printf '%s' "${rows:-24}"
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

abora_double_rule() {
    local cols
    cols="$(abora_cols)"
    printf '  %b' "$ABORA_BLUE"
    _abora_repeat '═' $((cols - 4))
    printf '%b\n' "$ABORA_NC"
}

abora_wave_rule() {
    local cols
    cols="$(abora_cols)"
    printf '  %b' "$ABORA_FAINT"
    _abora_repeat '·' $((cols - 4))
    printf '%b\n' "$ABORA_NC"
}

# ── ASCII art logo ────────────────────────────────────────────────────────────

ABORA_ASCII_LOGO='
  %b▸▸%b %bABORA OS%b  %b'"%s"'

  %b    ,ggg,                                                         _,gggggg,_          ,gg,%b
  %b   dP""8I   ,dPYb,                                              ,d8P""d8P"Y8b,       i8""8i %b
  %b  dP   88   IP'"'"'`Yb                                             ,d8'"'"'   Y8   "8b,dP    `8,,8'"'"' %b
  %b dP    88   I8  8I                                             d8'"'"'    `Ybaaad88P'"'"'     `88'"'"'  %b
  %b,8'"'"'    88   I8  8'"'"'                                             8P       `""""Y8       dP"8,%b
  %bd88888888   I8 dP         ,ggggg,     ,gggggg,    ,gggg,gg     8b            d8      dP'"'"' `8a %b
  %b,8"     88   I8dP   88gg  dP"  "Y8ggg  dP""""8I   dP"  "Y8I     Y8,          ,8P     dP'"'"'   `Yb%b
  %bdP"  ,8P      Y8   I8P    8I   i8'"'"'    ,8I   ,8'"'"'    8I  i8'"'"'    ,8I     `Y8,        ,8P'"'"' _ ,dP'"'"'     I8%b
  %bYb,_,dP       `8b,,d8b,  ,8I  ,d8,   ,d8'"'"'  ,dP     Y8,,d8,   ,d8b,     `Y8b,,__,,d8P'"'"'  "888,,____,dP%b
  %b "Y8P"         `Y88P'"'"'"Y88P'"'"'  P"Y8888P"    8P      `Y8P"Y8888P"`Y8       `"Y8888P'"'"'    a8P"Y88888P" %b
'

abora_ascii_header() {
    local ver="${1:-$ABORA_UI_VERSION}"
    printf "$ABORA_ASCII_LOGO" \
        "$ABORA_ACCENT" "$ABORA_NC" \
        "$ABORA_WHITE" "$ABORA_NC" \
        "$ABORA_DIM" "$ver" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC" \
        "$ABORA_FAINT" "$ABORA_BLUE" "$ABORA_FAINT" "$ABORA_NC"
}

# ── Brand header ──────────────────────────────────────────────────────────────

abora_brand_header() {
    local cols inner left right pad max_left
    cols="$(abora_cols)"
    inner=$((cols - 6))
    [[ $inner -lt 18 ]] && inner=18

    left="  ▸ ABORA OS"
    right="${ABORA_UI_VERSION}  "
    max_left=$((inner - ${#right} - 1))
    [[ $max_left -lt 6 ]] && max_left=6
    if [[ "${#left}" -gt "$max_left" ]]; then
        left="$(abora_trunc "$left" "$max_left")"
    fi
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

# Compact brand line — fits in one row without a box.
abora_brand_line() {
    local ver="${1:-$ABORA_UI_VERSION}"
    printf '%b▸%b %bABORA OS%b  %b%s%b\n' \
        "$ABORA_ACCENT" "$ABORA_NC" \
        "$ABORA_WHITE" "$ABORA_NC" \
        "$ABORA_DIM" "$ver" "$ABORA_NC"
}

# ── Card box ──────────────────────────────────────────────────────────────────

# Draw a bordered card with an optional title.
# Usage: abora_card "Title" "content lines..."
# The card auto-wraps content within the terminal width.
abora_card_start() {
    local title="${1:-}" cols inner
    cols="$(abora_cols)"
    inner=$((cols - 6))
    [[ $inner -lt 20 ]] && inner=20
    [[ $inner -gt 70 ]] && inner=70

    printf '  %b╭─' "$ABORA_BLUE"
    if [[ -n "$title" ]]; then
        printf '%b %s ' "$ABORA_ACCENT" "$title"
        local remaining=$((inner - ${#title} - 3))
        [[ $remaining -lt 0 ]] && remaining=0
        _abora_repeat '─' "$remaining"
    else
        _abora_repeat '─' "$inner"
    fi
    printf '╮%b\n' "$ABORA_NC"
}

abora_card_end() {
    local cols inner
    cols="$(abora_cols)"
    inner=$((cols - 6))
    [[ $inner -lt 20 ]] && inner=20
    [[ $inner -gt 70 ]] && inner=70

    printf '  %b╰' "$ABORA_BLUE"
    _abora_repeat '─' "$((inner + 1))"
    printf '╯%b\n' "$ABORA_NC"
}

# ── Step indicator ────────────────────────────────────────────────────────────

# Render a horizontal step flow:  ① Welcome  →  ② Names  →  ③ Locale ...
# Args: current_step total_steps step_names...
abora_step_indicator() {
    local current="$1" total="$2"
    shift 2
    local names=("$@")
    local cols i label sep
    cols="$(abora_cols)"

    for ((i = 0; i < total; i++)); do
        label="${names[$i]:-Step $((i+1))}"

        if [[ "$i" -lt "$current" ]]; then
            # completed
            printf '  %b✓%b %b%s%b' "$ABORA_GREEN" "$ABORA_NC" "$ABORA_GREEN" "$label" "$ABORA_NC"
        elif [[ "$i" -eq "$current" ]]; then
            # active
            printf '  %b●%b %b%s%b' "$ABORA_ACCENT" "$ABORA_NC" "$ABORA_WHITE" "$label" "$ABORA_NC"
        else
            # upcoming
            printf '  %b○%b %b%s%b' "$ABORA_FAINT" "$ABORA_NC" "$ABORA_DIM" "$label" "$ABORA_NC"
        fi

        if [[ "$i" -lt $((total - 1)) ]]; then
            if [[ "$i" -lt "$current" ]]; then
                sep=" %b──%b "
            elif [[ "$i" -eq "$current" ]]; then
                sep=" %b─▶%b "
            else
                sep=" %b──%b "
            fi
            printf "$sep" "$ABORA_FAINT" "$ABORA_NC"
        fi
    done
    printf '\n'
}

# ── Banner ────────────────────────────────────────────────────────────────────

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

# Compact banner using the ASCII logo (only on wide terminals).
abora_wide_banner() {
    local title="${1:-}" subtitle="${2:-}"
    local cols
    cols="$(abora_cols)"

    printf '\n'
    if [[ "$cols" -ge 78 ]]; then
        abora_ascii_header
        printf '\n'
        abora_wave_rule
    else
        abora_brand_header
    fi
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

# ── Key-value row ─────────────────────────────────────────────────────────────

# Print a neatly aligned key-value pair.
# Usage: abora_kv "key" "value" [key_width]
abora_kv() {
    local key="$1" value="$2" key_width="${3:-18}"
    printf '  %b%-*s%b  %b%s%b\n' \
        "$ABORA_DIM" "$key_width" "$key" "$ABORA_NC" \
        "$ABORA_CYAN" "$value" "$ABORA_NC"
}

# Print a key-value with a dim/faint value (for read-only info).
abora_kv_faint() {
    local key="$1" value="$2" key_width="${3:-18}"
    printf '  %b%-*s%b  %b%s%b\n' \
        "$ABORA_DIM" "$key_width" "$key" "$ABORA_NC" \
        "$ABORA_FAINT" "$value" "$ABORA_NC"
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

# Smooth progress bar with gradient-like shading.
abora_progress_smooth() {
    local percent="$1" cols width filled empty mid
    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    cols="$(abora_cols)"
    width=$((cols - 12))
    [[ $width -lt 20 ]] && width=20
    [[ $width -gt 60 ]] && width=60

    filled=$((percent * width / 100))
    empty=$((width - filled))

    # Use accent color for the leading edge
    if [[ "$filled" -gt 1 ]]; then
        mid=$((filled - 1))
        printf '  %b' "$ABORA_BLUE"
        _abora_repeat '█' "$mid"
        printf '%b█' "$ABORA_ACCENT"
    elif [[ "$filled" -eq 1 ]]; then
        printf '  %b█' "$ABORA_ACCENT"
    else
        printf '  %b' "$ABORA_BLUE"
    fi
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

# ── Spinner ───────────────────────────────────────────────────────────────────

# Simple one-frame spinner for non-blocking status.
# Usage: abora_spinner_tick "message" [frame_number]
_abora_spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

abora_spinner_tick() {
    local msg="$1" frame="${2:-0}"
    local idx=$((frame % ${#_abora_spinner_frames[@]}))
    printf '\r  %b%s%b  %s' "$ABORA_ACCENT" "${_abora_spinner_frames[$idx]}" "$ABORA_NC" "$msg"
}

# Clear the spinner line.
abora_spinner_done() {
    printf '\r%*s\r' "$(abora_cols)" ''
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

# ── Checkbox menu helper ─────────────────────────────────────────────────────

# Render a checkbox-style option.
# Usage: abora_checkbox "label" is_checked
abora_checkbox() {
    local label="$1" checked="$2"
    if [[ "$checked" == "yes" || "$checked" == "true" ]]; then
        printf '  %b[✓]%b %b%s%b\n' "$ABORA_ACCENT" "$ABORA_NC" "$ABORA_WHITE" "$label" "$ABORA_NC"
    else
        printf '  %b[ ]%b %b%s%b\n' "$ABORA_FAINT" "$ABORA_NC" "$ABORA_DIM" "$label" "$ABORA_NC"
    fi
}
