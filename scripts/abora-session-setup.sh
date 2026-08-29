#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

default_wallpaper="${ABORA_DEFAULT_WALLPAPER:-/etc/abora/default-wallpaper.png}"
default_dark_wallpaper="${ABORA_DEFAULT_DARK_WALLPAPER:-$default_wallpaper}"
if [[ ! -s "$default_wallpaper" && -s /etc/abora/default-wallpaper.png ]]; then
    default_wallpaper="/etc/abora/default-wallpaper.png"
fi
if [[ ! -s "$default_dark_wallpaper" ]]; then
    default_dark_wallpaper="$default_wallpaper"
fi
default_wallpaper_uri="file://${default_wallpaper}"
default_dark_wallpaper_uri="file://${default_dark_wallpaper}"
gsettings_bin="${ABORA_GSETTINGS_BIN:-gsettings}"
theme_sync_script="${ABORA_THEME_SYNC_SCRIPT:-/etc/abora/theme-sync.sh}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/abora"
marker_file="${state_dir}/wallpaper-seed"
theme_marker_file="${state_dir}/light-theme-seed"
dotfiles_url_file="${ABORA_DOTFILES_URL_FILE:-/etc/nixos/abora/dotfiles-url}"
dotfiles_marker_file="${state_dir}/dotfiles-import-seed"
dotfiles_import_bin="${ABORA_DOTFILES_IMPORT_BIN:-abora-dotfiles-import}"
dotfiles_checkout_dir="${XDG_CACHE_HOME:-$HOME/.cache}/abora-dotfiles"
swaybg_pid_file="${XDG_RUNTIME_DIR:-/tmp}/abora-swaybg.pid"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
icon_theme="${ABORA_ICON_THEME:-Papirus}"
qt5ct_colors="${ABORA_QT5CT_COLORS:-/run/current-system/sw/share/qt5ct/colors/airy.conf}"
qt6ct_colors="${ABORA_QT6CT_COLORS:-/run/current-system/sw/share/qt6ct/colors/airy.conf}"
launch_sound="${ABORA_LAUNCH_SOUND:-/etc/abora/effects/v3StartingAbora.mp3}"
launch_sound_marker="${XDG_RUNTIME_DIR:-/tmp}/abora-launch-sound.played"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

play_launch_sound_once() {
    [[ -s "$launch_sound" ]] || return 0
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0
    [[ ! -f "$launch_sound_marker" ]] || return 0

    mkdir -p "$(dirname "$launch_sound_marker")"
    : > "$launch_sound_marker"

    if command_exists mpg123; then
        nohup mpg123 -q "$launch_sound" >/dev/null 2>&1 &
        return 0
    fi

    if command_exists mpv; then
        nohup mpv --really-quiet --no-video "$launch_sound" >/dev/null 2>&1 &
        return 0
    fi

    if command_exists ffplay; then
        nohup ffplay -nodisp -autoexit -loglevel quiet "$launch_sound" >/dev/null 2>&1 &
        return 0
    fi
}

ensure_zsh_profile() {
    local zdotdir="${ZDOTDIR:-${HOME:-}}"
    local target=""

    [[ -n "$zdotdir" ]] || return 0
    target="${zdotdir}/.zshrc"
    [[ -e "$target" ]] && return 0

    mkdir -p "$(dirname "$target")"
    cat > "$target" <<'EOF'
# Abora OS zsh profile.
# System-wide prompt and fastfetch setup live in /etc/zshrc.
EOF
}

desktop_signature() {
    printf '%s:%s\n' "${XDG_CURRENT_DESKTOP:-}" "${DESKTOP_SESSION:-}"
}

mark_seeded() {
    mkdir -p "$state_dir"
    printf '%s|%s\n' "$(basename "$default_wallpaper")" "$(basename "$default_dark_wallpaper")" > "$marker_file"
}

already_seeded() {
    [[ -f "$marker_file" ]] || return 1
    [[ "$(cat "$marker_file" 2>/dev/null || true)" == "$(basename "$default_wallpaper")|$(basename "$default_dark_wallpaper")" ]]
}

mark_theme_seeded() {
    mkdir -p "$state_dir"
    printf 'light\n' > "$theme_marker_file"
}

