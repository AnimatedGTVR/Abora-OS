#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  ABORA OS INSTALLER  ·  v4
#  Clean full-screen TUI — OMARCHY-inspired
# ════════════════════════════════════════════════════════════════════
set -uo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_lib() {
    local name="$1" extra="${2:-}"
    local f
    for f in "$extra" "$script_dir/$name" "$script_dir/abora-$name" \
              "/etc/abora/$name" "/etc/abora/abora-$name"; do
        [[ -n "$f" && -f "$f" ]] && printf '%s' "$f" && return 0
    done
    return 1
}
desktop_profiles_lib="$(_find_lib "desktop-profiles.sh" "${ABORA_DESKTOP_PROFILES_LIB:-}")" \
    || { printf 'abora-installer: desktop-profiles.sh not found\n' >&2; exit 1; }
app_catalog_lib="$(_find_lib "app-catalog.sh" "${ABORA_APP_CATALOG_LIB:-}")" \
    || { printf 'abora-installer: app-catalog.sh not found\n' >&2; exit 1; }
# shellcheck source=/dev/null
source "$desktop_profiles_lib"
# shellcheck source=/dev/null
source "$app_catalog_lib"

# ── State ─────────────────────────────────────────────────────────────────────
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
title_file="/etc/abora/title.txt"
_CUSTOM_APPS=()   # filled by step_apps
config_log="/tmp/abora-config.log"
install_log="/tmp/abora-install.log"
version="${ABORA_VERSION:-}"
[[ -z "$version" && -f /etc/abora/VERSION ]] && version="$(tr -d '\n' < /etc/abora/VERSION)"
[[ -z "$version" ]] && version="v4"
STEP_RESULT=""
_STEP_IDX=0
_TOTAL_STEPS=9
_STEP_NAMES=("Welcome" "Network" "Desktop" "Account" "Password" "Apps" "Options" "Disk" "Review")

# ── Colors ────────────────────────────────────────────────────────────────────
G='\033[1;32m'
C='\033[1;36m'
W='\033[1;37m'
GY='\033[90m'
RD='\033[1;31m'
Y='\033[1;33m'
BG='\033[0;32m'
NC='\033[0m'

# ── ASCII art banner ──────────────────────────────────────────────────────────
_ART=(
'  ▄▄▄▄   ██████   ████  ██████   ▄▄▄▄    ████  ███████'
' ██  ██  ██   ██ ██  ██ ██  ██  ██  ██  ██  ██ ██     '
' ██████  ██████  ██  ██ █████   ██████  ██  ██  █████  '
' ██  ██  ██   ██ ██  ██ ██  ██  ██  ██  ██  ██     ██  '
' ██  ██  ██████   ████  ██  ██  ██  ██   ████  ██████  '
)

# ── Terminal helpers ──────────────────────────────────────────────────────────
_cols() { tput cols  2>/dev/null || printf '80'; }
_rows() { tput lines 2>/dev/null || printf '24'; }
_div()  { local c; c=$(_cols); printf '%*s' "$((c-4))" '' | tr ' ' '─'; }

# ── Screen header: clear + compact brand + step tracker + title ───────────────
_screen() {
    local title="$1" sub="${2:-}" show_art="${3:-0}"
    clear
    printf '\n'

    if [[ "$show_art" == "1" ]]; then
        local line
        for line in "${_ART[@]}"; do
            printf '%b  %s%b\n' "$G" "$line" "$NC"
        done
        printf '\n'
    fi

    # Brand + step location
    printf '  %bABORA%b %bOS%b' "$C" "$NC" "$W" "$NC"
    if [[ $_STEP_IDX -lt $_TOTAL_STEPS ]]; then
        local cur_name="${_STEP_NAMES[$_STEP_IDX]}"
        printf '  %b│%b  Step %d of %d  —  %b%s%b' \
            "$GY" "$NC" "$((_STEP_IDX+1))" "$_TOTAL_STEPS" "$W" "$cur_name" "$NC"
    fi
    printf '\n'

    # Progress dots: ✓ = done, ● = current, ○ = todo
    printf '  '
    local _pi
    for (( _pi=0; _pi<_TOTAL_STEPS; _pi++ )); do
        if   [[ $_STEP_IDX -ge $_TOTAL_STEPS || $_pi -lt $_STEP_IDX ]]; then
            printf '%b✓%b' "$BG" "$NC"
        elif [[ $_pi -eq $_STEP_IDX ]]; then
            printf '%b●%b' "$C"  "$NC"
        else
            printf '%b○%b' "$GY" "$NC"
        fi
        [[ $_pi -lt $((_TOTAL_STEPS-1)) ]] && printf '%b─%b' "$GY" "$NC"
    done
    printf '\n'

    local d; d="$(_div)"
    printf '%b  %s%b\n' "$GY" "$d" "$NC"
    printf '%b  %s%b\n' "$W" "$title" "$NC"
    [[ -n "$sub" ]] && printf '%b  %s%b\n' "$GY" "$sub" "$NC"
    printf '%b  %s%b\n\n' "$GY" "$d" "$NC"
}

# ── Hint bar ──────────────────────────────────────────────────────────────────
_hint() {
    printf '\n%b  ─  %s%b\n' "$GY" "$1" "$NC"
}

