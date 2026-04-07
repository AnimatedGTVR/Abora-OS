#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

gsettings_bin="${ABORA_GSETTINGS_BIN:-gsettings}"
theme_dir="${ABORA_THEME_DIR:-/etc/abora/themes}"

is_gnome_session() {
    case "${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}" in
        *GNOME*:* | *gnome*:* | *:gnome* | *:GNOME*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

read_setting() {
    local schema="$1"
    local key="$2"
    "$gsettings_bin" get "$schema" "$key" 2>/dev/null || true
}

current_wallpaper_basename() {
    local value=""
    local path=""

    value="$(read_setting org.gnome.desktop.background picture-uri-dark)"
    if [[ -z "$value" || "$value" == "''" ]]; then
        value="$(read_setting org.gnome.desktop.background picture-uri)"
    fi

    value="${value#\'}"
    value="${value%\'}"
    path="${value#file://}"

    if [[ -n "$path" ]]; then
        basename "$path"
    fi
}

find_theme_file() {
    local wallpaper_name="$1"
    local file=""

    shopt -s nullglob
    for file in "${theme_dir}"/*.conf; do
        [[ "$(basename "$file")" == "current.conf" ]] && continue
        unset ABORA_THEME_WALLPAPER
        # shellcheck source=/dev/null
        . "$file"
        if [[ "${ABORA_THEME_WALLPAPER:-}" == "$wallpaper_name" ]]; then
            printf '%s\n' "$file"
            return 0
        fi
    done

    return 1
}

apply_theme_for_wallpaper() {
    local wallpaper_name="$1"
    local theme_file=""
    local accent=""
    local scheme=""

    [[ -n "$wallpaper_name" ]] || return 0
    theme_file="$(find_theme_file "$wallpaper_name")" || return 0

    unset ABORA_THEME_GNOME_ACCENT ABORA_THEME_GNOME_SCHEME
    # shellcheck source=/dev/null
    . "$theme_file"

    accent="${ABORA_THEME_GNOME_ACCENT:-}"
    scheme="${ABORA_THEME_GNOME_SCHEME:-}"

    if [[ -n "$accent" ]]; then
        "$gsettings_bin" set org.gnome.desktop.interface accent-color "'${accent}'" >/dev/null 2>&1 || true
    fi

    if [[ -n "$scheme" ]]; then
        "$gsettings_bin" set org.gnome.desktop.interface color-scheme "'${scheme}'" >/dev/null 2>&1 || true
    fi
}

main() {
    local last_wallpaper=""
    local current_wallpaper=""
    local oneshot=0

    if [[ "${1:-}" == "--once" ]]; then
        oneshot=1
        shift || true
    fi

    command -v "$gsettings_bin" >/dev/null 2>&1 || exit 0
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || exit 0
    is_gnome_session || exit 0

    last_wallpaper="$(current_wallpaper_basename)"
    apply_theme_for_wallpaper "$last_wallpaper"

    if [[ "$oneshot" -eq 1 ]]; then
        exit 0
    fi

    while sleep 2; do
        current_wallpaper="$(current_wallpaper_basename)"
        if [[ "$current_wallpaper" != "$last_wallpaper" ]]; then
            apply_theme_for_wallpaper "$current_wallpaper"
            last_wallpaper="$current_wallpaper"
        fi
    done
}

main "$@"