theme_already_seeded() {
    [[ -f "$theme_marker_file" ]]
}

clear_legacy_dark_theme_marker() {
    local legacy_marker="${state_dir}/dark-theme-seed"
    if [[ -f "$legacy_marker" && ! -f "$theme_marker_file" ]]; then
        rm "$legacy_marker" 2>/dev/null || true
    fi
}

# If the installer saved a dotfiles Git URL (Dotfiles page in the GUI
# installer, hyprland/other editions), clone it and import it via
# abora-dotfiles-import. Only marks itself done on success — first boot
# commonly has no network yet (or briefly doesn't), so a failed attempt
# is retried on the next login rather than getting stuck; a run that
# genuinely succeeds writes the marker and never runs again.
import_dotfiles_once() {
    [[ -f "$dotfiles_url_file" ]] || return 0
    [[ ! -f "$dotfiles_marker_file" ]] || return 0
    command -v "$dotfiles_import_bin" >/dev/null 2>&1 || return 0

    local url
    url="$(tr -d '[:space:]' < "$dotfiles_url_file" 2>/dev/null || true)"
    [[ -n "$url" ]] || return 0

    mkdir -p "$state_dir"
    if "$dotfiles_import_bin" --git-url "$url" "$dotfiles_checkout_dir" \
        >>"${state_dir}/dotfiles-import.log" 2>&1; then
        printf 'imported\n' > "$dotfiles_marker_file"
    fi
}

set_gsettings_string() {
    local schema="$1"
    local key="$2"
    local value="$3"

    command_exists "$gsettings_bin" || return 1
    "$gsettings_bin" set "$schema" "$key" "$value" >/dev/null 2>&1 || return 1
}

set_xfconf_string() {
    local channel="$1"
    local property="$2"
    local value="$3"

    command_exists xfconf-query || return 1
    xfconf-query -c "$channel" -p "$property" -s "$value" >/dev/null 2>&1 \
        || xfconf-query -c "$channel" -p "$property" -n -t string -s "$value" >/dev/null 2>&1 \
        || return 1
}

write_light_gtk_settings() {
    local gtk3_dir="${config_home}/gtk-3.0"
    local gtk4_dir="${config_home}/gtk-4.0"

    mkdir -p "$gtk3_dir" "$gtk4_dir"

    cat > "${gtk3_dir}/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=0
gtk-theme-name=Adwaita
gtk-icon-theme-name=${icon_theme}
EOF

    cat > "${gtk4_dir}/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=0
gtk-theme-name=Adwaita
gtk-icon-theme-name=${icon_theme}
EOF
}

write_light_qt_settings() {
    local qt5_dir="${config_home}/qt5ct"
    local qt6_dir="${config_home}/qt6ct"

    mkdir -p "$qt5_dir" "$qt6_dir"

    cat > "${qt5_dir}/qt5ct.conf" <<EOF
[Appearance]
color_scheme_path=${qt5ct_colors}
custom_palette=true
icon_theme=${icon_theme}
standard_dialogs=default
style=Fusion
EOF

    cat > "${qt6_dir}/qt6ct.conf" <<EOF
[Appearance]
color_scheme_path=${qt6ct_colors}
custom_palette=true
icon_theme=${icon_theme}
standard_dialogs=default
style=Fusion
EOF
}

write_lxqt_light_settings() {
    local lxqt_dir="${config_home}/lxqt"

    mkdir -p "$lxqt_dir"

    cat > "${lxqt_dir}/lxqt.conf" <<EOF
[General]
icon_theme=${icon_theme}
theme=light

[Qt]
style=Fusion
EOF
}

export_light_environment() {
    local qt_platform_theme="${1:-}"

    export GTK_THEME="Adwaita"
    export QT_STYLE_OVERRIDE="Fusion"

    if [[ -n "$qt_platform_theme" ]]; then
        export QT_QPA_PLATFORMTHEME="$qt_platform_theme"
    fi

    if command_exists systemctl; then
        systemctl --user import-environment GTK_THEME QT_STYLE_OVERRIDE QT_QPA_PLATFORMTHEME >/dev/null 2>&1 || true
    fi

    if command_exists dbus-update-activation-environment; then
        dbus-update-activation-environment --systemd GTK_THEME QT_STYLE_OVERRIDE QT_QPA_PLATFORMTHEME >/dev/null 2>&1 || true
    fi
}

