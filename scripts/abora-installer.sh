#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  ABORA OS INSTALLER  ·  v3
#  Two-panel TUI — sidebar step tracker + content area
# ════════════════════════════════════════════════════════════════════
set -uo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_lib() {
    local name="$1"
    local candidates=(
        "${2:-}"
        "$script_dir/$name"
        "$script_dir/abora-$name"
        "/etc/abora/$name"
        "/etc/abora/abora-$name"
    )
    for f in "${candidates[@]}"; do
        [[ -n "$f" && -f "$f" ]] && printf '%s' "$f" && return 0
    done
    return 1
}

desktop_profiles_lib="$(_find_lib "desktop-profiles.sh" "${ABORA_DESKTOP_PROFILES_LIB:-}")" || {
    printf 'abora-installer: desktop-profiles.sh not found\n' >&2; exit 1
}
app_catalog_lib="$(_find_lib "app-catalog.sh" "${ABORA_APP_CATALOG_LIB:-}")" || {
    printf 'abora-installer: app-catalog.sh not found\n' >&2; exit 1
}

# shellcheck source=/dev/null
source "$desktop_profiles_lib"
# shellcheck source=/dev/null
source "$app_catalog_lib"

# ── State ────────────────────────────────────────────────────────────────────
disk=""
efi_part=""
root_part=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
keyboard_value="us"
xkb_layout_value="us"
anix_enabled="yes"
desktop_profile="gnome"
desktop_label="GNOME"
desktop_variant_id="gnome"
wallpaper_name="oceandusk.png"
starter_apps_bundle="favorites"
starter_apps_label="Fan Favorites"
github_identity="Skipped"
user_password_hash=""
config_log="/tmp/abora-config.log"
install_log="/tmp/abora-install.log"
title_file="/etc/abora/title.txt"
version="${ABORA_VERSION:-}"
[[ -z "$version" && -f /etc/abora/VERSION ]] && version="$(tr -d '\n' < /etc/abora/VERSION)"
[[ -z "$version" ]] && version="v3"

# ── Colors ───────────────────────────────────────────────────────────────────
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
W='\033[1;37m'
BW='\033[0;37m'
C='\033[1;36m'
BC='\033[0;36m'
B='\033[1;34m'
G='\033[1;32m'
BG='\033[0;32m'
RD='\033[1;31m'
BR='\033[0;31m'
Y='\033[1;33m'
MG='\033[1;35m'
GY='\033[90m'

# ── Step result (set by step functions, read by main) ────────────────────────
STEP_RESULT=""

# ── Layout constants ─────────────────────────────────────────────────────────
SB_W=22          # sidebar width (includes its right border)
HDR_H=3          # header rows
FTR_H=2          # footer rows

# Computed each frame
COLS=80; ROWS=24
CT_R=0; CT_C=0; CT_H=0; CT_W=0   # content top-row, left-col, height, width

# ── Terminal primitives ───────────────────────────────────────────────────────
_at()   { printf '\033[%d;%dH' "$1" "$2"; }
_cls()  { printf '\033[2J\033[H'; }
_show() { tput cnorm 2>/dev/null || true; }
_hide() { tput civis 2>/dev/null || true; }
_save() { printf '\033[s'; }
_rest() { printf '\033[u'; }

_hline() {   # row col width [char]
    local r=$1 c=$2 w=$3 ch="${4:-─}"
    _at "$r" "$c"
    local line; line="$(printf '%*s' "$w" '' | tr ' ' "$ch")"
    printf '%s' "$line"
}

_box() {   # row col height width [title]
    local r=$1 c=$2 h=$3 w=$4 title="${5:-}"
    local inner=$((w-2)) ir ic
    # top
    _at "$r" "$c"
    if [[ -n "$title" ]]; then
        local tl=${#title}
        local lp=$(( (inner - tl - 2) / 2 ))
        local rp=$(( inner - tl - 2 - lp ))
        printf '┌'; printf '%*s' "$lp" | tr ' ' '─'
        printf ' %s ' "$title"
        printf '%*s' "$rp" | tr ' ' '─'; printf '┐'
    else
        printf '┌'; printf '%*s' "$inner" | tr ' ' '─'; printf '┐'
    fi
    # sides
    for (( ir = r+1; ir < r+h-1; ir++ )); do
        _at "$ir" "$c";         printf '│'
        _at "$ir" $((c+w-1));   printf '│'
    done
    # bottom
    _at $((r+h-1)) "$c"
    printf '└'; printf '%*s' "$inner" | tr ' ' '─'; printf '┘'
}

_fill() {   # row col height width [char]
    local r=$1 c=$2 h=$3 w=$4 ch="${5:- }"
    local line; line="$(printf '%*s' "$w" '' | tr ' ' "$ch")"
    local ir
    for (( ir = r; ir < r+h; ir++ )); do
        _at "$ir" "$c"; printf '%s' "$line"
    done
}

_trunc() {   # string maxlen
    local s="$1" n="$2"
    [[ ${#s} -gt $n ]] && printf '%s…' "${s:0:$((n-1))}" || printf '%s' "$s"
}

# ── Key reading ───────────────────────────────────────────────────────────────
# Sets: KEY_NAME  (UP DOWN LEFT RIGHT ENTER ESC CHAR BACKSPACE)
#       KEY_CHAR  (the raw char for CHAR type)
read_key() {
    local ch seq
    IFS= read -rsn1 ch
    KEY_CHAR="$ch"
    KEY_NAME="CHAR"
    if [[ "$ch" == $'\x1b' ]]; then
        IFS= read -rsn1 -t 0.1 seq || true
        if [[ "$seq" == '[' ]]; then
            IFS= read -rsn1 -t 0.1 seq || true
            case "$seq" in
                A) KEY_NAME="UP"    ;;
                B) KEY_NAME="DOWN"  ;;
                C) KEY_NAME="RIGHT" ;;
                D) KEY_NAME="LEFT"  ;;
                *) KEY_NAME="ESC"   ;;
            esac
        else
            KEY_NAME="ESC"
        fi
    elif [[ "$ch" == $'\r' || "$ch" == $'\n' ]]; then
        KEY_NAME="ENTER"
    elif [[ "$ch" == $'\x7f' || "$ch" == $'\x08' ]]; then
        KEY_NAME="BACKSPACE"
    elif [[ "$ch" == $'\x09' ]]; then
        KEY_NAME="TAB"
    fi
}

# ── Layout ────────────────────────────────────────────────────────────────────
_layout() {
    COLS=$(tput cols  2>/dev/null || printf '80')
    ROWS=$(tput lines 2>/dev/null || printf '24')
    CT_R=$(( HDR_H + 2 ))          # content starts after header + divider
    CT_C=$(( SB_W + 2 ))           # content starts after sidebar + its border + 1
    CT_H=$(( ROWS - HDR_H - FTR_H - 2 ))
    CT_W=$(( COLS - SB_W - 3 ))    # -sidebar -left-border -right-border
}

