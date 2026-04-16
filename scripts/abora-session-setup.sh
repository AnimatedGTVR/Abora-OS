#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

default_wallpaper="${ABORA_DEFAULT_WALLPAPER:-/etc/abora/default-wallpaper.png}"
default_wallpaper_uri="file://${default_wallpaper}"
gsettings_bin="${ABORA_GSETTINGS_BIN:-gsettings}"
theme_sync_script="${ABORA_THEME_SYNC_SCRIPT:-/etc/abora/theme-sync.sh}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/abora"
marker_file="${state_dir}/wallpaper-seed"
theme_marker_file="${state_dir}/dark-theme-seed"
swaybg_pid_file="${XDG_RUNTIME_DIR:-/tmp}/abora-swaybg.pid"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
qt5ct_colors="${ABORA_QT5CT_COLORS:-/run/current-system/sw/share/qt5ct/colors/darker.conf}"
qt6ct_colors="${ABORA_QT6CT_COLORS:-/run/current-system/sw/share/qt6ct/colors/darker.conf}"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

desktop_signature() {
    printf '%s:%s\n' "${XDG_CURRENT_DESKTOP:-}" "${DESKTOP_SESSION:-}"
}

mark_seeded() {
    mkdir -p "$state_dir"
    printf '%s\n' "$(basename "$default_wallpaper")" > "$marker_file"
}

already_seeded() {
    [[ -f "$marker_file" ]] || return 1
    [[ "$(cat "$marker_file" 2>/dev/null || true)" == "$(basename "$default_wallpaper")" ]]
}

mark_theme_seeded() {
    mkdir -p "$state_dir"
    printf 'dark\n' > "$theme_marker_file"
}

theme_already_seeded() {
    [[ -f "$theme_marker_file" ]]
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

write_dark_gtk_settings() {
    local gtk3_dir="${config_home}/gtk-3.0"
    local gtk4_dir="${config_home}/gtk-4.0"

    mkdir -p "$gtk3_dir" "$gtk4_dir"

    cat > "${gtk3_dir}/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
EOF

    cat > "${gtk4_dir}/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
EOF
}

write_dark_qt_settings() {
    local qt5_dir="${config_home}/qt5ct"
    local qt6_dir="${config_home}/qt6ct"

    mkdir -p "$qt5_dir" "$qt6_dir"

    cat > "${qt5_dir}/qt5ct.conf" <<EOF
[Appearance]
color_scheme_path=${qt5ct_colors}
custom_palette=true
icon_theme=Adwaita
standard_dialogs=default
style=Fusion
EOF

    cat > "${qt6_dir}/qt6ct.conf" <<EOF
[Appearance]
color_scheme_path=${qt6ct_colors}
custom_palette=true
icon_theme=Adwaita
standard_dialogs=default
style=Fusion
EOF
}

write_lxqt_dark_settings() {
    local lxqt_dir="${config_home}/lxqt"

    mkdir -p "$lxqt_dir"

    cat > "${lxqt_dir}/lxqt.conf" <<'EOF'
[General]
icon_theme=Adwaita
theme=dark

[Qt]
style=Fusion
EOF
}

export_dark_environment() {
    local qt_platform_theme="${1:-}"

    export GTK_THEME="Adwaita:dark"
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

seed_gnome_dark() {
    set_gsettings_string org.gnome.desktop.interface color-scheme "'prefer-dark'" || true
    set_gsettings_string org.gnome.desktop.interface gtk-theme "'Adwaita-dark'" || true
}

seed_cinnamon_dark() {
    set_gsettings_string org.cinnamon.desktop.interface gtk-theme "'Adwaita-dark'" || true
    set_gsettings_string org.cinnamon.desktop.interface icon-theme "'Adwaita'" || true
}

seed_mate_dark() {
    set_gsettings_string org.mate.interface gtk-theme "'Adwaita-dark'" || true
    set_gsettings_string org.mate.interface icon-theme "'Adwaita'" || true
}

seed_xfce_dark() {
    set_xfconf_string xsettings /Net/ThemeName "Adwaita-dark" || true
    set_xfconf_string xsettings /Net/IconThemeName "Adwaita" || true
}

seed_plasma_dark() {
    if command_exists plasma-apply-lookandfeel; then
        plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null 2>&1 || true
    elif command_exists lookandfeeltool; then
        lookandfeeltool -a org.kde.breezedark.desktop >/dev/null 2>&1 || true
    fi

    if command_exists kwriteconfig6; then
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark >/dev/null 2>&1 || true
        kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze >/dev/null 2>&1 || true
        kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark >/dev/null 2>&1 || true
        kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark >/dev/null 2>&1 || true
    elif command_exists kwriteconfig5; then
        kwriteconfig5 --file kdeglobals --group General --key ColorScheme BreezeDark >/dev/null 2>&1 || true
        kwriteconfig5 --file kdeglobals --group KDE --key widgetStyle Breeze >/dev/null 2>&1 || true
        kwriteconfig5 --file kdeglobals --group Icons --key Theme breeze-dark >/dev/null 2>&1 || true
        kwriteconfig5 --file plasmarc --group Theme --key name breeze-dark >/dev/null 2>&1 || true
    fi
}

seed_dark_theme_for_session() {
    local signature="$1"

    write_dark_gtk_settings
    write_dark_qt_settings

    case "$signature" in
        *GNOME*:* | *gnome*:* | *:gnome* | *:GNOME* | *ubuntu:gnome* | *:ubuntu*)
            seed_gnome_dark
            export_dark_environment
            ;;
        *Budgie*:* | *budgie*:* | *:budgie* | *:Budgie*)
            seed_gnome_dark
            export_dark_environment
            ;;
        *Cinnamon*:* | *cinnamon*:* | *:cinnamon* | *:Cinnamon*)
            seed_cinnamon_dark
            export_dark_environment
            ;;
        *MATE*:* | *mate*:* | *:mate* | *:MATE*)
            seed_mate_dark
            export_dark_environment
            ;;
        *XFCE*:* | *xfce*:* | *:xfce* | *:XFCE*)
            seed_xfce_dark
            export_dark_environment
            ;;
        *KDE*:* | *Plasma*:* | *plasma*:* | *:plasma* | *:Plasma*)
            seed_plasma_dark
            export_dark_environment
            ;;
        *LXQt*:* | *lxqt*:* | *:lxqt* | *:LXQt*)
            write_lxqt_dark_settings
            export_dark_environment "qt6ct"
            ;;
        *i3*:* | *:i3* | \
        *awesome*:* | *:awesome* | \
        *Openbox*:* | *openbox*:* | *:openbox* | *:Openbox* | \
        *bspwm*:* | *:bspwm* | \
        *qtile*:* | *:qtile* | \
        *fluxbox*:* | *:fluxbox* | \
        *icewm*:* | *:icewm* | \
        *herbstluftwm*:* | *:herbstluftwm* | \
        *dwm*:* | *:dwm*)
            export_dark_environment "qt6ct"
            ;;
        *Hyprland*:* | *hyprland*:* | *:hyprland* | *:Hyprland* | \
        *sway*:* | *:sway* | *:sway-uwsm* | \
        *niri*:* | *:niri* | \
        *river*:* | *:river*)
            export_dark_environment "qt6ct"
            ;;
        *)
            export_dark_environment
            ;;
    esac
}