seed_gnome_light() {
    set_gsettings_string org.gnome.desktop.interface color-scheme "'prefer-light'" || true
    set_gsettings_string org.gnome.desktop.interface gtk-theme "'Adwaita'" || true
    set_gsettings_string org.gnome.desktop.interface icon-theme "'${icon_theme}'" || true
}

gnome_light_seeded() {
    command_exists "$gsettings_bin" || return 1
    [[ "$("$gsettings_bin" get org.gnome.desktop.interface color-scheme 2>/dev/null || true)" == "'prefer-light'" ]]
}

seed_cinnamon_light() {
    set_gsettings_string org.cinnamon.desktop.interface gtk-theme "'Adwaita'" || true
    set_gsettings_string org.cinnamon.desktop.interface icon-theme "'${icon_theme}'" || true
}

seed_mate_light() {
    set_gsettings_string org.mate.interface gtk-theme "'Adwaita'" || true
    set_gsettings_string org.mate.interface icon-theme "'${icon_theme}'" || true
}

seed_xfce_light() {
    set_xfconf_string xsettings /Net/ThemeName "Adwaita" || true
    set_xfconf_string xsettings /Net/IconThemeName "$icon_theme" || true
}

seed_plasma_light() {
    if command_exists plasma-apply-lookandfeel; then
        plasma-apply-lookandfeel -a org.kde.breeze.desktop >/dev/null 2>&1 || true
    elif command_exists lookandfeeltool; then
        lookandfeeltool -a org.kde.breeze.desktop >/dev/null 2>&1 || true
    fi

    if command_exists kwriteconfig6; then
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeLight >/dev/null 2>&1 || true
        kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze >/dev/null 2>&1 || true
        kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze >/dev/null 2>&1 || true
        kwriteconfig6 --file plasmarc --group Theme --key name breeze-light >/dev/null 2>&1 || true
    elif command_exists kwriteconfig5; then
        kwriteconfig5 --file kdeglobals --group General --key ColorScheme BreezeLight >/dev/null 2>&1 || true
        kwriteconfig5 --file kdeglobals --group KDE --key widgetStyle Breeze >/dev/null 2>&1 || true
        kwriteconfig5 --file kdeglobals --group Icons --key Theme breeze >/dev/null 2>&1 || true
        kwriteconfig5 --file plasmarc --group Theme --key name breeze-light >/dev/null 2>&1 || true
    fi
}

# Every desktop shell defaults to a dark theme out of the box; Abora's
# brand look is light-by-default, so this forces a light GTK/Qt/DE-native
# theme on first login for whichever session is actually running (matched
# by XDG_CURRENT_DESKTOP:DESKTOP_SESSION signature) — runs only once, guarded
# by theme_already_seeded()/mark_theme_seeded(), so a user who deliberately
# switches back to dark afterward never gets overridden again.
seed_light_theme_for_session() {
    local signature="$1"

    write_light_gtk_settings
    write_light_qt_settings

    case "$signature" in
        *COSMIC*:* | *cosmic*:* | *:COSMIC* | *:cosmic*)
            export_light_environment
            ;;
        *mango*:* | *Mango*:* | *MangoWM*:* | *:mango* | *:Mango* | *:MangoWM*)
            export_light_environment "qt6ct"
            ;;
        *GNOME*:* | *gnome*:* | *:gnome* | *:GNOME* | *ubuntu:gnome* | *:ubuntu*)
            seed_gnome_light
            export_light_environment
            ;;
        *Budgie*:* | *budgie*:* | *:budgie* | *:Budgie*)
            seed_gnome_light
            export_light_environment
            ;;
        *Cinnamon*:* | *cinnamon*:* | *:cinnamon* | *:Cinnamon*)
            seed_cinnamon_light
            export_light_environment
            ;;
        *MATE*:* | *mate*:* | *:mate* | *:MATE*)
            seed_mate_light
            export_light_environment
            ;;
        *XFCE*:* | *xfce*:* | *:xfce* | *:XFCE*)
            seed_xfce_light
            export_light_environment
            ;;
        *KDE*:* | *Plasma*:* | *plasma*:* | *:plasma* | *:Plasma*)
            seed_plasma_light
            export_light_environment
            ;;
        *LXQt*:* | *lxqt*:* | *:lxqt* | *:LXQt*)
            write_lxqt_light_settings
            export_light_environment "qt6ct"
            ;;
        *i3*:* | *:i3* | \
        *awesome*:* | *:awesome* | \
        *Openbox*:* | *openbox*:* | *:openbox* | *:Openbox* | \
        *bspwm*:* | *:bspwm* | \
        *qtile*:* | *:qtile* | \
        *fluxbox*:* | *:fluxbox* | \
        *icewm*:* | *:icewm* | \
        *herbstluftwm*:* | *:herbstluftwm*)
            export_light_environment "qt6ct"
            ;;
        *Hyprland*:* | *hyprland*:* | *:hyprland* | *:Hyprland* | \
        *sway*:* | *:sway* | *:sway-uwsm* | \
        *niri*:* | *:niri* | \
        *river*:* | *:river*)
            export_light_environment "qt6ct"
            ;;
        *)
            export_light_environment
            ;;
    esac

    play_launch_sound_once || true
}