_draw_header() {
    # Row 1 — top border
    _at 1 1
    printf "${B}╔${NC}"
    printf "${B}%s${NC}" "$(printf '%*s' $((COLS-2)) | tr ' ' '═')"
    printf "${B}╗${NC}"

    # Row 2 — title bar
    _at 2 1
    printf "${B}║${NC}"
    printf "${W}  ◈  ABORA OS INSTALLER${NC}"
    local verstr="  ${version}  "
    local pad=$(( COLS - 25 - ${#verstr} - 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%*s' "$pad"
    printf "${GY}%s${NC}" "$verstr"
    printf "${B}║${NC}"

    # Row 3 — bottom of header with sidebar T-junction
    _at 3 1
    printf "${B}╠${NC}"
    printf "${B}%s${NC}" "$(printf '%*s' $((SB_W)) | tr ' ' '═')"
    printf "${B}╦${NC}"
    printf "${B}%s${NC}" "$(printf '%*s' $((COLS - SB_W - 3)) | tr ' ' '═')"
    printf "${B}╣${NC}"
}

_draw_footer() {
    local frow=$(( ROWS - FTR_H + 1 ))
    # divider
    _at "$frow" 1
    printf "${B}╠${NC}"
    printf "${B}%s${NC}" "$(printf '%*s' $((SB_W)) | tr ' ' '═')"
    printf "${B}╩${NC}"
    printf "${B}%s${NC}" "$(printf '%*s' $((COLS - SB_W - 3)) | tr ' ' '═')"
    printf "${B}╣${NC}"

    # key hints
    _at $(( frow + 1 )) 1
    printf "${B}║${NC}"
    printf "${GY}  ↑↓ Move   Enter Select   Esc Back   Ctrl+C Quit${NC}"
    local hintpad=$(( COLS - 52 - 2 ))
    [[ $hintpad -lt 0 ]] && hintpad=0
    printf '%*s' "$hintpad"
    printf "${B}║${NC}"

    # bottom border
    _at $(( frow + 2 )) 1  2>/dev/null || true
    printf "${B}╚${NC}"
    printf "${B}%s${NC}" "$(printf '%*s' $((COLS-2)) | tr ' ' '═')"
    printf "${B}╝${NC}"
}

# Step definitions: "key|label"
STEPS=(
    "network|Network"
    "welcome|Welcome"
    "desktop|Desktop"
    "names|User"
    "password|Password"
    "options|Options"
    "disk|Disk"
    "confirm|Confirm"
)
STEP_DONE=()   # filled as steps complete

_draw_sidebar() {
    local current_key="$1"
    local sb_content_w=$(( SB_W - 2 ))
    local r=$(( HDR_H + 2 ))
    local max_r=$(( ROWS - FTR_H ))
    local i=0

    # sidebar right border
    for (( sr = HDR_H + 2; sr < ROWS - FTR_H + 1; sr++ )); do
        _at "$sr" $(( SB_W + 1 ))
        printf "${B}║${NC}"
    done

    # clear sidebar area
    _fill "$r" 2 $(( max_r - r )) "$sb_content_w"

    _at "$r" 2; printf "${GY}  STEPS${NC}"
    (( r++ )) || true
    _at "$r" 2; printf "${GY}  %s${NC}" "$(printf '%*s' "$sb_content_w" | tr ' ' '─')"
    (( r++ )) || true

    for step_def in "${STEPS[@]}"; do
        local key="${step_def%%|*}"
        local label="${step_def##*|}"
        [[ $r -ge $max_r ]] && break

        _at "$r" 2
        if [[ "$key" == "$current_key" ]]; then
            printf "${C}  →  %-*s${NC}" $(( sb_content_w - 5 )) "$label"
        elif _step_done "$key"; then
            printf "${BG}  ✓  ${NC}${GY}%-*s${NC}" $(( sb_content_w - 5 )) "$label"
        else
            printf "${GY}  ·  %-*s${NC}" $(( sb_content_w - 5 )) "$label"
        fi
        (( r++ )) || true
    done
}

_step_done() {
    local k="$1"
    local d
    for d in "${STEP_DONE[@]+"${STEP_DONE[@]}"}"; do
        [[ "$d" == "$k" ]] && return 0
    done
    return 1
}

_mark_done() {
    local k="$1"
    _step_done "$k" || STEP_DONE+=("$k")
}

# Draw the full chrome (header + sidebar + footer) — call before drawing content
_chrome() {
    local step_key="${1:-}"
    _layout
    _hide
    _cls
    _draw_header
    _draw_sidebar "$step_key"
    _draw_footer

    # content area right border
    for (( cr = CT_R; cr < CT_R + CT_H; cr++ )); do
        _at "$cr" $(( CT_C + CT_W ))
        printf "${B}║${NC}"
    done
    # clear content area
    _fill "$CT_R" "$CT_C" "$CT_H" $(( CT_W - 1 ))
}

# Print inside content area at relative row/col (1-based within content)
_cat() {   # rel_row rel_col text...
    local rr=$1 rc=$2; shift 2
    _at $(( CT_R + rr - 1 )) $(( CT_C + rc - 1 ))
    printf '%b' "$@"
}

# Content area heading
_content_title() {
    local title="$1" sub="${2:-}"
    _cat 1 1 "${W}${title}${NC}"
    if [[ -n "$sub" ]]; then
        _cat 2 1 "${GY}${sub}${NC}"
    fi
    _cat 3 1 "${B}$(printf '%*s' $(( CT_W - 2 )) | tr ' ' '─')${NC}"
}

# ── Progress bar ──────────────────────────────────────────────────────────────
_pbar() {   # row col width percent color
    local r=$1 c=$2 w=$3 pct=$4 clr="${5:-$C}"
    local filled=$(( w * pct / 100 ))
    local empty=$(( w - filled ))
    _at "$r" "$c"
    printf "${clr}"
    [[ $filled -gt 0 ]] && printf '%*s' "$filled" | tr ' ' '█'
    printf "${GY}"
    [[ $empty -gt 0 ]] && printf '%*s' "$empty" | tr ' ' '░'
    printf "${NC}"
}

# ── Text input field ──────────────────────────────────────────────────────────
# Returns result in INPUT_VAL
input_field() {   # row col width prompt default [secret]
    local r=$1 c=$2 w=$3 prompt="$4" def="${5:-}" secret="${6:-}"
    local val="$def"
    local cursor_pos=${#val}

    _show
    while true; do
        # draw field
        _at "$r" "$c"
        printf "${GY}%s${NC} " "$prompt"
        local fc=$(( c + ${#prompt} + 1 ))
        local fw=$(( w - ${#prompt} - 2 ))
        _at "$r" "$fc"
        printf "${W}["
        if [[ "$secret" == "secret" ]]; then
            local stars; stars="$(printf '%*s' "${#val}" | tr ' ' '*')"
            printf "${C}%-*s${NC}" "$fw" "$stars"
        else
            printf "${C}%-*s${NC}" "$fw" "$(_trunc "$val" "$fw")"
        fi
        printf "${W}]${NC}"

        IFS= read -rsn1 KEY_CHAR
        case "$KEY_CHAR" in
            $'\x7f'|$'\x08')
                [[ ${#val} -gt 0 ]] && val="${val%?}"
                ;;
            $'\r'|$'\n')
                break
                ;;
            $'\x1b')
                INPUT_VAL="__back__"
                _hide
                return 0
                ;;
            $'\x03')
                exit 0
                ;;
            *)
                val="${val}${KEY_CHAR}"
                ;;
        esac
    done
    INPUT_VAL="$val"
    _hide
}

# ── Radio card selector ───────────────────────────────────────────────────────
# options array format: "key|Label|Description line 1|Description line 2"
# Returns selected index in RADIO_IDX
radio_cards() {   # start_row options_array_name [default_key]
    local start_r="$1"
    local -n _opts="$2"
    local default_key="${3:-}"
    local sel=0 i

    # find default
    for (( i=0; i<${#_opts[@]}; i++ )); do
        local k="${_opts[$i]%%|*}"
        [[ "$k" == "$default_key" ]] && sel=$i && break
    done

    while true; do
        # draw cards
        local r="$start_r"
        for (( i=0; i<${#_opts[@]}; i++ )); do
            IFS='|' read -r key lbl desc1 desc2 <<< "${_opts[$i]}"
            local card_w=$(( CT_W - 3 ))
            local cr=$(( CT_R + r - 1 ))
            if [[ $i -eq $sel ]]; then
                _at "$cr" "$CT_C"; printf "${C}┌%s┐${NC}" "$(printf '%*s' $((card_w-2)) | tr ' ' '─')"
                _at $((cr+1)) "$CT_C"; printf "${C}│${NC}  ${C}◉  ${W}%-*s${NC}  ${C}│${NC}" $(( card_w - 8 )) "$lbl"
                _at $((cr+2)) "$CT_C"; printf "${C}│${NC}     ${GY}%-*s${NC}  ${C}│${NC}" $(( card_w - 7 )) "$(_trunc "$desc1" $(( card_w - 7 )))"
                if [[ -n "$desc2" ]]; then
                    _at $((cr+3)) "$CT_C"; printf "${C}│${NC}     ${GY}%-*s${NC}  ${C}│${NC}" $(( card_w - 7 )) "$(_trunc "$desc2" $(( card_w - 7 )))"
                    _at $((cr+4)) "$CT_C"; printf "${C}└%s┘${NC}" "$(printf '%*s' $((card_w-2)) | tr ' ' '─')"
                    r=$(( r + 6 ))
                else
                    _at $((cr+3)) "$CT_C"; printf "${C}└%s┘${NC}" "$(printf '%*s' $((card_w-2)) | tr ' ' '─')"
                    r=$(( r + 5 ))
                fi
            else
                _at "$cr" "$CT_C"; printf "${GY}┌%s┐${NC}" "$(printf '%*s' $((card_w-2)) | tr ' ' '─')"
                _at $((cr+1)) "$CT_C"; printf "${GY}│${NC}  ${GY}○  ${BW}%-*s${NC}  ${GY}│${NC}" $(( card_w - 8 )) "$lbl"
                _at $((cr+2)) "$CT_C"; printf "${GY}│${NC}     ${GY}%-*s${NC}  ${GY}│${NC}" $(( card_w - 7 )) "$(_trunc "$desc1" $(( card_w - 7 )))"
                if [[ -n "$desc2" ]]; then
                    _at $((cr+3)) "$CT_C"; printf "${GY}│${NC}     ${GY}%-*s${NC}  ${GY}│${NC}" $(( card_w - 7 )) "$(_trunc "$desc2" $(( card_w - 7 )))"
                    _at $((cr+4)) "$CT_C"; printf "${GY}└%s┘${NC}" "$(printf '%*s' $((card_w-2)) | tr ' ' '─')"
                    r=$(( r + 6 ))
                else
                    _at $((cr+3)) "$CT_C"; printf "${GY}└%s┘${NC}" "$(printf '%*s' $((card_w-2)) | tr ' ' '─')"
                    r=$(( r + 5 ))
                fi
            fi
        done

        read_key
        case "$KEY_NAME" in
            UP)    (( sel > 0 )) && (( sel-- )) || true ;;
            DOWN)  (( sel < ${#_opts[@]} - 1 )) && (( sel++ )) || true ;;
            ENTER) RADIO_IDX=$sel; return 0 ;;
            ESC|BACKSPACE) RADIO_IDX=-1; return 0 ;;
        esac
    done
}

# ── Toggle list ───────────────────────────────────────────────────────────────
# options: "key|label|description" — state tracked in TOGGLE_STATE assoc array
toggle_list() {   # start_row options_array_name toggle_state_array_name
    local start_r="$1"
    local -n _topts="$2"
    local -n _tstate="$3"
    local sel=0

    while true; do
        local r="$start_r"
        for (( i=0; i<${#_topts[@]}; i++ )); do
            IFS='|' read -r tkey tlbl tdesc <<< "${_topts[$i]}"
            local on="${_tstate[$tkey]:-off}"
            local cr=$(( CT_R + r - 1 ))
            local tw=$(( CT_W - 3 ))
            if [[ $i -eq $sel ]]; then
                if [[ "$on" == "on" ]]; then
                    _at "$cr" "$CT_C"; printf "${C}  ◉  ${W}%-*s${GY}  %s${NC}" $(( tw / 2 )) "$tlbl" "$tdesc"
                else
                    _at "$cr" "$CT_C"; printf "${C}  ○  ${GY}%-*s  %s${NC}" $(( tw / 2 )) "$tlbl" "$tdesc"
                fi
            else
                if [[ "$on" == "on" ]]; then
                    _at "$cr" "$CT_C"; printf "${BG}  ◉  ${BW}%-*s${GY}  %s${NC}" $(( tw / 2 )) "$tlbl" "$tdesc"
                else
                    _at "$cr" "$CT_C"; printf "${GY}  ○  %-*s  %s${NC}" $(( tw / 2 )) "$tlbl" "$tdesc"
                fi
            fi
            (( r++ )) || true
        done

        read_key
        case "$KEY_NAME" in
            UP)   (( sel > 0 )) && (( sel-- )) || true ;;
            DOWN) (( sel < ${#_topts[@]} - 1 )) && (( sel++ )) || true ;;
            ENTER|CHAR)
                if [[ "$KEY_NAME" == "CHAR" && "$KEY_CHAR" != " " ]]; then continue; fi
                local tk="${_topts[$sel]%%|*}"
                [[ "${_tstate[$tk]:-off}" == "on" ]] && _tstate[$tk]="off" || _tstate[$tk]="on"
                ;;
            TAB) TOGGLE_IDX="done"; return 0 ;;
            ESC|BACKSPACE) TOGGLE_IDX="back"; return 0 ;;
        esac
    done
}

# ── Status message (inline, bottom of content) ───────────────────────────────
_status() {   # message [color]
    local msg="$1" clr="${2:-$GY}"
    _at $(( CT_R + CT_H - 2 )) "$CT_C"
    printf "${clr}  %s${NC}" "$(_trunc "$msg" $(( CT_W - 4 )))"
}

_clear_status() {
    _at $(( CT_R + CT_H - 2 )) "$CT_C"
    printf '%*s' $(( CT_W - 1 ))
}

# ── Bottom action bar ─────────────────────────────────────────────────────────
_actions() {   # left_label right_label
    local lbl_l="$1" lbl_r="$2"
    local row=$(( CT_R + CT_H - 1 ))
    local aw=$(( CT_W - 2 ))
    _at "$row" "$CT_C"
    printf '%*s' "$aw"
    _at "$row" "$CT_C"
    printf "${GY}  ← ${W}%s${NC}" "$lbl_l"
    local rlen=$(( ${#lbl_r} + 4 ))
    _at "$row" $(( CT_C + aw - rlen ))
    printf "${W}%s${NC} ${GY}→${NC}" "$lbl_r"
}

# ════════════════════════════════════════════════════════════════════
#  STEPS
# ════════════════════════════════════════════════════════════════════

# ── Step: Network ─────────────────────────────────────────────────────────────
_wifi_ssids=(); _wifi_signals=(); _wifi_security=()

_net_bar() {
    local sig="${1:-0}"
    if   [[ "$sig" -ge 80 ]]; then printf '${G}████${NC}'
    elif [[ "$sig" -ge 60 ]]; then printf '${Y}███░${NC}'
    elif [[ "$sig" -ge 40 ]]; then printf '${Y}██░░${NC}'
    elif [[ "$sig" -ge 20 ]]; then printf '${RD}█░░░${NC}'
    else                           printf '${GY}░░░░${NC}'
    fi
}

_net_scan() {
    _wifi_ssids=(); _wifi_signals=(); _wifi_security=()
    nmcli device wifi rescan 2>/dev/null || true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line="${line%"${line##*[![:space:]]}"}"
        local security="${line##*:}"
        local rest="${line%:"$security"}"
        local signal="${rest##*:}"
        local ssid="${rest%:"$signal"}"
        ssid="${ssid//\\:/∶}"
        [[ -z "$ssid" || "$ssid" == "--" ]] && continue
        [[ "$signal" =~ ^[0-9]+$ ]] || continue
        local seen=0
        for j in "${!_wifi_ssids[@]}"; do
            [[ "${_wifi_ssids[$j]}" == "$ssid" ]] && seen=1 && break
        done
        [[ $seen -eq 1 ]] && continue
        _wifi_ssids+=("$ssid"); _wifi_signals+=("$signal"); _wifi_security+=("$security")
    done < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | sort -t: -k2 -rn 2>/dev/null || true)
}

_net_connected() {
    nmcli -t networking connectivity check 2>/dev/null | grep -q "^full$"
}

step_network() {
    _chrome "network"
    _content_title "Connect to the Internet" "A network connection is needed to download system packages."

    _status "Scanning for networks…" "$GY"
    _net_scan
    _clear_status

    local sel=0 msg="" msg_clr="$GY"
    local connected=0
    _net_connected && connected=1 || true

    while true; do
        _layout
        local r=5

        # Ethernet section
        _cat $r 1 "${W}Ethernet${NC}"
        (( r++ )) || true
        local eth_found=0
        while IFS= read -r iface; do
            [[ -z "$iface" ]] && continue
            eth_found=1
            local state; state="$(nmcli -t -f GENERAL.STATE device show "$iface" 2>/dev/null | cut -d: -f2 | head -1 || true)"
            if printf '%s' "$state" | grep -qi "connected"; then
                _cat $r 1 "  ${G}✓  Ethernet (${iface}) — connected${NC}"
                connected=1
            else
                _cat $r 1 "  ${GY}─  Ethernet (${iface}) — unplugged${NC}"
            fi
            (( r++ )) || true
        done < <(nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="ethernet"{print $1}' || true)
        [[ $eth_found -eq 0 ]] && { _cat $r 1 "  ${GY}No ethernet detected${NC}"; (( r++ )) || true; }

        (( r++ )) || true
        _cat $r 1 "${W}WiFi${NC}"
        (( r++ )) || true

        if [[ ${#_wifi_ssids[@]} -eq 0 ]]; then
            _cat $r 1 "  ${GY}No wireless networks found. Press R to rescan.${NC}"
            (( r++ )) || true
        else
            local max_show=$(( CT_H - r - 6 ))
            [[ $max_show -lt 1 ]] && max_show=1
            local start=0 end=$(( ${#_wifi_ssids[@]} - 1 ))
            if [[ ${#_wifi_ssids[@]} -gt $max_show ]]; then
                start=$(( sel - max_show / 2 )); [[ $start -lt 0 ]] && start=0
                end=$(( start + max_show - 1 ))
                [[ $end -ge ${#_wifi_ssids[@]} ]] && end=$(( ${#_wifi_ssids[@]} - 1 )) && start=$(( end - max_show + 1 ))
            fi
            [[ $start -gt 0 ]] && { _cat $r 1 "  ${GY}↑ more above${NC}"; (( r++ )) || true; }
            for (( i=start; i<=end; i++ )); do
                local sig="${_wifi_signals[$i]:-0}"
                local sec="${_wifi_security[$i]:-}"
                local locked=""; [[ -n "$sec" && "$sec" != "--" ]] && locked=" 🔒"
                local bar_str="" clr="$GY"
                if   [[ "$sig" -ge 80 ]]; then bar_str="████"; clr="$G"
                elif [[ "$sig" -ge 60 ]]; then bar_str="███░"; clr="$Y"
                elif [[ "$sig" -ge 40 ]]; then bar_str="██░░"; clr="$Y"
                elif [[ "$sig" -ge 20 ]]; then bar_str="█░░░"; clr="$RD"
                else bar_str="░░░░"; fi
                local ssid_display="${_wifi_ssids[$i]}"
                if [[ $i -eq $sel ]]; then
                    _cat $r 1 "  ${C}›  ${clr}${bar_str}${NC}  ${W}${ssid_display}${NC}${GY}${locked}${NC}"
                else
                    _cat $r 1 "  ${GY}   ${bar_str}  ${ssid_display}${locked}${NC}"
                fi
                (( r++ )) || true
            done
            [[ $end -lt $(( ${#_wifi_ssids[@]} - 1 )) ]] && { _cat $r 1 "  ${GY}↓ more below${NC}"; (( r++ )) || true; }
        fi

        # status / message
        if [[ -n "$msg" ]]; then
            _status "$msg" "$msg_clr"
        elif [[ $connected -eq 1 ]]; then
            _status "Connected — you can continue." "$BG"
        else
            _status "Not connected. Select a network or skip." "$GY"
        fi

        if [[ $connected -eq 1 ]]; then
            _actions "Rescan (R)" "Continue"
        else
            _actions "Rescan (R)   Skip" "Connect"
        fi

        read_key
        case "$KEY_NAME" in
            UP)   (( sel > 0 )) && (( sel-- )) || true ;;
            DOWN) (( sel < ${#_wifi_ssids[@]} - 1 )) && (( sel++ )) || true ;;
            ENTER)
                if [[ $connected -eq 1 ]]; then
                    _mark_done "network"; STEP_RESULT="next"; return
                fi
                if [[ ${#_wifi_ssids[@]} -gt 0 ]]; then
                    local chosen_ssid="${_wifi_ssids[$sel]}"
                    local chosen_sec="${_wifi_security[$sel]:-}"
                    if [[ -n "$chosen_sec" && "$chosen_sec" != "--" ]]; then
                        _status "Enter WiFi password for: ${chosen_ssid}" "$W"
                        _show
                        local wpass=""
                        _at $(( CT_R + CT_H - 3 )) "$CT_C"
                        printf "${GY}  Password: ${W}[${NC}"
                        local pw_col=$(( CT_C + 13 ))
                        local pw_w=$(( CT_W - 16 ))
                        IFS= read -rsp "" wpass
                        printf "${W}]${NC}"
                        _hide
                        if [[ -n "$wpass" ]]; then
                            _status "Connecting to ${chosen_ssid}…" "$GY"
                            if nmcli device wifi connect "$chosen_ssid" password "$wpass" >/dev/null 2>&1; then
                                connected=1; msg="Connected to ${chosen_ssid}"; msg_clr="$BG"
                            else
                                msg="Failed to connect. Check password."; msg_clr="$RD"
                            fi
                        fi
                    else
                        _status "Connecting to ${chosen_ssid}…" "$GY"
                        if nmcli device wifi connect "$chosen_ssid" >/dev/null 2>&1; then
                            connected=1; msg="Connected to ${chosen_ssid}"; msg_clr="$BG"
                        else
                            msg="Failed to connect."; msg_clr="$RD"
                        fi
                    fi
                fi
                ;;
            CHAR)
                case "${KEY_CHAR,,}" in
                    r) _status "Rescanning…" "$GY"; _net_scan; msg=""; msg_clr="$GY" ;;
                    s) _mark_done "network"; STEP_RESULT="next"; return ;;
                    c) [[ $connected -eq 1 ]] && { _mark_done "network"; STEP_RESULT="next"; return; } ;;
                esac
                ;;
            ESC|BACKSPACE) STEP_RESULT="next"; return ;;  # can't go back from network
        esac
    done
}

# ── Step: Welcome ─────────────────────────────────────────────────────────────
step_welcome() {
    _chrome "welcome"
    _content_title "Welcome to Abora OS" "A simpler path into NixOS."

    local r=5
    _cat $r 1 "${W}You're about to install Abora OS ${version}.${NC}"; (( r+=2 )) || true
    _cat $r 1 "${GY}This installer will guide you through:${NC}"; (( r++ )) || true
    _cat $r 3 "${C}◈${NC}  Choosing your desktop environment"; (( r++ )) || true
    _cat $r 3 "${C}◈${NC}  Creating your user account"; (( r++ )) || true
    _cat $r 3 "${C}◈${NC}  Selecting the install disk"; (( r++ )) || true
    _cat $r 3 "${C}◈${NC}  Writing the system (usually 5–10 minutes)"; (( r+=2 )) || true

    _cat $r 1 "${GY}The selected disk will be completely erased.${NC}"; (( r+=2 )) || true
    _cat $r 1 "${GY}Make sure you are connected to the internet.${NC}"

    _actions "" "Let's go"

    while true; do
        read_key
        case "$KEY_NAME" in
            ENTER|RIGHT) _mark_done "welcome"; STEP_RESULT="next"; return ;;
            ESC|BACKSPACE) STEP_RESULT="back"; return ;;
        esac
    done
}

# ── Step: Desktop ─────────────────────────────────────────────────────────────
step_desktop() {
    _chrome "desktop"
    _content_title "Choose Your Desktop" "Pick the environment you'll work in every day."

    local opts=(
        "gnome|GNOME|Modern, clean, and polished. Best for newcomers.|Gesture-friendly, great HiDPI support."
        "plasma|KDE Plasma|Powerful and highly customizable.|Windows-like layout. Fine-grained control."
        "hyprland|Hyprland|Minimal tiling compositor for advanced users.|Keyboard-driven, lightweight, fast."
    )

    radio_cards 5 opts "$desktop_profile"

    if [[ "$RADIO_IDX" -ge 0 ]]; then
        IFS='|' read -r key lbl _ _ <<< "${opts[$RADIO_IDX]}"
        desktop_profile="$key"
        abora_sync_desktop_label "$desktop_profile"
        _mark_done "desktop"
        STEP_RESULT="next"; return
    else
        STEP_RESULT="back"; return
    fi
}

# ── Step: User / Names ────────────────────────────────────────────────────────
step_names() {
    local field=0  # 0=username 1=hostname 2=timezone

    while true; do
        _chrome "names"
        _content_title "Your Account" "Set up your username and system identity."

        local r=5

        # ── Username
        local u_col=$(( CT_C + 2 ))
        _cat $r 1 "${W}Username${NC}"; (( r++ )) || true
        _cat $r 1 "${GY}  Letters, numbers, and _ only. Lowercase.${NC}"; (( r+=2 )) || true
        _at $(( CT_R + r - 1 )) "$u_col"
        if [[ $field -eq 0 ]]; then
            printf "${C}› ${NC}${GY}username:${NC} ${W}${username_value}${C}▌${NC}"
        else
            printf "  ${GY}username:${NC} ${BW}${username_value}${NC}"
        fi
        (( r+=2 )) || true

        # ── Hostname
        _cat $r 1 "${W}Hostname${NC}"; (( r++ )) || true
        _cat $r 1 "${GY}  Network name of your machine.${NC}"; (( r+=2 )) || true
        _at $(( CT_R + r - 1 )) "$u_col"
        if [[ $field -eq 1 ]]; then
            printf "${C}› ${NC}${GY}hostname: ${NC}${W}${hostname_value}${C}▌${NC}"
        else
            printf "  ${GY}hostname: ${NC}${BW}${hostname_value}${NC}"
        fi
        (( r+=2 )) || true

        # ── Timezone
        _cat $r 1 "${W}Timezone${NC}"; (( r++ )) || true
        _cat $r 1 "${GY}  e.g. America/New_York, Europe/London${NC}"; (( r+=2 )) || true
        _at $(( CT_R + r - 1 )) "$u_col"
        if [[ $field -eq 2 ]]; then
            printf "${C}› ${NC}${GY}timezone: ${NC}${W}${timezone_value}${C}▌${NC}"
        else
            printf "  ${GY}timezone: ${NC}${BW}${timezone_value}${NC}"
        fi

        _actions "Back" "Next (Tab to switch field)"
        _show

        IFS= read -rsn1 KEY_CHAR
        case "$KEY_CHAR" in
            $'\t')  field=$(( (field + 1) % 3 )); _hide; continue ;;
            $'\r'|$'\n')
                _hide
                if [[ $field -eq 2 ]]; then
                    _mark_done "names"; STEP_RESULT="next"; return
                else
                    field=$(( field + 1 ))
                fi
                continue
                ;;
            $'\x1b') _hide; STEP_RESULT="back"; return ;;
            $'\x7f'|$'\x08')
                case $field in
                    0) [[ ${#username_value} -gt 0 ]] && username_value="${username_value%?}" ;;
                    1) [[ ${#hostname_value}  -gt 0 ]] && hostname_value="${hostname_value%?}" ;;
                    2) [[ ${#timezone_value}  -gt 0 ]] && timezone_value="${timezone_value%?}" ;;
                esac
                ;;
            $'\x03') exit 0 ;;
            *)
                case $field in
                    0)
                        if [[ "$KEY_CHAR" =~ ^[a-z0-9_]$ ]]; then
                            username_value="${username_value}${KEY_CHAR}"
                            # auto-fill hostname if still default
                            [[ "$hostname_value" == "abora" || "$hostname_value" == "${username_value%?}" ]] \
                                && hostname_value="$username_value"
                        fi
                        ;;
                    1) hostname_value="${hostname_value}${KEY_CHAR}" ;;
                    2) timezone_value="${timezone_value}${KEY_CHAR}" ;;
                esac
                ;;
        esac
    done
}

# ── Step: Password ────────────────────────────────────────────────────────────
_pw_strength() {
    local p="$1" score=0
    [[ ${#p} -ge 8  ]] && (( score++ )) || true
    [[ ${#p} -ge 12 ]] && (( score++ )) || true
    [[ "$p" =~ [A-Z] ]] && (( score++ )) || true
    [[ "$p" =~ [0-9] ]] && (( score++ )) || true
    [[ "$p" =~ [^a-zA-Z0-9] ]] && (( score++ )) || true
    printf '%d' "$score"
}

step_password() {
    local pass1="" pass2="" field=0

    while true; do
        _chrome "password"
        _content_title "Set Your Password" "Choose a strong password for your account."

        local r=5
        _cat $r 1 "${W}Password${NC}"; (( r++ )) || true

        # draw masked fields
        local u_col=$(( CT_C + 2 ))
        local fw=$(( CT_W - 20 ))
        local stars1; stars1="$(printf '%*s' "${#pass1}" | tr ' ' '●')"
        local stars2; stars2="$(printf '%*s' "${#pass2}" | tr ' ' '●')"
        (( r++ )) || true

        _at $(( CT_R + r - 1 )) "$u_col"
        if [[ $field -eq 0 ]]; then
            printf "${C}›${NC} ${GY}password:  ${NC}${W}[%-*s${C}▌${W}]${NC}" "$fw" "$stars1"
        else
            printf "  ${GY}password:  ${NC}[${BW}%-*s${NC}]" "$fw" "$stars1"
        fi
        (( r+=2 )) || true

        _at $(( CT_R + r - 1 )) "$u_col"
        if [[ $field -eq 1 ]]; then
            printf "${C}›${NC} ${GY}confirm:   ${NC}${W}[%-*s${C}▌${W}]${NC}" "$fw" "$stars2"
        else
            printf "  ${GY}confirm:   ${NC}[${BW}%-*s${NC}]" "$fw" "$stars2"
        fi
        (( r+=2 )) || true

        # strength meter
        if [[ ${#pass1} -gt 0 ]]; then
            local strength; strength="$(_pw_strength "$pass1")"
            local s_colors=("$RD" "$RD" "$Y" "$Y" "$G" "$G")
            local s_labels=("" "Too short" "Weak" "OK" "Good" "Strong")
            local clr="${s_colors[$strength]}"
            local lbl="${s_labels[$strength]}"
            _cat $r 1 "  ${GY}Strength: ${NC}"
            local sr=$(( CT_R + r - 1 ))
            _at "$sr" $(( CT_C + 13 ))
            local bar_w=20
            local filled=$(( bar_w * strength / 5 ))
            printf "${clr}"
            [[ $filled -gt 0 ]] && printf '%*s' "$filled" | tr ' ' '█'
            printf "${GY}"
            [[ $(( bar_w - filled )) -gt 0 ]] && printf '%*s' $(( bar_w - filled )) | tr ' ' '░'
            printf "${NC}  ${clr}%s${NC}" "$lbl"
            (( r++ )) || true
        fi

        # match status
        if [[ ${#pass1} -gt 0 && ${#pass2} -gt 0 ]]; then
            if [[ "$pass1" == "$pass2" ]]; then
                _status "Passwords match." "$BG"
            else
                _status "Passwords do not match." "$RD"
            fi
        fi

        _actions "Back" "Next (Tab to switch field)"
        _show

        IFS= read -rsn1 KEY_CHAR
        case "$KEY_CHAR" in
            $'\t')  field=$(( (field + 1) % 2 )) ;;
            $'\r'|$'\n')
                if [[ $field -eq 0 ]]; then
                    field=1
                else
                    if [[ -z "$pass1" ]]; then
                        _status "Password cannot be empty." "$RD"
                        sleep 1
                    elif [[ "$pass1" != "$pass2" ]]; then
                        _status "Passwords do not match." "$RD"
                        sleep 1
                        pass2=""
                        field=1
                    else
                        if command -v mkpasswd >/dev/null 2>&1; then
                            user_password_hash="$(mkpasswd -m yescrypt "$pass1")"
                        elif command -v openssl >/dev/null 2>&1; then
                            user_password_hash="$(printf '%s' "$pass1" | openssl passwd -6 -stdin)"
                        else
                            _status "No password hashing tool found (mkpasswd/openssl)." "$RD"
                            sleep 2
                            continue
                        fi
                        unset pass1 pass2
                        _mark_done "password"
                        STEP_RESULT="next"; return
                    fi
                fi
                ;;
            $'\x1b') _hide; STEP_RESULT="back"; return ;;
            $'\x7f'|$'\x08')
                [[ $field -eq 0 ]] && [[ ${#pass1} -gt 0 ]] && pass1="${pass1%?}"
                [[ $field -eq 1 ]] && [[ ${#pass2} -gt 0 ]] && pass2="${pass2%?}"
                ;;
            $'\x03') exit 0 ;;
            *)
                [[ $field -eq 0 ]] && pass1="${pass1}${KEY_CHAR}"
                [[ $field -eq 1 ]] && pass2="${pass2}${KEY_CHAR}"
                ;;
        esac
    done
}

# ── Step: Options ─────────────────────────────────────────────────────────────
step_options() {
    local -A tstate=([anix]="$( [[ "$anix_enabled" == "yes" ]] && printf 'on' || printf 'off' )")
    local topts=(
        "anix|ANIX|The NixOS configuration layer — recommended for new users"
    )
    local apps_sel=0
    local apps_list=("favorites" "essentials" "none")
    local apps_labels=("Fan Favorites  — browser, media, productivity" \
                       "Essentials     — minimal set" \
                       "None           — bare system")
    # find current
    for (( i=0; i<${#apps_list[@]}; i++ )); do
        [[ "${apps_list[$i]}" == "$starter_apps_bundle" ]] && apps_sel=$i && break
    done

    local section=0  # 0=toggles 1=apps

    while true; do
        _chrome "options"
        _content_title "System Options" "Choose extras for your installation."

        local r=5
        _cat $r 1 "${W}Features${NC}"; (( r+=2 )) || true

        # draw ANIX toggle
        local on="${tstate[anix]}"
        local cr=$(( CT_R + r - 1 ))
        if [[ $section -eq 0 ]]; then
            if [[ "$on" == "on" ]]; then
                _at "$cr" "$CT_C"; printf "${C}  ◉  ${W}ANIX${NC}  ${GY}The NixOS configuration layer — recommended for new users${NC}"
            else
                _at "$cr" "$CT_C"; printf "${C}  ○  ${GY}ANIX  The NixOS configuration layer — recommended for new users${NC}"
            fi
        else
            if [[ "$on" == "on" ]]; then
                _at "$cr" "$CT_C"; printf "${BG}  ◉  ${BW}ANIX${NC}  ${GY}The NixOS configuration layer — recommended for new users${NC}"
            else
                _at "$cr" "$CT_C"; printf "${GY}  ○  ANIX  The NixOS configuration layer — recommended for new users${NC}"
            fi
        fi
        (( r+=3 )) || true

        _cat $r 1 "${W}Starter Apps${NC}"; (( r+=2 )) || true
        for (( i=0; i<${#apps_list[@]}; i++ )); do
            cr=$(( CT_R + r - 1 ))
            if [[ $section -eq 1 && $i -eq $apps_sel ]]; then
                _at "$cr" "$CT_C"; printf "${C}  ◉  ${W}%s${NC}" "${apps_labels[$i]}"
            elif [[ "${apps_list[$i]}" == "$starter_apps_bundle" && $section -ne 1 ]]; then
                _at "$cr" "$CT_C"; printf "${BG}  ◉  ${BW}%s${NC}" "${apps_labels[$i]}"
            else
                _at "$cr" "$CT_C"; printf "${GY}  ○  %s${NC}" "${apps_labels[$i]}"
            fi
            (( r++ )) || true
        done

        _actions "Back" "Next"

        read_key
        case "$KEY_NAME" in
            UP)
                if [[ $section -eq 0 ]]; then
                    : # already at top
                elif [[ $section -eq 1 ]]; then
                    if [[ $apps_sel -gt 0 ]]; then (( apps_sel-- )) || true
                    else section=0; fi
                fi
                ;;
            DOWN)
                if [[ $section -eq 0 ]]; then section=1
                elif [[ $apps_sel -lt $(( ${#apps_list[@]} - 1 )) ]]; then (( apps_sel++ )) || true
                fi
                ;;
            ENTER|CHAR)
                if [[ "$KEY_NAME" == "CHAR" && "$KEY_CHAR" != " " && "$KEY_CHAR" != $'\r' ]]; then continue; fi
                if [[ $section -eq 0 ]]; then
                    [[ "${tstate[anix]}" == "on" ]] && tstate[anix]="off" || tstate[anix]="on"
                else
                    starter_apps_bundle="${apps_list[$apps_sel]}"
                    sync_starter_apps_label
                    _mark_done "options"
                    [[ "${tstate[anix]}" == "on" ]] && anix_enabled="yes" || anix_enabled="no"
                    STEP_RESULT="next"; return
                fi
                ;;
            RIGHT)
                [[ "${tstate[anix]}" == "on" ]] && anix_enabled="yes" || anix_enabled="no"
                starter_apps_bundle="${apps_list[$apps_sel]}"
                sync_starter_apps_label
                _mark_done "options"
                STEP_RESULT="next"; return
                ;;
            ESC|BACKSPACE) STEP_RESULT="back"; return ;;
        esac
    done
}

# ── Step: Disk ────────────────────────────────────────────────────────────────
step_disk() {
    while true; do
        _chrome "disk"
        _content_title "Select Install Disk" "The selected disk will be completely erased."

        local entries=() labels=() paths=()
        while IFS='|' read -r name size model; do
            labels+=("/dev/${name}  ${size}  ${model}")
            paths+=("/dev/${name}")
            entries+=("$name|$size|$model")
        done < <(collect_disks)

        local r=5
        if [[ ${#paths[@]} -eq 0 ]]; then
            _cat $r 1 "${RD}No installable disks found.${NC}"; (( r++ )) || true
            _cat $r 1 "${GY}Press R to rescan.${NC}"
            _actions "Back" "Rescan (R)"
            while true; do
                read_key
                [[ "$KEY_NAME" == "CHAR" && "${KEY_CHAR,,}" == "r" ]] && break
                [[ "$KEY_NAME" == "ESC" || "$KEY_NAME" == "BACKSPACE" ]] && STEP_RESULT="back"; return
            done
            continue
        fi

        # disk table header
        _cat $r 1 "${GY}  $(printf '%-12s %-8s %s' 'DEVICE' 'SIZE' 'MODEL')${NC}"; (( r++ )) || true
        _cat $r 1 "${B}  $(printf '%*s' $(( CT_W - 4 )) | tr ' ' '─')${NC}"; (( r++ )) || true

        local sel=0
        while true; do
            # draw disk list
            local dr=$r
            for (( i=0; i<${#paths[@]}; i++ )); do
                IFS='|' read -r dname dsize dmodel <<< "${entries[$i]}"
                local cr=$(( CT_R + dr - 1 ))
                if [[ $i -eq $sel ]]; then
                    _at "$cr" "$CT_C"
                    printf "${C}  › %-12s ${W}%-8s ${GY}%s${NC}" "/dev/$dname" "$dsize" "$(_trunc "$dmodel" $(( CT_W - 26 )))"
                else
                    _at "$cr" "$CT_C"
                    printf "${GY}    %-12s %-8s %s${NC}" "/dev/$dname" "$dsize" "$(_trunc "$dmodel" $(( CT_W - 26 )))"
                fi
                (( dr++ )) || true
            done

            # warn if selected disk is live disk
            local cur_disk="${paths[$sel]}"
            local root_parent; root_parent="$(lsblk -no pkname "$(findmnt -n -o SOURCE /)" 2>/dev/null || true)"
            if [[ -n "$root_parent" && "$cur_disk" == "/dev/${root_parent}" ]]; then
                _status "⚠  This looks like your live USB — erasing it will destroy the installer!" "$Y"
            else
                _status "All data on ${cur_disk} will be erased." "$GY"
            fi
            _actions "Back" "Select"

            read_key
            case "$KEY_NAME" in
                UP)    (( sel > 0 )) && (( sel-- )) || true ;;
                DOWN)  (( sel < ${#paths[@]} - 1 )) && (( sel++ )) || true ;;
                CHAR)  [[ "${KEY_CHAR,,}" == "r" ]] && break ;;
                ENTER|RIGHT)
                    disk="${paths[$sel]}"
                    _mark_done "disk"
                    STEP_RESULT="next"; return
                    ;;
                ESC|BACKSPACE) STEP_RESULT="back"; return ;;
            esac
        done
    done
}

# ── Step: Confirm ─────────────────────────────────────────────────────────────
step_confirm() {
    _chrome "confirm"
    _content_title "Ready to Install" "Review your choices. The disk will be wiped."

    local r=5
    local lw=14
    local cw=$(( CT_W - lw - 4 ))

    _box $(( CT_R + r - 1 )) "$CT_C" 12 $(( CT_W - 1 ))
    (( r++ )) || true

    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Disk')${NC}${W}${disk}${NC}"         ; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Desktop')${NC}${W}${desktop_label}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Username')${NC}${W}${username_value}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Hostname')${NC}${W}${hostname_value}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Timezone')${NC}${W}${timezone_value}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Keyboard')${NC}${W}${keyboard_value}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'ANIX')${NC}${W}${anix_enabled}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'Apps')${NC}${W}${starter_apps_label}${NC}"; (( r++ )) || true
    _cat $r 2 "${GY}$(printf '%-*s' "$lw" 'GitHub')${NC}${W}${github_identity}${NC}"; (( r++ )) || true

    (( r++ )) || true
    _cat $r 1 "${RD}  ⚠  All data on ${disk} will be permanently erased.${NC}"

    _actions "Back" "Install Now"

    while true; do
        read_key
        case "$KEY_NAME" in
            ENTER|RIGHT) STEP_RESULT="install"; return ;;
            ESC|BACKSPACE) STEP_RESULT="back"; return ;;
        esac
    done
}

# ── Step: Install ─────────────────────────────────────────────────────────────
step_install() {
    _layout; _hide; _cls

    # Full-screen install layout (no sidebar)
    # Top bar
    _at 1 1; printf "${B}╔%s╗${NC}" "$(printf '%*s' $((COLS-2)) | tr ' ' '═')"
    _at 2 1; printf "${B}║${NC}${W}  ◈  INSTALLING ABORA OS${NC}"
    local ipad=$(( COLS - 27 - ${#version} - 3 ))
    [[ $ipad -lt 0 ]] && ipad=0
    printf '%*s' "$ipad"; printf "${GY}  %s  ${NC}" "$version"
    printf "${B}║${NC}"
    _at 3 1; printf "${B}╠%s╣${NC}" "$(printf '%*s' $((COLS-2)) | tr ' ' '═')"

    # Phase panel (left) | Log panel (right)
    local phase_w=28
    local log_w=$(( COLS - phase_w - 3 ))
    local panel_h=$(( ROWS - 5 ))
    local panel_top=4

    # outer borders
    for (( pr = panel_top; pr < panel_top + panel_h; pr++ )); do
        _at "$pr" 1; printf "${B}║${NC}"
        _at "$pr" $(( phase_w + 2 )); printf "${B}║${NC}"
        _at "$pr" "$COLS"; printf "${B}║${NC}"
    done

    # phase/log divider header
    _at "$panel_top" 2; printf "${GY}  PHASES${NC}"
    _at "$panel_top" $(( phase_w + 3 )); printf "${GY}  RECENT OUTPUT${NC}"

    # bottom
    _at $(( panel_top + panel_h )) 1
    printf "${B}╠%s╩%s╣${NC}" \
        "$(printf '%*s' "$phase_w" | tr ' ' '═')" \
        "$(printf '%*s' "$log_w" | tr ' ' '═')"
    _at $(( panel_top + panel_h + 1 )) 1
    printf "${B}║${NC}  ${GY}Full log: /tmp/abora-install.log${NC}"
    local fpad=$(( COLS - 38 - 2 ))
    [[ $fpad -lt 0 ]] && fpad=0
    printf '%*s' "$fpad"
    printf "${B}║${NC}"
    _at $(( panel_top + panel_h + 2 )) 1
    printf "${B}╚%s╝${NC}" "$(printf '%*s' $((COLS-2)) | tr ' ' '═')"

    # Phase list
    local phases=("Partitioning disk" "Mounting filesystem" "Generating config" "Downloading packages" "Activating system" "Installing bootloader")
    local phase_row=$(( panel_top + 2 ))
    for ph in "${phases[@]}"; do
        _at "$phase_row" 3; printf "${GY}  ·  %s${NC}" "$ph"; (( phase_row++ )) || true
    done

    # progress bar row
    local pbar_row=$(( panel_top + panel_h - 3 ))
    _at "$pbar_row" 2; printf "${GY}  Progress${NC}"
    (( pbar_row++ )) || true

    _update_phase() {
        local idx="$1"   # 0-based
        local phrow=$(( panel_top + 2 ))
        for (( pi=0; pi<${#phases[@]}; pi++ )); do
            _at "$phrow" 3
            if [[ $pi -lt $idx ]]; then
                printf "${BG}  ✓  %s${NC}" "${phases[$pi]}"
            elif [[ $pi -eq $idx ]]; then
                printf "${C}  →  %s${NC}" "${phases[$pi]}"
            else
                printf "${GY}  ·  %s${NC}" "${phases[$pi]}"
            fi
            (( phrow++ )) || true
        done
    }

    _update_log() {
        local lf="$1"
        [[ ! -f "$lf" ]] && return
        local log_top=$(( panel_top + 2 ))
        local log_rows=$(( panel_h - 4 ))
        local lc=0
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ETA[[:space:]]|^[[:space:]]*[0-9]+\.[0-9]+\ (GiB|MiB|KiB) ]] && continue
            local lr=$(( log_top + lc ))
            [[ $lr -ge $(( log_top + log_rows )) ]] && break
            _at "$lr" $(( phase_w + 4 ))
            printf '%*s' "$log_w"
            _at "$lr" $(( phase_w + 4 ))
            printf "${GY}%s${NC}" "$(_trunc "$line" $(( log_w - 2 )))"
            (( lc++ )) || true
        done < <(tail -n "$log_rows" "$lf" 2>/dev/null | grep -v '^$' | tail -n "$log_rows")
    }

    _update_elapsed() {
        local el="$1" pct="$2"
        local m=$(( el / 60 )) s=$(( el % 60 ))
        _at $(( pbar_row - 1 )) 2
        printf "${GY}  Progress${NC}"
        _pbar "$pbar_row" 3 $(( phase_w - 2 )) "$pct"
        _at "$pbar_row" $(( 3 + phase_w - 10 ))
        printf "${W} %3d%%${NC}" "$pct"
        _at $(( pbar_row + 1 )) 3
        printf "${GY}Elapsed: %02dm %02ds${NC}" "$m" "$s"
    }

    # ── Run the actual install ────────────────────────────────────────────────
    local start_ts; start_ts="$(date +%s)"

    # Phase 0: Partition
    _update_phase 0
    _update_elapsed 0 5
    partition_disk || {
        _at $(( panel_top + panel_h - 1 )) 2
        printf "${RD}  Partitioning failed. Press Enter.${NC}"
        _show; read -r; STEP_RESULT="fail"; return
    }

    # Phase 1: Mount
    _update_phase 1
    _update_elapsed 5 10
    mount_target || {
        _at $(( panel_top + panel_h - 1 )) 2
        printf "${RD}  Mount failed. Press Enter.${NC}"
        _show; read -r; STEP_RESULT="fail"; return
    }

    # Phase 2: Generate config
    _update_phase 2
    _update_elapsed 10 18
    generate_config || {
        _at $(( panel_top + panel_h - 1 )) 2
        printf "${RD}  Config generation failed. Press Enter.${NC}"
        _show; read -r; STEP_RESULT="fail"; return
    }

    # Phase 3-5: nixos-install (covers download, activate, bootloader)
    _update_phase 3
    printf '[*] Starting nixos-install\n' > "$install_log"

    local nixpkgs_path
    nixpkgs_path="$(resolve_nixpkgs_path)" || {
        _at $(( panel_top + panel_h - 1 )) 2
        printf "${RD}  Cannot locate nixpkgs. Press Enter.${NC}"
        _show; read -r; STEP_RESULT="fail"; return
    }
    local nix_path="nixpkgs=${nixpkgs_path}:nixos-config=/mnt/etc/nixos/configuration.nix"

    NIX_PATH="$nix_path" timeout 900 nixos-install \
        --root /mnt \
        --no-root-passwd \
        --show-trace \
        --option substituters "https://cache.nixos.org" \
        --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
        --option max-substitution-jobs 32 \
        --option http-connections 128 \
        --option max-jobs auto \
        --option max-silent-time 300 \
        --cores 0 \
        -I "nixpkgs=${nixpkgs_path}" \
        -I "nixos-config=/mnt/etc/nixos/configuration.nix" \
        >>"$install_log" 2>&1 &
    local install_pid="$!"

    while kill -0 "$install_pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start_ts ))
        local pct=18
        local cur_phase=3

        if grep -qi 'installing the boot loader' "$install_log" 2>/dev/null; then
            cur_phase=5; pct=93
        elif grep -qi 'setting up /etc\|activating the configuration\|running activation' "$install_log" 2>/dev/null; then
            cur_phase=4; pct=88
        elif grep -qi 'created.*symlinks in user environment' "$install_log" 2>/dev/null; then
            cur_phase=4; pct=82
        elif grep -qi "copying path '/nix/store" "$install_log" 2>/dev/null; then
            cur_phase=3; pct=70
        elif grep -qi 'building the configuration' "$install_log" 2>/dev/null; then
            cur_phase=3; pct=60
        fi

        # let time push pct up within current phase band, cap at 99
        local time_bonus=$(( elapsed / 8 ))
        pct=$(( pct + time_bonus ))
        [[ $pct -gt 99 ]] && pct=99

        _update_phase "$cur_phase"
        _update_log "$install_log"
        _update_elapsed "$elapsed" "$pct"
        sleep 1
    done

    if wait "$install_pid"; then
        local elapsed=$(( $(date +%s) - start_ts ))
        _update_phase 6
        _update_elapsed "$elapsed" 100
        _update_log "$install_log"
        copy_github_auth_to_target
        cleanup_target
        STEP_RESULT="done"; return
    else
        printf '\n[x] nixos-install failed\n' >> "$install_log"
        # show first error
        local first_err; first_err="$(grep -m1 '^error:' "$install_log" 2>/dev/null || true)"
        _at $(( panel_top + panel_h - 1 )) 2
        printf "${RD}  Failed: %s${NC}" "$(_trunc "${first_err:-see log}" $(( COLS - 14 )))"
        _show; read -r
        STEP_RESULT="fail"; return
    fi
}

step_finish() {
    _chrome ""
    _content_title "Installation Complete" "Abora OS is ready."

    local r=5
    _cat $r 1 "${G}  ✓  Abora OS ${version} installed successfully.${NC}"; (( r+=3 )) || true
    _cat $r 1 "${W}Next steps:${NC}"; (( r++ )) || true
    _cat $r 3 "${C}1.${NC}  Remove the USB / installation media."; (( r++ )) || true
    _cat $r 3 "${C}2.${NC}  Reboot — your disk will be selected automatically."; (( r++ )) || true
    _cat $r 3 "${C}3.${NC}  Log in as ${W}${username_value}${NC} on the ${W}${desktop_label}${NC} desktop."

    (( r+=3 )) || true
    local opts=("Reboot into Abora OS" "Power off")
    local sel=0

    while true; do
        for (( i=0; i<${#opts[@]}; i++ )); do
            local cr=$(( CT_R + r + i - 1 ))
            _at "$cr" "$CT_C"
            if [[ $i -eq $sel ]]; then
                printf "${C}  ›  ${W}%s${NC}" "${opts[$i]}"
            else
                printf "     ${GY}%s${NC}" "${opts[$i]}"
            fi
        done

        read_key
        case "$KEY_NAME" in
            UP)    (( sel > 0 )) && (( sel-- )) || true ;;
            DOWN)  (( sel < 1 )) && (( sel++ )) || true ;;
            ENTER)
                sync
                [[ $sel -eq 0 ]] && reboot || poweroff
                sleep 10
                exit 0
                ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════
#  BACKEND  (all bug fixes from audit applied)
# ════════════════════════════════════════════════════════════════════

sync_starter_apps_label() {
    case "${starter_apps_bundle,,}" in
        none)       starter_apps_label="No starter apps" ;;
        favorites)  starter_apps_label="Fan Favorites" ;;
        essentials) starter_apps_label="Essentials" ;;
        social)     starter_apps_label="Social" ;;
        creator)    starter_apps_label="Creator" ;;
        developer)  starter_apps_label="Developer" ;;
        *)          starter_apps_label="Custom" ;;
    esac
}

refresh_github_identity() {
    command -v gh >/dev/null 2>&1 || { github_identity="GitHub CLI unavailable"; return 0; }
    if gh auth status --hostname github.com >/dev/null 2>&1; then
        local login; login="$(gh api user --jq '.login' 2>/dev/null || true)"
        github_identity="${login:+Signed in as ${login}}"
        [[ -z "$github_identity" ]] && github_identity="Signed in"
    else
        github_identity="Skipped"
    fi
}

auto_detect_timezone() {
    local d; d="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    [[ -n "$d" ]] && timezone_value="$d"
}

auto_detect_keyboard() {
    local d; d="$(localectl status 2>/dev/null | awk '/VC Keymap:/ { print $3 }' || true)"
    [[ "$d" =~ ^[a-z][a-z0-9_-]*$ ]] && keyboard_value="$d" && sync_xkb_layout
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
}

resolve_nixpkgs_path() {
    for candidate in \
        "${ABORA_NIXPKGS_PATH:-}" \
        /etc/abora/nixpkgs \
        /etc/nix/path/nixpkgs \
        "$(nix eval --raw 2>/dev/null --extra-experimental-features 'nix-command flakes' \
            '(builtins.getFlake "path:/etc/nixos").inputs.nixpkgs.outPath' 2>/dev/null || true)" \
        "$(nix eval --raw nixpkgs#path 2>/dev/null || true)" \
        "$(nix-instantiate --eval -E '<nixpkgs>' 2>/dev/null || true)"; do
        [[ -n "$candidate" && -d "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) next
            model = ""
            for (i = 3; i < NF; i++) model = model (model ? " " : "") $i
            if (model == "") model = "Unknown model"
            print $1 "|" $2 "|" model
        }'
}

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

disk_part_suffix() {
    case "$disk" in *nvme*|*mmcblk*|*loop*) printf 'p' ;; *) printf '' ;; esac
}

partition_disk() {
    local suffix=""
    umount -R /mnt 2>/dev/null || true
    wipefs -af "$disk" >/dev/null \
        || { printf 'Failed to wipe %s\n' "$disk" >&2; return 1; }
    parted -s "$disk" mklabel gpt \
        || { printf 'Failed to create partition table\n' >&2; return 1; }
    parted -s "$disk" unit MiB mkpart BIOSBOOT  1    3
    parted -s "$disk" set 1 bios_grub on
    parted -s "$disk" unit MiB mkpart ESP fat32 3    515
    parted -s "$disk" set 2 esp on
    parted -s "$disk" unit MiB mkpart primary ext4 515 100%
    partprobe "$disk"
    udevadm settle
    suffix="$(disk_part_suffix)"
    efi_part="${disk}${suffix}2"
    root_part="${disk}${suffix}3"
    mkfs.vfat -F 32 -n ABORA_EFI  "$efi_part"  >/dev/null \
        || { printf 'Failed to format EFI partition\n' >&2; return 1; }
    mkfs.ext4 -F -L ABORA_ROOT    "$root_part" >/dev/null \
        || { printf 'Failed to format root partition\n' >&2; return 1; }
}

mount_target() {
    mkdir -p /mnt
    mount "$root_part" /mnt \
        || { printf 'Failed to mount %s\n' "$root_part" >&2; return 1; }
    mkdir -p /mnt/boot
    mount "$efi_part" /mnt/boot \
        || { printf 'Failed to mount %s\n' "$efi_part" >&2; return 1; }
}

_cp_required() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || { printf 'Required file missing: %s\n' "$src" >&2; return 1; }
    cp "$src" "$dst"
}

write_branding_assets() {
    local live_bg="/etc/abora/bootloader/background.png"
    local live_limine="/etc/abora/bootloader/limine-background.png"
    local live_theme="/etc/abora/bootloader/theme.txt"

    mkdir -p /mnt/etc/nixos/abora/plymouth \
             /mnt/etc/nixos/abora/bootloader \
             /mnt/etc/nixos/abora/wallpapers \
             /mnt/etc/nixos/abora/themes \
             /mnt/etc/nixos/abora/effects

    _cp_required "$title_file"                     /mnt/etc/nixos/abora/title.txt
    _cp_required /etc/abora/VERSION                /mnt/etc/nixos/abora/VERSION
    _cp_required /etc/abora/abora.sh               /mnt/etc/nixos/abora/abora.sh
    _cp_required /etc/abora/ui.sh                  /mnt/etc/nixos/abora/ui.sh
    _cp_required /etc/abora/config.sh              /mnt/etc/nixos/abora/config.sh
    _cp_required /etc/abora/desktop.sh             /mnt/etc/nixos/abora/desktop.sh
    _cp_required /etc/abora/doctor.sh              /mnt/etc/nixos/abora/doctor.sh
    _cp_required /etc/abora/recovery.sh            /mnt/etc/nixos/abora/recovery.sh
    _cp_required /etc/abora/welcome.sh             /mnt/etc/nixos/abora/welcome.sh
    _cp_required /etc/abora/app-catalog.sh         /mnt/etc/nixos/abora/app-catalog.sh
    _cp_required /etc/abora/apps.sh                /mnt/etc/nixos/abora/apps.sh
    _cp_required /etc/abora/support-report.sh      /mnt/etc/nixos/abora/support-report.sh
    _cp_required /etc/abora/hardware-test.sh       /mnt/etc/nixos/abora/hardware-test.sh
    _cp_required /etc/abora/default-wallpaper.png  /mnt/etc/nixos/abora/default-wallpaper.png
    _cp_required /etc/abora/fastfetch-logo.txt     /mnt/etc/nixos/abora/fastfetch-logo.txt
    _cp_required /etc/abora/fastfetch-config.jsonc /mnt/etc/nixos/abora/fastfetch-config.jsonc
    _cp_required /etc/abora/desktop-profiles.sh    /mnt/etc/nixos/abora/desktop-profiles.sh
    _cp_required /etc/abora/installed-base.nix     /mnt/etc/nixos/abora/installed-base.nix
    _cp_required /etc/abora/session-setup.sh       /mnt/etc/nixos/abora/session-setup.sh
    _cp_required /etc/abora/theme-sync.sh          /mnt/etc/nixos/abora/theme-sync.sh
    _cp_required /etc/abora/update.sh              /mnt/etc/nixos/abora/update.sh
    _cp_required /etc/abora/plymouth/abora.plymouth /mnt/etc/nixos/abora/plymouth/abora.plymouth
    _cp_required /etc/abora/plymouth/abora.script   /mnt/etc/nixos/abora/plymouth/abora.script
    [[ -f /etc/abora/effects/v3StartingAbora.mp3 ]] && \
        cp /etc/abora/effects/v3StartingAbora.mp3 /mnt/etc/nixos/abora/effects/v3StartingAbora.mp3 || true

    [[ -f "$live_bg" ]]    || { printf 'Missing bootloader background\n' >&2; return 1; }
    [[ -f "$live_theme" ]] || { printf 'Missing bootloader theme\n' >&2; return 1; }
    local limine_src="$live_bg"
    [[ -f "$live_limine" ]] && limine_src="$live_limine"
    install -Dm0644 "$live_bg"     /mnt/etc/nixos/abora/bootloader/background.png
    install -Dm0644 "$limine_src"  /mnt/etc/nixos/abora/bootloader/limine-background.png
    install -Dm0644 "$live_theme"  /mnt/etc/nixos/abora/bootloader/theme.txt

    find /etc/abora/wallpapers -maxdepth 1 -type f \
        -exec cp {} /mnt/etc/nixos/abora/wallpapers/ \; 2>/dev/null || true
    find /etc/abora/themes     -maxdepth 1 -type f \
        -exec cp {} /mnt/etc/nixos/abora/themes/ \;     2>/dev/null || true

    mkdir -p /mnt/etc/nixos/abora
    : > /mnt/etc/nixos/abora/apps.list
    cat > /mnt/etc/nixos/abora/apps.nix <<'EOF'
{ pkgs, ... }: { environment.systemPackages = with pkgs; []; }
EOF
    write_starter_apps_list  /mnt/etc/nixos/abora/apps.list
    render_apps_module_file  /mnt/etc/nixos/abora/apps.nix /mnt/etc/nixos/abora/apps.list

    [[ -s /mnt/etc/nixos/abora/apps.nix ]] || { printf 'App module empty\n' >&2; return 1; }
}

write_starter_apps_list() {
    local target_file="$1"
    : > "$target_file"
    [[ "${starter_apps_bundle,,}" == "none" ]] && return 0
    abora_list_bundle_apps "${starter_apps_bundle}" > "$target_file" 2>/dev/null || true
}

render_apps_module_file() {
    local target_nix="$1" app_list="$2"
    [[ -s "$app_list" ]] || return 0
    {
        printf '{ pkgs, ... }:\n{\n  environment.systemPackages = with pkgs; [\n'
        while IFS= read -r app_expr; do
            [[ -n "$app_expr" ]] && printf '    %s\n' "$app_expr"
        done < "$app_list"
        printf '  ];\n}\n'
    } > "$target_nix"
}

write_install_assets() {
    write_branding_assets
    [[ -f /etc/abora/anix.sh         ]] && cp /etc/abora/anix.sh         /mnt/etc/nixos/abora/anix.sh         || true
    [[ -f /etc/abora/anix-module.nix ]] && cp /etc/abora/anix-module.nix /mnt/etc/nixos/abora/anix-module.nix || true
    [[ -f /etc/abora/abora-options.nix ]] && cp /etc/abora/abora-options.nix /mnt/etc/nixos/abora/abora-options.nix || true
}

ensure_target_install_files() {
    mkdir -p /mnt/etc/nixos/abora
    [[ -f /mnt/etc/nixos/abora/apps.list ]] || : > /mnt/etc/nixos/abora/apps.list
    if [[ ! -f /mnt/etc/nixos/abora/apps.nix ]]; then
        printf '{ pkgs, ... }: { environment.systemPackages = with pkgs; []; }\n' \
            > /mnt/etc/nixos/abora/apps.nix
    fi
}

copy_github_auth_to_target() {
    local root_hosts="/root/.config/gh/hosts.yml"
    [[ -f "$root_hosts" ]] || return 0
    [[ "$github_identity" != "Skipped" ]] || return 0
    local target_dir="/mnt/home/${username_value}/.config/gh"
    mkdir -p "$target_dir"
    cp "$root_hosts" "$target_dir/hosts.yml"
    chmod 600 "$target_dir/hosts.yml"
    local uid="1000" gid="100"
    if command -v nixos-enter >/dev/null 2>&1; then
        uid="$(nixos-enter --root /mnt -c "id -u ${username_value}" 2>/dev/null || printf '1000')"
        gid="$(nixos-enter --root /mnt -c "id -g ${username_value}" 2>/dev/null || printf '100')"
    fi
    chown -R "${uid}:${gid}" "/mnt/home/${username_value}/.config"
}

cleanup_target() {
    sync
    umount -R /mnt 2>/dev/null || true
}

generate_config() {
    printf '[*] nixos-generate-config\n' > "$config_log"
    nixos-generate-config --root /mnt >> "$config_log" 2>&1 \
        || { printf 'nixos-generate-config failed\n' >&2; return 1; }

    write_install_assets

    local desktop_block; desktop_block="$(abora_desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value")"
    local desktop_packages; desktop_packages="$(abora_desktop_package_block "$desktop_profile")"

    [[ -n "$user_password_hash" ]] || { printf 'Password hash empty\n' >&2; return 1; }
    [[ -n "$desktop_block" ]]      || { printf 'Desktop block empty for: %s\n' "$desktop_profile" >&2; return 1; }

    if [[ "$anix_enabled" == "yes" ]]; then
        cat > /mnt/etc/nixos/anix.nix <<EOF
{ ... }:
{
  anix.enable   = true;
  anix.hostname = "${hostname_value}";
  anix.timezone = "${timezone_value}";
  anix.keyboard.console = "${keyboard_value}";
  anix.keyboard.xkb     = "${xkb_layout_value}";
  anix.desktop          = "${desktop_profile}";
  anix.wallpaper        = "${wallpaper_name}";
}
EOF
    fi

    cat > /mnt/etc/nixos/configuration.nix <<EOF
{ lib, ... }:
let appModule = ./abora/apps.nix; in
{
  imports = [
    ./hardware-configuration.nix
    ./abora/installed-base.nix
    ./abora-local.nix
  ] ++ lib.optional (builtins.pathExists appModule) appModule;
}
EOF

    cat > /mnt/etc/nixos/abora-local.nix <<EOF
{ pkgs, lib, ... }:
{
  system.nixos.variantName = "Abora ${version} ${desktop_label} Edition";
  system.nixos.variant_id  = "${desktop_variant_id}";

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.limine = {
    enable                = true;
    biosSupport           = true;
    biosDevice            = "${disk}";
    efiSupport            = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "${hostname_value}";
  time.timeZone       = "${timezone_value}";
  console.keyMap      = "${keyboard_value}";

${desktop_block}

  users.users."${username_value}" = {
    isNormalUser    = true;
    description     = "${username_value}";
    createHome      = true;
    shell           = pkgs.bash;
    extraGroups     = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword  = "${user_password_hash}";
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
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.abora = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        let
          lib       = nixpkgs.lib;
          appModule  = ./abora/apps.nix;
          anixModule = ./abora/anix-module.nix;
          anixLayer  = ./anix.nix;
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
EOF
}

# ════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════
main() {
    require_root

    # Ensure TERM is set for tput
    export TERM="${TERM:-xterm-256color}"

    # check terminal size — wait up to 3s for terminal to report correct size
    local cols rows attempts=0
    while true; do
        cols=$(tput cols  2>/dev/null || printf '80')
        rows=$(tput lines 2>/dev/null || printf '24')
        [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
        [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
        if [[ $cols -ge 80 && $rows -ge 24 ]]; then
            break
        fi
        (( attempts++ )) || true
        if [[ $attempts -ge 3 ]]; then
            printf 'Terminal too small (%dx%d). Need at least 80x24.\n' "$cols" "$rows"
            printf 'Try resizing your terminal window and running abora-install again.\n'
            exit 1
        fi
        sleep 1
    done

    # restore terminal on any exit
    trap 'tput cnorm 2>/dev/null || true; stty echo 2>/dev/null || true; tput rmcup 2>/dev/null || true' EXIT
    stty -echo 2>/dev/null || true
    tput smcup 2>/dev/null || true

    sync_starter_apps_label
    refresh_github_identity || true
    auto_detect_timezone    || true
    auto_detect_keyboard    || true

    command -v mkpasswd >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1 || {
        tput rmcup 2>/dev/null || true; tput cnorm 2>/dev/null || true; stty echo 2>/dev/null || true
        printf 'No password hashing tool found (mkpasswd or openssl required).\n' >&2
        exit 1
    }

    local steps=("network" "welcome" "desktop" "names" "password" "options" "disk" "confirm")
    local idx=0

    while true; do
        local step="${steps[$idx]}"
        STEP_RESULT=""

        case "$step" in
            network)  step_network  ;;
            welcome)  step_welcome  ;;
            desktop)  step_desktop  ;;
            names)    step_names    ;;
            password) step_password ;;
            options)  step_options  ;;
            disk)     step_disk     ;;
            confirm)  step_confirm  ;;
        esac

        case "$STEP_RESULT" in
            next)
                [[ $idx -lt $(( ${#steps[@]} - 1 )) ]] && (( idx++ )) || true
                ;;
            back)
                [[ $idx -gt 0 ]] && (( idx-- )) || true
                ;;
            install)
                step_install
                if [[ "$STEP_RESULT" == "done" ]]; then
                    step_finish
                    exit 0
                fi
                # on fail, go back to confirm
                ;;
        esac
    done
}

main "$@"
