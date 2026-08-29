#!/usr/bin/env bash
# Abora OS Installer - Abora OS v4 Everest
# Compact Omarchy-inspired TUI: large wordmark, boxed choices, simple prompts.

set -uo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export TERM="${TERM:-linux}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_log="/tmp/abora-config.log"
install_log="/tmp/abora-install.log"

# ── State ──────────────────────────────────────────────────────────────────────
disk=""
efi_part=""
root_part=""
install_disk_mode="erase"
target_partition=""
target_esp=""
hostname_value="abora"
username_value="abora"
timezone_value="UTC"
keyboard_value="us"
xkb_layout_value="us"
locale_value="en_US.UTF-8"
language_label="English (United States)"
desktop_profile="cosmic"
desktop_label="COSMIC"
desktop_variant_id="cosmic"
wallpaper_name="titlis-alps.jpg"
gpu_value="auto"
starter_apps_bundle="favorites"
starter_apps_label="Fan Favorites"
install_apps_during_setup="${ABORA_INSTALL_APPS_DURING_SETUP:-no}"
gaming_enabled="${ABORA_GAMING_ENABLED:-no}"
gaming_steam="${ABORA_GAMING_STEAM:-yes}"
gaming_big_picture="${ABORA_GAMING_BIG_PICTURE:-yes}"
gaming_autostart="${ABORA_GAMING_AUTOSTART:-no}"
gaming_gamescope="${ABORA_GAMING_GAMESCOPE:-yes}"
gaming_vulkan="${ABORA_GAMING_VULKAN:-yes}"
gaming_controller="${ABORA_GAMING_CONTROLLER:-yes}"
gaming_mangohud="${ABORA_GAMING_MANGOHUD:-yes}"
gaming_gamemode="${ABORA_GAMING_GAMEMODE:-yes}"
gaming_launchers="${ABORA_GAMING_LAUNCHERS:-yes}"
anix_enabled="yes"
github_identity="Skipped"
user_password_hash=""
root_password_hash=""
root_password_mode="same"
version="${ABORA_VERSION:-}"
release_name="${ABORA_RELEASE_NAME:-Abora OS v4 Everest}"
release_short="${ABORA_RELEASE_SHORT:-v4 Everest}"
reconfig_mode="${ABORA_RECONFIG:-0}"
batch_mode=0
batch_params_file=""
abora_edition="${ABORA_EDITION:-cosmic}"
abora_default_desktop="${ABORA_DEFAULT_DESKTOP:-cosmic}"
abora_release_stage="${ABORA_RELEASE_STAGE:-alpha}"
case "$abora_release_stage" in
    stable|final|release)
        abora_release_channel="${ABORA_RELEASE_CHANNEL:-stable}"
        ;;
    *)
        abora_release_channel="${ABORA_RELEASE_CHANNEL:-unstable}"
        ;;
esac
dotfiles_url=""

case "${ABORA_REPO_REF:-} ${ABORA_PRE_ALPHA_REF:-} ${version:-}" in
    *ALPHA*|*alpha*|*pre-alpha*|*prealpha*|*edge*)
        abora_release_channel="${ABORA_RELEASE_CHANNEL:-unstable}"
        ;;
esac