seed_gnome_like() {
    local schema="$1"

    set_gsettings_string "$schema" picture-uri "'${default_wallpaper_uri}'" || return 1
    set_gsettings_string "$schema" picture-uri-dark "'${default_wallpaper_uri}'" || true
    set_gsettings_string "$schema" picture-options "'zoom'" || true
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

    nohup swaybg -i "$default_wallpaper" -m fill >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$swaybg_pid_file"
}

seed_hyprland() {
    seed_swaybg
}

run_theme_sync_once() {
    [[ -x "$theme_sync_script" ]] || return 0
    bash "$theme_sync_script" --once >/dev/null 2>&1 || true
}

main() {
    local signature=""

    [[ -f "$default_wallpaper" ]] || exit 0
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || exit 0

    signature="$(desktop_signature)"

    if ! theme_already_seeded; then
        seed_dark_theme_for_session "$signature"
        mark_theme_seeded
    fi

    case "$signature" in
        *GNOME*:* | *gnome*:* | *:gnome* | *:GNOME* | *ubuntu:gnome* | *:ubuntu*)
            if ! already_seeded; then
                seed_gnome_like org.gnome.desktop.background && mark_seeded
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
        *i3*:* | *:i3* | \
        *awesome*:* | *:awesome* | \
        *Openbox*:* | *openbox*:* | *:openbox* | *:Openbox* | \
        *bspwm*:* | *:bspwm* | \
        *qtile*:* | *:qtile* | \
        *fluxbox*:* | *:fluxbox* | \
        *icewm*:* | *:icewm* | \
        *herbstluftwm*:* | *:herbstluftwm* | \
        *dwm*:* | *:dwm*)
            seed_feh || true
            ;;
        *Hyprland*:* | *hyprland*:* | *:hyprland* | *:Hyprland* | \
        *sway*:* | *:sway* | *:sway-uwsm* | \
        *niri*:* | *:niri* | \
        *river*:* | *:river*)
            seed_swaybg || true
            ;;
        *)
            if [[ -n "${DISPLAY:-}" ]]; then
                seed_feh || true
            elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
                seed_swaybg || true
            fi
            ;;
    esac
}

main "$@"
