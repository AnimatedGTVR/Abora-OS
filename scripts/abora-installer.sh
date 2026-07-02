#!/usr/bin/env bash
# Abora OS Installer — DENALI 3.14 Edition
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
wallpaper_name="Daytime-MNT.jpg"
starter_apps_bundle="favorites"
starter_apps_label="Fan Favorites"
install_apps_during_setup="${ABORA_INSTALL_APPS_DURING_SETUP:-no}"
anix_enabled="yes"
github_identity="Skipped"
user_password_hash=""
root_password_hash=""
root_password_mode="same"
version="${ABORA_VERSION:-}"
reconfig_mode="${ABORA_RECONFIG:-0}"
batch_mode=0
batch_params_file=""

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
CG=$'\033[38;5;240m'   # Stone gray   — dim / pending steps
CP=$'\033[38;5;82m'    # Green        — done / success
CW=$'\033[38;5;33m'    # Abora blue   — primary accent (choices, highlights)
CB=$'\033[38;5;33m'    # Abora blue   — logo / branding
CE=$'\033[38;5;196m'   # Red          — errors
CY=$'\033[38;5;220m'   # Yellow       — warnings / notices
CC=$'\033[38;5;253m'   # Cloud white  — body text

# ── Gum integration ───────────────────────────────────────────────────────────
GUM_BIN=""
_init_gum() {
    GUM_BIN="$(command -v gum 2>/dev/null || true)"
    [[ -n "$GUM_BIN" ]] || return 0
    export GUM_CHOOSE_CURSOR="  › "
    export GUM_CHOOSE_CURSOR_FOREGROUND="214"
    export GUM_CHOOSE_HEADER_FOREGROUND="253"
    export GUM_CHOOSE_HEADER_BOLD="true"
    export GUM_CHOOSE_ITEM_FOREGROUND="253"
    export GUM_CHOOSE_SELECTED_FOREGROUND="214"
    export GUM_CHOOSE_SELECTED_BOLD="true"
    export GUM_INPUT_PROMPT="  › "
    export GUM_INPUT_PROMPT_FOREGROUND="214"
    export GUM_INPUT_CURSOR_FOREGROUND="214"
}
_init_gum

# ── Abora TUI engine ───────────────────────────────────────────────────────────

_TABS=("Language" "Network" "Identity" "Desktop" "Apps" "Options" "Preflight" "Disk" "Confirm")

draw_logo() {
    printf '  %bABORA OS%b  %b▸%b  %bDENALI 3.14%b\n' \
        "${B}${CW}" "$R" "${D}${CG}" "$R" "${D}${CG}" "$R"
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
    printf '  %b│%b  %bABORA OS%b  %b▸%b  DENALI 3.14%b                              %b│%b\n' \
        "$CF" "$R" "${B}${CW}" "$R" "${D}${CG}" "$R" "${D}${CG}" "$CF" "$R"
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
            "${gum_items[@]}" 2>/dev/tty)" || { MENU_RESULT=0; return 0; }
        for (( i=0; i<count; i++ )); do
            if [[ "${gum_items[$i]}" == "$selected" ]]; then
                MENU_RESULT=$i; return 0
            fi
        done
        MENU_RESULT=0; return 0
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
    if declare -F draw_log_tail >/dev/null 2>&1 && [[ -f "$install_log" ]]; then
        draw_log_tail "$install_log" 7
        printf '\n'
    fi
    # Unmount before handing off to a shell so nothing is left mounted.
    cleanup_target 2>/dev/null || true
    printf '  %bInstall failed — dropping to a live shell.%b\n' "$CY" "$R"
    printf '  %bRun %babora-install%b to retry the installer.\n\n' "$CC" "${B}${CW}" "$R"
    # exec replaces this process so systemd sees a 0 exit when the user
    # leaves the shell — preventing the Restart=on-failure service from
    # relaunching the installer automatically.
    exec bash --login </dev/tty >/dev/tty 2>/dev/tty || exit 0
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

timezone_exists() {
    local tz="$1" base
    safe_timezone "$tz" || return 1
    for base in "${ABORA_ZONEINFO_PATH:-}" /usr/share/zoneinfo /run/current-system/sw/share/zoneinfo; do
        [[ -n "$base" && -f "${base}/${tz}" ]] && return 0
    done
    return 1
}

hash_password() {
    local password="$1"
    command -v openssl >/dev/null 2>&1 || return 1
    openssl passwd -6 -stdin <<<"$password"
}