# ── Key reader — sets KEY_NAME and KEY_CHAR ───────────────────────────────────
KEY_NAME="" KEY_CHAR=""
read_key() {
    local ch="" seq=""
    IFS= read -rsn1 ch
    KEY_CHAR="$ch"
    KEY_NAME="CHAR"
    if [[ "$ch" == $'\x1b' ]]; then
        IFS= read -rsn1 -t0.1 seq || true
        if [[ "$seq" == '[' ]]; then
            IFS= read -rsn1 -t0.1 seq || true
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
    elif [[ "$ch" == '' || "$ch" == $'\r' || "$ch" == $'\n' ]]; then KEY_NAME="ENTER"
    elif [[ "$ch" == $'\x7f' || "$ch" == $'\x08' ]];             then KEY_NAME="BACKSPACE"
    elif [[ "$ch" == $'\x09' ]];                                  then KEY_NAME="TAB"
    elif [[ "$ch" == $'\x03' ]];                                  then KEY_NAME="CTRL_C"; tput cnorm 2>/dev/null; stty echo 2>/dev/null; exit 0
    fi
}

# ── Arrow-key menu ── MENU_IDX = selected (-1 = ESC/back) ────────────────────
# Usage: _menu <default_idx> "Label|description" ...
MENU_IDX=0
_menu() {
    local sel="${1:-0}"; shift
    local items=("$@")
    local count=${#items[@]}

    _render_menu() {
        local i
        for i in "${!items[@]}"; do
            local lbl="${items[$i]%%|*}"
            local dsc="${items[$i]#*|}"
            [[ "$dsc" == "$lbl" ]] && dsc=""
            if [[ $i -eq $sel ]]; then
                printf '%b  ──▶  %-26s%b' "$C" "$lbl" "$NC"
                [[ -n "$dsc" ]] && printf '  %b%s%b' "$GY" "$dsc" "$NC"
            else
                printf '%b    ·  %s%b' "$GY" "$lbl" "$NC"
            fi
            printf '\n'
        done
    }

    _render_menu
    while true; do
        read_key
        local moved=0
        case "$KEY_NAME" in
            UP)    [[ $sel -gt 0 ]]           && (( sel-- )) && moved=1 ;;
            DOWN)  [[ $sel -lt $((count-1)) ]] && (( sel++ )) && moved=1 ;;
            ENTER) MENU_IDX=$sel;  printf '\033[%dA\033[J' "$count"; return 0 ;;
            ESC)   MENU_IDX=-1;    printf '\033[%dA\033[J' "$count"; return 1 ;;
        esac
        if [[ $moved -eq 1 ]]; then
            printf '\033[%dA' "$count"
            _render_menu
        fi
    done
}

# ── Text input — INPUT_VAL ────────────────────────────────────────────────────
INPUT_VAL=""
_input() {
    local prompt="$1" default="${2:-}"
    stty echo 2>/dev/null || true
    printf '  %b%s%b' "$W" "$prompt" "$NC"
    [[ -n "$default" ]] && printf '  %b(%s)%b' "$GY" "$default" "$NC"
    printf ':  '
    local val
    IFS= read -re val || val=""
    INPUT_VAL="${val:-$default}"
    stty -echo 2>/dev/null || true
}

# ── Secret input — SECRET_VAL ─────────────────────────────────────────────────
SECRET_VAL=""
_secret() {
    local prompt="$1"
    stty echo 2>/dev/null || true
    printf '  %b%s%b:  ' "$W" "$prompt" "$NC"
    local val
    IFS= read -rs val || val=""
    printf '\n'
    stty -echo 2>/dev/null || true
    SECRET_VAL="$val"
}

# ── Summary table ─────────────────────────────────────────────────────────────
# Usage: _table "Field|Value" "Field|Value" ...
_table() {
    local fw=16
    local cols; cols=$(_cols)
    local vw=$(( cols - fw - 8 ))
    [[ $vw -lt 20 ]] && vw=30
    local sf; sf="$(printf '%*s' $((fw+2)) '' | tr ' ' '-')"
    local sv; sv="$(printf '%*s' $((vw+2)) '' | tr ' ' '-')"
    printf '  %b+%s+%s+%b\n' "$GY" "$sf" "$sv" "$NC"
    printf '  %b| %-*s | %-*s |%b\n' "$GY" "$fw" "Field" "$vw" "Value" "$NC"
    printf '  %b+%s+%s+%b\n' "$GY" "$sf" "$sv" "$NC"
    local e
    for e in "$@"; do
        local f="${e%%|*}" v="${e#*|}"
        printf '  | %b%-*s%b | %b%-*s%b |\n' "$GY" "$fw" "$f" "$NC" "$W" "$vw" "$v" "$GY"
    done
    printf '  %b+%s+%s+%b\n' "$GY" "$sf" "$sv" "$NC"
}

# ── Progress bar ──────────────────────────────────────────────────────────────
_pbar() {
    local pct="$1" width="${2:-40}"
    local f=$(( width * pct / 100 ))
    local e=$(( width - f ))
    printf '%b' "$C"
    [[ $f -gt 0 ]] && printf '%*s' "$f" '' | tr ' ' '█'
    printf '%b' "$GY"
    [[ $e -gt 0 ]] && printf '%*s' "$e" '' | tr ' ' '░'
    printf '%b %3d%%%b' "$W" "$pct" "$NC"
}