# Parse args: support both --reconfig and --batch <params-file>
_args=("$@")
_i=0
while (( _i < ${#_args[@]} )); do
    case "${_args[$_i]}" in
        --reconfig|-r) reconfig_mode=1 ;;
        --batch)
            batch_mode=1
            _i=$(( _i + 1 ))
            batch_params_file="${_args[$_i]:-}"
            ;;
    esac
    _i=$(( _i + 1 ))
done
unset _args _i

# ── Library loading ────────────────────────────────────────────────────────────
# Tries, in order: an explicit env-var override (for tests), the repo layout
# (running from a checkout), then the installed live-ISO layout under
# /etc/abora — so this same script works unmodified whether it's being run
# from a git clone or from the actual live image.
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
CF=$'\033[38;5;17m'    # Dark navy    — frames / borders
CI=$'\033[38;5;75m'    # Sky blue     — prompts / info
CS=$'\033[1;97m'       # Snow white   — headings
CG=$'\033[38;5;67m'    # Blue gray    — dim / pending steps
CP=$'\033[38;5;45m'    # Cyan blue    — done / success
CW=$'\033[38;5;33m'    # Abora blue   — primary accent (choices, highlights)
CB=$'\033[38;5;33m'    # Abora blue   — logo / branding
CE=$'\033[38;5;196m'   # Red          — errors
CY=$'\033[38;5;39m'    # Bright blue  — warnings / notices
CC=$'\033[38;5;253m'   # Cloud white  — body text

# ── Gum integration ───────────────────────────────────────────────────────────
# gum (charmbracelet/gum) renders the actual list-picker/text-input widgets
# used below; every prompt function falls back to a plain read/case-based
# prompt when gum isn't on PATH, so the installer still runs on a minimal
# live image that doesn't ship it.
GUM_BIN=""
_init_gum() {
    GUM_BIN="$(command -v gum 2>/dev/null || true)"
    [[ -n "$GUM_BIN" ]] || return 0
    export GUM_CHOOSE_CURSOR="  ▸ "
    export GUM_CHOOSE_CURSOR_FOREGROUND="33"
    export GUM_CHOOSE_HEADER_FOREGROUND="39"
    export GUM_CHOOSE_HEADER_BOLD="true"
    export GUM_CHOOSE_ITEM_FOREGROUND="253"
    export GUM_CHOOSE_SELECTED_FOREGROUND="45"
    export GUM_CHOOSE_SELECTED_BOLD="true"
    export GUM_INPUT_PROMPT="  ▸ "
    export GUM_INPUT_PROMPT_FOREGROUND="33"
    export GUM_INPUT_CURSOR_FOREGROUND="45"
    export GUM_INPUT_HEADER_FOREGROUND="39"
    export GUM_INPUT_HEADER_BOLD="true"
}
_init_gum

# ── Abora TUI engine ───────────────────────────────────────────────────────────

_TABS=("Language" "Network" "Identity" "Desktop" "Apps" "Options" "GPU" "Dotfiles" "Disk" "Preflight" "Confirm")

terminal_cols() {
    tput cols 2>/dev/null || stty size 2>/dev/null | awk '{print $2}' || printf '80'
}

terminal_rows() {
    tput lines 2>/dev/null || stty size 2>/dev/null | awk '{print $1}' || printf '24'
}

tui_size_warning() {
    local cols rows
    cols="$(terminal_cols)"
    rows="$(terminal_rows)"
    [[ -n "$cols" && "$cols" =~ ^[0-9]+$ ]] || cols=80
    [[ -n "$rows" && "$rows" =~ ^[0-9]+$ ]] || rows=24
    if (( cols < 80 || rows < 24 )); then
        warn "Terminal is ${cols}x${rows}; Abora's installer is easier to use at 80x24 or larger."
        msg "If menus look broken, resize the window or choose Debug installer -> Open terminal."
        pause
    fi
}

draw_logo() {
    printf '  %bABORA OS%b  %b▸%b  %b%s%b\n' \
        "${B}${CW}" "$R" "${D}${CG}" "$R" "${D}${CG}" "$release_short" "$R"
}

rule() {
    printf '  %b────────────────────────────────────────────────────────%b\n' "$CF" "$R"
}

tab_header() {
    local step="$1"
    local step_name="${_TABS[$((step - 1))]}"
    local total=${#_TABS[@]}

    printf '\033[2J\033[H'
    printf '\n'
    printf '  %b┌────────────────────────────────────────────────────────┐%b\n' "$CF" "$R"
    printf '  %b│%b  %bABORA OS%b  %b▸%b  %-40s%b│%b\n' \
        "$CF" "$R" "${B}${CW}" "$R" "${D}${CG}" "$release_short" "$R" "$CF" "$R"
    printf '  %b└────────────────────────────────────────────────────────┘%b\n' "$CF" "$R"
    printf '\n'
    printf '  %bStep %d of %d%b  %b·%b  %b%s%b\n' \
        "$CG" "$step" "$total" "$R" \
        "$CG" "$R" \
        "${B}${CW}" "$step_name" "$R"
    rule
    printf '\n'
    # 3-column step grid
    local i col
    for ((i = 0; i < total; i++)); do
        col=$(( i % 3 ))
        local label="${_TABS[$i]}"
        if (( i + 1 < step )); then
            printf '  %b✓%b  %b%-16s%b' "$CP" "$R" "${D}${CG}" "$label" "$R"
        elif (( i + 1 == step )); then
            printf '  %b›%b  %b%-16s%b' "${B}${CW}" "$R" "${B}${CS}" "$label" "$R"
        else
            printf '  %b·%b  %b%-16s%b' "$CG" "$R" "${D}${CG}" "$label" "$R"
        fi
        if [[ "$col" -eq 2 || "$i" -eq $((total - 1)) ]]; then
            printf '\n'
        fi
    done
    printf '\n'
}

# Menu — arrow-key selection via gum when available, numbered fallback.
# Each item: "Label|short description". Sets MENU_RESULT (0-indexed).
MENU_RESULT=0
menu() {
    local title="$1"; shift
    local -a items=("$@")
    local count=${#items[@]}
    local -a labels=() descs=() gum_items=()
    local i item label desc

    for item in "${items[@]}"; do
        label="${item%%|*}"
        desc="${item#*|}"
        [[ "$desc" == "$label" ]] && desc=""
        labels+=("$label")
        descs+=("$desc")
        if [[ -n "$desc" && ${#desc} -gt 44 ]]; then
            desc="${desc:0:43}…"
        fi
        if [[ -n "$desc" ]]; then
            gum_items+=("${label}  — ${desc}")
        else
            gum_items+=("$label")
        fi
    done

    if [[ -n "$GUM_BIN" ]]; then
        [[ -n "$title" ]] && printf '  %b%s%b\n\n' "${B}${CS}" "$title" "$R"
        local selected
        selected="$("$GUM_BIN" choose \
            --height "$(( count + 4 ))" \
            --cursor.foreground 33 \
            --header.foreground 39 \
            --item.foreground 253 \
            --selected.foreground 45 \
            --selected.bold \
            "${gum_items[@]}" 2>/dev/tty)" || {
                local old_gum="$GUM_BIN"
                GUM_BIN=""
                warn "Interactive picker failed; using numbered fallback menu."
                menu "$title" "${items[@]}"
                GUM_BIN="$old_gum"
                return 0
            }
        for (( i=0; i<count; i++ )); do
            if [[ "${gum_items[$i]}" == "$selected" ]]; then
                MENU_RESULT=$i; return 0
            fi
        done
        local old_gum="$GUM_BIN"
        GUM_BIN=""
        warn "Interactive picker returned an unknown choice; using numbered fallback menu."
        menu "$title" "${items[@]}"
        GUM_BIN="$old_gum"
        return 0
    fi

    # Fallback: numbered list
    [[ -n "$title" ]] && printf '  %b%s%b\n' "${B}${CS}" "$title" "$R"
    printf '  %bType a number and press Enter%b\n\n' "${D}${CG}" "$R"
    for (( i=0; i<count; i++ )); do
        local d="${descs[$i]}"
        [[ ${#d} -gt 40 ]] && d="${d:0:39}…"
        printf '  %b%2d%b  %b%-26s%b  %b%s%b\n' \
            "$CW" "$((i+1))" "$R" "${labels[$i]}" "$R" "${D}${CG}" "$d" "$R"
    done
    printf '\n'
    while true; do
        printf '  %b›%b ' "$CW" "$R"
        local choice
        read -r choice </dev/tty || choice=""
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            MENU_RESULT=$(( choice - 1 ))
            return 0
        fi
        printf '  %bEnter a number from 1 to %d%b\n' "$CY" "$count" "$R"
    done
}

# prompt_field — uses gum input when available; stdout is the captured value
prompt_field() {
    local prompt="$1" default="$2"
    if [[ -n "$GUM_BIN" ]]; then
        local val
        val="$("$GUM_BIN" input \
            --placeholder "$default" \
            --prompt "  ${prompt}  › " \
            --width 52 \
            --prompt.foreground 33 \
            --cursor.foreground 45 \
            2>/dev/tty)" || val=""
        printf '%s\n' "${val:-$default}"
        return
    fi
    printf '  %b%-16s%b %b│%b %s %b›%b ' "$CI" "$prompt" "$R" "$CG" "$R" "$default" "$CW" "$R" >&2
    local val
    read -r val </dev/tty || val=""
    printf '%s\n' "${val:-$default}"
}

prompt_password() {
    local prompt="$1"
    if [[ -n "$GUM_BIN" ]]; then
        local val
        val="$("$GUM_BIN" input \
            --password \
            --prompt "  ${prompt}  › " \
            --width 52 \
            --prompt.foreground 33 \
            --cursor.foreground 45 \
            2>/dev/tty)" || val=""
        printf '%s\n' "$val"
        return
    fi
    printf '  %b%-16s%b %b│%b %b›%b ' "$CI" "$prompt" "$R" "$CG" "$R" "$CW" "$R" >&2
    local val
    read -rs val </dev/tty || val=""
    printf '\n' >&2
    printf '%s\n' "$val"
}

ok()   { printf '  %b✓%b  %s\n' "$CP" "$R" "$1"; }
warn() { printf '  %b⚠%b  %s\n' "$CY" "$R" "$1"; }
err()  { printf '  %b✗%b  %s\n' "$CE" "$R" "$1"; }
msg()  { printf '  %b·%b  %s\n' "$CI" "$R" "$1"; }

choice_panel() {
    printf '\n'
    printf '  %bCurrent settings%b\n' "${B}${CS}" "$R"
    printf '  %b  ──────────────────────────────────%b\n' "$CF" "$R"
    printf '  %b  Language%b  %s (%s)\n' "$CG" "$R" "$language_label" "$locale_value"
    printf '  %b  Keyboard%b  %s / %s\n' "$CG" "$R" "$keyboard_value" "$xkb_layout_value"
    printf '  %b  Timezone%b  %s\n' "$CG" "$R" "$timezone_value"
    printf '  %b  Desktop %b  %s\n' "$CG" "$R" "$desktop_label"
    printf '  %b  ──────────────────────────────────%b\n' "$CF" "$R"
    printf '\n'
}

pause() {
    printf '\n  %bPress Enter to continue …%b' "${D}${CG}" "$R"
    read -rs _ </dev/tty || true
    printf '\n'
}

die() {
    err "$*"
    printf 'INSTALL ERROR: %s\n' "$*" >>"$install_log" 2>/dev/null || true
    # In batch mode, exit so automation can read the error from stdout/logs.
    if [[ "${batch_mode:-0}" -eq 1 ]]; then
        printf 'FATAL: %s\n' "$*" >&2
        cleanup_target 2>/dev/null || true
        exit 1
    fi
    printf '\n  %bLog: %s%b\n\n' "${D}${CG}" "$install_log" "$R"
    # Unmount before handing off to a shell so nothing is left mounted.
    cleanup_target 2>/dev/null || true
    failed_install_menu "$*"
}

failed_install_menu() {
    local reason="${1:-Install failed.}"
    while true; do
        if declare -F release_header >/dev/null 2>&1; then
            release_header "Install Failed"
        else
            printf '\033[2J\033[H\n'
            printf '  %bInstall Failed%b\n\n' "${B}${CE}" "$R"
        fi
        err "$reason"
        printf '  %bLog: %s%b\n\n' "${D}${CG}" "$install_log" "$R"
        if declare -F draw_log_tail >/dev/null 2>&1 && [[ -f "$install_log" ]]; then
            draw_log_tail "$install_log" 12
            printf '\n'
        fi
        printf '  %bHelpful commands%b  %babora logs%b  %b·%b  %babora network%b  %b·%b  %babora support-report%b\n\n' \
            "${B}${CS}" "$R" "${B}${CW}" "$R" "$CI" "$R" "${B}${CW}" "$R" "$CI" "$R" "${B}${CW}" "$R"

        menu "What now?" \
            "Try installer again|Return to the first screen" \
            "Network tools|Fix Wi-Fi, DNS, or cache reachability" \
            "Debug tools|View logs, hardware test, support report" \
            "Open terminal|Drop to the live shell" \
            "Power off|Shut down this machine"

        case "$MENU_RESULT" in
            0)
                if command -v abora-install >/dev/null 2>&1; then
                    exec abora-install
                fi
                exec "$0"
                ;;
            1)
                if declare -F network_tools_menu >/dev/null 2>&1; then
                    network_tools_menu yes
                else
                    warn "Network tools are not loaded yet."
                    pause
                fi
                ;;
            2)
                if declare -F debug_tools_menu >/dev/null 2>&1; then
                    debug_tools_menu
                else
                    warn "Debug tools are not loaded yet."
                    pause
                fi
                ;;
            3)
                printf '\n  %bRun %babora-install%b to retry the installer.%b\n\n' "$CC" "${B}${CW}" "$R" "$R"
                exec bash --login </dev/tty >/dev/tty 2>/dev/tty || exit 0
                ;;
            4)
                poweroff || exit 0
                ;;
        esac
    done
}

# ── Utility ───────────────────────────────────────────────────────────────────

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || { err "Run the installer as root."; exit 1; }
}

safe_identifier() { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]; }
safe_hostname()   { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]]; }
safe_keymap()     { [[ "$1" =~ ^[A-Za-z0-9_+.-]+$ ]]; }
safe_locale()     { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_.@-]*$ && "$1" == *.* ]]; }
safe_timezone()   { [[ "$1" =~ ^[A-Za-z0-9_+./-]+$ && "$1" != *..* && "$1" != /* ]]; }

# Accepts a handful of common short/legacy timezone names (typed by a user,
# or produced by some batch-mode callers) and maps them to real IANA zone
# names before timezone_exists()/nixos-generate-config ever see them.
normalize_timezone() {
    local tz="$1"
    tz="${tz//$'\r'/}"
    tz="${tz#"${tz%%[![:space:]]*}"}"
    tz="${tz%"${tz##*[![:space:]]}"}"

    case "${tz^^}" in
        UTC|GMT|Z)
            printf 'UTC\n'
            ;;
        EST|EDT|EASTERN|US/EASTERN)
            printf 'America/New_York\n'
            ;;
        CST|CDT|CENTRAL|US/CENTRAL)
            printf 'America/Chicago\n'
            ;;
        MST|MDT|MOUNTAIN|US/MOUNTAIN)
            printf 'America/Denver\n'
            ;;
        PST|PDT|PACIFIC|US/PACIFIC)
            printf 'America/Los_Angeles\n'
            ;;
        *)
            printf '%s\n' "$tz"
            ;;
    esac
}

# Checks a timezone name three ways so this works on both the live ISO
# (zoneinfo files present but timedatectl may be unavailable) and other
# environments (a chroot with only timedatectl reachable): a zoneinfo file
# on disk, or a match against `timedatectl list-timezones`.
timezone_exists() {
    local tz="$1" base
    tz="$(normalize_timezone "$tz")"
    [[ "$tz" == "UTC" ]] && return 0
    safe_timezone "$tz" || return 1
    for base in "${ABORA_ZONEINFO_PATH:-}" /usr/share/zoneinfo /run/current-system/sw/share/zoneinfo; do
        [[ -n "$base" && -f "${base}/${tz}" ]] && return 0
    done
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl list-timezones 2>/dev/null | grep -Fxq "$tz" && return 0
    fi
    return 1
}

# SHA-512 crypt hash (openssl passwd -6) — the format NixOS's
# users.users.<name>.hashedPassword expects, so the plaintext password
# never gets written into the generated config.
hash_password() {
    local password="$1"
    command -v openssl >/dev/null 2>&1 || return 1
    openssl passwd -6 -stdin <<<"$password"
}

# Escapes a value for safe interpolation into a Nix double-quoted string
# literal: backslash and '"' are the two characters that would otherwise let
# the value break out of the string, and '$' must be escaped so Nix doesn't
# treat "${...}" as antiquotation. Newlines are stripped rather than escaped
# since none of this installer's string fields (hostname, username, etc.)
# are legitimately multi-line.
nix_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\$/\\\$}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/}"
    printf '%s' "$value"
}

nix_bool() {
    case "$1" in
        yes|true|1) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

set_nix_bool_assignment() {
    local file="$1" key="$2" value="$3" nix_value tmp
    nix_value="$(nix_bool "$value")"
    if grep -Eq "^[[:space:]]*${key//./\\.}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key//./\\.}[[:space:]]*=.*|  ${key} = ${nix_value};|" "$file"
        return 0
    fi
    tmp="$(mktemp)"
    awk -v line="  ${key} = ${nix_value};" '
        /^[[:space:]]*}[[:space:]]*$/ && !done { print line; done=1 }
        { print }
        END { if (!done) print line }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
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

apply_language_defaults() {
    local can_set_tz=0
    [[ -z "$timezone_value" || "$timezone_value" == "UTC" ]] && can_set_tz=1
    _maybe_timezone() {
        (( can_set_tz )) && timezone_value="$1"
    }

    case "$locale_value" in
        en_US.UTF-8) language_label="English (United States)"; keyboard_value="us"; xkb_layout_value="us"; _maybe_timezone "UTC" ;;
        en_GB.UTF-8) language_label="English (United Kingdom)"; keyboard_value="uk"; xkb_layout_value="gb"; _maybe_timezone "Europe/London" ;;
        es_ES.UTF-8) language_label="Spanish"; keyboard_value="es"; xkb_layout_value="es"; _maybe_timezone "Europe/Madrid" ;;
        fr_FR.UTF-8) language_label="French"; keyboard_value="fr"; xkb_layout_value="fr"; _maybe_timezone "Europe/Paris" ;;
        de_DE.UTF-8) language_label="Deutsch"; keyboard_value="de"; xkb_layout_value="de"; _maybe_timezone "Europe/Berlin" ;;
        it_IT.UTF-8) language_label="Italiano"; keyboard_value="it"; xkb_layout_value="it"; _maybe_timezone "Europe/Rome" ;;
        pt_BR.UTF-8) language_label="Portuguese Brazil"; keyboard_value="br-abnt2"; xkb_layout_value="br"; _maybe_timezone "America/Sao_Paulo" ;;
        pt_PT.UTF-8) language_label="Portuguese Portugal"; keyboard_value="pt-latin1"; xkb_layout_value="pt"; _maybe_timezone "Europe/Lisbon" ;;
        nl_NL.UTF-8) language_label="Nederlands"; keyboard_value="us"; xkb_layout_value="us"; _maybe_timezone "Europe/Amsterdam" ;;
        pl_PL.UTF-8) language_label="Polski"; keyboard_value="pl"; xkb_layout_value="pl"; _maybe_timezone "Europe/Warsaw" ;;
        ru_RU.UTF-8) language_label="Russian"; keyboard_value="ru"; xkb_layout_value="ru"; _maybe_timezone "Europe/Moscow" ;;
        tr_TR.UTF-8) language_label="Turkish"; keyboard_value="trq"; xkb_layout_value="tr"; _maybe_timezone "Europe/Istanbul" ;;
        ja_JP.UTF-8) language_label="Japanese"; keyboard_value="jp106"; xkb_layout_value="jp"; _maybe_timezone "Asia/Tokyo" ;;
        ko_KR.UTF-8) language_label="Korean"; keyboard_value="kr"; xkb_layout_value="kr"; _maybe_timezone "Asia/Seoul" ;;
        zh_CN.UTF-8) language_label="Chinese Simplified"; keyboard_value="us"; xkb_layout_value="us"; _maybe_timezone "Asia/Shanghai" ;;
        *)
            language_label="$locale_value"
            sync_xkb_layout
            ;;
    esac
}

valid_gpus=(nouveau nvidia nvidia-open amdgpu intel none)

# Detect the primary GPU vendor via lspci and resolve it to a concrete
# abora.gpu value. Never resolves to the proprietary "nvidia" driver on its
# own — NVIDIA hardware resolves to "nouveau" (open-source, no license to
# accept) unless the user explicitly picks "nvidia" or "nvidia-open" in
# step_gpu.
detect_gpu() {
    local gpu_line=""
    if command -v lspci >/dev/null 2>&1; then
        gpu_line="$(lspci 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' | head -n1)"
    fi

    case "$gpu_line" in
        *NVIDIA*|*nvidia*) printf 'nouveau\n' ;;
        *AMD*|*ATI*|*amd*) printf 'amdgpu\n' ;;
        *Intel*|*intel*)   printf 'intel\n' ;;
        *)                 printf 'none\n' ;;
    esac
}

# Render the raw NixOS config lines for the selected GPU driver. Kept in
# sync with nix/modules/abora-options.nix's abora.gpu handling — this is
# only needed here because the installer writes abora-local.nix as plain
# NixOS options rather than through the abora.* options module.
gpu_config_block() {
    local gpu="$1"
    case "$gpu" in
        nouveau)
            cat <<'EOF'
  services.xserver.videoDrivers = lib.mkDefault [ "nouveau" ];
EOF
            ;;
        nvidia|nvidia-open)
            local open_flag="false"
            [[ "$gpu" == "nvidia-open" ]] && open_flag="true"
            cat <<EOF
  services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = ${open_flag};
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
EOF
            ;;
        amdgpu)
            cat <<'EOF'
  services.xserver.videoDrivers = lib.mkDefault [ "amdgpu" ];
EOF
            ;;
        intel)
            cat <<'EOF'
  services.xserver.videoDrivers = lib.mkDefault [ "modesetting" ];
EOF
            ;;
        *)
            : # none / unrecognised — leave NixOS's own defaults in place.
            ;;
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
    gpu_value="$(detect_gpu)"
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

# ABORA_ALLOW_OFFLINE_INSTALL=1 is the documented escape hatch for offline
# installs — it forces this check to pass so an unreachable binary cache
# never blocks an install that can be satisfied entirely from packages
# already present on the ISO (see check_install_environment's use of this).
cache_reachable() {
    [[ "${ABORA_ALLOW_OFFLINE_INSTALL:-0}" == "1" ]] && return 0
    if command -v curl >/dev/null 2>&1; then
        curl -fsI --connect-timeout 5 --max-time 8 https://cache.nixos.org >/dev/null 2>&1
        return $?
    fi
    net_connected
}

start_nm() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl daemon-reload         >/dev/null 2>&1 || true
    systemctl unmask NetworkManager >/dev/null 2>&1 || true
    systemctl enable --now NetworkManager >/dev/null 2>&1 \
        || systemctl start NetworkManager >/dev/null 2>&1 \
        || return 1
}

network_status() {
    printf '  %bNetwork status%b\n' "${B}${CS}" "$R"
    if command -v nmcli >/dev/null 2>&1; then
        printf '\n  %bConnectivity%b\n' "$CI" "$R"
        nmcli networking connectivity check 2>/dev/null | sed 's/^/    /' || true
        printf '\n  %bDevices%b\n' "$CI" "$R"
        nmcli device status 2>/dev/null | sed 's/^/    /' || true
        printf '\n  %bWi-Fi radios%b\n' "$CI" "$R"
        nmcli radio 2>/dev/null | sed 's/^/    /' || true
        return 0
    fi
    warn "nmcli is not available on this live image."
}

log_network_snapshot() {
    {
        printf '[installer] network snapshot start\n'
        if command -v nmcli >/dev/null 2>&1; then
            printf '[installer] nmcli connectivity: '
            nmcli networking connectivity check 2>/dev/null || true
            printf '[installer] nmcli device status:\n'
            nmcli device status 2>/dev/null || true
            printf '[installer] nmcli radio:\n'
            nmcli radio 2>/dev/null || true
            printf '[installer] visible Wi-Fi networks:\n'
            nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || true
        else
            printf '[installer] nmcli unavailable\n'
        fi
        if command -v resolvectl >/dev/null 2>&1; then
            printf '[installer] resolvectl dns:\n'
            resolvectl dns 2>/dev/null || true
        fi
        if curl -fsI --connect-timeout 5 --max-time 8 https://cache.nixos.org >/dev/null 2>&1; then
            printf '[installer] cache.nixos.org reachable: yes\n'
        else
            printf '[installer] cache.nixos.org reachable: no\n'
        fi
        printf '[installer] network snapshot end\n'
    } >>"$install_log" 2>&1 || true
}

open_nmtui_or_explain() {
    start_nm >/dev/null 2>&1 || true
    if command -v nmtui >/dev/null 2>&1; then
        nmtui || true
        start_nm >/dev/null 2>&1 || true
        return 0
    fi

    warn "nmtui is not available."
    if command -v nmcli >/dev/null 2>&1; then
        msg "Use Quick Wi-Fi connect instead; it uses nmcli directly."
    else
        msg "Open a terminal and check whether NetworkManager is installed/running."
    fi
    pause
}

quick_wifi_connect() {
    local _ssid="" _sec="" _pw=""
    start_nm >/dev/null 2>&1 || true
    if ! command -v nmcli >/dev/null 2>&1; then
        warn "nmcli is not available; cannot scan Wi-Fi from the installer."
        pause
        return 1
    fi

    nmcli networking on >/dev/null 2>&1 || true
    nmcli radio wifi on >/dev/null 2>&1 || true
    nmcli device wifi rescan >/dev/null 2>&1 || true
    printf '\n'
    nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || warn "No Wi-Fi networks reported by NetworkManager."
    printf '\n'
    printf '  %bSSID:%b ' "$CI" "$R"
    read -r _ssid </dev/tty || _ssid=""
    if [[ -z "${_ssid:-}" ]]; then
        warn "No SSID entered."
        pause
        return 1
    fi

    _sec="$(nmcli -t -f SSID,SECURITY device wifi list 2>/dev/null \
        | awk -F: -v s="$_ssid" '$1==s{print $2;exit}')"
    if [[ -n "${_sec:-}" && "$_sec" != "--" ]]; then
        printf '  %bPassword:%b ' "$CI" "$R"
        read -rs _pw </dev/tty || _pw=""
        printf '\n'
        nmcli device wifi connect "$_ssid" password "$_pw" || true
    else
        nmcli device wifi connect "$_ssid" || true
    fi

    if net_connected; then
        ok "Connected."
    else
        warn "Still not connected. Check the SSID/password or try nmtui."
    fi
    pause
}

network_tools_menu() {
    local allow_offline="${1:-yes}"
    while true; do
        release_header "Network Tools"
        start_nm >/dev/null 2>&1 || true
        if net_connected; then
            ok "Network is connected."
        else
            warn "No internet connection detected."
        fi
        printf '\n'
        network_status
        printf '\n'

        if [[ "$allow_offline" == "yes" ]]; then
            menu "Network setup" \
                "Open nmtui|Full NetworkManager TUI if available" \
                "Quick Wi-Fi connect|Scan and connect with nmcli" \
                "Turn Wi-Fi on and rescan|Wake up NetworkManager Wi-Fi" \
                "Re-check connection|Test connectivity again" \
                "Continue offline|Use only packages already on the ISO" \
                "Back|Return to installer"
        else
            menu "Network setup" \
                "Open nmtui|Full NetworkManager TUI if available" \
                "Quick Wi-Fi connect|Scan and connect with nmcli" \
                "Turn Wi-Fi on and rescan|Wake up NetworkManager Wi-Fi" \
                "Re-check connection|Test connectivity again" \
                "Back|Return to installer"
        fi

        case "$MENU_RESULT" in
            0) open_nmtui_or_explain ;;
            1) quick_wifi_connect ;;
            2)
                if command -v nmcli >/dev/null 2>&1; then
                    nmcli networking on >/dev/null 2>&1 || true
                    nmcli radio wifi on >/dev/null 2>&1 || true
                    nmcli device wifi rescan >/dev/null 2>&1 || true
                    ok "Requested Wi-Fi radio on and rescan."
                else
                    warn "nmcli is not available."
                fi
                pause
                ;;
            3)
                if net_connected; then ok "Connected."; else warn "Still no connection."; fi
                pause
                ;;
            4)
                if [[ "$allow_offline" == "yes" ]]; then
                    ABORA_ALLOW_OFFLINE_INSTALL=1
                    export ABORA_ALLOW_OFFLINE_INSTALL
                    warn "Offline install allowed. It will only work if needed Nix paths are already on the ISO."
                    pause
                    return 0
                fi
                return 0
                ;;
            5) return 0 ;;
        esac
    done
}

# Whole-disk device names (no /dev/ prefix, one per line) currently backing
# any live mount or loop device -- i.e. candidates for "the disk Abora
# actually booted from". The live squashfs is loop-mounted from a file on
# that disk (see boot.initrd.kernelModules in nix/profiles/live.nix: loop,
# overlay, squashfs, isofs), so a name-prefix check alone (fd/loop/ram/sr/
# zram) never catches a USB installer stick: it enumerates as an ordinary
# disk like any internal drive. This checks every currently mounted
# filesystem's source device *and* every active loop device's backing file,
# resolving each back to its parent whole-disk via `lsblk -no pkname`,
# rather than guessing one specific mount point -- NixOS's exact squashfs
# mount path isn't something worth hardcoding and getting subtly wrong.
boot_media_disks() {
    { findmnt -rno SOURCE 2>/dev/null; losetup -n -O BACK-FILE 2>/dev/null; } \
        | while IFS= read -r src; do
            [[ -n "$src" && "$src" == /dev/* ]] || continue
            local real pk
            real="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"
            pk="$(lsblk -dno PKNAME "$real" 2>/dev/null | head -n1)"
            if [[ -n "$pk" ]]; then
                printf '%s\n' "$pk"
            else
                lsblk -dno NAME "$real" 2>/dev/null | head -n1
            fi
        done | sort -u
}

collect_disks() {
    local -A boot_names=()
    local name
    while IFS= read -r name; do
        [[ -n "$name" ]] && boot_names["$name"]=1
    done < <(boot_media_disks)

    # Deliberately not `${!boot_names[*]:-}`: bash parses `:-` stacked onto
    # the array-keys form as indirect expansion of the first key's value,
    # not "default when the array has no keys" -- it silently produces an
    # empty string even when boot_names is populated. Guard emptiness with
    # a plain conditional instead.
    local boot_list=""
    [[ ${#boot_names[@]} -gt 0 ]] && boot_list="${!boot_names[*]}"

    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk -v boot_list="$boot_list" '
        BEGIN {
            n = split(boot_list, arr, " ")
            for (i = 1; i <= n; i++) boot[arr[i]] = 1
        }
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) next
            if ($1 in boot) next
            model = ""
            for (i = 3; i < NF; i++) model = model (model ? " " : "") $i
            if (model == "") model = "Unknown model"
            print "/dev/" $1 "|" $2 "  " model
        }'
}

# GPT partition-type GUID for an EFI System Partition — the one PARTTYPE
# value that means "this is an ESP" regardless of filesystem label,
# mountpoint, or which OS created it.
readonly ESP_PARTTYPE_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

# Shared parsing core: reads `lsblk -P` (KEY="value" pairs, one line per
# device) on stdin and calls the awk function named by -v fn on a
# per-line associative array `f` of every requested column. -P instead of
# plain columnar `-o` output deliberately — lsblk's normal column mode is
# space-padded/aligned, not a fixed delimiter, so any value containing a
# space (a Windows "System Reserved" LABEL is the single most common real
# example, and exactly the kind of partition this dual-boot-safe disk
# mode needs to describe correctly) silently shifts every field after it
# out of position. -P's KEY="value" pairs keep each value intact
# regardless of what's inside it, parsed here with a POSIX match() loop
# rather than gawk-only extensions, matching this file's existing
# portable-awk style.
_lsblk_pairs_awk_prelude='
    function parse_pairs(line,    rest, m, pair, eq) {
        delete f
        rest = line
        while (match(rest, /[A-Za-z]+="[^"]*"/)) {
            pair = substr(rest, RSTART, RLENGTH)
            eq = index(pair, "=")
            f[substr(pair, 1, eq - 1)] = substr(pair, eq + 2, length(pair) - eq - 2)
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
'

# Partition names (no /dev/ prefix, system-wide, not scoped to one disk)
# that are somebody else's parent device right now — a LUKS/LVM/RAID
# member shows no mountpoint of its own even while very much in active
# use, only its mapped child does (e.g. a LUKS partition's decrypted
# "root" mapper). Checked system-wide via PKNAME rather than only under
# the target disk's own lsblk tree because the mapper device itself
# doesn't nest under the disk in flat (-l) output.
_partitions_with_children() {
    lsblk -Pnb -o NAME,PKNAME 2>/dev/null | awk "$_lsblk_pairs_awk_prelude"'
        { parse_pairs($0); if (f["PKNAME"] != "") print f["PKNAME"] }
    ' | sort -u
}

# Existing partitions on $1 (a whole disk, e.g. /dev/nvme0n1), one
# "path|description" row per line, for the "use an existing partition"
# install mode's picker — candidate *root* targets specifically, so this
# deliberately excludes ESP-typed partitions too, not just busy ones:
# step_disk_existing_partition() separately finds and reuses an existing
# ESP via find_existing_esp() and mounts it unformatted, so offering that
# same partition here as a root candidate would let an operator select
# it, reformat it as ext4 in partition_disk_existing(), and destroy the
# very ESP the install is relying on reusing intact. TYPE=="part" only
# (not "disk" or a LUKS "crypt" mapper child lsblk also lists) and
# deliberately excludes anything currently mounted *or* backing a
# mounted/active child device (LUKS, LVM, RAID) — reformatting a
# partition out from under the running system, directly or through a
# mapper, is exactly the kind of mistake this list exists to prevent,
# not just fail to prevent.
list_disk_partitions() {
    local disk="$1"
    local busy_list; busy_list="$(_partitions_with_children | tr '\n' ' ')"

    lsblk -Pnb -o NAME,SIZE,FSTYPE,PARTTYPE,LABEL,TYPE,MOUNTPOINT "$disk" 2>/dev/null | \
        awk -v esp="$ESP_PARTTYPE_GUID" -v busy_list="$busy_list" "$_lsblk_pairs_awk_prelude"'
        BEGIN {
            n = split(busy_list, arr, " ")
            for (i = 1; i <= n; i++) busy[arr[i]] = 1
        }
        {
            parse_pairs($0)
            if (f["TYPE"] != "part") next
            if (f["MOUNTPOINT"] != "") next
            if (f["NAME"] in busy) next
            if (f["PARTTYPE"] == esp) next

            size_h = f["SIZE"] + 0
            fstype = (f["FSTYPE"] == "" ? "no filesystem" : f["FSTYPE"])
            unit = "B"
            if (size_h >= 1073741824) { size_h /= 1073741824; unit = "G" }
            else if (size_h >= 1048576) { size_h /= 1048576; unit = "M" }
            desc = sprintf("%.1f%s  %s", size_h, unit, fstype)
            if (f["LABEL"] != "") desc = desc "  (" f["LABEL"] ")"
            print "/dev/" f["NAME"] "|" desc
        }'
}

# First existing ESP-typed partition on $1, or empty if none — used by the
# "use an existing partition" install mode to reuse a pre-existing EFI
# System Partition (the normal, correct thing to do alongside an existing
# Windows or Linux install, which already has one) instead of creating a
# second one.
find_existing_esp() {
    local disk="$1"
    lsblk -Pnb -o NAME,PARTTYPE,TYPE "$disk" 2>/dev/null | \
        awk -v esp="$ESP_PARTTYPE_GUID" "$_lsblk_pairs_awk_prelude"'
        {
            parse_pairs($0)
            if (f["TYPE"] == "part" && f["PARTTYPE"] == esp) { print "/dev/" f["NAME"]; exit }
        }'
}

check_install_environment() {
    local mode="${1:-summary}"
    local failed=0 cmd path nixpkgs
    local commands_ok=0 assets_ok=0
    local check_selected_values=1
    local -a commands=(
        wipefs parted partprobe udevadm mkfs.vfat mkfs.ext4 mount blkid
        nixos-generate-config nixos-install openssl curl
    )
    local -a required_paths=(
        /etc/abora/VERSION
        /etc/abora/title.txt
        /etc/abora/abora.sh
        /etc/abora/ui.sh
        /etc/abora/config.sh
        /etc/abora/build.sh
        /etc/abora/adopt-nixos.sh
        /etc/abora/desktop.sh
        /etc/abora/gaming.sh
        /etc/abora/check-full.sh
        /etc/abora/doctor.sh
        /etc/abora/dotfiles-import.sh
        /etc/abora/recovery.sh
        /etc/abora/welcome.sh
        /etc/abora/app-catalog.sh
        /etc/abora/apps.sh
        /etc/abora/custom-packages.sh
        /etc/abora/support-report.sh
        /etc/abora/hardware-test.sh
        /etc/abora/repair-flake-purity.sh
        /etc/abora/default-wallpaper.png
        /etc/abora/fastfetch-logo.txt
        /etc/abora/fastfetch-config.jsonc
        /etc/abora/desktop-profiles.sh
        /etc/abora/desktops
        /etc/abora/wallpapers
        /etc/abora/themes
        /etc/abora/mango/config.conf
        /etc/abora/pkgs/mango.nix
        /etc/abora/pkgs/scenefx-0_5.nix
        /etc/abora/pkgs/modularity.nix
        /etc/abora/pkgs/moducpp-anix.nix
        /etc/abora/pkgs/abora-update-resolver.nix
        /etc/abora/pkgs/abora-plan-tool.nix
        /etc/abora/tools/moducpp-anix
        /etc/abora/installed-base.nix
        /etc/abora/abora-options.nix
        /etc/abora/anix.sh
        /etc/abora/anix-module.nix
        /etc/abora/tinypm/Cargo.toml
        /etc/abora/tinypm/src/main.rs
        /etc/abora/tinypm/src/bin/grab.rs
        /etc/abora/update-resolver/AboraUpdateResolver.csproj
        /etc/abora/update-resolver/Program.cs
        /etc/abora/plan-tool/AboraPlanTool.csproj
        /etc/abora/plan-tool/Program.cs
        /etc/abora/vendor/modularity
        /etc/abora/installer.sh
        /etc/abora/setup-launcher.sh
        /etc/abora/setup.desktop
        /etc/abora/session-setup.sh
        /etc/abora/theme-sync.sh
        /etc/abora/update.sh
        /etc/abora/bootloader/background.png
        /etc/abora/bootloader/theme.txt
        /etc/abora/plymouth/abora.plymouth
        /etc/abora/plymouth/abora.script
    )
    local -a optional_paths=(
        /etc/abora/docs/wiki/ANIX-V1.md
        /etc/abora/docs/wiki/ANIX-V2-Languages.md
        /etc/abora/docs/wiki/TinyPM.md
        /etc/abora/docs/wiki/Abora-Tools.md
        /etc/abora/docs/wiki/Abora-Gaming.md
        /etc/abora/docs/wiki/Recovery.md
        /etc/abora/docs/wiki/Updating-Abora.md
    )

    case "$mode" in
        live|tools|assets)
            check_selected_values=0
            ;;
    esac

    [[ -r /dev/tty ]] || { err "No readable /dev/tty; run from a real terminal."; failed=1; }

    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            commands_ok=$((commands_ok + 1))
            [[ "$mode" == "detail" ]] && ok "Found ${cmd}"
        else
            err "Missing command: ${cmd}"
            failed=1
        fi
    done

    nixpkgs="$(resolve_nixpkgs || true)"
    if [[ -n "$nixpkgs" ]]; then
        if [[ "$mode" == "detail" ]]; then
            ok "Nixpkgs source: ${nixpkgs}"
        else
            ok "Nixpkgs source ready"
        fi
    else
        err "Cannot resolve nixpkgs path."
        failed=1
    fi

    if cache_reachable; then
        [[ "$mode" == "detail" ]] && ok "Nix cache reachable"
    else
        # Not fatal: every supported desktop/app profile already ships in the
        # live ISO's local store, so a normal install never needs the cache.
        # Only an explicit fast-install path (pulling newer store paths from
        # cache.nixos.org instead of building/using what's local) would need
        # this, and no such path exists in this installer today. This used to
        # set failed=1 unconditionally, which made Preflight impossible to
        # pass on any offline machine regardless of what the user chose.
        warn "Nix cache unreachable — offline install will use only what's on the ISO."
    fi

    for path in "${required_paths[@]}"; do
        if [[ -e "$path" ]]; then
            assets_ok=$((assets_ok + 1))
            [[ "$mode" == "detail" ]] && ok "Asset present: ${path}"
        else
            err "Missing install asset: ${path}"
            failed=1
        fi
    done

    for path in "${optional_paths[@]}"; do
        if [[ -e "$path" ]]; then
            [[ "$mode" == "detail" ]] && ok "Optional asset present: ${path}"
        else
            warn "Optional asset missing: ${path}"
        fi
    done

    if (( check_selected_values == 1 )); then
        timezone_value="$(normalize_timezone "$timezone_value")"
        safe_locale "$locale_value" || { err "Invalid locale: ${locale_value}"; failed=1; }
        timezone_exists "$timezone_value" || { err "Invalid or unavailable timezone: ${timezone_value}"; failed=1; }
        safe_keymap "$keyboard_value" || { err "Invalid console keymap: ${keyboard_value}"; failed=1; }
        safe_keymap "$xkb_layout_value" || { err "Invalid XKB layout: ${xkb_layout_value}"; failed=1; }
        [[ -n "$user_password_hash" ]] || { err "User password hash is empty."; failed=1; }

        # These three are re-validated here (not just in the interactive step_*
        # prompts) so --batch installs get the exact same guarantees: a batch
        # params file can set hostname/username/disk to anything, and nothing
        # else on the batch path re-checks them before they're baked into
        # generated Nix config or handed to wipefs/parted.
        safe_hostname "$hostname_value" || { err "Invalid hostname: ${hostname_value}"; failed=1; }
        safe_identifier "$username_value" || { err "Invalid username: ${username_value}"; failed=1; }
        [[ -n "$disk" && -b "$disk" ]] || { err "Invalid or missing installation disk: '${disk}'"; failed=1; }
    elif [[ "$mode" != "detail" ]]; then
        ok "Selected install values will be checked after disk and user setup"
    fi

    if [[ "$mode" != "detail" ]]; then
        ok "Tools ready: ${commands_ok}/${#commands[@]}"
        ok "Installer assets ready: ${assets_ok}/${#required_paths[@]}"
        ok "Selected language and locale values look valid"
    fi

    return "$failed"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PAGES
# ═══════════════════════════════════════════════════════════════════════════════

page_welcome() {
    printf '\033[2J\033[H'
    printf '\n'
    # Logo printed via heredoc — safe for backticks, single quotes, and all special chars
    while IFS= read -r _logo_line; do
        printf '%b%s%b\n' "$CB" "$_logo_line" "$R"
    done <<'ABORA_LOGO'
          ,ggg,                                                _,gggggg,_         ,gg,
          dP""8I   ,dPYb,                                     ,d8P""d8P"Y8b,      i8""8i
         dP   88   IP'`Yb                                    ,d8'   Y8   "8b,dP   `8,,8'
        dP    88   I8  8I                                    d8'    `Ybaaad88P'    `88'
       ,8'    88   I8  8'                                    8P       `""""Y8      dP"8,
       d88888888   I8 dP       ,ggggg,   ,gggggg,    ,gggg,gg8b            d8     dP' `8a
 __   ,8"     88   I8dP   88ggdP"  "Y8gggdP""""8I   dP"  "Y8IY8,          ,8P    dP'   `Yb
dP"  ,8P      Y8   I8P    8I i8'    ,8I ,8'    8I  i8'    ,8I`Y8,        ,8P'_ ,dP'     I8
Yb,_,dP       `8b,,d8b,  ,8I,d8,   ,d8',dP     Y8,,d8,   ,d8b,`Y8b,,__,,d8P' "888,,____,dP
 "Y8P"         `Y88P'"Y88P"'P"Y8888P"  8P      `Y8P"Y8888P"`Y8  `"Y8888P"'   a8P"Y88888P"
ABORA_LOGO
    printf '\n'
    printf '  %bAbora OS Live%b  %b·  NixOS-based Linux  ·  v%s%b\n' \
        "${B}${CS}" "$R" "${D}${CG}" "$version" "$R"
    printf '\n'
    printf '  %b────────────────────────────────────────────────────────%b\n' "$CF" "$R"
    printf '\n'
    printf '  %bThis installer guides you through 9 steps to set up%b\n' "$CC" "$R"
    printf '  %bAbora OS. All data on the chosen disk will be erased.%b\n' "$CC" "$R"
    printf '\n'
    printf '  %b  ①%b  Language, keyboard, and timezone\n' "$CW" "$R"
    printf '  %b  ②%b  Network connectivity\n' "$CW" "$R"
    printf '  %b  ③%b  User account, hostname, password\n' "$CW" "$R"
    printf '  %b  ④%b  Desktop environment and apps\n' "$CW" "$R"
    printf '  %b  ⑤%b  Disk selection and install\n' "$CW" "$R"
    printf '\n'
    printf '  %b────────────────────────────────────────────────────────%b\n' "$CF" "$R"
    printf '\n'
    if [[ -n "$GUM_BIN" ]]; then
        printf '  %bUse arrow keys to navigate menus. Press Enter to select.%b\n' "${D}${CG}" "$R"
    else
        printf '  %bType a number to navigate menus. Press Enter to confirm.%b\n' "${D}${CG}" "$R"
    fi
    printf '\n'
    printf '  %bPress Enter to begin%b\n' "$CW" "$R"
    printf '\n'
    read -rs _ </dev/tty || true
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — LANGUAGE
# ═══════════════════════════════════════════════════════════════════════════════

step_language() {
    while true; do
        tab_header 1
        printf '  %bLanguage & Region%b\n\n' "${B}${CS}" "$R"
        msg "This sets the installed system locale, console keymap, desktop keyboard, and starting timezone."
        msg "You can still adjust timezone and keyboard on the Identity page."
        choice_panel
        printf '\n'

        menu "Choose system language" \
            "English (US)|en_US.UTF-8" \
            "English (UK)|en_GB.UTF-8" \
            "Spanish|es_ES.UTF-8" \
            "French|fr_FR.UTF-8" \
            "Deutsch|de_DE.UTF-8" \
            "Italiano|it_IT.UTF-8" \
            "Portuguese Brazil|pt_BR.UTF-8" \
            "Portuguese Portugal|pt_PT.UTF-8" \
            "Nederlands|nl_NL.UTF-8" \
            "Polski|pl_PL.UTF-8" \
            "Russian|ru_RU.UTF-8" \
            "Turkish|tr_TR.UTF-8" \
            "Japanese|ja_JP.UTF-8" \
            "Korean|ko_KR.UTF-8" \
            "Chinese Simplified|zh_CN.UTF-8" \
            "Custom locale|Type a locale manually"

        if [[ "$MENU_RESULT" -eq 15 ]]; then
            local v
            while true; do
                v="$(prompt_field "Locale" "$locale_value")"
                [[ -n "$v" ]] && locale_value="$v"
                if safe_locale "$locale_value"; then
                    language_label="$locale_value"
                    break
                fi
                warn "Use a locale like en_US.UTF-8, de_DE.UTF-8, or fr_FR.UTF-8."
            done
        fi

        case "$MENU_RESULT" in
            0) locale_value="en_US.UTF-8" ;;
            1) locale_value="en_GB.UTF-8" ;;
            2) locale_value="es_ES.UTF-8" ;;
            3) locale_value="fr_FR.UTF-8" ;;
            4) locale_value="de_DE.UTF-8" ;;
            5) locale_value="it_IT.UTF-8" ;;
            6) locale_value="pt_BR.UTF-8" ;;
            7) locale_value="pt_PT.UTF-8" ;;
            8) locale_value="nl_NL.UTF-8" ;;
            9) locale_value="pl_PL.UTF-8" ;;
            10) locale_value="ru_RU.UTF-8" ;;
            11) locale_value="tr_TR.UTF-8" ;;
            12) locale_value="ja_JP.UTF-8" ;;
            13) locale_value="ko_KR.UTF-8" ;;
            14) locale_value="zh_CN.UTF-8" ;;
        esac
        apply_language_defaults

        printf '\n'
        ok "Language: ${language_label}"
        ok "Locale: ${locale_value}"
        ok "Keyboard: ${keyboard_value} / ${xkb_layout_value}"
        ok "Timezone: ${timezone_value}"
        pause
        return 0
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — NETWORK
# ═══════════════════════════════════════════════════════════════════════════════

step_network() {
    start_nm 2>/dev/null || true
    local ok=0
    if net_connected; then ok=1; fi

    while true; do
        tab_header 2
        printf '  %bNetwork Setup%b\n\n' "${B}${CS}" "$R"

        if (( ok )); then
            ok "Connected — internet available"
        else
            warn "No internet connection detected"
        fi
        printf '\n'

        menu "" \
            "Network tools|Status, nmtui, quick Wi-Fi, and rescan" \
            "Quick Wi-Fi connect|Scan and connect with nmcli" \
            "Re-check connection|Test connectivity again" \
            "Continue|Proceed with current state"

        case "$MENU_RESULT" in
            0)
                network_tools_menu yes
                ;;
            1)
                quick_wifi_connect
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
#  STEP 3 — IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════

step_identity() {
    tab_header 3
    printf '  %bIdentity & Locale%b\n\n' "${B}${CS}" "$R"
    printf '  %bSystem language%b  %s (%s)\n\n' "$CI" "$R" "$language_label" "$locale_value"
    choice_panel

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
    while true; do
        v="$(prompt_field "Timezone" "$timezone_value")"
        [[ -n "$v" ]] && timezone_value="$(normalize_timezone "$v")"
        if timezone_exists "$timezone_value"; then break; fi
        warn "Use a valid timezone, for example America/New_York, EST, Eastern, or UTC."
    done

    while true; do
        v="$(prompt_field "Console keymap" "$keyboard_value")"
        [[ -n "$v" ]] && keyboard_value="$v"
        if safe_keymap "$keyboard_value"; then break; fi
        warn "Use letters, numbers, dash, underscore, plus, or dot only."
    done
    sync_xkb_layout

    while true; do
        v="$(prompt_field "XKB layout (X11)" "$xkb_layout_value")"
        [[ -n "$v" ]] && xkb_layout_value="$v"
        if safe_keymap "$xkb_layout_value"; then break; fi
        warn "Use letters, numbers, dash, underscore, plus, or dot only."
    done

    printf '\n'

    # Password
    while true; do
        local p1; p1="$(prompt_password "Password")"
        local p2; p2="$(prompt_password "Confirm password")"
        [[ -z "$p1" ]] && { warn "Password cannot be empty."; continue; }
        [[ "$p1" != "$p2" ]] && { warn "Passwords do not match."; continue; }
        user_password_hash="$(hash_password "$p1")"
        [[ -n "$user_password_hash" ]] || { warn "Could not hash password; openssl passwd failed."; continue; }
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
                root_password_hash="$(hash_password "$p1")"
                [[ -n "$root_password_hash" ]] || { warn "Could not hash root password; openssl passwd failed."; continue; }
                ok "Root password set."
                break
            done
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — DESKTOP
# ═══════════════════════════════════════════════════════════════════════════════

step_desktop() {
    tab_header 4

    # Every edition installs the full desktop matrix — the edition only
    # decides the ISO's own live-session default (see RELEASE_NOTES.md,
    # "Every edition still installs the full desktop matrix — the edition
    # just decides the ISO's live-session default"). All editions get a
    # picker; "other" and "hyprland" show tiling WMs first since that's
    # what those ISOs are built around, matching the GUI installer.
    local -a profiles=()
    local profile
    local profile_source=abora_supported_desktop_profiles
    [[ "${abora_edition:-}" == "other" || "${abora_edition:-}" == "hyprland" ]] && profile_source=abora_tiling_wm_profiles
    local default_desktop="${abora_default_desktop:-$abora_edition}"
    while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        abora_sync_desktop_label "$profile"
        if [[ "$profile" == "$default_desktop" ]]; then
            profiles=("${desktop_label}|${profile}" "${profiles[@]}")
        else
            profiles+=("${desktop_label}|${profile}")
        fi
    done < <("$profile_source")

    local title="Choose Your Desktop Environment"
    [[ "${abora_edition:-}" == "other" || "${abora_edition:-}" == "hyprland" ]] && title="Choose Your Window Manager"
    menu "$title" "${profiles[@]}"
    desktop_profile="${profiles[$MENU_RESULT]#*|}"
    abora_sync_desktop_label "$desktop_profile"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 5 — APPS
# ═══════════════════════════════════════════════════════════════════════════════

step_apps() {
    tab_header 5

    menu "Choose a Starter App Bundle" \
        "Fan Favorites|Saved for after first boot — recommended" \
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

    install_apps_during_setup="no"
    if [[ "$starter_apps_bundle" != "none" ]]; then
        printf '\n'
        menu "When should apps install?" \
            "After first boot|Fast install — apply later with abora apps rebuild" \
            "During setup|Slow — can take a long time or fail on cache misses"
        [[ "$MENU_RESULT" -eq 1 ]] && install_apps_during_setup="yes"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 6 — OPTIONS
# ═══════════════════════════════════════════════════════════════════════════════

step_options() {
    tab_header 6

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

    printf '\n'
    menu "Gaming Layer" \
        "Skip gaming setup|Smallest install — add gaming later" \
        "Desktop gaming|Steam, 32-bit graphics, GameMode, MangoHud, Vulkan tools" \
        "Desktop gaming + Big Picture|Also add a controller-friendly Steam launcher" \
        "Big Picture console mode|Add a Gamescope login session for TV/controller use"
    case "$MENU_RESULT" in
        0)
            gaming_enabled="no"
            gaming_steam="no"
            gaming_big_picture="no"
            gaming_autostart="no"
            gaming_gamescope="no"
            gaming_vulkan="no"
            gaming_controller="no"
            gaming_mangohud="no"
            gaming_gamemode="no"
            gaming_launchers="no"
            ;;
        1)
            gaming_enabled="yes"
            gaming_steam="yes"
            gaming_big_picture="no"
            gaming_autostart="no"
            gaming_gamescope="no"
            gaming_vulkan="yes"
            gaming_controller="yes"
            gaming_mangohud="yes"
            gaming_gamemode="yes"
            gaming_launchers="yes"
            ;;
        2)
            gaming_enabled="yes"
            gaming_steam="yes"
            gaming_big_picture="yes"
            gaming_autostart="no"
            gaming_gamescope="no"
            gaming_vulkan="yes"
            gaming_controller="yes"
            gaming_mangohud="yes"
            gaming_gamemode="yes"
            gaming_launchers="yes"
            ;;
        3)
            gaming_enabled="yes"
            gaming_steam="yes"
            gaming_big_picture="yes"
            gaming_autostart="no"
            gaming_gamescope="yes"
            gaming_vulkan="yes"
            gaming_controller="yes"
            gaming_mangohud="yes"
            gaming_gamemode="yes"
            gaming_launchers="yes"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 7 — GPU
# ═══════════════════════════════════════════════════════════════════════════════

step_gpu() {
    # Shared by both flows (release_install_flow and the --reconfig wizard),
    # which use two different, differently-ordered progress headers --
    # tab_header's _TABS array reflects the reconfig step_* sequence
    # (Language, Network, Identity, Desktop, Apps, Options, GPU, Dotfiles,
    # Disk, Preflight, Confirm), not release_install_flow's real order
    # (Welcome, Network, Disk, Identity, Locale, Desktop, GPU, Gaming, Apps,
    # Preflight, Review). Always calling tab_header 7 here showed a step
    # grid with wrong checkmarks during a real install (Disk unchecked
    # despite already being confirmed, Apps/Options checked despite not
    # having run yet) -- reproduced by actually running the installer.
    if [[ "${reconfig_mode:-0}" == "1" ]]; then
        tab_header 7
    else
        release_header "GPU driver"
    fi

    local detected="$gpu_value"
    msg "Detected GPU driver: ${detected}"
    printf '\n'

    case "$detected" in
        nouveau)
            menu "NVIDIA GPU detected" \
                "Use open-source (nouveau)|Recommended — no license to accept, works out of the box" \
                "Use proprietary (nvidia)|Best performance/features on most NVIDIA cards" \
                "Use open kernel modules (nvidia-open)|NVIDIA's open-source modules — Turing (2018+) or newer only"
            case "$MENU_RESULT" in
                0) gpu_value="nouveau" ;;
                1) gpu_value="nvidia" ;;
                2) gpu_value="nvidia-open" ;;
            esac
            ;;
        amdgpu)
            ok "AMD GPU detected — amdgpu (open-source) will be used."
            gpu_value="amdgpu"
            ;;
        intel)
            ok "Intel GPU detected — the open-source Intel driver will be used."
            gpu_value="intel"
            ;;
        *)
            warn "No GPU vendor was detected automatically."
            menu "GPU driver" \
                "None (kernel default)|Let NixOS pick a driver automatically" \
                "NVIDIA (nouveau, open-source)" \
                "NVIDIA (proprietary)" \
                "NVIDIA (open kernel modules)" \
                "AMD (amdgpu)" \
                "Intel"
            case "$MENU_RESULT" in
                0) gpu_value="none" ;;
                1) gpu_value="nouveau" ;;
                2) gpu_value="nvidia" ;;
                3) gpu_value="nvidia-open" ;;
                4) gpu_value="amdgpu" ;;
                5) gpu_value="intel" ;;
            esac
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 8 — DOTFILES
# ═══════════════════════════════════════════════════════════════════════════════
# Only shown for editions where a bare tiling WM/compositor is genuinely
# unusable without some config: hyprland (single-desktop edition) and other
# (the tiling-WM picker). Every other edition ships a full desktop shell
# that works out of the box, so asking about dotfiles there would just be
# noise.

step_dotfiles() {
    case "${abora_edition:-}" in
        hyprland|other) : ;;
        *) return 0 ;;
    esac

    tab_header 8
    printf '  %bDotfiles (Optional)%b\n\n' "${B}${CS}" "$R"
    msg "Import your own config from a Git repository after first boot."
    printf '\n'

    menu "Dotfiles" \
        "Skip|Configure ${desktop_label} manually later" \
        "Import from a Git URL|GitHub, GitLab, Codeberg, or any public Git URL"

    if [[ "$MENU_RESULT" -eq 1 ]]; then
        printf '\n'
        printf '  %bDotfiles Git URL:%b ' "$CW" "$R"
        read -r dotfiles_url </dev/tty || dotfiles_url=""
        dotfiles_url="${dotfiles_url// /}"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 9 — PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════════

step_preflight() {
    while true; do
        tab_header 10
        printf '  %bInstall Preflight%b\n\n' "${B}${CS}" "$R"
        msg "Checking tools, installer assets, and Nix paths."
        printf '\n'

        if check_install_environment live; then
            printf '\n'
            ok "The live installer environment is ready."
            pause
            return 0
        fi

        printf '\n'
        warn "Fix the items above before continuing."
        msg "For network problems, choose Network tools or run abora network from a terminal."
        printf '\n'
        menu "Preflight failed" \
            "Run checks again|Re-test after fixing the live environment" \
            "Network tools|Fix Wi-Fi, DNS, or cache reachability" \
            "Debug tools|View logs, hardware test, support report" \
            "Open terminal|Drop to the live shell" \
            "Cancel|Abort and return to the live shell"
        case "$MENU_RESULT" in
            0) continue ;;
            1) network_tools_menu yes ;;
            2) debug_tools_menu ;;
            3) open_live_terminal ;;
            *) exit 1 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 10 — DISK
# ═══════════════════════════════════════════════════════════════════════════════

step_disk() {
    tab_header 9
    warn "Choose the target disk. What gets erased depends on the mode you pick next."
    printf '\n'

    local -a disks=() row
    while IFS= read -r row; do
        [[ -n "$row" ]] && disks+=("$row")
    done < <(collect_disks)
    if [[ ${#disks[@]} -eq 0 ]]; then
        warn "No installable disks found."
        printf '\n'
        menu "Disk tools" \
            "Scan again|Refresh the disk list" \
            "Open terminal|Use lsblk, dmesg, or nvme/sata tools" \
            "Debug installer|Run hardware tests or collect a support report" \
            "Cancel|Return to the live shell"
        case "$MENU_RESULT" in
            0) step_disk; return ;;
            1) open_live_terminal; step_disk; return ;;
            2) debug_tools_menu; step_disk; return ;;
            *) exit 1 ;;
        esac
    fi

    menu "Choose Installation Disk" "${disks[@]}"
    disk="${disks[$MENU_RESULT]%%|*}"
    install_disk_mode="erase"
    target_partition=""
    target_esp=""

    printf '\n'
    menu "How should Abora use ${disk}?" \
        "Erase entire disk|Wipe everything and use the whole disk" \
        "Use an existing partition|Format only one partition; keep everything else (dual-boot)" \
        "Choose a different disk|Go back"
    case "$MENU_RESULT" in
        0) step_disk_confirm_erase ;;
        1) step_disk_existing_partition ;;
        *) step_disk; return ;;
    esac
}

step_disk_confirm_erase() {
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
    install_disk_mode="erase"
}

# The "don't wipe the full disk" path: format only one existing partition
# the operator explicitly picks, reusing an existing ESP on the same disk
# rather than creating a second one. Requires both to already exist —
# this does not carve free space into new partitions, and does not
# offer a partition that's mounted or backing an active LUKS/LVM/RAID
# device (see list_disk_partitions()).
step_disk_existing_partition() {
    printf '\n'
    local -a parts=() row
    while IFS= read -r row; do
        [[ -n "$row" ]] && parts+=("$row")
    done < <(list_disk_partitions "$disk")

    if [[ ${#parts[@]} -eq 0 ]]; then
        warn "No usable existing partitions found on ${disk}."
        printf '\n'
        msg "Every partition on this disk is either mounted, in active use, or there isn't a free one yet — this mode needs an existing, unused partition to format."
        printf '\n'
        menu "OK" "Back|Choose a different disk or mode"
        step_disk
        return
    fi

    local esp; esp="$(find_existing_esp "$disk")"
    if [[ -z "$esp" ]]; then
        warn "No existing EFI System Partition found on ${disk}."
        printf '\n'
        msg "This mode reuses an existing ESP instead of creating a new one. Use 'Erase entire disk' instead, or create an ESP with another tool first."
        printf '\n'
        menu "OK" "Back|Choose a different disk or mode"
        step_disk
        return
    fi

    menu "Choose the partition to install onto" "${parts[@]}"
    target_partition="${parts[$MENU_RESULT]%%|*}"
    target_esp="$esp"

    printf '\n'
    warn "This will erase ${target_partition} and use it as the Abora root partition."
    msg "Everything else on ${disk} — including the existing EFI partition ${target_esp}, reused as-is — stays untouched."
    printf '\n'
    menu "Are you sure?" \
        "Yes — format ${target_partition} and install|Only this one partition will be erased" \
        "No — go back|Choose a different partition"
    if [[ "$MENU_RESULT" -eq 1 ]]; then
        step_disk_existing_partition
        return
    fi
    install_disk_mode="existing"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 9 — CONFIRM
# ═══════════════════════════════════════════════════════════════════════════════

_print_summary() {
    if [[ -n "$disk" && "$install_disk_mode" == "existing" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Disk:" "$R" "${disk}  (only ${target_partition} will be erased)"
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "EFI partition:" "$R" "${target_esp}  ← reused as-is, not reformatted"
    elif [[ -n "$disk" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Disk:" "$R" "${disk}  ← will be erased"
    else
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Disk:" "$R" "unchanged"
    fi
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Hostname:" "$R" "$hostname_value"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Username:" "$R" "$username_value"
    printf '  %b  %-16s%b  %s (%s)\n' "${D}${CI}" "Language:" "$R" "$language_label" "$locale_value"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Timezone:" "$R" "$timezone_value"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Keyboard:" "$R" "${keyboard_value} / ${xkb_layout_value}"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Desktop:"  "$R" "${desktop_label} (${desktop_profile})"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "GPU:"      "$R" "$gpu_value"
    if [[ -n "$dotfiles_url" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Dotfiles:" "$R" "$dotfiles_url"
    fi
    if [[ "$starter_apps_bundle" == "none" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:" "$R" "$starter_apps_label"
    elif [[ "$install_apps_during_setup" == "yes" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:" "$R" "${starter_apps_label} (during setup)"
    else
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:" "$R" "${starter_apps_label} (after first boot)"
    fi
    if [[ "$gaming_enabled" == "yes" ]]; then
        local gaming_desc="enabled"
        [[ "$gaming_big_picture" == "yes" ]] && gaming_desc+=", Big Picture"
        [[ "$gaming_gamescope" == "yes" ]] && gaming_desc+=", Gamescope session"
        [[ "$gaming_vulkan" == "yes" ]] && gaming_desc+=", Vulkan tools"
        [[ "$gaming_autostart" == "yes" ]] && gaming_desc+=", autostart"
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Gaming:" "$R" "$gaming_desc"
    else
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Gaming:" "$R" "off"
    fi
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "ANIX:"     "$R" "$anix_enabled"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Root:"     "$R" "$root_password_mode"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "GitHub:"   "$R" "$github_identity"
    printf '\n'
}

step_confirm() {
    local install_now_desc="Erase ${disk} and install ${release_name}"
    [[ "$install_disk_mode" == "existing" ]] && \
        install_now_desc="Format ${target_partition} and install ${release_name}"

    while true; do
        tab_header 11
        printf '  %bInstallation Summary%b\n\n' "${B}${CS}" "$R"
        _print_summary

        menu "Ready to install?" \
            "Install now|${install_now_desc}" \
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
                    user_password_hash="$(hash_password "$p1")"
                    [[ -n "$user_password_hash" ]] || { warn "Could not hash password; openssl passwd failed."; continue; }
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

# nvme/mmcblk/loop devices number their partitions as <disk>p<N> (e.g.
# nvme0n1p2), while sd*/vd*/hd* disks are just <disk><N> (sda2) — this
# suffix is what lets efi_part/root_part below be built generically for
# either naming scheme.
disk_part_suffix() {
    case "$disk" in *nvme*|*mmcblk*|*loop*) printf 'p' ;; *) printf '' ;; esac
}

log_install_step() {
    printf '[installer] %s\n' "$*" >>"$install_log"
}

# GPT layout: a 1MiB BIOS-boot partition (for Limine's legacy-BIOS path),
# a FAT32 ESP (UEFI), and the rest as the ext4 root — the same disk boots
# either BIOS or UEFI without needing to know which at partition time.
partition_disk() {
    log_install_step "partition_disk: start disk=${disk}"
    if [[ -z "$disk" || ! -b "$disk" ]]; then
        log_install_step "partition_disk: refusing — '${disk}' is not a block device"
        return 1
    fi
    umount -R /mnt >/dev/null 2>&1 || true
    wipefs -af "$disk" >>"$install_log" 2>&1 || return 1
    parted -s "$disk" mklabel gpt >>"$install_log" 2>&1 || return 1
    parted -s "$disk" unit MiB mkpart BIOSBOOT 1 3 >>"$install_log" 2>&1 || return 1
    parted -s "$disk" set 1 bios_grub on >>"$install_log" 2>&1 || return 1
    parted -s "$disk" unit MiB mkpart ESP fat32 3 515 >>"$install_log" 2>&1 || return 1
    parted -s "$disk" set 2 esp on >>"$install_log" 2>&1 || return 1
    parted -s "$disk" unit MiB mkpart primary ext4 515 100% >>"$install_log" 2>&1 || return 1
    partprobe "$disk" >>"$install_log" 2>&1 || true
    udevadm settle >>"$install_log" 2>&1 || true

    local sfx; sfx="$(disk_part_suffix)"
    efi_part="${disk}${sfx}2"
    root_part="${disk}${sfx}3"
    log_install_step "partition_disk: efi=${efi_part} root=${root_part}"

    local n
    for n in 1 2 3 4 5; do
        [[ -b "$efi_part" && -b "$root_part" ]] && break
        sleep 1
        partprobe "$disk" >>"$install_log" 2>&1 || true
        udevadm settle >>"$install_log" 2>&1 || true
    done
    [[ -b "$efi_part" ]] || { log_install_step "partition_disk: missing EFI partition ${efi_part}"; return 1; }
    [[ -b "$root_part" ]] || { log_install_step "partition_disk: missing root partition ${root_part}"; return 1; }

    mkfs.vfat -F 32 -n ABORA_EFI "$efi_part" >>"$install_log" 2>&1 || return 1
    mkfs.ext4 -F -L ABORA_ROOT "$root_part" >>"$install_log" 2>&1 || return 1
    sync || true
    udevadm settle >>"$install_log" 2>&1 || true
    ensure_root_label "$root_part" || {
        log_install_step "partition_disk: root label verification failed for ${root_part}"
        return 1
    }
    log_install_step "partition_disk: verified root label ABORA_ROOT on ${root_part}"
    log_install_step "partition_disk: format complete"
}

# The "use an existing partition" counterpart to partition_disk(): formats
# only $target_partition as the new root, reuses $target_esp completely
# unformatted, and never touches wipefs/mklabel/mkpart at all — everything
# else already on $disk (a Windows install, another Linux install, a data
# partition) is left exactly as it was. Requires an existing ESP to
# already be present on the disk (set via find_existing_esp in
# step_disk()); this mode does not carve a new one out of free space.
partition_disk_existing() {
    log_install_step "partition_disk_existing: start disk=${disk} target=${target_partition} esp=${target_esp}"
    if [[ -z "$target_partition" || ! -b "$target_partition" ]]; then
        log_install_step "partition_disk_existing: refusing — '${target_partition}' is not a block device"
        return 1
    fi
    if [[ -z "$target_esp" || ! -b "$target_esp" ]]; then
        log_install_step "partition_disk_existing: refusing — '${target_esp}' is not a block device"
        return 1
    fi
    if [[ "$target_partition" == "$disk" || "$target_esp" == "$disk" ]]; then
        log_install_step "partition_disk_existing: refusing — target resolves to the whole disk, not a partition"
        return 1
    fi

    umount -R /mnt >/dev/null 2>&1 || true
    # Deliberately no wipefs/mklabel/mkpart here — that's the entire point
    # of this mode. Only the one partition the operator explicitly chose
    # and confirmed in step_disk() ever gets formatted.
    mkfs.ext4 -F -L ABORA_ROOT "$target_partition" >>"$install_log" 2>&1 || return 1
    sync || true
    udevadm settle >>"$install_log" 2>&1 || true

    efi_part="$target_esp"
    root_part="$target_partition"
    log_install_step "partition_disk_existing: efi=${efi_part} root=${root_part}"

    ensure_root_label "$root_part" || {
        log_install_step "partition_disk_existing: root label verification failed for ${root_part}"
        return 1
    }
    log_install_step "partition_disk_existing: verified root label ABORA_ROOT on ${root_part}"
    log_install_step "partition_disk_existing: format complete (disk otherwise untouched)"
}

mount_target() {
    log_install_step "mount_target: start root=${root_part} efi=${efi_part}"
    mkdir -p /mnt || return 1
    mount "$root_part" /mnt >>"$install_log" 2>&1 || return 1
    mkdir -p /mnt/boot || return 1
    mount "$efi_part" /mnt/boot >>"$install_log" 2>&1 || return 1
    log_install_step "mount_target: complete"
}

cp_required() {
    [[ -f "$1" ]] || { printf 'Required file missing: %s\n' "$1" >&2; return 1; }
    cp "$1" "$2"
}

write_starter_app_ids() {
    local target="$1" id
    : > "$target"
    [[ "$starter_apps_bundle" == "none" ]] && return 0
    while IFS= read -r id; do
        [[ -n "$id" ]] && printf '%s\n' "$id" >> "$target"
    done < <(abora_catalog_bundle_ids "$starter_apps_bundle" 2>/dev/null || true)
}

write_starter_app_exprs() {
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

write_docs_fallback() {
    local docs_dir="$1"
    mkdir -p "$docs_dir/wiki"
    for doc in ANIX-V1 ANIX-V2-Languages TinyPM Abora-Tools Abora-Gaming Recovery Updating-Abora; do
        [[ -f "$docs_dir/wiki/${doc}.md" ]] && continue
        cat > "$docs_dir/wiki/${doc}.md" <<EOF
# ${doc}

This Abora ISO did not include the full local documentation payload.

Useful commands:

\`\`\`sh
abora doctor
anix status
anix doctor
tinypm doctor
tinypm providers
\`\`\`
EOF
    done
}

# Copies mango's config.conf into the installed /etc/nixos tree itself
# (rather than referencing it from the live ISO's /nix/store) so the
# installed flake stays self-contained: a store path from the live ISO's
# build is a temporary GC root that can vanish, so the installed config must
# never reference it. rewrite_installed_mango_config_paths() below then
# patches any Nix files that got copied from the ISO already pointing at
# that store path, redirecting them to this local copy instead.
install_mango_config_asset() {
    local root="${1:-/mnt}"
    local dest="${root}/etc/nixos/abora/mango/config.conf"
    local candidate

    mkdir -p "$(dirname "$dest")"
    for candidate in \
        /etc/abora/mango/config.conf \
        "${root}/etc/nixos/.abora-upstream/assets/mango/config.conf" \
        /etc/nixos/.abora-upstream/assets/mango/config.conf \
        "${root}/etc/nixos/assets/mango/config.conf"; do
        if [[ -f "$candidate" ]]; then
            cp "$candidate" "$dest"
            return 0
        fi
    done

    : > "$dest"
}

rewrite_installed_mango_config_paths() {
    local root="${1:-/mnt}"
    local abora_dir="${root}/etc/nixos/abora"
    local bad_store='/nix/store'
    bad_store="${bad_store}/assets/mango/config.conf"
    local file

    for file in "$abora_dir/abora-options.nix" "$abora_dir/installed-base.nix"; do
        [[ -f "$file" ]] || continue
        sed -i \
            -e "s|\"${bad_store}\"|./mango/config.conf|g" \
            -e "s|${bad_store}|./mango/config.conf|g" \
            -e 's|../../assets/mango/config\.conf|./mango/config.conf|g' \
            -e 's|../../../assets/mango/config\.conf|./mango/config.conf|g' \
            "$file"
    done

    if [[ -d "$abora_dir/desktops" ]]; then
        while IFS= read -r -d '' file; do
            sed -i \
                -e "s|\"${bad_store}\"|../mango/config.conf|g" \
                -e "s|${bad_store}|../mango/config.conf|g" \
                -e 's|../../assets/mango/config\.conf|../mango/config.conf|g' \
                -e 's|../../../assets/mango/config\.conf|../mango/config.conf|g' \
                "$file"
        done < <(
            grep -RIlZ \
                -e "$bad_store" \
                -e '../../assets/mango/config.conf' \
                -e '../../../assets/mango/config.conf' \
                "$abora_dir/desktops" 2>/dev/null || true
        )
    fi
}

write_branding_assets() {
    local root="${1:-/mnt}"
    mkdir -p "${root}/etc/nixos/abora/plymouth" \
             "${root}/etc/nixos/abora/bootloader" \
             "${root}/etc/nixos/abora/desktops" \
             "${root}/etc/nixos/abora/mango" \
             "${root}/etc/nixos/abora/pkgs" \
             "${root}/etc/nixos/abora/wallpapers" \
             "${root}/etc/nixos/abora/themes" \
             "${root}/etc/nixos/abora/effects" \
             "${root}/etc/nixos/abora/anix-languages" \
             "${root}/etc/nixos/abora/tools" \
             "${root}/etc/nixos/abora/vendor"

    local f
    for f in VERSION title.txt abora.sh ui.sh config.sh build.sh adopt-nixos.sh desktop.sh doctor.sh \
              gaming.sh check-full.sh recovery.sh welcome.sh app-catalog.sh apps.sh support-report.sh \
              custom-packages.sh hardware-test.sh default-wallpaper.png fastfetch-logo.txt \
              fastfetch-config.jsonc desktop-profiles.sh installed-base.nix \
              installer.sh setup-launcher.sh setup.desktop repair-flake-purity.sh \
              session-setup.sh dotfiles-import.sh theme-sync.sh update.sh welcome-gui.py config-gui.py \
              gaming-welcome-gui.py; do
        cp_required "/etc/abora/${f}" "${root}/etc/nixos/abora/${f}"
    done
    [[ -f /etc/abora/Abora-LOGO.png ]] && \
        cp /etc/abora/Abora-LOGO.png "${root}/etc/nixos/abora/Abora-LOGO.png"
    [[ -f /etc/abora/Abora-Text.png ]] && \
        cp /etc/abora/Abora-Text.png "${root}/etc/nixos/abora/Abora-Text.png"
    cp_required /etc/abora/plymouth/abora.plymouth "${root}/etc/nixos/abora/plymouth/abora.plymouth"
    cp_required /etc/abora/plymouth/abora.script   "${root}/etc/nixos/abora/plymouth/abora.script"
    install_mango_config_asset "$root"
    cp_required /etc/abora/pkgs/mango.nix          "${root}/etc/nixos/abora/pkgs/mango.nix"
    cp_required /etc/abora/pkgs/scenefx-0_5.nix    "${root}/etc/nixos/abora/pkgs/scenefx-0_5.nix"
    cp_required /etc/abora/pkgs/modularity.nix     "${root}/etc/nixos/abora/pkgs/modularity.nix"
    cp_required /etc/abora/pkgs/moducpp-anix.nix   "${root}/etc/nixos/abora/pkgs/moducpp-anix.nix"
    cp_required /etc/abora/pkgs/abora-update-resolver.nix "${root}/etc/nixos/abora/pkgs/abora-update-resolver.nix"
    cp_required /etc/abora/pkgs/abora-update-resolver-deps.json "${root}/etc/nixos/abora/pkgs/abora-update-resolver-deps.json"
    cp_required /etc/abora/pkgs/abora-plan-tool.nix "${root}/etc/nixos/abora/pkgs/abora-plan-tool.nix"
    cp_required /etc/abora/pkgs/abora-plan-tool-deps.json "${root}/etc/nixos/abora/pkgs/abora-plan-tool-deps.json"
    cp_required /etc/abora/tools/moducpp-anix      "${root}/etc/nixos/abora/tools/moducpp-anix"
    cp_required /etc/abora/anix-module.nix         "${root}/etc/nixos/abora/anix-module.nix"
    cp_required /etc/abora/abora-options.nix       "${root}/etc/nixos/abora/abora-options.nix"
    cp -a /etc/abora/vendor/modularity "${root}/etc/nixos/abora/vendor/modularity"

    [[ -f /etc/abora/anix.sh           ]] && cp /etc/abora/anix.sh            "${root}/etc/nixos/abora/anix.sh"
    if [[ -f /etc/abora/effects/v3StartingAbora.mp3 ]]; then
        cp /etc/abora/effects/v3StartingAbora.mp3 "${root}/etc/nixos/abora/effects/v3StartingAbora.mp3"
    elif [[ -f /etc/abora/effects/LaunchingAbora.mp3 ]]; then
        cp /etc/abora/effects/LaunchingAbora.mp3 "${root}/etc/nixos/abora/effects/v3StartingAbora.mp3"
    fi

    cp -a /etc/abora/desktops/. "${root}/etc/nixos/abora/desktops/"
    cp -a /etc/abora/wallpapers/. "${root}/etc/nixos/abora/wallpapers/"
    cp -a /etc/abora/themes/. "${root}/etc/nixos/abora/themes/"
    if [[ -d /etc/abora/anix-languages ]]; then
        cp -a /etc/abora/anix-languages/. "${root}/etc/nixos/abora/anix-languages/"
    fi
    rewrite_installed_mango_config_paths "$root"

    if [[ -e /etc/abora/tinypm ]]; then
        mkdir -p "${root}/etc/nixos/abora/tinypm"
        # -a preserves modes (including executable bits) and copies relative
        # symlinks as symlinks.  No -L so we never follow absolute symlinks
        # that may exist in older live ISOs.
        cp -a /etc/abora/tinypm/. "${root}/etc/nixos/abora/tinypm/"
    fi

    if [[ -e /etc/abora/update-resolver ]]; then
        mkdir -p "${root}/etc/nixos/abora/update-resolver"
        cp -a /etc/abora/update-resolver/. "${root}/etc/nixos/abora/update-resolver/"
    fi

    if [[ -e /etc/abora/plan-tool ]]; then
        mkdir -p "${root}/etc/nixos/abora/plan-tool"
        cp -a /etc/abora/plan-tool/. "${root}/etc/nixos/abora/plan-tool/"
    fi

    if [[ -d /etc/abora/docs ]]; then
        mkdir -p "${root}/etc/nixos/abora/docs"
        cp -a /etc/abora/docs/. "${root}/etc/nixos/abora/docs/"
    fi
    write_docs_fallback "${root}/etc/nixos/abora/docs"

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

    find -L /etc/abora/wallpapers -maxdepth 1 -type f \
        -exec cp -L {} "${root}/etc/nixos/abora/wallpapers/" \; 2>/dev/null || true
    find -L /etc/abora/themes -maxdepth 1 -type f \
        -exec cp -L {} "${root}/etc/nixos/abora/themes/" \; 2>/dev/null || true

    if git -C "${root}/etc/nixos" rev-parse --git-dir >/dev/null 2>&1; then
        # One git-add call per path, not a single multi-path call: git add
        # fails (and stages nothing at all, for any of the paths given) the
        # moment one pathspec doesn't match. See the identical fix in
        # abora-repair-flake-purity.sh for the failure mode this avoids.
        for _branding_git_path in \
            abora/mango/config.conf \
            abora/abora-options.nix \
            abora/installed-base.nix \
            abora/desktops/mangowm.nix \
            abora/repair-flake-purity.sh; do
            git -C "${root}/etc/nixos" add "$_branding_git_path" 2>/dev/null || true
        done
    fi
}

# Writes the installed system's entire /etc/nixos tree: hardware-configuration.nix
# (via nixos-generate-config), the branding/asset copy, and four hand-written
# files — anix.nix (optional), configuration.nix (the import list),
# abora-local.nix (the plain NixOS-option form of every installer choice —
# this is what `abora config` reads/edits later), and flake.nix. Every
# user-supplied string goes through nix_string() first since these are all
# double-quoted Nix string literals.
generate_nixos_config() {
    local root="${1:-/mnt}"
    local cfgdir="${root}/etc/nixos"

    printf '[*] nixos-generate-config\n' > "$config_log"
    nixos-generate-config --root "$root" >> "$config_log" 2>&1
    write_branding_assets "$root"

    local desktop_pkgs root_pw_line host_nix user_nix locale_nix timezone_nix keyboard_nix xkb_nix desktop_nix wallpaper_nix anix_import_line disk_nix gpu_nix
    local gaming_enabled_nix gaming_steam_nix gaming_big_picture_nix gaming_autostart_nix gaming_gamescope_nix gaming_vulkan_nix gaming_controller_nix gaming_mangohud_nix gaming_gamemode_nix gaming_launchers_nix
    local disk_bios_support_nix
    timezone_value="$(normalize_timezone "$timezone_value")"
    desktop_pkgs="$(abora_desktop_package_block "$desktop_profile")"
    host_nix="$(nix_string "$hostname_value")"
    user_nix="$(nix_string "$username_value")"
    locale_nix="$(nix_string "$locale_value")"
    timezone_nix="$(nix_string "$timezone_value")"
    keyboard_nix="$(nix_string "$keyboard_value")"
    xkb_nix="$(nix_string "$xkb_layout_value")"
    desktop_nix="$(nix_string "$desktop_profile")"
    wallpaper_nix="$(nix_string "$wallpaper_name")"
    disk_nix="$(nix_string "$disk")"
    gpu_nix="$(nix_string "$gpu_value")"
    # "Use an existing partition" mode never creates a bios_grub partition
    # (it never repartitions the disk at all) -- `limine bios-install`
    # fails outright on a GPT disk with none. That failure is silent all
    # the way up (nixpkgs' limine-install.py doesn't check the subprocess
    # exit code), so a Legacy-BIOS machine using this mode would end up
    # with a fully unbootable install and no error anywhere. UEFI boot
    # through the reused ESP is unaffected either way.
    if [[ "$install_disk_mode" == "existing" ]]; then
        disk_bios_support_nix="false"
    else
        disk_bios_support_nix="true"
    fi
    gaming_enabled_nix="$(nix_bool "$gaming_enabled")"
    gaming_steam_nix="$(nix_bool "$gaming_steam")"
    gaming_big_picture_nix="$(nix_bool "$gaming_big_picture")"
    gaming_autostart_nix="$(nix_bool "$gaming_autostart")"
    gaming_gamescope_nix="$(nix_bool "$gaming_gamescope")"
    gaming_vulkan_nix="$(nix_bool "$gaming_vulkan")"
    gaming_controller_nix="$(nix_bool "$gaming_controller")"
    gaming_mangohud_nix="$(nix_bool "$gaming_mangohud")"
    gaming_gamemode_nix="$(nix_bool "$gaming_gamemode")"
    gaming_launchers_nix="$(nix_bool "$gaming_launchers")"

    # Persist the dotfiles Git URL (if any) so the first graphical session
    # can clone and import it automatically — see
    # abora-session-setup.sh's import_dotfiles_once(). Written for every
    # edition, not just hyprland/other: the field is opt-in and empty by
    # default, so there's no reason to special-case which editions get it.
    if [[ -n "$dotfiles_url" ]]; then
        printf '%s\n' "$dotfiles_url" > "${root}/etc/nixos/abora/dotfiles-url"
        chmod 644 "${root}/etc/nixos/abora/dotfiles-url"
    fi
    printf '%s\n' "$abora_release_channel" > "${root}/etc/nixos/abora/channel"
    chmod 644 "${root}/etc/nixos/abora/channel"

    # Keep starter apps out of the default install closure. The selected IDs are
    # saved for abora-apps after first boot; only explicitly requested slow-path
    # installs are baked into apps.nix during nixos-install.
    write_starter_app_ids "${root}/etc/nixos/abora/apps.list"
    if [[ "$install_apps_during_setup" == "yes" ]]; then
        write_starter_app_exprs "${root}/etc/nixos/abora/apps.install.list"
    else
        : > "${root}/etc/nixos/abora/apps.install.list"
    fi
    render_apps_nix "${root}/etc/nixos/abora/apps.nix" \
        "${root}/etc/nixos/abora/apps.install.list" \
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
  anix.hostname = "${host_nix}";
  anix.timezone = "${timezone_nix}";
  anix.keyboard.console = "${keyboard_nix}";
  anix.keyboard.xkb = "${xkb_nix}";
  anix.desktop = "${desktop_nix}";
  anix.wallpaper = "${wallpaper_nix}";
}
EOF
        anix_import_line="    ./anix.nix"
    else
        rm -f "${cfgdir}/anix.nix"
        anix_import_line=""
    fi

    cat > "${cfgdir}/configuration.nix" <<EOF
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./abora/installed-base.nix
    ./abora/abora-options.nix
    ./abora/anix-module.nix
    ./abora/apps.nix
    ./abora-local.nix
${anix_import_line}
  ];
}
EOF

    cat > "${cfgdir}/abora-local.nix" <<EOF
{ pkgs, lib, config, ... }:
{
  abora.hostname = "${host_nix}";
  abora.locale = "${locale_nix}";
  abora.timezone = "${timezone_nix}";
  abora.keyboard.console = "${keyboard_nix}";
  abora.keyboard.xkb = "${xkb_nix}";
  abora.desktop = "${desktop_nix}";
  abora.wallpaper = "${wallpaper_nix}";
  abora.gpu = "${gpu_nix}";
  abora.disk = "${disk_nix}";
  abora.diskBiosSupport = ${disk_bios_support_nix};
  abora.stateVersion = "26.05";
  abora.gaming.enable = ${gaming_enabled_nix};
  abora.gaming.steam = ${gaming_steam_nix};
  abora.gaming.bigPictureShortcut = ${gaming_big_picture_nix};
  abora.gaming.bigPictureAutostart = ${gaming_autostart_nix};
  abora.gaming.gamescopeSession = ${gaming_gamescope_nix};
  abora.gaming.controllerSupport = ${gaming_controller_nix};
  abora.gaming.mangohud = ${gaming_mangohud_nix};
  abora.gaming.gamemode = ${gaming_gamemode_nix};
  abora.gaming.vulkanTools = ${gaming_vulkan_nix};
  abora.gaming.launchers = ${gaming_launchers_nix};
  abora.extras.diagnostics = false;
  abora.extras.virtualizationGuests = false;
  abora.extras.mobileBroadband = false;
  abora.user.name = "${user_nix}";
  abora.user.hashedPassword = "${user_password_hash}";

  networking.networkmanager.enable = lib.mkForce true;
  i18n.supportedLocales = [
    "\${config.abora.locale}/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

${root_pw_line}
}
EOF
    # abora.user.hashedPassword above (and users.users.root.hashedPassword,
    # when root_pw_line sets a separate root password) must not be
    # world-readable -- the default umask leaves a freshly-created file at
    # 0644, which would let any local user on the installed system read the
    # hash and run an offline attack against it, exactly what /etc/shadow's
    # own restrictive permissions exist to prevent. See the matching guard
    # at the top of abora-config.sh's reads.
    chmod 0600 "${cfgdir}/abora-local.nix"

    cat > "${cfgdir}/flake.nix" <<EOF
{
  description = "Abora installed system";
  # Keep installed systems on the rolling NixOS package set used by Abora
  # v4 alpha. Avoid path:/etc/... here: on NixOS that path resolves through
  # /etc/static, which pure flake evaluation rejects as an absolute path.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations = {
      abora = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
        ];
      };
    };
  };
}
EOF
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

# GPT partition-type GUID for a BIOS boot partition (what `parted ... set 1
# bios_grub on` in partition_disk() creates) — the standard type Limine
# (and GRUB) look for when installing the legacy-BIOS stage 1 to a GPT
# disk.
readonly BIOS_BOOT_PARTTYPE_GUID="21686148-6449-6e6f-744e-656564454649"

# Whether $disk has a BIOS-boot-typed partition — used by validate_boot()
# to catch a `limine bios-install` that failed silently. See
# find_existing_esp() for why lsblk -P (not columnar -o output) is used.
_has_bios_boot_partition() {
    local disk="$1"
    lsblk -Pnb -o NAME,PARTTYPE,TYPE "$disk" 2>/dev/null | \
        awk -v bios="$BIOS_BOOT_PARTTYPE_GUID" "$_lsblk_pairs_awk_prelude"'
        {
            parse_pairs($0)
            if (f["TYPE"] == "part" && tolower(f["PARTTYPE"]) == bios) { found = 1; exit }
        }
        END { exit !found }'
}

# Sanity check that nixos-install actually produced a bootable ESP —
# either a generic UEFI fallback (BOOTX64.EFI) or a Limine EFI/BIOS binary —
# before declaring the install a success. A missing bootloader here means a
# silent, unbootable install, which is worse than failing loudly now.
#
# The BIOS half of this is deliberately more than a file-existence check:
# limine-install.py copies limine-bios.sys into /mnt/boot *before* it runs
# `limine bios-install <device>` — that copy happens unconditionally,
# regardless of whether the bios-install step that actually writes to the
# disk's boot sector/BIOS-boot partition succeeds, and nixpkgs never checks
# that subprocess's exit code (confirmed directly: `limine bios-install`
# fails outright, exit 1, on a GPT disk with no BIOS-boot partition). So
# the file's mere presence proves nothing about whether BIOS boot would
# actually work — only that biosSupport was requested. When BIOS support
# was requested for this install (install_disk_mode != "existing"; see
# diskBiosSupport), this also confirms the BIOS-boot partition
# bios-install depends on is still really there.
validate_boot() {
    local has_efi=0 has_bios_file=0

    [[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]] && has_efi=1
    find /mnt/boot -maxdepth 3 \
        \( -iname '*limine*.efi' -o -iname 'limine-bios.sys' \) 2>/dev/null \
        | grep -q . && has_bios_file=1

    if [[ "$has_efi" -eq 0 && "$has_bios_file" -eq 0 ]]; then
        die "Bootloader not found after nixos-install. See ${install_log}."
    fi

    if [[ "$install_disk_mode" != "existing" && -n "$disk" ]] \
        && ! _has_bios_boot_partition "$disk"; then
        die "BIOS boot was requested but ${disk} has no BIOS-boot partition — limine bios-install likely failed silently. See ${install_log}."
    fi
}

# Limine's config uses indentation-as-nesting ("/"-prefixed lines whose
# leading-slash count is the nesting depth) instead of a structured format,
# so finding "the first actual bootable entry" means walking that nesting
# by hand: tracks a stack of titles by depth, and an entry only counts once
# it's seen both a recognized `protocol:` and a `kernel_path:`/`path:` line
# at the same nesting level (a bare submenu heading is not itself bootable).
limine_first_bootable_entry() {
    local conf="$1"
    awk '
        function escape_entry(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/\//, "\\/", s)
            gsub(/#/, "\\#", s)
            return s
        }
        function finish_entry(    i, path) {
            if (entry_depth > 0 && protocol != "" && boot_path != "") {
                path = ""
                for (i = 1; i <= entry_depth; i++) {
                    if (stack[i] == "") {
                        continue
                    }
                    path = path (path == "" ? "" : "/") escape_entry(stack[i])
                }
                print path
                found = 1
                exit
            }
        }
        /^[[:space:]]*\/+/ {
            finish_entry()
            line = $0
            sub(/^[[:space:]]*/, "", line)
            match(line, /^\/+/)
            depth = RLENGTH
            title = substr(line, depth + 1)
            if (substr(title, 1, 1) == "+") {
                title = substr(title, 2)
            }
            sub(/[[:space:]]+$/, "", title)
            stack[depth] = title
            for (i = depth + 1; i <= 32; i++) {
                delete stack[i]
            }
            entry_depth = depth
            protocol = ""
            boot_path = ""
            next
        }
        /^[[:space:]]*protocol:[[:space:]]*(linux|limine|multiboot|multiboot1|multiboot2)[[:space:]]*$/ {
            protocol = $0
            next
        }
        /^[[:space:]]*(kernel_path|path):[[:space:]]*/ {
            boot_path = $0
            next
        }
        END {
            if (!found) {
                finish_entry()
            }
        }
    ' "$conf"
}

# NixOS's Limine generator doesn't always set default_entry to something
# that will actually boot unattended (nested submenus, multiple stanzas),
# so this pins default_entry to the first real bootable entry found above,
# sets a short timeout, and disables the config editor — a fresh install
# should reach a login prompt on its own without the user ever seeing (or
# needing to touch) the boot menu.
repair_limine_boot_menu() {
    local root="${1:-/mnt}"
    local conf="${root}/boot/limine/limine.conf"
    local entry tmp

    [[ -f "$conf" ]] || return 0

    entry="$(limine_first_bootable_entry "$conf" | head -n 1 || true)"
    [[ -n "$entry" ]] || die "Limine config has no bootable entry. See ${install_log}."

    tmp="${conf}.abora-tmp"
    {
        printf 'timeout: 5\n'
        printf 'default_entry: %s\n' "$entry"
        printf 'editor_enabled: no\n'
        awk 'tolower($0) !~ /^[[:space:]]*(timeout|default_entry|editor_enabled)[[:space:]]*:/' "$conf"
    } > "$tmp"
    mv "$tmp" "$conf"
    sync || true
    printf '[installer] repaired limine default_entry=%s timeout=5\n' "$entry" >>"$install_log"
}

target_has_system_profile() {
    local root="${1:-/mnt}"
    local system_profile="${root}/nix/var/nix/profiles/system"

    [[ -e "$system_profile" || -L "$system_profile" ]] && return 0
    compgen -G "${root}/nix/var/nix/profiles/system-*-link" >/dev/null 2>&1 && return 0
    return 1
}

target_has_installed_boot_path() {
    local root="${1:-/mnt}"

    [[ -f "${root}/boot/EFI/BOOT/BOOTX64.EFI" ]] && return 0
    find "${root}/boot" -maxdepth 3 \
        \( -iname '*limine*.efi' -o -iname 'limine-bios.sys' \) 2>/dev/null \
        | grep -q .
}

validate_installed_system() {
    local root="${1:-/mnt}"
    local failed=0
    local system_profile="${root}/nix/var/nix/profiles/system"

    [[ -e "${root}/etc/NIXOS" ]] || {
        printf 'Missing installed marker: %s\n' "${root}/etc/NIXOS" >>"$install_log"
        failed=1
    }
    target_has_system_profile "$root" || target_has_installed_boot_path "$root" || {
        printf 'Missing installed system profile or boot path: %s\n' "$system_profile" >>"$install_log"
        failed=1
    }
    [[ -e "${root}/etc/nixos/configuration.nix" ]] || {
        printf 'Missing installed config: %s\n' "${root}/etc/nixos/configuration.nix" >>"$install_log"
        failed=1
    }
    [[ -e "${root}/etc/nixos/abora-local.nix" ]] || {
        printf 'Missing installed local config: %s\n' "${root}/etc/nixos/abora-local.nix" >>"$install_log"
        failed=1
    }

    if (( failed == 0 )); then
        mkdir -p "${root}/etc/abora"
        {
            printf 'installed_at=%s\n' "$(date -Iseconds 2>/dev/null || date)"
            printf 'root_label=ABORA_ROOT\n'
            printf 'desktop=%s\n' "$desktop_profile"
            printf 'tinypm=present\n'
            printf 'anix=%s\n' "$anix_enabled"
        } > "${root}/etc/abora/INSTALLED"
        return 0
    fi

    die "nixos-install finished, but the target does not look installed. See ${install_log}."
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

register_efi_boot_entry() {
    # Skip on BIOS-only systems — efibootmgr only works under UEFI.
    [[ -d /sys/firmware/efi ]] || return 0
    command -v efibootmgr >/dev/null 2>&1 || return 0

    # Remove any stale Abora entries so we don't accumulate duplicates.
    local num
    while IFS= read -r num; do
        efibootmgr --delete-bootnum --bootnum "$num" >/dev/null 2>&1 || true
    done < <(efibootmgr 2>/dev/null | grep -oP '(?<=Boot)[0-9A-F]{4}(?=\*? Abora OS)' || true)

    # Create the new entry (EFI partition is always partition 2).
    efibootmgr \
        --create --disk "$disk" --part 2 \
        --label "Abora OS" \
        --loader '\EFI\BOOT\BOOTX64.EFI' \
        >/dev/null 2>&1 || return 0

    # Move it to the front of the NVRAM boot order.
    local new_num current_order
    new_num="$(efibootmgr 2>/dev/null \
        | grep -oP '(?<=Boot)[0-9A-F]{4}(?=\*? Abora OS)' | head -1 || true)"
    [[ -n "$new_num" ]] || return 0
    current_order="$(efibootmgr 2>/dev/null \
        | grep '^BootOrder:' | sed 's/BootOrder: //' || true)"
    if [[ -n "$current_order" ]]; then
        efibootmgr --bootorder "${new_num},${current_order}" >/dev/null 2>&1 || true
    else
        efibootmgr --bootorder "$new_num" >/dev/null 2>&1 || true
    fi
    ok "EFI NVRAM boot entry registered (Boot${new_num} → first)"
}

cleanup_target() {
    sync || true
    umount -R /mnt >/dev/null 2>&1 || true
}

eject_media() {
    command -v eject >/dev/null 2>&1 || return 0
    local d real fstype type
    for d in /dev/sr[0-9]* /dev/cdrom /dev/dvd /dev/disk/by-label/NIXOS_ISO /dev/disk/by-label/ABORA_ISO /dev/disk/by-label/ABORA_OS; do
        [[ -e "$d" ]] || continue
        real="$(readlink -f "$d" 2>/dev/null || printf '%s\n' "$d")"
        type="$(lsblk -dnro TYPE "$real" 2>/dev/null | head -n 1 || true)"
        fstype="$(lsblk -dnro FSTYPE "$real" 2>/dev/null | head -n 1 || true)"
        [[ "$real" == /dev/sr* || "$type" == "rom" || "$fstype" == "iso9660" ]] || continue
        eject "$d" >/dev/null 2>&1 && return 0
    done
    return 0
}

ensure_root_label() {
    local device="$1"
    local current=""
    local n

    [[ -b "$device" ]] || return 1

    for n in 1 2 3 4 5; do
        udevadm settle >>"$install_log" 2>&1 || true
        current="$(blkid -s LABEL -o value "$device" 2>/dev/null | head -n 1 || true)"
        [[ "$current" == "ABORA_ROOT" ]] && return 0

        if command -v e2label >/dev/null 2>&1; then
            e2label "$device" ABORA_ROOT >>"$install_log" 2>&1 || true
        elif command -v tune2fs >/dev/null 2>&1; then
            tune2fs -L ABORA_ROOT "$device" >>"$install_log" 2>&1 || true
        fi

        sync || true
        sleep 1
    done

    current="$(blkid -s LABEL -o value "$device" 2>/dev/null | head -n 1 || true)"
    [[ "$current" == "ABORA_ROOT" ]]
}

live_media_present() {
    local d real fstype type
    for d in /dev/sr[0-9]* /dev/cdrom /dev/dvd /dev/disk/by-label/NIXOS_ISO /dev/disk/by-label/ABORA_ISO /dev/disk/by-label/ABORA_OS; do
        [[ -e "$d" ]] || continue
        real="$(readlink -f "$d" 2>/dev/null || printf '%s\n' "$d")"
        type="$(lsblk -dnro TYPE "$real" 2>/dev/null | head -n 1 || true)"
        fstype="$(lsblk -dnro FSTYPE "$real" 2>/dev/null | head -n 1 || true)"
        [[ "$real" == /dev/sr* || "$type" == "rom" || "$fstype" == "iso9660" ]] && return 0
    done
    return 1
}

request_reboot() {
    local virt=""
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    if live_media_present; then
        printf '\n  %bLive install media is still attached.%b\n' "$CY" "$R"
        printf '  %bPowering off instead so Abora does not fall back into the live ISO again.%b\n' "$CI" "$R"
        if [[ "$virt" == "qemu" || "$virt" == "kvm" ]]; then
            printf '  On the host, run %bmake qemu-disk%b to boot the installed system.\n' "${B}${CW}" "$R"
        else
            printf '  Remove the USB/DVD, then boot from the installed disk.\n'
        fi
        request_poweroff
        return
    fi
    if [[ "$virt" == "qemu" || "$virt" == "kvm" ]]; then
        printf '\n  %bQEMU/KVM detected: powering off instead of rebooting into the ISO again.%b\n' "$CI" "$R"
        printf '  On the host, run %bmake qemu-disk%b to boot the installed system.\n' "${B}${CW}" "$R"
        request_poweroff
        return
    fi

    printf '\n  %bRebooting now...%b\n' "$CI" "$R"
    sync || true

    systemctl reboot --no-wall >/dev/null 2>&1 || true
    sleep 4
    systemctl reboot --force --force >/dev/null 2>&1 || true
    sleep 2
    reboot -f >/dev/null 2>&1 || true
    sleep 2

    if [[ -w /proc/sysrq-trigger ]]; then
        printf b > /proc/sysrq-trigger 2>/dev/null || true
    fi

    err "Automatic reboot did not start."
    printf '  %bUse the VM power menu, or close QEMU and run %bmake qemu-disk%b.%b\n' "${D}${CG}" "${B}${CW}" "${D}${CG}" "$R"
    pause
    exec bash --login </dev/tty >/dev/tty 2>/dev/tty || exit 1
}

request_poweroff() {
    printf '\n  %bPowering off now...%b\n' "$CI" "$R"
    sync || true

    systemctl poweroff --no-wall >/dev/null 2>&1 || true
    sleep 4
    systemctl poweroff --force --force >/dev/null 2>&1 || true
    sleep 2
    poweroff -f >/dev/null 2>&1 || true
    sleep 2

    err "Automatic poweroff did not start."
    pause
    exec bash --login </dev/tty >/dev/tty 2>/dev/tty || exit 1
}

progress_line() {
    local percent="$1" label="$2" width=44 filled empty
    filled=$(( percent * width / 100 ))
    empty=$(( width - filled ))
    printf '  '
    printf '%b' "$CW"
    printf '%*s' "$filled" '' | tr ' ' '█'
    printf '%b' "$CG"
    printf '%*s' "$empty" '' | tr ' ' '░'
    printf '%b  %b%3d%%%b  %b%s%b\n' "$R" "${B}${CS}" "$percent" "$R" "$CC" "$label" "$R"
}

draw_install_title() {
    printf '  %b┌────────────────────────────────────────────────────────┐%b\n' "$CF" "$R"
    printf '  %b│%b  %bABORA OS%b  %b▸%b  %-40s%b│%b\n' \
        "$CF" "$R" "${B}${CW}" "$R" "${D}${CG}" "Installing ${release_short}" "$R" "$CF" "$R"
    printf '  %b└────────────────────────────────────────────────────────┘%b\n' "$CF" "$R"
}

monotonic_seconds() {
    local uptime
    if [[ -r /proc/uptime ]]; then
        read -r uptime _ < /proc/uptime
        printf '%s\n' "${uptime%%.*}"
    else
        date +%s 2>/dev/null || printf '0\n'
    fi
}

format_elapsed() {
    local seconds="$1"
    (( seconds < 0 )) && seconds=0
    printf '%02d:%02d' "$((seconds / 60))" "$((seconds % 60))"
}

file_size() {
    local file="$1"
    stat -c '%s' "$file" 2>/dev/null || wc -c < "$file" 2>/dev/null || printf '0'
}

# nixos-install gives no structured progress output, just a raw build log,
# so this guesses a human-readable stage by pattern-matching the last few
# lines — purely cosmetic (drives the "Status" line in draw_install_status),
# never affects whether the install itself succeeds or fails.
detect_install_activity() {
    local file="$1"
    [[ -s "$file" ]] || {
        printf 'Working'
        return 0
    }

    if tail -n 24 "$file" 2>/dev/null | grep -Eq "building '/nix/store/.*\\.drv'|building /nix/store/.*\\.drv"; then
        printf 'Building Nix system derivations locally'
    elif tail -n 24 "$file" 2>/dev/null | grep -Eq '(^|\]| )Compiling |Running phase: (buildPhase|configurePhase)|build flags:|ninja-[0-9]|mesonConfigurePhase|Checking for (function|type|header)|Header ".*" has symbol'; then
        printf 'Building packages from source; this can take a while in a VM'
    elif tail -n 24 "$file" 2>/dev/null | grep -Eq 'copying path|copying .*from|these [0-9]+ paths will be fetched|downloading|fetching'; then
        printf 'Downloading/copying packages from cache'
    elif tail -n 24 "$file" 2>/dev/null | grep -Eq 'installing the boot loader|setting up /etc|building the system configuration|updating /boot'; then
        printf 'Installing system files'
    elif tail -n 24 "$file" 2>/dev/null | grep -Eq -- '-> /nix/store/|/nix/store/.*->|creating symlinks|setting up tmpfiles|activating the configuration'; then
        printf 'Activating system — almost done'
    elif tail -n 24 "$file" 2>/dev/null | grep -Eq 'setting up GNOME|gdm|gnome-shell|dconf|glib-compile'; then
        printf 'Configuring GNOME desktop'
    else
        printf 'Working'
    fi
}

process_activity() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || {
        printf 'starting'
        return 0
    }
    ps -o comm= -p "$pid" 2>/dev/null | tr -d '\n' || printf 'running'
}

truncate_line() {
    local text="$1" width="$2"
    text="${text//$'\t'/  }"
    text="${text//$'\r'/}"
    if (( ${#text} > width )); then
        printf '%s...\n' "${text:0:$((width - 3))}"
    else
        printf '%s\n' "$text"
    fi
}

draw_log_tail() {
    local file="$1" lines="${2:-8}" width=68 line count=0
    printf '  %bLog output%b\n' "${B}${CS}" "$R"
    printf '  %b┌────────────────────────────────────────────────────────────┐%b\n' "$CF" "$R"
    if [[ -s "$file" ]]; then
        while IFS= read -r line; do
            line="$(truncate_line "$line" "$width")"
            printf '  %b│%b %-58.58s %b│%b\n' "$CF" "$R" "$line" "$CF" "$R"
            count=$((count + 1))
        done < <(tail -n "$lines" "$file" 2>/dev/null)
    fi
    while (( count < lines )); do
        printf '  %b│%b %-58s %b│%b\n' "$CF" "$R" "" "$CF" "$R"
        count=$((count + 1))
    done
    printf '  %b└────────────────────────────────────────────────────────────┘%b\n' "$CF" "$R"
}

draw_install_status() {
    local percent="$1" stage="$2" pid="$3" started="$4" status="${5:-Working}" idle="${6:-0}"
    local now elapsed proc
    now="$(monotonic_seconds)"
    elapsed=$((now - started))
    proc="$(process_activity "$pid")"

    printf '\033[2J\033[H'
    printf '\n'
    draw_install_title
    printf '\n'
    progress_line "$percent" "$stage"
    printf '\n'
    printf '  %bStatus%b   %s\n' "$CI" "$R" "$status"
    printf '  %bElapsed%b  %s   %bPID%b  %s   %bProcess%b  %s\n' \
        "$CI" "$R" "$(format_elapsed "$elapsed")" "$CI" "$R" "$pid" "$CI" "$R" "$proc"
    printf '  %bLog age%b  %s since last output\n' "$CI" "$R" "$(format_elapsed "$idle")"
    printf '\n'
    draw_log_tail "$install_log" 8
    printf '\n'
    printf '  %bNix can sit on one build step for many minutes in a VM. If Log age keeps resetting, it is still alive.%b\n' "${D}${CG}" "$R"
}

# Runs a long-lived install command in the background and redraws a status
# panel every 2s while it's alive. Distinguishes "quiet but still working"
# from "actually stuck" by tracking the install log's file size rather than
# just wall-clock elapsed time — Nix can legitimately sit on one derivation
# for many minutes, so only genuine log silence (idle_timeout, 30 min) or an
# absolute cap (hard_timeout, 90 min) ever kills the command.
run_with_log_panel() {
    local percent="$1" stage="$2"
    shift 2

    local warn_after=480 hard_timeout=5400 idle_timeout=1800
    local started pid rc now elapsed status last_size current_size last_change idle
    started="$(monotonic_seconds)"
    last_change="$started"
    last_size="$(file_size "$install_log")"
    status="Started"
    draw_install_status "$percent" "$stage" "-" "$started" "$status" 0

    "$@" >>"$install_log" 2>&1 &
    pid=$!

    while kill -0 "$pid" >/dev/null 2>&1; do
        now="$(monotonic_seconds)"
        elapsed=$((now - started))
        current_size="$(file_size "$install_log")"
        if [[ "$current_size" != "$last_size" ]]; then
            last_size="$current_size"
            last_change="$now"
        fi
        idle=$((now - last_change))
        status="$(detect_install_activity "$install_log")"
        if (( idle >= 120 )); then
            status="Working, no new log output for $(format_elapsed "$idle")"
        elif (( elapsed >= 900 )); then
            status="${status} after 15 minutes"
        elif (( elapsed >= warn_after )); then
            status="${status} for over 8 minutes"
        elif (( elapsed >= 300 )); then
            status="${status} after 5 minutes"
        fi
        draw_install_status "$percent" "$stage" "$pid" "$started" "$status" "$idle"
        if (( idle >= idle_timeout )); then
            printf '\n  %bInstall command produced no new log output for 30 minutes; stopping it.%b\n' "$CY" "$R"
            kill "$pid" >/dev/null 2>&1 || true
            sleep 5
            kill -KILL "$pid" >/dev/null 2>&1 || true
            wait "$pid" >/dev/null 2>&1 || true
            draw_install_status "$percent" "$stage" "$pid" "$started" "Stopped after 30 minutes of no log output" "$idle"
            return 124
        fi
        if (( elapsed >= hard_timeout )); then
            printf '\n  %bInstall command exceeded 90 minutes; stopping it.%b\n' "$CY" "$R"
            kill "$pid" >/dev/null 2>&1 || true
            sleep 5
            kill -KILL "$pid" >/dev/null 2>&1 || true
            wait "$pid" >/dev/null 2>&1 || true
            draw_install_status "$percent" "$stage" "$pid" "$started" "Stopped after 90 minute timeout" "$idle"
            return 124
        fi
        sleep 2
    done

    wait "$pid"
    rc=$?
    if (( rc == 0 )); then
        draw_install_status "$percent" "$stage" "$pid" "$started" "Complete" 0
    else
        draw_install_status "$percent" "$stage" "$pid" "$started" "Failed" 0
    fi
    return "$rc"
}

run_install() {
    printf '\033[2J\033[H'
    printf '\n'
    draw_install_title
    printf '  %bInstalling %s%b\n' "$CC" "$release_name" "$R"
    printf '  %bLog: %s%b\n' "${D}${CG}" "$install_log" "$R"
    printf '\n'

    : > "$install_log"
    log_network_snapshot

    progress_line 5 "Starting"
    msg "Running final safety checks…"
    if ! check_install_environment final >>"$install_log" 2>&1; then
        die "Preflight failed before partitioning. See ${install_log}."
    fi

    msg "Preparing target disk…"
    if [[ "$install_disk_mode" == "existing" ]]; then
        if ! partition_disk_existing; then die "Formatting the selected partition failed. See ${install_log}."; fi
    else
        if ! partition_disk; then die "Partitioning failed. See ${install_log}."; fi
    fi
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

    local nix_config
    nix_config="$(printf '%s\n' \
        "experimental-features = nix-command flakes" \
        "substituters = https://cache.nixos.org" \
        "trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
        "connect-timeout = 10" \
        "stalled-download-timeout = 120" \
        "fallback = true" \
        "builders-use-substitutes = true" \
        "max-jobs = 2" \
        "cores = 2" \
        "max-substitution-jobs = 32" \
        "http-connections = 32")"

    msg "Running nixos-install…"
    log_network_snapshot
    # --flake, not the legacy NIX_PATH+configuration.nix path this used to
    # take: that legacy evaluation is structurally different from the
    # flake-based nixosSystem { ... } that actually built this live ISO
    # (nix/profiles/live.nix, via flake.nix's mkLive), even when pointed at
    # the identical nixpkgs tree via $nixpkgs. That divergence gives
    # out-of-tree packages -- notably abora-plan-tool and
    # abora-update-resolver, both Native AOT dotnet builds not available on
    # any binary cache -- a different derivation hash than the copies
    # already sitting fully built in this live system's own /nix/store, so
    # nixos-install rebuilt them from source instead of reusing them. That
    # rebuild (dotnetBuildHook running a real AOT compile) is expensive
    # enough to crash outright in a memory-constrained install VM. Building
    # through the same flake shape this ISO was built from keeps install and
    # update evaluation consistent enough for custom Abora packages to be
    # reused whenever the Nixpkgs input still matches.
    if ! run_with_log_panel 70 "Installing system" \
        env "NIX_CONFIG=${nix_config}" \
        nixos-install --root /mnt --no-root-passwd --flake "/mnt/etc/nixos#abora"; then
        die "nixos-install failed. See ${install_log}."
    fi
    progress_line 90 "System installed"

    validate_installed_system "/mnt"
    repair_limine_boot_menu "/mnt"
    validate_boot

    msg "Registering EFI boot entry…"
    register_efi_boot_entry

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
    printf '\n\n'
    printf '  %b┌────────────────────────────────────────────────────────┐%b\n' "$CF" "$R"
    printf '  %b│%b  %b✓  Installation Complete%b                               %b│%b\n' \
        "$CF" "$R" "${B}${CP}" "$R" "$CF" "$R"
    printf '  %b│%b  %b%-52s%b  %b│%b\n' \
        "$CF" "$R" "$CS" "${release_name} is installed" "$R" "$CF" "$R"
    printf '  %b└────────────────────────────────────────────────────────┘%b\n' "$CF" "$R"
    printf '\n'
    if [[ "$starter_apps_bundle" != "none" && "$install_apps_during_setup" != "yes" ]]; then
        printf '  %b·%b  Apps: %b%s%b saved — run %babora apps rebuild%b after first boot.\n' \
            "$CI" "$R" "$CC" "$starter_apps_label" "$R" "${B}${CW}" "$R"
        printf '\n'
    fi
    printf '  %b·%b  QEMU users: run %bmake qemu-disk%b (not make qemu).\n' "$CI" "$R" "${B}${CW}" "$R"
    printf '  %b·%b  Real hardware: remove the USB/DVD before rebooting.\n' "$CI" "$R"
    printf '\n'
    printf '  %bLogs:%b  %s\n' "$CG" "$R" "$install_log"
    printf '\n'

    menu "What would you like to do?" \
        "Power off|Recommended — detach ISO, then boot the installed disk" \
        "Reboot into Abora OS|Only after detaching the live ISO" \
        "Stay in live shell|Remain in the live environment"

    case "$MENU_RESULT" in
        0)
            cleanup_target
            eject_media
            request_poweroff
            ;;
        1)
            cleanup_target
            eject_media
            printf '\n'
            printf '  %b⚠%b  Detach the Abora ISO before the VM restarts:\n' "$CY" "$R"
            printf '  %b·%b  QEMU: close and launch with disk image, not ISO\n' "$CG" "$R"
            printf '  %b·%b  VBox/VMware: Storage → remove ISO from virtual drive\n' "$CG" "$R"
            printf '  %b·%b  Real hardware: physically remove the USB/DVD\n' "$CG" "$R"
            printf '\n'
            printf '  %bPress Enter when ISO is detached (auto in 30 s) …%b ' "$CW" "$R"
            read -rt 30 _ </dev/tty 2>/dev/null || true
            printf '\n'
            if live_media_present; then
                printf '  %bLive media still attached — falling back to poweroff.%b\n' "$CY" "$R"
            fi
            request_reboot
            ;;
        2)
            printf '\nRemaining in live shell.\n\n'
            exec bash --login </dev/tty >/dev/tty 2>/dev/tty || true
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  RECONFIG MODE
# ═══════════════════════════════════════════════════════════════════════════════
# Entered via `abora-install --reconfig` on an already-installed system (see
# `abora setup`) — reuses the same step_* wizard pages to collect new values,
# but instead of partitioning/nixos-install, run_reconfig() patches the
# existing abora-local.nix/anix.nix in place with sed and runs
# `nixos-rebuild switch`. read_current_config()/read_anix_config() seed the
# wizard's fields from what's already on disk so unfilled fields don't
# revert to installer defaults.

read_current_config() {
    local f="/etc/nixos/abora-local.nix"
    [[ -f "$f" ]] || return 0
    local v
    v="$(sed -nE 's/^[[:space:]]*networking\.hostName *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && hostname_value="$v"
    v="$(sed -nE 's/^[[:space:]]*i18n\.defaultLocale *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && locale_value="$v"
    v="$(sed -nE 's/^[[:space:]]*time\.timeZone *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && timezone_value="$v"
    v="$(sed -nE 's/^[[:space:]]*console\.keyMap *= *"([^"]+)".*/\1/p' "$f" | head -1)"
    [[ -n "$v" ]] && keyboard_value="$v"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.enable *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_enabled="yes"
    [[ "$v" == "false" ]] && gaming_enabled="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.steam *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_steam="yes"
    [[ "$v" == "false" ]] && gaming_steam="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.bigPictureShortcut *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_big_picture="yes"
    [[ "$v" == "false" ]] && gaming_big_picture="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.bigPictureAutostart *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_autostart="yes"
    [[ "$v" == "false" ]] && gaming_autostart="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.gamescopeSession *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_gamescope="yes"
    [[ "$v" == "false" ]] && gaming_gamescope="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.vulkanTools *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_vulkan="yes"
    [[ "$v" == "false" ]] && gaming_vulkan="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.controllerSupport *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_controller="yes"
    [[ "$v" == "false" ]] && gaming_controller="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.mangohud *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_mangohud="yes"
    [[ "$v" == "false" ]] && gaming_mangohud="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.gamemode *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_gamemode="yes"
    [[ "$v" == "false" ]] && gaming_gamemode="no"
    v="$(sed -nE 's/^[[:space:]]*abora\.gaming\.launchers *= *(true|false).*/\1/p' "$f" | head -1)"
    [[ "$v" == "true" ]] && gaming_launchers="yes"
    [[ "$v" == "false" ]] && gaming_launchers="no"
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
    write_starter_app_ids "${cfgdir}/abora/apps.list"
    write_starter_app_exprs "${cfgdir}/abora/apps.install.list"
    render_apps_nix "${cfgdir}/abora/apps.nix" "${cfgdir}/abora/apps.install.list"
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
            -e "s|i18n\.defaultLocale *= *\"[^\"]*\"|i18n.defaultLocale = \"${locale_value}\"|" \
            -e "s|time\.timeZone *= *\"[^\"]*\"|time.timeZone = \"${timezone_value}\"|" \
            -e "s|console\.keyMap *= *\"[^\"]*\"|console.keyMap = \"${keyboard_value}\"|" \
            -e "s|abora\.desktop *= *\"[^\"]*\"|abora.desktop = \"${desktop_profile}\"|" \
            -e "s|abora\.gpu *= *\"[^\"]*\"|abora.gpu = \"${gpu_value}\"|" \
            "$abora_local" 2>/dev/null || true
        if [[ -n "$user_password_hash" ]]; then
            local root_pw_patch="${root_password_hash:-!}"
            sed -i \
                -e "s|abora\.user\.hashedPassword *= *\"[^\"]*\"|abora.user.hashedPassword = \"${user_password_hash}\"|" \
                -e "s|users\.users\.root\.hashedPassword *= *\"[^\"]*\"|users.users.root.hashedPassword = \"${root_pw_patch}\"|" \
                "$abora_local" 2>/dev/null || true
        fi
        set_nix_bool_assignment "$abora_local" "abora.gaming.enable" "$gaming_enabled"
        set_nix_bool_assignment "$abora_local" "abora.gaming.steam" "$gaming_steam"
        set_nix_bool_assignment "$abora_local" "abora.gaming.bigPictureShortcut" "$gaming_big_picture"
        set_nix_bool_assignment "$abora_local" "abora.gaming.bigPictureAutostart" "$gaming_autostart"
        set_nix_bool_assignment "$abora_local" "abora.gaming.gamescopeSession" "$gaming_gamescope"
        set_nix_bool_assignment "$abora_local" "abora.gaming.controllerSupport" "$gaming_controller"
        set_nix_bool_assignment "$abora_local" "abora.gaming.mangohud" "$gaming_mangohud"
        set_nix_bool_assignment "$abora_local" "abora.gaming.gamemode" "$gaming_gamemode"
        set_nix_bool_assignment "$abora_local" "abora.gaming.vulkanTools" "$gaming_vulkan"
        set_nix_bool_assignment "$abora_local" "abora.gaming.launchers" "$gaming_launchers"
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
#  RELEASE INSTALLER FLOW
# ═══════════════════════════════════════════════════════════════════════════════

release_header() {
    local title="${1:-Install Abora OS}"
    printf '\033[2J\033[H'
    printf '\n'
    printf '  %b┌────────────────────────────────────────────────────────┐%b\n' "$CF" "$R"
    printf '  %b│%b  %bABORA OS%b  %b▸%b  %b%-40s%b│%b\n' \
        "$CF" "$R" "${B}${CW}" "$R" "$CI" "$release_short" "$R" "$CF" "$R"
    printf '  %b└────────────────────────────────────────────────────────┘%b\n' "$CF" "$R"
    printf '\n'
    printf '  %b%s%b\n' "${B}${CS}" "$title" "$R"
    rule
    printf '\n'
}

open_live_terminal() {
    printf '\n'
    ok "Opening a live terminal. Run abora-install to return."
    printf '\n'
    exec bash --login </dev/tty >/dev/tty 2>/dev/tty || exit 0
}

debug_tools_menu() {
    while true; do
        release_header "Debug Tools"
        msg "Use these when the installer acts weird or you need logs before installing."
        msg "Nothing here partitions or installs Abora."
        printf '\n'

        menu "Debug issues" \
            "View installer log|Tail /tmp/abora-install.log" \
            "View config log|Tail /tmp/abora-config.log" \
            "Run hardware test|Check disks, GPU, Wi-Fi, firmware, and boot mode" \
            "Create support report|Collect a redacted archive for bug reports" \
            "Network tools|Open nmtui for Wi-Fi or Ethernet setup" \
            "Open terminal|Drop to a live shell" \
            "Back|Return to welcome"

        case "$MENU_RESULT" in
            0)
                release_header "Installer Log"
                if [[ -f "$install_log" ]]; then
                    draw_log_tail "$install_log" 22
                else
                    warn "No installer log yet at ${install_log}."
                fi
                pause
                ;;
            1)
                release_header "Config Log"
                if [[ -f "$config_log" ]]; then
                    draw_log_tail "$config_log" 22
                else
                    warn "No config log yet at ${config_log}."
                fi
                pause
                ;;
            2)
                release_header "Hardware Test"
                if command -v abora >/dev/null 2>&1; then
                    abora hardware-test --with-report || true
                elif command -v abora-hardware-test >/dev/null 2>&1; then
                    abora-hardware-test --with-report || true
                else
                    warn "Hardware test command is not available on this live image."
                fi
                pause
                ;;
            3)
                release_header "Support Report"
                if command -v abora >/dev/null 2>&1; then
                    abora support-report || true
                elif command -v abora-support-report >/dev/null 2>&1; then
                    abora-support-report || true
                else
                    warn "Support report command is not available on this live image."
                fi
                pause
                ;;
            4)
                release_header "Network Tools"
                network_tools_menu no
                ;;
            5)
                open_live_terminal
                ;;
            6)
                return 0
                ;;
        esac
    done
}