seed_gnome_like() {
    local schema="$1"

    set_gsettings_string "$schema" picture-uri "'${default_wallpaper_uri}'" || return 1
    set_gsettings_string "$schema" picture-uri-dark "'${default_dark_wallpaper_uri}'" || true
    set_gsettings_string "$schema" picture-options "'zoom'" || true
}

seed_gnome_wallpapers() {
    seed_gnome_like org.gnome.desktop.background || return 1
    seed_gnome_like org.gnome.desktop.screensaver || true
}

read_gsettings_string() {
    local schema="$1"
    local key="$2"
    local value=""

    command_exists "$gsettings_bin" || return 1
    value="$("$gsettings_bin" get "$schema" "$key" 2>/dev/null || true)"
    value="${value#\'}"
    value="${value%\'}"
    printf '%s\n' "$value"
}

gnome_wallpaper_uri_missing() {
    local schema="$1"
    local key="$2"
    local value=""
    local path=""

    value="$(read_gsettings_string "$schema" "$key" || true)"
    [[ -n "$value" && "$value" != "''" ]] || return 1
    [[ "$value" == file://* ]] || return 0

    path="${value#file://}"
    [[ -s "$path" ]] && return 1
    return 0
}

gnome_wallpaper_schema_empty() {
    local schema="$1"
    local light=""
    local dark=""

    light="$(read_gsettings_string "$schema" picture-uri || true)"
    dark="$(read_gsettings_string "$schema" picture-uri-dark || true)"
    [[ -z "$light" || "$light" == "''" ]] && [[ -z "$dark" || "$dark" == "''" ]]
}

gnome_wallpaper_active_uri_empty() {
    local schema="$1"
    local scheme=""
    local key="picture-uri"
    local value=""

    scheme="$(read_gsettings_string org.gnome.desktop.interface color-scheme || true)"
    if [[ "$scheme" == "prefer-dark" ]]; then
        key="picture-uri-dark"
    fi

    value="$(read_gsettings_string "$schema" "$key" || true)"
    [[ -z "$value" || "$value" == "''" ]]
}

gnome_wallpaper_options_need_repair() {
    local schema="$1"
    local value=""

    value="$(read_gsettings_string "$schema" picture-options || true)"
    case "$value" in
        none|centered|scaled|stretched)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

gnome_wallpaper_is_stale_abora_uri() {
    local schema="$1"
    local key="$2"
    local value=""
    local basename_value=""
    local default_name=""

    value="$(read_gsettings_string "$schema" "$key" || true)"
    [[ "$value" == file://* ]] || return 1

    basename_value="$(basename "${value#file://}")"
    default_name="$(basename "$default_wallpaper")"
    [[ -n "$basename_value" && -n "$default_name" ]] || return 1
    [[ "$basename_value" == "$default_name" ]] && return 1

    case "$value" in
        file:///etc/abora/*|file:///run/current-system/sw/share/backgrounds/abora/*|*abora-gaming*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

gnome_wallpapers_need_repair() {
    gnome_wallpaper_schema_empty org.gnome.desktop.background && return 0
    gnome_wallpaper_active_uri_empty org.gnome.desktop.background && return 0
    gnome_wallpaper_options_need_repair org.gnome.desktop.background && return 0
    gnome_wallpaper_uri_missing org.gnome.desktop.background picture-uri && return 0
    gnome_wallpaper_uri_missing org.gnome.desktop.background picture-uri-dark && return 0
    gnome_wallpaper_is_stale_abora_uri org.gnome.desktop.background picture-uri && return 0
    gnome_wallpaper_is_stale_abora_uri org.gnome.desktop.background picture-uri-dark && return 0
    gnome_wallpaper_active_uri_empty org.gnome.desktop.screensaver && return 0
    gnome_wallpaper_options_need_repair org.gnome.desktop.screensaver && return 0
    gnome_wallpaper_uri_missing org.gnome.desktop.screensaver picture-uri && return 0
    gnome_wallpaper_uri_missing org.gnome.desktop.screensaver picture-uri-dark && return 0
    gnome_wallpaper_is_stale_abora_uri org.gnome.desktop.screensaver picture-uri && return 0
    gnome_wallpaper_is_stale_abora_uri org.gnome.desktop.screensaver picture-uri-dark && return 0
    return 1
}

seed_cinnamon() {
    set_gsettings_string org.cinnamon.desktop.background picture-uri "'${default_wallpaper_uri}'" || return 1
    set_gsettings_string org.cinnamon.desktop.background picture-options "'zoom'" || true
}

seed_mate() {
    set_gsettings_string org.mate.background picture-filename "'${default_wallpaper}'" || return 1
    set_gsettings_string org.mate.background picture-options "'zoom'" || true
}

seed_xfce() {
    local prop=""
    local found=0

    command_exists xfconf-query || return 1

    while IFS= read -r prop; do
        [[ -n "$prop" ]] || continue
        xfconf-query -c xfce4-desktop -p "$prop" -s "$default_wallpaper" >/dev/null 2>&1 || true
        found=1
    done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)

    if [[ "$found" -eq 0 ]]; then
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -n -t string -s "$default_wallpaper" >/dev/null 2>&1 || return 1
    fi
}

seed_plasma() {
    command_exists plasma-apply-wallpaperimage || return 1
    plasma-apply-wallpaperimage "$default_wallpaper" >/dev/null 2>&1
}

seed_lxqt() {
    command_exists pcmanfm-qt || return 1
    pcmanfm-qt --set-wallpaper="$default_wallpaper" >/dev/null 2>&1
}

seed_feh() {
    command_exists feh || return 1
    [[ -n "${DISPLAY:-}" ]] || return 1
    feh --no-fehbg --bg-fill "$default_wallpaper" >/dev/null 2>&1
}

seed_swaybg() {
    command_exists swaybg || return 1
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 1

    if [[ -f "$swaybg_pid_file" ]] && kill -0 "$(cat "$swaybg_pid_file" 2>/dev/null || true)" 2>/dev/null; then
        return 0
    fi

    mkdir -p "$(dirname "$swaybg_pid_file")"
    nohup swaybg -i "$default_wallpaper" -m fill >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$swaybg_pid_file"
}

seed_hyprland() {
    seed_swaybg
}

seed_cosmic() {
    local cosmic_bg_dir="${config_home}/cosmic/com.system76.CosmicBackground/v1"
    local wallpaper_path="$default_wallpaper"

    # Keep COSMIC on the bright default wallpaper too; Titlis Alps should stay
    # visible even if the desktop has its own day/night theme state.
    if [[ ! -s "$wallpaper_path" ]]; then
        wallpaper_path="$default_wallpaper"
    fi

    mkdir -p "$cosmic_bg_dir"

    # Write the COSMIC background config in the same RON files cosmic-bg reads.
    cat > "${cosmic_bg_dir}/all" <<EOF
(
    output: "all",
    source: Path("${wallpaper_path}"),
    filter_by_theme: false,
    rotation_frequency: 3600,
    filter_method: Lanczos,
    scaling_mode: Zoom,
    sampling_method: Alphanumeric,
)
EOF
    printf '[All]\n' > "${cosmic_bg_dir}/backgrounds"
}

run_theme_sync_once() {
    [[ -x "$theme_sync_script" ]] || return 0
    bash "$theme_sync_script" --once >/dev/null 2>&1 || true
}

main() {
    local signature=""
    local wait_seconds="${ABORA_SESSION_SETUP_WAIT:-0}"
    local wallpaper_available=0

    ensure_zsh_profile

    [[ -s "$default_wallpaper" ]] && wallpaper_available=1
    while [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" && "$wait_seconds" =~ ^[0-9]+$ && "$wait_seconds" -gt 0 ]]; do
        sleep 1
        wait_seconds=$((wait_seconds - 1))
    done
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || exit 0

    import_dotfiles_once

    signature="$(desktop_signature)"
    clear_legacy_dark_theme_marker

    if ! theme_already_seeded \
        || { [[ "$signature" == *GNOME*:* || "$signature" == *gnome*:* || "$signature" == *:gnome* || "$signature" == *:GNOME* || "$signature" == *ubuntu:gnome* || "$signature" == *:ubuntu* ]] && ! gnome_light_seeded; }; then
        seed_light_theme_for_session "$signature"
        mark_theme_seeded
    fi

    [[ "$wallpaper_available" -eq 1 ]] || exit 0

    case "$signature" in
        *COSMIC*:* | *cosmic*:* | *:COSMIC* | *:cosmic*)
            if ! already_seeded; then
                seed_cosmic && mark_seeded
            fi
            ;;
        *GNOME*:* | *gnome*:* | *:gnome* | *:GNOME* | *ubuntu:gnome* | *:ubuntu*)
            if ! already_seeded || gnome_wallpapers_need_repair; then
                seed_gnome_wallpapers && mark_seeded
            fi
            run_theme_sync_once
            ;;
        *Budgie*:* | *budgie*:* | *:budgie* | *:Budgie*)
            if ! already_seeded; then
                seed_gnome_like org.gnome.desktop.background && mark_seeded
            fi
            ;;
        *Cinnamon*:* | *cinnamon*:* | *:cinnamon* | *:Cinnamon*)
            if ! already_seeded; then
                seed_cinnamon && mark_seeded
            fi
            ;;
        *MATE*:* | *mate*:* | *:mate* | *:MATE*)
            if ! already_seeded; then
                seed_mate && mark_seeded
            fi
            ;;
        *XFCE*:* | *xfce*:* | *:xfce* | *:XFCE*)
            if ! already_seeded; then
                seed_xfce && mark_seeded
            fi
            ;;
        *KDE*:* | *Plasma*:* | *plasma*:* | *:plasma* | *:Plasma*)
            if ! already_seeded; then
                seed_plasma && mark_seeded
            fi
            ;;
        *LXQt*:* | *lxqt*:* | *:lxqt* | *:LXQt*)
            if ! already_seeded; then
                if seed_lxqt || seed_feh; then
                    mark_seeded
                fi
            fi
            ;;
        *mango*:* | *Mango*:* | *MangoWM*:* | *:mango* | *:Mango* | *:MangoWM*)
            # MangoWM is a wlroots compositor — use swaybg for wallpaper
            if ! already_seeded; then
                seed_swaybg && mark_seeded
            fi
            ;;
        *i3*:* | *:i3* | \
        *awesome*:* | *:awesome* | \
        *Openbox*:* | *openbox*:* | *:openbox* | *:Openbox* | \
        *bspwm*:* | *:bspwm* | \
        *qtile*:* | *:qtile* | \
        *fluxbox*:* | *:fluxbox* | \
        *icewm*:* | *:icewm* | \
        *herbstluftwm*:* | *:herbstluftwm*)
            if ! already_seeded; then
                seed_feh && mark_seeded || true
            fi
            ;;
        *Hyprland*:* | *hyprland*:* | *:hyprland* | *:Hyprland* | \
        *sway*:* | *:sway* | *:sway-uwsm* | \
        *niri*:* | *:niri* | \
        *river*:* | *:river*)
            if ! already_seeded; then
                seed_swaybg && mark_seeded || true
            fi
            ;;
        *)
            if [[ -n "${DISPLAY:-}" ]]; then
                if ! already_seeded; then
                    seed_feh && mark_seeded || true
                fi
            elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
                if ! already_seeded; then
                    seed_swaybg && mark_seeded || true
                fi
            fi
            ;;
    esac
}

main "$@"