# ── Inline spinner for blocking ops — call in a loop ─────────────────────────
_SPIN_IDX=0
_SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_spin() {
    local msg="${1:-Working…}"
    printf '\r  %b%s%b  %b%s%b' "$C" "${_SPIN_FRAMES[$_SPIN_IDX]}" "$NC" "$GY" "$msg" "$NC"
    _SPIN_IDX=$(( (_SPIN_IDX + 1) % ${#_SPIN_FRAMES[@]} ))
}

# ════════════════════════════════════════════════════════════════════
#  STEPS
# ════════════════════════════════════════════════════════════════════

step_welcome() {
    _screen "Welcome to Abora OS  ${version}" "Let's get your system installed." 1
    printf '  %bAbora OS is a NixOS-based distribution focused on usability.%b\n' "$GY" "$NC"
    printf '  %bThis installer will guide you through setup in a few steps.%b\n\n' "$GY" "$NC"
    printf '  %bWhat you will need:%b\n' "$W" "$NC"
    printf '  %b  ·  An internet connection%b\n' "$GY" "$NC"
    printf '  %b  ·  A disk to install to (will be erased)%b\n' "$GY" "$NC"
    printf '  %b  ·  About 10–20 minutes%b\n\n' "$GY" "$NC"
    _hint "↵ Continue  ·  Ctrl+C Quit"
    read_key
    STEP_RESULT="next"
}

step_network() {
    while true; do
        _screen "Network Connection" "An internet connection is needed to download packages."

        # Check connection with spinner
        printf '  %bChecking connection…%b' "$GY" "$NC"
        local connected=0
        nmcli -t networking connectivity check 2>/dev/null | grep -q "^full$" && connected=1 || true
        printf '\r%*s\r' 40 ''   # clear the checking line

        if [[ $connected -eq 1 ]]; then
            local iface; iface="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
                | awk -F: '$2~/ethernet|wireless/{print $1; exit}' || true)"
            printf '  %b✓  Connected%b' "$BG" "$NC"
            [[ -n "$iface" ]] && printf '  %b(%s)%b' "$GY" "$iface" "$NC"
            printf '\n\n'
            _menu 0 \
                "Continue|Proceed with installation" \
                "Connect to a different network"
            if [[ $MENU_IDX -eq 0 ]]; then
                STEP_RESULT="next"; return
            fi
        else
            printf '  %b✗  No internet connection detected%b\n\n' "$RD" "$NC"
        fi

        # WiFi scan with spinner
        printf '  %bScanning for networks…%b' "$GY" "$NC"
        nmcli device wifi rescan 2>/dev/null || true
        printf '\r%*s\r' 40 ''

        local ssids=() signals=() secs=()
        while IFS=: read -r ssid sig sec; do
            [[ -z "$ssid" || "$ssid" == "--" ]] && continue
            [[ "$sig" =~ ^[0-9]+$ ]] || continue
            local seen=0
            local s
            for s in "${ssids[@]+"${ssids[@]}"}"; do [[ "$s" == "$ssid" ]] && seen=1 && break; done
            [[ $seen -eq 1 ]] && continue
            ssids+=("$ssid"); signals+=("$sig"); secs+=("$sec")
        done < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null \
                  | sort -t: -k2 -rn | head -10 || true)

        local menu_items=()
        local i
        for i in "${!ssids[@]}"; do
            local bar="░░░░"
            local sig="${signals[$i]}"
            [[ $sig -ge 75 ]] && bar="████"
            [[ $sig -ge 50 && $sig -lt 75 ]] && bar="███░"
            [[ $sig -ge 25 && $sig -lt 50 ]] && bar="██░░"
            [[ $sig -ge 1  && $sig -lt 25 ]] && bar="█░░░"
            local lock=""; [[ "${secs[$i]}" != "--" && -n "${secs[$i]}" ]] && lock=" 🔒"
            menu_items+=("${ssids[$i]}${lock}|${bar} ${sig}%")
        done
        menu_items+=("Rescan" "Skip (no network)" "← Back")

        if [[ ${#ssids[@]} -eq 0 ]]; then
            printf '  %bNo wireless networks found.%b\n\n' "$GY" "$NC"
        else
            printf '  %bWireless networks:%b\n\n' "$W" "$NC"
        fi

        _hint "↑↓ navigate  ·  ↵ select"
        _menu 0 "${menu_items[@]}"
        local choice=$MENU_IDX
        local net_count=${#ssids[@]}

        if [[ $choice -lt $net_count ]]; then
            local chosen="${ssids[$choice]}"
            printf '\n  %bConnecting to %s...%b\n' "$W" "$chosen" "$NC"
            printf '  %bPassword (leave empty if open):%b  ' "$GY" "$NC"
            stty echo 2>/dev/null || true
            local wp=""
            IFS= read -rs wp || true
            printf '\n'
            stty -echo 2>/dev/null || true
            if [[ -n "$wp" ]]; then
                nmcli device wifi connect "$chosen" password "$wp" >/dev/null 2>&1 || true
            else
                nmcli device wifi connect "$chosen" >/dev/null 2>&1 || true
            fi
            sleep 2
        elif [[ $choice -eq $net_count ]]; then
            : # rescan — loop
        elif [[ $choice -eq $((net_count+1)) ]]; then
            STEP_RESULT="next"; return
        elif [[ $choice -eq $((net_count+2)) ]]; then
            STEP_RESULT="back"; return
        elif [[ $choice -eq -1 ]]; then
            STEP_RESULT="back"; return
        fi
    done
}

step_desktop() {
    # id|Display Label|Category|Description
    local _de_list=(
        "gnome|GNOME|Full Desktop|Modern, clean, polished. Best for newcomers."
        "plasma|KDE Plasma|Full Desktop|Powerful and customizable. Windows-like feel."
        "xfce|XFCE|Full Desktop|Lightweight, stable, traditional. Fast on old hardware."
        "cinnamon|Cinnamon|Full Desktop|Familiar and traditional. Windows-like layout."
        "mate|MATE|Full Desktop|Classic GNOME 2 fork. Simple and efficient."
        "budgie|Budgie|Full Desktop|Modern and elegant. Clean, simple design."
        "lxqt|LXQt|Full Desktop|Lightweight Qt desktop. Minimal and fast."
        "pantheon|Pantheon|Full Desktop|Elementary OS desktop. Beautiful and focused."
        "enlightenment|Enlightenment|Full Desktop|Unique compositing DE. Very low footprint."
        "hyprland|Hyprland|Wayland Compositor|Dynamic tiling, GPU-accelerated. Keyboard-driven."
        "sway|Sway|Wayland Compositor|i3-compatible Wayland compositor. Minimal."
        "niri|Niri|Wayland Compositor|Scrollable-tiling Wayland compositor."
        "river|River|Wayland Compositor|Dynamic tiling Wayland compositor."
        "i3|i3|Window Manager|Popular tiling WM. Keyboard-driven and scriptable."
        "awesome|AwesomeWM|Window Manager|Lua-configured tiling WM. Highly extensible."
        "openbox|Openbox|Window Manager|Lightweight stacking WM. Simple and fast."
        "bspwm|BSPWM|Window Manager|Binary space partitioning tiling WM."
        "qtile|Qtile|Window Manager|Python-configured WM. Fully customizable."
        "fluxbox|Fluxbox|Window Manager|Fast and lightweight stacking WM."
        "icewm|IceWM|Window Manager|Classic lightweight WM. Very fast startup."
        "herbstluftwm|Herbstluftwm|Window Manager|Manual tiling, command-based."
        "none|No Desktop|None|Terminal only. No graphical environment installed."
    )

    local ids=() labels=() cats=() descs=()
    local _entry
    for _entry in "${_de_list[@]}"; do
        IFS='|' read -r _id _lbl _cat _desc <<< "$_entry"
        ids+=("$_id"); labels+=("$_lbl"); cats+=("$_cat"); descs+=("$_desc")
    done

    local count=${#ids[@]}
    local cur=0
    local rows; rows=$(_rows)
    local visible=$(( rows - 14 ))
    [[ $visible -lt 5 ]] && visible=5

    while true; do
        _screen "Choose Your Desktop" "Pick the environment you'll use every day."

        local win_start=0
        if [[ $count -gt $visible ]]; then
            win_start=$(( cur - visible / 2 ))
            [[ $win_start -lt 0 ]] && win_start=0
            [[ $(( win_start + visible )) -ge $count ]] && win_start=$(( count - visible ))
        fi
        local win_end=$(( win_start + visible - 1 ))
        [[ $win_end -ge $count ]] && win_end=$(( count - 1 ))

        [[ $win_start -gt 0 ]] && printf '  %b  ↑ %d more above%b\n' "$GY" "$win_start" "$NC"

        local prev_cat="" i
        for (( i = win_start; i <= win_end; i++ )); do
            if [[ "${cats[$i]}" != "$prev_cat" ]]; then
                prev_cat="${cats[$i]}"
                printf '\n  %b─── %s%b\n' "$C" "$prev_cat" "$NC"
            fi
            if [[ $i -eq $cur ]]; then
                printf '%b  ──▶  %-16s%b  %b%s%b\n' \
                    "$C" "${labels[$i]}" "$NC" "$GY" "${descs[$i]}" "$NC"
            else
                printf '%b    ·  %s%b\n' "$GY" "${labels[$i]}" "$NC"
            fi
        done

        local remaining=$(( count - 1 - win_end ))
        [[ $remaining -gt 0 ]] && printf '\n  %b  ↓ %d more below%b\n' "$GY" "$remaining" "$NC"

        _hint "↑↓ Move   ↵ Select   Esc Back"

        read_key
        case "$KEY_NAME" in
            UP)    [[ $cur -gt 0 ]] && (( cur-- )) ;;
            DOWN)  [[ $cur -lt $((count-1)) ]] && (( cur++ )) ;;
            ENTER)
                desktop_profile="${ids[$cur]}"
                abora_sync_desktop_label "$desktop_profile" 2>/dev/null || true
                STEP_RESULT="next"
                return
                ;;
            ESC) STEP_RESULT="back"; return ;;
        esac
    done
}

step_names() {
    while true; do
        _screen "Create Your Account" "Set up your user details. Press Enter to keep the default."

        _input "Username" "$username_value"
        local new_user="$INPUT_VAL"
        if [[ -z "$new_user" || ! "$new_user" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
            printf '\n  %bInvalid username. Use lowercase letters, digits, _ or -. Press Enter.%b\n' "$RD" "$NC"
            read -r
            continue
        fi
        username_value="$new_user"

        _input "Hostname" "$hostname_value"
        local new_host="$INPUT_VAL"
        if [[ -z "$new_host" || ! "$new_host" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; then
            printf '\n  %bInvalid hostname. Press Enter.%b\n' "$RD" "$NC"
            read -r
            continue
        fi
        hostname_value="$new_host"

        _input "Timezone" "$timezone_value"
        timezone_value="$INPUT_VAL"

        STEP_RESULT="next"
        return
    done
}

step_password() {
    while true; do
        _screen "Set Your Password" "Choose a strong password for ${username_value}."

        _secret "Password"
        local p1="$SECRET_VAL"
        _secret "Confirm password"
        local p2="$SECRET_VAL"

        if [[ "$p1" != "$p2" ]]; then
            printf '\n  %bPasswords do not match. Try again.%b\n\n' "$RD" "$NC"
            sleep 1
            continue
        fi
        if [[ ${#p1} -lt 6 ]]; then
            printf '\n  %bPassword must be at least 6 characters.%b\n\n' "$RD" "$NC"
            sleep 1
            continue
        fi

        # Strength hint
        local strength="Weak"
        [[ ${#p1} -ge 10 ]] && strength="OK"
        [[ ${#p1} -ge 12 && "$p1" =~ [A-Z] && "$p1" =~ [0-9] ]] && strength="Good"
        [[ ${#p1} -ge 16 && "$p1" =~ [^a-zA-Z0-9] ]] && strength="Strong"
        printf '  %bStrength: %s%b\n\n' "$GY" "$strength" "$NC"

        # Hash
        local hash=""
        command -v mkpasswd >/dev/null 2>&1 && \
            hash="$(printf '%s' "$p1" | mkpasswd -s -m sha-512 2>/dev/null || true)"
        [[ -z "$hash" ]] && command -v openssl >/dev/null 2>&1 && \
            hash="$(openssl passwd -6 "$p1" 2>/dev/null || true)"

        if [[ -z "$hash" ]]; then
            printf '  %bFailed to hash password. Try again.%b\n\n' "$RD" "$NC"
            sleep 1
            continue
        fi
        user_password_hash="$hash"
        STEP_RESULT="next"
        return
    done
}

step_apps() {
    # Parse the catalog: id|Name|pkg|Category|Description|default
    local ids=() names=() cats=() descs=() sel=()
    while IFS='|' read -r id name pkg cat desc def; do
        [[ -z "$id" || "$id" == '#'* ]] && continue
        ids+=("$id"); names+=("$name"); cats+=("$cat")
        descs+=("$desc"); sel+=("${def:-no}")
    done < <(abora_app_catalog 2>/dev/null || true)

    local count=${#ids[@]}
    if [[ $count -eq 0 ]]; then
        STEP_RESULT="next"; return
    fi

    local cur=0   # cursor index
    local rows; rows=$(_rows)
    local art_lines=$(( ${#_ART[@]} + 5 ))  # art + margins + header
    local footer_lines=4
    local visible=$(( rows - art_lines - footer_lines ))
    [[ $visible -lt 4 ]] && visible=4

    while true; do
        _screen "Choose Your Apps" "Space toggle  ·  ↑↓ navigate  ·  A all  ·  N none  ·  ↵ done"

        # scroll window
        local win_start=0
        if [[ $count -gt $visible ]]; then
            win_start=$(( cur - visible / 2 ))
            [[ $win_start -lt 0 ]] && win_start=0
            [[ $(( win_start + visible )) -ge $count ]] && win_start=$(( count - visible ))
        fi
        local win_end=$(( win_start + visible - 1 ))
        [[ $win_end -ge $count ]] && win_end=$(( count - 1 ))

        [[ $win_start -gt 0 ]] && printf '  %b  ↑ %d more above%b\n' "$GY" "$win_start" "$NC"

        local prev_cat=""
        local i
        for (( i = win_start; i <= win_end; i++ )); do
            # Category header
            if [[ "${cats[$i]}" != "$prev_cat" ]]; then
                prev_cat="${cats[$i]}"
                printf '\n  %b─── %s%b\n' "$C" "$prev_cat" "$NC"
            fi

            local check="  "; [[ "${sel[$i]}" == "yes" ]] && check="✓ "
            if [[ $i -eq $cur ]]; then
                printf '%b  › [%s] %-24s%b  %b%s%b\n' \
                    "$W" "$check" "${names[$i]}" "$NC" "$GY" "${descs[$i]}" "$NC"
            else
                local clr="$GY"; [[ "${sel[$i]}" == "yes" ]] && clr="$W"
                printf '%b    [%s] %s%b\n' "$clr" "$check" "${names[$i]}" "$NC"
            fi
        done

        local remaining=$(( count - 1 - win_end ))
        [[ $remaining -gt 0 ]] && printf '\n  %b  ↓ %d more below%b\n' "$GY" "$remaining" "$NC"

        local n_sel=0
        for s in "${sel[@]+"${sel[@]}"}"; do [[ "$s" == "yes" ]] && (( n_sel++ )) || true; done
        printf '\n  %b%d / %d apps selected%b\n' "$C" "$n_sel" "$count" "$NC"

        read_key
        case "$KEY_NAME" in
            UP)    [[ $cur -gt 0 ]] && (( cur-- )) ;;
            DOWN)  [[ $cur -lt $((count-1)) ]] && (( cur++ )) ;;
            ENTER) break ;;
            ESC)   STEP_RESULT="back"; return ;;
            CHAR)
                case "$KEY_CHAR" in
                    ' ') [[ "${sel[$cur]}" == "yes" ]] && sel[$cur]="no" || sel[$cur]="yes" ;;
                    a|A) for (( i=0; i<count; i++ )); do sel[$i]="yes"; done ;;
                    n|N) for (( i=0; i<count; i++ )); do sel[$i]="no";  done ;;
                esac
                ;;
        esac
    done

    # Store selection
    starter_apps_bundle="custom"
    starter_apps_label="Custom (${n_sel} apps)"
    _CUSTOM_APPS=()
    for i in "${!ids[@]}"; do
        [[ "${sel[$i]}" == "yes" ]] && _CUSTOM_APPS+=("${ids[$i]}")
    done

    STEP_RESULT="next"
}

step_options() {
    _screen "Installation Options" "Finalize how Abora is set up."

    printf '  %bAnix — graphical app manager:%b\n\n' "$W" "$NC"
    local anix_default=0
    [[ "$anix_enabled" == "no" ]] && anix_default=1
    _menu $anix_default \
        "Enable Anix|Recommended — browse and install apps from a GUI" \
        "Disable Anix"
    if [[ $MENU_IDX -eq -1 ]]; then STEP_RESULT="back"; return; fi
    [[ $MENU_IDX -eq 0 ]] && anix_enabled="yes" || anix_enabled="no"

    STEP_RESULT="next"
}

step_disk() {
    while true; do
        _screen "Select Installation Disk" "⚠  The chosen disk will be completely erased."

        local disk_lines=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && disk_lines+=("$line")
        done < <(collect_disks 2>/dev/null || true)

        if [[ ${#disk_lines[@]} -eq 0 ]]; then
            printf '  %bNo suitable disks found.%b\n' "$RD" "$NC"
            printf '  %bEnsure a disk is attached and press Enter to rescan.%b\n\n' "$GY" "$NC"
            read -r
            continue
        fi

        local menu_items=()
        local disk_names=()
        for line in "${disk_lines[@]}"; do
            local dname="${line%%|*}"
            local drest="${line#*|}"
            local dsize="${drest%%|*}"
            local dmodel="${drest#*|}"
            disk_names+=("$dname")
            menu_items+=("/dev/$dname  $dsize|$dmodel")
        done
        menu_items+=("← Back")

        _hint "↑↓ navigate  ·  ↵ select"
        _menu 0 "${menu_items[@]}"

        if [[ $MENU_IDX -eq -1 || $MENU_IDX -eq ${#disk_names[@]} ]]; then
            STEP_RESULT="back"; return
        fi

        disk="/dev/${disk_names[$MENU_IDX]}"
        STEP_RESULT="next"
        return
    done
}

step_confirm() {
    _screen "Confirm Installation" "Review your choices before we begin."

    _table \
        "Desktop|$desktop_label" \
        "Username|$username_value" \
        "Password|$(printf '%.0s*' 1 2 3 4 5 6)" \
        "Hostname|$hostname_value" \
        "Timezone|$timezone_value" \
        "Keyboard|$keyboard_value" \
        "Disk|$disk" \
        "Apps|$starter_apps_label" \
        "Anix|$anix_enabled"

    printf '\n  %b⚠  All data on %s will be permanently and irreversibly erased.%b\n\n' "$RD" "$disk" "$NC"

    printf '  %bDoes this look right?%b\n\n' "$C" "$NC"
    _menu 0 "Yes, install Abora OS" "No, change something"
    if [[ $MENU_IDX -eq 0 ]]; then
        STEP_RESULT="install"
    else
        STEP_RESULT="back"
    fi
}

step_install() {
    local phases=(
        "Partitioning disk"
        "Mounting filesystem"
        "Generating configuration"
        "Downloading packages"
        "Activating system"
        "Installing bootloader"
    )

    _draw_install() {
        local cur="$1" pct="$2" elapsed="$3"
        clear
        printf '\n'
        printf '  %bABORA%b %bOS%b  %b│%b  Installing — do not power off\n' \
            "$C" "$NC" "$W" "$NC" "$GY" "$NC"
        printf '  '
        local _di
        for (( _di=0; _di<_TOTAL_STEPS; _di++ )); do
            printf '%b✓%b' "$BG" "$NC"
            [[ $_di -lt $((_TOTAL_STEPS-1)) ]] && printf '%b─%b' "$GY" "$NC"
        done
        printf '\n'
        local d; d="$(_div)"
        printf '%b  %s%b\n\n' "$GY" "$d" "$NC"

        # Phase list
        local i
        for i in "${!phases[@]}"; do
            if   [[ $i -lt $cur ]]; then printf '  %b  ✓  %s%b\n' "$BG" "${phases[$i]}" "$NC"
            elif [[ $i -eq $cur ]]; then printf '  %b  →  %s%b\n' "$C"  "${phases[$i]}" "$NC"
            else                         printf '  %b  ·  %s%b\n' "$GY" "${phases[$i]}" "$NC"
            fi
        done

        # Progress bar + timer
        local m=$(( elapsed/60 )) s=$(( elapsed%60 ))
        printf '\n  '; _pbar "$pct" 48
        printf '   %b%02d:%02d%b\n\n' "$GY" "$m" "$s" "$NC"

        # Live log — last 6 lines stripped of ANSI
        printf '%b  ── Recent output ──────────────────────────────────────────%b\n' "$GY" "$NC"
        local cols; cols=$(_cols)
        local max_w=$(( cols - 6 ))
        local lc=0
        while IFS= read -r ln; do
            [[ -z "$ln" ]] && continue
            ln="$(printf '%s' "$ln" | sed 's/\x1b\[[0-9;]*[mGKH]//g' | tr -d '\r')"
            [[ -z "$ln" ]] && continue
            printf '  %b%-*.*s%b\n' "$GY" "$max_w" "$max_w" "$ln" "$NC"
            (( lc++ )) || true
            [[ $lc -ge 5 ]] && break
        done < <(tail -10 "$install_log" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -5)
        printf '%b  ── Full log: %s%b\n' "$GY" "$install_log" "$NC"
    }

    _fail() {
        printf '\n  %b✗  %s%b\n' "$RD" "$1" "$NC"
        printf '  %bPress Enter to go back and try again.%b\n' "$GY" "$NC"
        stty echo 2>/dev/null || true; read -r; stty -echo 2>/dev/null || true
        STEP_RESULT="fail"
    }

    _draw_install 0 2 0

    partition_disk || { _fail "Partitioning failed. Check the log for details."; return; }
    _draw_install 1 8 0

    mount_target   || { _fail "Mount failed. Check the log for details."; return; }
    _draw_install 2 15 0

    generate_config || { _fail "Config generation failed. Check the log for details."; return; }
    _draw_install 3 20 0

    local nixpkgs_path
    nixpkgs_path="$(resolve_nixpkgs_path)" \
        || { _fail "Cannot locate nixpkgs. Is the ISO intact?"; return; }

    printf '[*] Starting nixos-install\n' > "$install_log"
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
    local pid="$!"

    local start; start="$(date +%s)"
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start ))
        local phase=3 pct=20

        if   grep -qi 'installing the boot loader'            "$install_log" 2>/dev/null; then phase=5; pct=93
        elif grep -qi 'activating\|setting up /etc'           "$install_log" 2>/dev/null; then phase=4; pct=85
        elif grep -qi 'created.*symlinks in user environment' "$install_log" 2>/dev/null; then phase=4; pct=78
        elif grep -qi "copying path '/nix/store"              "$install_log" 2>/dev/null; then phase=3; pct=50
        elif grep -qi 'building the configuration'            "$install_log" 2>/dev/null; then phase=3; pct=35
        fi

        local bonus=$(( elapsed / 10 ))
        pct=$(( pct + bonus ))
        [[ $pct -gt 99 ]] && pct=99

        _draw_install "$phase" "$pct" "$elapsed"
        sleep 1
    done

    if wait "$pid"; then
        _draw_install 6 100 $(( $(date +%s) - start ))
        copy_github_auth_to_target || true
        cleanup_target             || true
        STEP_RESULT="done"
    else
        _fail "nixos-install failed. See $install_log for details."
    fi
}

step_finish() {
    _STEP_IDX=$((_TOTAL_STEPS))   # all steps done — show ✓✓✓✓✓✓✓✓✓
    _screen "Installation Complete" "Abora OS has been installed successfully."

    printf '  %b✓  %s installed successfully%b\n\n' "$BG" "Abora OS ${version}" "$NC"
    printf '  %bNext steps:%b\n' "$W" "$NC"
    printf '  %b  1.  Remove the USB / live media%b\n' "$GY" "$NC"
    printf '  %b  2.  Reboot — your disk will be selected automatically%b\n' "$GY" "$NC"
    printf '  %b  3.  Log in as %b%s%b on the %b%s%b desktop%b\n\n' \
        "$GY" "$W" "$username_value" "$GY" "$W" "$desktop_label" "$GY" "$NC"

    printf '  %bWhat would you like to do?%b\n\n' "$C" "$NC"
    _menu 0 "Reboot into Abora OS" "Power off"
    sync
    if [[ $MENU_IDX -eq 0 ]]; then
        reboot
    else
        poweroff
    fi
    sleep 10
    exit 0
}

# ════════════════════════════════════════════════════════════════════
#  BACKEND  (unchanged from audit-fixed version)
# ════════════════════════════════════════════════════════════════════

sync_starter_apps_label() {
    case "${starter_apps_bundle,,}" in
        none)       starter_apps_label="None"          ;;
        favorites)  starter_apps_label="Fan Favorites" ;;
        essentials) starter_apps_label="Essentials"    ;;
        social)     starter_apps_label="Social"        ;;
        creator)    starter_apps_label="Creator"       ;;
        developer)  starter_apps_label="Developer"     ;;
        *)          starter_apps_label="Custom"        ;;
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
    [[ "$d" =~ ^[a-z][a-z0-9_-]*$ ]] && keyboard_value="$d" && sync_xkb_layout || true
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
}

resolve_nixpkgs_path() {
    local candidate
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
        us) xkb_layout_value="us" ;;  uk) xkb_layout_value="gb" ;;
        de) xkb_layout_value="de" ;;  fr) xkb_layout_value="fr" ;;
        es) xkb_layout_value="es" ;;  it) xkb_layout_value="it" ;;
        pt) xkb_layout_value="pt" ;;  ru) xkb_layout_value="ru" ;;
        *)  xkb_layout_value="$keyboard_value" ;;
    esac
}

disk_part_suffix() {
    case "$disk" in *nvme*|*mmcblk*|*loop*) printf 'p' ;; *) printf '' ;; esac
}