source_build_menu() {
    release_header "Build From Source"
    msg "Advanced path for people who want to compile Abora themselves."
    msg "Recommended: build on an installed Linux/NixOS workstation, not inside this live ISO."
    printf '\n'
    printf '  %bRequired%b\n' "${B}${CS}" "$R"
    printf '  %b·%b Nix with flakes and nix-command enabled\n' "$CI" "$R"
    printf '  %b·%b Git and enough disk space for Nix builds\n' "$CI" "$R"
    printf '  %b·%b QEMU if you want to boot-test locally\n' "$CI" "$R"
    printf '\n'
    printf '  %bCommands%b\n' "${B}${CS}" "$R"
    printf '  %bgit clone https://github.com/AnimatedGTVR/Abora-OS.git%b\n' "$CW" "$R"
    printf '  %bcd Abora-OS%b\n' "$CW" "$R"
    printf '  %bnix build .#nixosConfigurations.abora.config.system.build.toplevel%b\n' "$CW" "$R"
    printf '\n'
    printf '  %bFriendly wrapper%b\n' "${B}${CS}" "$R"
    printf '  %babora build --from-source%b\n' "$CW" "$R"
    printf '\n'
    printf '  %bISO build commands%b\n' "${B}${CS}" "$R"
    printf '  %bmake doctor%b\n' "$CW" "$R"
    printf '  %bmake iso%b        %b# default Cosmic edition%b\n' "$CW" "$D$CG" "$R"
    printf '  %bmake iso-all%b    %b# all five editions%b\n' "$CW" "$D$CG" "$R"
    printf '\n'
    printf '  %bTip%b  Use the terminal option if you want to clone/build manually now.\n' "${B}${CY}" "$R"
    printf '\n'

    menu "Source build" \
        "Open terminal|Run these commands yourself" \
        "Back|Return to welcome"
    [[ "$MENU_RESULT" -eq 0 ]] && open_live_terminal
}