nix_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/}"
    printf '%s' "$value"
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

detect_defaults() {
    local d
    d="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    [[ -n "$d" ]] && timezone_value="$d"
    d="$(localectl status 2>/dev/null | awk '/VC Keymap:/{print $3;exit}' || true)"
    if [[ "$d" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        keyboard_value="$d"; sync_xkb_layout
    fi
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

collect_disks() {
    lsblk -dn -e 7,11 -o NAME,SIZE,MODEL,TYPE | awk '
        $NF == "disk" {
            if ($1 ~ /^(fd|loop|ram|sr|zram)/) next
            model = ""
            for (i = 3; i < NF; i++) model = model (model ? " " : "") $i
            if (model == "") model = "Unknown model"
            print "/dev/" $1 "|" $2 "  " model
        }'
}

check_install_environment() {
    local mode="${1:-summary}"
    local failed=0 cmd path nixpkgs
    local commands_ok=0 assets_ok=0
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
        /etc/abora/desktop.sh
        /etc/abora/doctor.sh
        /etc/abora/recovery.sh
        /etc/abora/welcome.sh
        /etc/abora/app-catalog.sh
        /etc/abora/apps.sh
        /etc/abora/support-report.sh
        /etc/abora/hardware-test.sh
        /etc/abora/repair-flake-purity.sh
        /etc/abora/default-wallpaper.png
        /etc/abora/fastfetch-logo.txt
        /etc/abora/fastfetch-config.jsonc
        /etc/abora/desktop-profiles.sh
        /etc/abora/mango/config.conf
        /etc/abora/pkgs/mango.nix
        /etc/abora/pkgs/modularity.nix
        /etc/abora/installed-base.nix
        /etc/abora/anix.sh
        /etc/abora/anix-module.nix
        /etc/abora/tinypm/tinypm
        /etc/abora/tinypm/grab
        /etc/abora/tinypm/Parcel
        /etc/abora/tinypm/version
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
        /etc/abora/docs/wiki/TinyPM-V4.md
        /etc/abora/docs/wiki/Abora-Tools.md
        /etc/abora/docs/wiki/Recovery.md
        /etc/abora/tinypm/lib/core/system.sh
    )

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
        err "Nix cache unreachable; fast install needs internet."
        failed=1
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

    safe_locale "$locale_value" || { err "Invalid locale: ${locale_value}"; failed=1; }
    timezone_exists "$timezone_value" || { err "Invalid or unavailable timezone: ${timezone_value}"; failed=1; }
    safe_keymap "$keyboard_value" || { err "Invalid console keymap: ${keyboard_value}"; failed=1; }
    safe_keymap "$xkb_layout_value" || { err "Invalid XKB layout: ${xkb_layout_value}"; failed=1; }
    [[ -n "$user_password_hash" ]] || { err "User password hash is empty."; failed=1; }

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
    printf '  %bDENALI 3.14%b  %b·  NixOS-based Linux  ·  v%s%b\n' \
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
            "Open nmtui|Wi-Fi setup, hidden SSIDs, VPNs" \
            "Quick Wi-Fi connect|Scan and connect from terminal" \
            "Re-check connection|Test connectivity again" \
            "Continue|Proceed with current state"

        case "$MENU_RESULT" in
            0)
                nmtui 2>/dev/null || true
                start_nm 2>/dev/null || true
                ;;
            1)
                nmcli radio wifi on >/dev/null 2>&1 || true
                nmcli device wifi rescan >/dev/null 2>&1 || true
                printf '\n'
                nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || true
                printf '\n'
                printf '  %bSSID:%b ' "$CI" "$R"
                local _ssid; read -r _ssid </dev/tty || _ssid=""
                if [[ -n "${_ssid:-}" ]]; then
                    local _sec
                    _sec="$(nmcli -t -f SSID,SECURITY device wifi list 2>/dev/null \
                        | awk -F: -v s="$_ssid" '$1==s{print $2;exit}')"
                    if [[ -n "${_sec:-}" && "$_sec" != "--" ]]; then
                        printf '  %bPassword:%b ' "$CI" "$R"
                        local _pw; read -rs _pw </dev/tty || _pw=""
                        printf '\n'
                        nmcli device wifi connect "$_ssid" password "$_pw" 2>/dev/null || true
                    else
                        nmcli device wifi connect "$_ssid" 2>/dev/null || true
                    fi
                fi
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
        [[ -n "$v" ]] && timezone_value="$v"
        if timezone_exists "$timezone_value"; then break; fi
        warn "Use a valid zoneinfo name, for example America/New_York or UTC."
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

    local -a profiles=()
    local profile
    while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        abora_sync_desktop_label "$profile"
        profiles+=("${desktop_label}|${profile}")
    done < <(abora_supported_desktop_profiles)

    menu "Choose Your Desktop Environment" "${profiles[@]}"
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
            "After first boot|Fast install — apply later with abora-apps rebuild" \
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
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 7 — PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════════

step_preflight() {
    while true; do
        tab_header 7
        printf '  %bInstall Preflight%b\n\n' "${B}${CS}" "$R"
        msg "Checking tools, installer assets, Nix paths, and selected values."
        printf '\n'

        if check_install_environment; then
            printf '\n'
            ok "Everything needed for install is present."
            pause
            return 0
        fi

        printf '\n'
        warn "Fix the items above before erasing a disk."
        printf '\n'
        menu "Preflight failed" \
            "Run checks again|Re-test after fixing the live environment" \
            "Cancel|Abort and return to the live shell"
        [[ "$MENU_RESULT" -eq 0 ]] && continue
        exit 1
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 8 — DISK
# ═══════════════════════════════════════════════════════════════════════════════

step_disk() {
    tab_header 8
    warn "All data on the selected disk will be permanently erased!"
    printf '\n'

    local -a disks=() row
    while IFS= read -r row; do
        [[ -n "$row" ]] && disks+=("$row")
    done < <(collect_disks)
    [[ ${#disks[@]} -eq 0 ]] && die "No installable disks found."

    menu "Choose Installation Disk" "${disks[@]}"
    disk="${disks[$MENU_RESULT]%%|*}"

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
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 9 — CONFIRM
# ═══════════════════════════════════════════════════════════════════════════════

_print_summary() {
    if [[ -n "$disk" ]]; then
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
    if [[ "$starter_apps_bundle" == "none" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:" "$R" "$starter_apps_label"
    elif [[ "$install_apps_during_setup" == "yes" ]]; then
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:" "$R" "${starter_apps_label} (during setup)"
    else
        printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Apps:" "$R" "${starter_apps_label} (after first boot)"
    fi
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "ANIX:"     "$R" "$anix_enabled"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "Root:"     "$R" "$root_password_mode"
    printf '  %b  %-16s%b  %s\n' "${D}${CI}" "GitHub:"   "$R" "$github_identity"
    printf '\n'
}

step_confirm() {
    while true; do
        tab_header 9
        printf '  %bInstallation Summary%b\n\n' "${B}${CS}" "$R"
        _print_summary

        menu "Ready to install?" \
            "Install now|Erase ${disk} and install Abora OS DENALI 3.14" \
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

disk_part_suffix() {
    case "$disk" in *nvme*|*mmcblk*|*loop*) printf 'p' ;; *) printf '' ;; esac
}

log_install_step() {
    printf '[installer] %s\n' "$*" >>"$install_log"
}

partition_disk() {
    log_install_step "partition_disk: start disk=${disk}"
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

write_tinypm_system_fallback() {
    local target="$1"
    mkdir -p "$(dirname "$target")"
    cat > "$target" <<'EOF'
#!/usr/bin/env bash
# Fallback TinyPM system bridge for older Abora ISO payloads.
system_command_state() { command -v "$1" >/dev/null 2>&1 && printf available || printf missing; }
system_layer_name() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}:${PRETTY_NAME:-}" in
            abora:*|*:*"Abora"*) printf 'Abora OS'; return ;;
            nixos:*|*nixos*) printf 'NixOS'; return ;;
        esac
    fi
    printf 'Linux'
}
system_config_dir() { printf '%s\n' "${TINYPM_SYSTEM_CONFIG:-${ANIX_SYSTEM_CONFIG:-/etc/nixos}}"; }
system_file_exists() { [[ -e "$1" ]]; }
system_flake_state() { [[ -f "$(system_config_dir)/flake.nix" ]] && printf present || printf missing; }
system_generation_state() { [[ -e /run/current-system ]] && printf active || printf unknown; }
system_native_strategy() { printf 'Native packages with Abora/ANIX bridges when available'; }
system_print_report() {
    printf 'Parcel system layer\n'
    printf '%s\n' '------------------------------------------------------------'
    printf '  %-18s %s\n' system "$(system_layer_name)"
    printf '  %-18s %s\n' config_dir "$(system_config_dir)"
    printf '  %-18s %s\n' flake "$(system_flake_state)"
    printf '  %-18s %s\n' generation "$(system_generation_state)"
    printf '  %-18s %s\n' abora "$(system_command_state abora)"
    printf '  %-18s %s\n' anix "$(system_command_state anix)"
}
system_bridge_command() {
    local tool="$1"; shift
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not available on this system"
    [[ $# -gt 0 ]] || set -- help
    exec "$tool" "$@"
}
EOF
}

write_docs_fallback() {
    local docs_dir="$1"
    mkdir -p "$docs_dir/wiki"
    for doc in ANIX-V1 TinyPM-V4 Abora-Tools Recovery; do
        [[ -f "$docs_dir/wiki/${doc}.md" ]] && continue
        cat > "$docs_dir/wiki/${doc}.md" <<EOF
# ${doc}

This Abora ISO did not include the full local documentation payload.

Useful commands:

\`\`\`sh
abora doctor
anix status
anix doctor
tinypm system
tinypm sources
\`\`\`
EOF
    done
}

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
             "${root}/etc/nixos/abora/effects"

    local f
    for f in VERSION title.txt abora.sh ui.sh config.sh desktop.sh doctor.sh \
              check-full.sh recovery.sh welcome.sh app-catalog.sh apps.sh support-report.sh \
              hardware-test.sh default-wallpaper.png fastfetch-logo.txt \
              fastfetch-config.jsonc desktop-profiles.sh installed-base.nix \
              installer.sh setup-launcher.sh setup.desktop repair-flake-purity.sh \
              session-setup.sh theme-sync.sh update.sh; do
        cp_required "/etc/abora/${f}" "${root}/etc/nixos/abora/${f}"
    done
    [[ -f /etc/abora/Abora-LOGO.png ]] && \
        cp /etc/abora/Abora-LOGO.png "${root}/etc/nixos/abora/Abora-LOGO.png"
    cp_required /etc/abora/plymouth/abora.plymouth "${root}/etc/nixos/abora/plymouth/abora.plymouth"
    cp_required /etc/abora/plymouth/abora.script   "${root}/etc/nixos/abora/plymouth/abora.script"
    install_mango_config_asset "$root"
    cp_required /etc/abora/pkgs/mango.nix          "${root}/etc/nixos/abora/pkgs/mango.nix"
    cp_required /etc/abora/pkgs/modularity.nix     "${root}/etc/nixos/abora/pkgs/modularity.nix"
    cp_required /etc/abora/anix-module.nix         "${root}/etc/nixos/abora/anix-module.nix"
    cp_required /etc/abora/abora-options.nix       "${root}/etc/nixos/abora/abora-options.nix"

    [[ -f /etc/abora/anix.sh           ]] && cp /etc/abora/anix.sh            "${root}/etc/nixos/abora/anix.sh"
    [[ -f /etc/abora/effects/v3StartingAbora.mp3 ]] && \
        cp /etc/abora/effects/v3StartingAbora.mp3 "${root}/etc/nixos/abora/effects/v3StartingAbora.mp3"

    cp -a /etc/abora/desktops/. "${root}/etc/nixos/abora/desktops/"
    rewrite_installed_mango_config_paths "$root"

    if [[ -e /etc/abora/tinypm ]]; then
        mkdir -p "${root}/etc/nixos/abora/tinypm"
        # -a preserves modes (including executable bits) and copies relative
        # symlinks as symlinks.  No -L so we never follow absolute symlinks
        # that may exist in older live ISOs.
        cp -a /etc/abora/tinypm/. "${root}/etc/nixos/abora/tinypm/"
        # Drop any bin/ subdir — it only ever held installation-specific
        # absolute symlinks from the dev machine, not needed at install time.
        rm -rf "${root}/etc/nixos/abora/tinypm/bin" 2>/dev/null || true
    fi
    if [[ ! -f "${root}/etc/nixos/abora/tinypm/lib/core/system.sh" ]]; then
        write_tinypm_system_fallback "${root}/etc/nixos/abora/tinypm/lib/core/system.sh"
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
        git -C "${root}/etc/nixos" add \
            abora/mango/config.conf \
            abora/abora-options.nix \
            abora/installed-base.nix \
            abora/desktops/mangowm.nix \
            abora/repair-flake-purity.sh \
            2>/dev/null || true
    fi
}

generate_nixos_config() {
    local root="${1:-/mnt}"
    local cfgdir="${root}/etc/nixos"

    printf '[*] nixos-generate-config\n' > "$config_log"
    nixos-generate-config --root "$root" >> "$config_log" 2>&1
    write_branding_assets "$root"

    local desktop_block desktop_pkgs root_pw_line host_nix user_nix locale_nix timezone_nix keyboard_nix xkb_nix desktop_nix wallpaper_nix anix_import_line
    desktop_block="$(abora_desktop_config_block "$desktop_profile" "$xkb_layout_value" "$username_value")"
    desktop_pkgs="$(abora_desktop_package_block "$desktop_profile")"
    [[ -n "$desktop_block" ]] || die "Empty desktop block for $desktop_profile."
    host_nix="$(nix_string "$hostname_value")"
    user_nix="$(nix_string "$username_value")"
    locale_nix="$(nix_string "$locale_value")"
    timezone_nix="$(nix_string "$timezone_value")"
    keyboard_nix="$(nix_string "$keyboard_value")"
    xkb_nix="$(nix_string "$xkb_layout_value")"
    desktop_nix="$(nix_string "$desktop_profile")"
    wallpaper_nix="$(nix_string "$wallpaper_name")"

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
{ pkgs, lib, ... }:
{
  system.nixos.variantName = "Abora OS DENALI 3.14 ${desktop_label} Edition";
  system.nixos.variant_id = "${desktop_variant_id}";
  # OS release branding is set centrally in abora/installed-base.nix.

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.efiSysMountPoint = "/boot";
  boot.loader.timeout = 5;
  boot.loader.limine = {
    enable = true;
    enableEditor = false;
    maxGenerations = 8;
    biosSupport = true;
    biosDevice = "${disk}";
    partitionIndex = 1;
    force = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "${host_nix}";
  networking.networkmanager.enable = lib.mkForce true;
  i18n.defaultLocale = "${locale_nix}";
  i18n.supportedLocales = [
    "${locale_nix}/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  time.timeZone = "${timezone_nix}";
  console.keyMap = "${keyboard_nix}";

${desktop_block}

  users.users."${user_nix}" = {
    isNormalUser = true;
    description = "${user_nix}";
    createHome = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "${user_password_hash}";
  };

${root_pw_line}

  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "26.05";
}
EOF

    cat > "${cfgdir}/flake.nix" <<EOF
{
  description = "Abora installed system";
  # Use the standard flake input so future rebuilds and updates work in pure
  # evaluation mode on the installed system.
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

validate_boot() {
    [[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]] && return 0
    find /mnt/boot -maxdepth 3 \
        \( -iname '*limine*.efi' -o -iname 'limine-bios.sys' \) 2>/dev/null \
        | grep -q . && return 0
    die "Bootloader not found after nixos-install. See ${install_log}."
}

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
    printf '  %b│%b  %bABORA OS%b  %b▸%b  Installing DENALI 3.14%b                  %b│%b\n' \
        "$CF" "$R" "${B}${CW}" "$R" "${D}${CG}" "$R" "${D}${CG}" "$CF" "$R"
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

detect_install_activity() {
    local file="$1"
    [[ -s "$file" ]] || {
        printf 'Working'
        return 0
    }

    if tail -n 24 "$file" 2>/dev/null | grep -Eq '(^|\]| )Compiling |Running phase: (buildPhase|configurePhase)|build flags:|ninja-[0-9]|mesonConfigurePhase|Checking for (function|type|header)|Header ".*" has symbol'; then
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
    local percent="$1" stage="$2" pid="$3" started="$4" status="${5:-Working}"
    local now elapsed
    now="$(monotonic_seconds)"
    elapsed=$((now - started))

    printf '\033[2J\033[H'
    printf '\n'
    draw_install_title
    printf '\n'
    progress_line "$percent" "$stage"
    printf '\n'
    printf '  %bStatus%b   %s\n' "$CG" "$R" "$status"
    printf '  %bElapsed%b  %s   %bPID%b  %s\n' "$CG" "$R" "$(format_elapsed "$elapsed")" "$CG" "$R" "$pid"
    printf '\n'
    draw_log_tail "$install_log" 8
    printf '\n'
    printf '  %bNix may take a while to fetch or build packages — this is normal.%b\n' "${D}${CG}" "$R"
}

run_with_log_panel() {
    local percent="$1" stage="$2"
    shift 2

    local warn_after=480 hard_timeout=5400 idle_timeout=1800
    local started pid rc now elapsed status last_size current_size last_change idle
    started="$(monotonic_seconds)"
    last_change="$started"
    last_size="$(file_size "$install_log")"
    status="Started"
    draw_install_status "$percent" "$stage" "-" "$started" "$status"

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
        draw_install_status "$percent" "$stage" "$pid" "$started" "$status"
        if (( idle >= idle_timeout )); then
            printf '\n  %bInstall command produced no new log output for 30 minutes; stopping it.%b\n' "$CY" "$R"
            kill "$pid" >/dev/null 2>&1 || true
            sleep 5
            kill -KILL "$pid" >/dev/null 2>&1 || true
            wait "$pid" >/dev/null 2>&1 || true
            draw_install_status "$percent" "$stage" "$pid" "$started" "Stopped after 30 minutes of no log output"
            return 124
        fi
        if (( elapsed >= hard_timeout )); then
            printf '\n  %bInstall command exceeded 90 minutes; stopping it.%b\n' "$CY" "$R"
            kill "$pid" >/dev/null 2>&1 || true
            sleep 5
            kill -KILL "$pid" >/dev/null 2>&1 || true
            wait "$pid" >/dev/null 2>&1 || true
            draw_install_status "$percent" "$stage" "$pid" "$started" "Stopped after 90 minute timeout"
            return 124
        fi
        sleep 2
    done

    wait "$pid"
    rc=$?
    if (( rc == 0 )); then
        draw_install_status "$percent" "$stage" "$pid" "$started" "Complete"
    else
        draw_install_status "$percent" "$stage" "$pid" "$started" "Failed"
    fi
    return "$rc"
}

run_install() {
    printf '\033[2J\033[H'
    printf '\n'
    draw_install_title
    printf '  %bInstalling Abora DENALI 3.14%b\n' "$CC" "$R"
    printf '  %bLog: %s%b\n' "${D}${CG}" "$install_log" "$R"
    printf '\n'

    : > "$install_log"

    progress_line 5 "Starting"
    msg "Running final safety checks…"
    if ! check_install_environment detail >>"$install_log" 2>&1; then
        die "Preflight failed before partitioning. See ${install_log}."
    fi

    msg "Preparing target disk…"
    if ! partition_disk; then die "Partitioning failed. See ${install_log}."; fi
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
        "substituters = https://cache.nixos.org" \
        "trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
        "connect-timeout = 10" \
        "stalled-download-timeout = 120" \
        "fallback = false" \
        "builders-use-substitutes = true" \
        "max-substitution-jobs = 32" \
        "http-connections = 128")"

    msg "Running nixos-install…"
    if ! run_with_log_panel 70 "Installing system" \
        env "NIX_PATH=nixpkgs=${nixpkgs}:nixos-config=/mnt/etc/nixos/configuration.nix" \
        "NIX_CONFIG=${nix_config}" \
        nixos-install --root /mnt --no-root-passwd; then
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
    printf '  %b│%b  %bAbora OS DENALI 3.14 is installed%b                     %b│%b\n' \
        "$CF" "$R" "$CS" "$R" "$CF" "$R"
    printf '  %b└────────────────────────────────────────────────────────┘%b\n' "$CF" "$R"
    printf '\n'
    if [[ "$starter_apps_bundle" != "none" && "$install_apps_during_setup" != "yes" ]]; then
        printf '  %b·%b  Apps: %b%s%b saved — run %babora-apps rebuild%b after first boot.\n' \
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
            "$abora_local" 2>/dev/null || true
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

    page_welcome

    if [[ "${reconfig_mode:-0}" == "1" ]]; then
        read_current_config
        read_anix_config

        step_language
        step_identity
        step_desktop
        step_apps
        step_options

        tab_header 9
        printf '  %bReconfiguration Summary%b\n\n' "${B}${CS}" "$R"
        _print_summary

        menu "Apply reconfiguration?" \
            "Apply now|Write config and run nixos-rebuild switch" \
            "Cancel|Discard changes and exit"
        if [[ "$MENU_RESULT" -eq 1 ]]; then exit 0; fi

        run_reconfig
        page_done_reconfig
    else
        step_language
        step_network
        step_identity
        step_desktop
        step_apps
        step_options
        step_preflight
        step_disk
        step_confirm
        run_install
        page_done
    fi
}

main "$@"