partition_disk() {
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
    local suffix; suffix="$(disk_part_suffix)"
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
        cp /etc/abora/effects/v3StartingAbora.mp3 \
           /mnt/etc/nixos/abora/effects/v3StartingAbora.mp3 || true

    [[ -f "$live_bg" ]]    || { printf 'Missing bootloader background\n' >&2; return 1; }
    [[ -f "$live_theme" ]] || { printf 'Missing bootloader theme\n' >&2; return 1; }
    local limine_src="$live_bg"
    [[ -f "$live_limine" ]] && limine_src="$live_limine"
    install -Dm0644 "$live_bg"    /mnt/etc/nixos/abora/bootloader/background.png
    install -Dm0644 "$limine_src" /mnt/etc/nixos/abora/bootloader/limine-background.png
    install -Dm0644 "$live_theme" /mnt/etc/nixos/abora/bootloader/theme.txt

    find /etc/abora/wallpapers -maxdepth 1 -type f \
        -exec cp {} /mnt/etc/nixos/abora/wallpapers/ \; 2>/dev/null || true
    find /etc/abora/themes -maxdepth 1 -type f \
        -exec cp {} /mnt/etc/nixos/abora/themes/ \; 2>/dev/null || true

    : > /mnt/etc/nixos/abora/apps.list
    cat > /mnt/etc/nixos/abora/apps.nix <<'NIXEOF'
{ pkgs, ... }: { environment.systemPackages = with pkgs; []; }
NIXEOF
    write_starter_apps_list  /mnt/etc/nixos/abora/apps.list
    render_apps_module_file  /mnt/etc/nixos/abora/apps.nix /mnt/etc/nixos/abora/apps.list
    [[ -s /mnt/etc/nixos/abora/apps.nix ]] || { printf 'App module empty\n' >&2; return 1; }
}