release_welcome() {
    while true; do
        release_header "Welcome"
        msg "Fast release installer. Pick the basics; Abora handles the rest."
        msg "This installer erases one selected disk and installs the ${desktop_label} edition."
        printf '\n'
        menu "Start" \
            "Install Abora OS|Guided install to a disk" \
            "Open terminal|Drop to the live environment shell" \
            "Debug installer|View logs, run hardware tests, or collect a report" \
            "Build from source|Advanced commands for compiling Abora yourself" \
            "Exit|Stay in the live shell"
        case "$MENU_RESULT" in
            0) return 0 ;;
            1) open_live_terminal ;;
            2) debug_tools_menu ;;
            3) source_build_menu ;;
            4)
                printf '\n'
                ok "Live shell selected. Run abora-install to return."
                exit 0
                ;;
        esac
    done
}

release_network() {
    release_header "Network"
    start_nm || true
    if net_connected; then
        ok "Network is connected."
        pause
        return 0
    fi

    warn "Network is not connected. Online installs use cache.nixos.org; offline installs need all Nix paths already on the ISO."
    printf '\n'
    menu "Network setup" \
        "Network tools|Status, nmtui, quick Wi-Fi, and rescan" \
        "Quick Wi-Fi connect|Scan and connect with nmcli" \
        "Retry|Check network again" \
        "Continue anyway|Only works if every needed Nix path is already local"
    case "$MENU_RESULT" in
        0)
            network_tools_menu yes
            release_network
            return
            ;;
        1)
            quick_wifi_connect
            release_network
            return
            ;;
        2)
            release_network
            return
            ;;
        3)
            ABORA_ALLOW_OFFLINE_INSTALL=1
            export ABORA_ALLOW_OFFLINE_INSTALL
            ;;
    esac
}

release_disk() {
    # Use the same full disk picker as the detailed wizard. The old release
    # path auto-selected the only visible disk, which is fast in QEMU but too
    # risky on real hardware and did not expose the existing-partition path.
    step_disk
}

release_identity() {
    release_header "User"
    while true; do
        local v
        v="$(prompt_field "Hostname" "$hostname_value")"
        [[ -n "$v" ]] && hostname_value="$v"
        safe_hostname "$hostname_value" && break
        warn "Hostname can use letters, numbers, and hyphens."
    done

    while true; do
        local v
        v="$(prompt_field "Username" "$username_value")"
        [[ -n "$v" ]] && username_value="$v"
        safe_identifier "$username_value" && break
        warn "Username must start with a lowercase letter and use lowercase letters, numbers, '_' or '-'."
    done

    while true; do
        local p1 p2
        p1="$(prompt_password "Password")"
        p2="$(prompt_password "Confirm")"
        [[ -n "$p1" ]] || { warn "Password cannot be empty."; continue; }
        [[ "$p1" == "$p2" ]] || { warn "Passwords do not match."; continue; }
        user_password_hash="$(hash_password "$p1")"
        [[ -n "$user_password_hash" ]] || { warn "Could not hash password."; continue; }
        root_password_mode="same"
        root_password_hash="$user_password_hash"
        ok "Password set."
        pause
        return 0
    done
}