write_starter_apps_list() {
    local target_file="$1"
    : > "$target_file"
    if [[ "${starter_apps_bundle,,}" == "none" ]]; then
        return 0
    elif [[ "${starter_apps_bundle,,}" == "custom" ]]; then
        local id
        for id in "${_CUSTOM_APPS[@]+"${_CUSTOM_APPS[@]}"}"; do
            abora_app_catalog 2>/dev/null \
                | awk -F'|' -v id="$id" '$1==id{print $3}' >> "$target_file" || true
        done
    else
        abora_list_bundle_apps "${starter_apps_bundle}" > "$target_file" 2>/dev/null || true
    fi
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
    [[ -f /etc/abora/anix.sh          ]] && cp /etc/abora/anix.sh          /mnt/etc/nixos/abora/anix.sh         || true
    [[ -f /etc/abora/anix-module.nix  ]] && cp /etc/abora/anix-module.nix  /mnt/etc/nixos/abora/anix-module.nix || true
    [[ -f /etc/abora/abora-options.nix ]] && cp /etc/abora/abora-options.nix /mnt/etc/nixos/abora/abora-options.nix || true
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

    [[ -n "$user_password_hash" ]] || { printf 'Password hash empty\n' >&2;           return 1; }
    [[ -n "$desktop_block"      ]] || { printf 'Desktop block empty: %s\n' "$desktop_profile" >&2; return 1; }

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
    isNormalUser   = true;
    description    = "${username_value}";
    createHome     = true;
    shell          = pkgs.bash;
    extraGroups    = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "${user_password_hash}";
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
    export TERM="${TERM:-xterm-256color}"

    # Restore terminal on any exit
    trap 'tput cnorm 2>/dev/null || true; stty echo 2>/dev/null || true' EXIT

    stty -echo 2>/dev/null || true
    tput civis 2>/dev/null || true

    # Wait briefly for terminal to report correct size
    local cols rows attempts=0
    while true; do
        cols=$(tput cols  2>/dev/null || printf '80')
        rows=$(tput lines 2>/dev/null || printf '24')
        [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
        [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
        [[ $cols -ge 80 && $rows -ge 24 ]] && break
        (( attempts++ )) || true
        if [[ $attempts -ge 5 ]]; then
            tput cnorm 2>/dev/null || true; stty echo 2>/dev/null || true
            printf 'Terminal too small (%dx%d). Need at least 80x24.\n' "$cols" "$rows"
            exit 1
        fi
        sleep 1
    done

    sync_starter_apps_label
    refresh_github_identity || true
    auto_detect_timezone    || true
    auto_detect_keyboard    || true

    command -v mkpasswd >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1 || {
        tput cnorm 2>/dev/null; stty echo 2>/dev/null
        printf 'No password hashing tool found (mkpasswd or openssl required).\n' >&2
        exit 1
    }

    local steps=("welcome" "network" "desktop" "names" "password" "apps" "options" "disk" "confirm")
    local idx=0

    while true; do
        local step="${steps[$idx]}"
        _STEP_IDX=$idx
        STEP_RESULT=""

        case "$step" in
            welcome)  step_welcome  ;;
            network)  step_network  ;;
            desktop)  step_desktop  ;;
            names)    step_names    ;;
            password) step_password ;;
            apps)     step_apps     ;;
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
                ;;
        esac
    done
}

main "$@"