release_locale() {
    release_header "Region"
    menu "Locale" \
        "English (United States)|en_US.UTF-8" \
        "English (United Kingdom)|en_GB.UTF-8" \
        "Spanish|es_ES.UTF-8" \
        "French|fr_FR.UTF-8" \
        "German|de_DE.UTF-8" \
        "Custom|Type manually"
    case "$MENU_RESULT" in
        0) locale_value="en_US.UTF-8"; language_label="English (United States)" ;;
        1) locale_value="en_GB.UTF-8"; language_label="English (United Kingdom)" ;;
        2) locale_value="es_ES.UTF-8"; language_label="Spanish" ;;
        3) locale_value="fr_FR.UTF-8"; language_label="French" ;;
        4) locale_value="de_DE.UTF-8"; language_label="German" ;;
        5)
            while true; do
                locale_value="$(prompt_field "Locale" "$locale_value")"
                safe_locale "$locale_value" && break
                warn "Use a locale like en_US.UTF-8."
            done
            language_label="$locale_value"
            ;;
    esac
    apply_language_defaults

    while true; do
        local v
        v="$(prompt_field "Timezone" "$timezone_value")"
        [[ -n "$v" ]] && timezone_value="$(normalize_timezone "$v")"
        timezone_exists "$timezone_value" && break
        warn "Use America/New_York, EST, Eastern, UTC, etc."
    done

    while true; do
        local v
        v="$(prompt_field "Keyboard" "$keyboard_value")"
        [[ -n "$v" ]] && keyboard_value="$v"
        safe_keymap "$keyboard_value" && break
        warn "Use a valid keymap like us, gb, de, fr."
    done
    sync_xkb_layout
}

release_desktop() {
    release_header "Desktop"
    local -a profiles=() profile
    local default_profile="${abora_default_desktop:-${abora_edition:-cosmic}}"
    [[ "$default_profile" == "kde" ]] && default_profile="plasma"
    desktop_profile="$default_profile"
    abora_sync_desktop_label "$desktop_profile"

    case "${abora_edition:-}" in
        cosmic|hyprland|gnome|kde)
            ok "Recommended for this ISO: ${desktop_label}."
            msg "If you picked the wrong ISO, you can choose a different desktop now."
            printf '\n'
            menu "Desktop choice" \
                "Use ${desktop_label}|Recommended for this ISO" \
                "Choose another desktop|GNOME, COSMIC, KDE, Hyprland, and more"
            [[ "$MENU_RESULT" -eq 0 ]] && return 0
            ;;
    esac

    # Hyprland and "other" are built around tiling window managers, so show
    # those first here too, matching the GUI installer's ordering
    # (_edition_desktops in abora-installer-gui.py) instead of the plain
    # alphabetic-ish order every other edition gets.
    local -a ordered=()
    if [[ "${abora_edition:-}" == "hyprland" || "${abora_edition:-}" == "other" ]]; then
        while IFS= read -r profile; do
            [[ -n "$profile" ]] || continue
            ordered+=("$profile")
        done < <(abora_tiling_wm_profiles)
    fi
    while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        if ! printf '%s\n' "${ordered[@]}" | grep -qx "$profile"; then
            ordered+=("$profile")
        fi
    done < <(abora_supported_desktop_profiles)

    for profile in "${ordered[@]}"; do
        abora_sync_desktop_label "$profile"
        profiles+=("${desktop_label}|${profile}")
    done
    menu "Desktop" "${profiles[@]}"
    desktop_profile="${profiles[$MENU_RESULT]#*|}"
    abora_sync_desktop_label "$desktop_profile"
}

release_apps() {
    # Release default: keep installation fast and reliable. Starter bundles are
    # saved for first boot instead of inflating nixos-install.
    starter_apps_bundle="none"
    starter_apps_label="None"
    install_apps_during_setup="no"
}

release_gaming() {
    release_header "Gaming"
    msg "Optional gaming support can be added now, no matter which desktop you chose."
    msg "Skipping keeps the install smaller and faster."
    printf '\n'
    menu "Gaming setup" \
        "Skip gaming setup|Smallest install — add gaming later" \
        "Desktop gaming|Steam, 32-bit graphics, GameMode, MangoHud, Vulkan tools" \
        "Desktop gaming + Big Picture|Also add a controller-friendly Steam launcher" \
        "Big Picture console mode|Add a Gamescope login session for TV/controller use"
    case "$MENU_RESULT" in
        0)
            gaming_enabled="no"
            gaming_steam="no"
            gaming_big_picture="no"
            gaming_autostart="no"
            gaming_gamescope="no"
            gaming_vulkan="no"
            gaming_controller="no"
            gaming_mangohud="no"
            gaming_gamemode="no"
            gaming_launchers="no"
            ;;
        1)
            gaming_enabled="yes"
            gaming_steam="yes"
            gaming_big_picture="no"
            gaming_autostart="no"
            gaming_gamescope="no"
            gaming_vulkan="yes"
            gaming_controller="yes"
            gaming_mangohud="yes"
            gaming_gamemode="yes"
            gaming_launchers="yes"
            ;;
        2)
            gaming_enabled="yes"
            gaming_steam="yes"
            gaming_big_picture="yes"
            gaming_autostart="no"
            gaming_gamescope="no"
            gaming_vulkan="yes"
            gaming_controller="yes"
            gaming_mangohud="yes"
            gaming_gamemode="yes"
            gaming_launchers="yes"
            ;;
        3)
            gaming_enabled="yes"
            gaming_steam="yes"
            gaming_big_picture="yes"
            gaming_autostart="no"
            gaming_gamescope="yes"
            gaming_vulkan="yes"
            gaming_controller="yes"
            gaming_mangohud="yes"
            gaming_gamemode="yes"
            gaming_launchers="yes"
            ;;
    esac
}

release_preflight() {
    release_header "Preflight"
    msg "Checking disk, password, timezone, assets, tools, and Nix cache."
    printf '\n'
    if check_install_environment final; then
        printf '\n'
        ok "Preflight passed."
        pause
        return 0
    fi

    printf '\n'
    warn "Preflight failed. See messages above."
    msg "For network problems, choose Network tools or run abora network from a terminal."
    menu "Next" \
        "Run checks again|Retry after fixing the issue" \
        "Network tools|Fix Wi-Fi, DNS, or cache reachability" \
        "Debug tools|View logs, hardware test, support report" \
        "Open terminal|Drop to the live shell" \
        "Cancel|Drop to live shell"
    case "$MENU_RESULT" in
        0) release_preflight ;;
        1) network_tools_menu yes; release_preflight ;;
        2) debug_tools_menu; release_preflight ;;
        3) open_live_terminal ;;
        *) exit 1 ;;
    esac
}

release_review() {
    release_header "Review"
    _print_summary
    printf '\n'
    if [[ "$install_disk_mode" == "existing" ]]; then
        warn "The next step formats ${target_partition} and installs Abora OS."
    else
        warn "The next step erases ${disk} and installs Abora OS."
    fi
    menu "Install now?" \
        "Install Abora OS|Start installation with the selected disk layout" \
        "Cancel|Return to live shell"
    [[ "$MENU_RESULT" -eq 0 ]] || exit 1
}

release_install_flow() {
    abora_sync_desktop_label "${abora_default_desktop:-${abora_edition:-cosmic}}"
    release_welcome
    release_network
    release_disk
    release_identity
    release_locale
    release_desktop
    step_gpu
    release_gaming
    release_apps
    release_preflight
    release_review
    run_install
    page_done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    require_root

    # ── Batch mode ───────────────────────────────────────────────────────────────
    # Automation/tests can pass a params file, skip TUI steps, and run the same
    # install engine. The normal supported user interface is the TUI.
    if [[ "${batch_mode:-0}" -eq 1 ]]; then
        [[ -n "$batch_params_file" && -f "$batch_params_file" ]] \
            || { printf 'ERROR: batch params file not found: %s\n' "$batch_params_file" >&2; exit 1; }
        # shellcheck source=/dev/null
        source "$batch_params_file"
        trap 'cleanup_target 2>/dev/null || true' EXIT
        detect_defaults 2>/dev/null || true
        : > "$install_log"
        printf '[batch] Starting Abora OS installation\n'
        printf '[batch] disk=%s hostname=%s desktop=%s\n' \
            "$disk" "$hostname_value" "$desktop_profile"
        run_install
        printf 'done!\n'
        exit 0
    fi

    trap 'if [[ "${reconfig_mode:-0}" != "1" ]]; then cleanup_target; fi' EXIT
    detect_defaults
    refresh_github_identity
    tui_size_warning

    if [[ "${reconfig_mode:-0}" == "1" ]]; then
        page_welcome
        read_current_config
        read_anix_config

        step_language
        step_identity
        step_desktop
        step_apps
        step_options
        step_gpu
        step_dotfiles

        tab_header 11
        printf '  %bReconfiguration Summary%b\n\n' "${B}${CS}" "$R"
        _print_summary

        menu "Apply reconfiguration?" \
            "Apply now|Write config and run nixos-rebuild switch" \
            "Cancel|Discard changes and exit"
        if [[ "$MENU_RESULT" -eq 1 ]]; then exit 0; fi

        run_reconfig
        page_done_reconfig
    else
        release_install_flow
    fi
}

main "$@"
