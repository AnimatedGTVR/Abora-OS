#!/usr/bin/env bash

abora_default_wallpaper_name() {
    printf 'oceandusk.png\n'
}

abora_default_wallpaper_uri() {
    printf 'file:///run/current-system/sw/share/backgrounds/abora/%s\n' "$(abora_default_wallpaper_name)"
}

abora_supported_desktop_profiles() {
    cat <<'EOF'
gnome
plasma
hyprland
sway
xfce
cinnamon
mate
budgie
lxqt
pantheon
lxde
enlightenment
i3
awesome
openbox
niri
river
qtile
bspwm
fluxbox
icewm
herbstluftwm
dwm
EOF
}

abora_sync_desktop_label() {
    case "$1" in
        gnome)
            desktop_label="GNOME"
            desktop_variant_id="gnome"
            ;;
        plasma)
            desktop_label="Plasma"
            desktop_variant_id="plasma"
            ;;
        hyprland)
            desktop_label="Hyprland"
            desktop_variant_id="hyprland"
            ;;
        xfce)
            desktop_label="XFCE"
            desktop_variant_id="xfce"
            ;;
        cinnamon)
            desktop_label="Cinnamon"
            desktop_variant_id="cinnamon"
            ;;
        mate)
            desktop_label="MATE"
            desktop_variant_id="mate"
            ;;
        budgie)
            desktop_label="Budgie"
            desktop_variant_id="budgie"
            ;;
        lxqt)
            desktop_label="LXQt"
            desktop_variant_id="lxqt"
            ;;
        sway)
            desktop_label="Sway"
            desktop_variant_id="sway"
            ;;
        lxde)
            desktop_label="LXDE"
            desktop_variant_id="lxde"
            ;;
        enlightenment)
            desktop_label="Enlightenment"
            desktop_variant_id="enlightenment"
            ;;
        awesome)
            desktop_label="AwesomeWM"
            desktop_variant_id="awesome"
            ;;
        pantheon)
            desktop_label="Pantheon"
            desktop_variant_id="pantheon"
            ;;
        i3)
            desktop_label="i3"
            desktop_variant_id="i3"
            ;;
        openbox)
            desktop_label="Openbox"
            desktop_variant_id="openbox"
            ;;
        niri)
            desktop_label="Niri"
            desktop_variant_id="niri"
            ;;
        river)
            desktop_label="River"
            desktop_variant_id="river"
            ;;
        qtile)
            desktop_label="Qtile"
            desktop_variant_id="qtile"
            ;;
        bspwm)
            desktop_label="BSPWM"
            desktop_variant_id="bspwm"
            ;;
        fluxbox)
            desktop_label="Fluxbox"
            desktop_variant_id="fluxbox"
            ;;
        icewm)
            desktop_label="IceWM"
            desktop_variant_id="icewm"
            ;;
        herbstluftwm)
            desktop_label="Herbstluftwm"
            desktop_variant_id="herbstluftwm"
            ;;
        dwm)
            desktop_label="DWM"
            desktop_variant_id="dwm"
            ;;
        *)
            desktop_label="GNOME"
            desktop_variant_id="gnome"
            ;;
    esac
}

abora_detect_desktop_profile() {
    local file="$1"

    if grep -q 'programs\.hyprland = {' "$file" || grep -q 'defaultSession = "hyprland-uwsm";' "$file"; then
        printf 'hyprland\n'
    elif grep -q 'services\.desktopManager\.plasma6\.enable = true;' "$file"; then
        printf 'plasma\n'
    elif grep -q 'desktopManager\.xfce\.enable = true;' "$file"; then
        printf 'xfce\n'
    elif grep -q 'desktopManager\.cinnamon\.enable = true;' "$file"; then
        printf 'cinnamon\n'
    elif grep -q 'desktopManager\.mate\.enable = true;' "$file"; then
        printf 'mate\n'
    elif grep -q 'desktopManager\.budgie\.enable = true;' "$file"; then
        printf 'budgie\n'
    elif grep -q 'desktopManager\.lxqt\.enable = true;' "$file"; then
        printf 'lxqt\n'
    elif grep -q 'desktopManager\.pantheon\.enable = true;' "$file"; then
        printf 'pantheon\n'
    elif grep -q 'programs\.sway\.enable = true;' "$file"; then
        printf 'sway\n'
    elif grep -q 'desktopManager\.lxde\.enable = true;' "$file"; then
        printf 'lxde\n'
    elif grep -q 'desktopManager\.enlightenment\.enable = true;' "$file"; then
        printf 'enlightenment\n'
    elif grep -q 'windowManager\.awesome\.enable = true;' "$file"; then
        printf 'awesome\n'
    elif grep -q 'windowManager\.i3\.enable = true;' "$file"; then
        printf 'i3\n'
    elif grep -q 'windowManager\.openbox\.enable = true;' "$file"; then
        printf 'openbox\n'
    elif grep -q 'programs\.niri\.enable = true;' "$file"; then
        printf 'niri\n'
    elif grep -q 'programs\.river\.enable = true;' "$file"; then
        printf 'river\n'
    elif grep -q 'windowManager\.qtile\.enable = true;' "$file"; then
        printf 'qtile\n'
    elif grep -q 'windowManager\.bspwm\.enable = true;' "$file"; then
        printf 'bspwm\n'
    elif grep -q 'windowManager\.fluxbox\.enable = true;' "$file"; then
        printf 'fluxbox\n'
    elif grep -q 'windowManager\.icewm\.enable = true;' "$file"; then
        printf 'icewm\n'
    elif grep -q 'windowManager\.herbstluftwm\.enable = true;' "$file"; then
        printf 'herbstluftwm\n'
    elif grep -q 'windowManager\.dwm\.enable = true;' "$file"; then
        printf 'dwm\n'
    else
        printf 'gnome\n'
    fi
}

abora_desktop_config_block() {
    local desktop_profile="$1"
    local xkb_layout_value="$2"
    local username_value="$3"
    local default_wallpaper_uri="${4:-$(abora_default_wallpaper_uri)}"

    case "$desktop_profile" in
        gnome)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.desktop.background]
    picture-uri='${default_wallpaper_uri}'
    picture-uri-dark='${default_wallpaper_uri}'
    picture-options='zoom'
    color-shading-type='solid'
    primary-color='#081223'
    secondary-color='#081223'

    [org.gnome.desktop.interface]
    accent-color='blue'
    color-scheme='prefer-dark'
  '';
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "${username_value}";
  services.displayManager.defaultSession = "gnome";
  services.gnome.gnome-keyring.enable = true;
EOF
            ;;
        plasma)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "plasma";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
EOF
            ;;
        hyprland)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "hyprland-uwsm";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
EOF
            ;;
        xfce)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.xfce.enable = true;
  };
  services.displayManager = {
    defaultSession = "xfce";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        cinnamon)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.cinnamon.enable = true;
  };
  services.displayManager = {
    defaultSession = "cinnamon";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        mate)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.mate.enable = true;
  };
  services.displayManager = {
    defaultSession = "mate";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        budgie)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.budgie.enable = true;
  };
  services.displayManager = {
    defaultSession = "budgie-desktop";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        lxqt)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.lxqt.enable = true;
  };
  services.displayManager = {
    defaultSession = "lxqt";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm.enable = true;
EOF
            ;;
        pantheon)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  services.displayManager = {
    defaultSession = "pantheon-wayland";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.pantheon.enable = true;
EOF
            ;;
        sway)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };
  services.displayManager = {
    defaultSession = "sway";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
EOF
            ;;
        lxde)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.lxde.enable = true;
  };
  services.displayManager = {
    defaultSession = "lxde";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        enlightenment)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    desktopManager.enlightenment.enable = true;
  };
  services.displayManager = {
    defaultSession = "enlightenment";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        awesome)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.awesome.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+awesome";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        i3)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.i3.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+i3";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        openbox)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.openbox.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+openbox";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        niri)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  programs.niri.enable = true;
  services.displayManager = {
    defaultSession = "niri";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
EOF
            ;;
        river)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
  };
  programs.river = {
    enable = true;
    xwayland.enable = true;
  };
  services.displayManager = {
    defaultSession = "river";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
EOF
            ;;
        qtile)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.qtile.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+qtile";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        bspwm)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.bspwm.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+bspwm";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        fluxbox)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.fluxbox.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "fluxbox";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        icewm)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.icewm.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "icewm-session";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        herbstluftwm)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.herbstluftwm.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+herbstluftwm";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
        dwm)
            cat <<EOF
  services.xserver = {
    enable = true;
    xkb.layout = "${xkb_layout_value}";
    windowManager.dwm.enable = true;
  };
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.displayManager = {
    defaultSession = "none+dwm";
    autoLogin.enable = true;
    autoLogin.user = "${username_value}";
  };
  services.xserver.displayManager.lightdm.enable = true;
EOF
            ;;
    esac
}

abora_desktop_package_block() {
    case "$1" in
        hyprland)
            cat <<'EOF'
    kitty
    swaybg
EOF
            ;;
        sway)
            cat <<'EOF'
    foot
    swayidle
    swaylock
EOF
            ;;
        niri)
            cat <<'EOF'
    foot
    waybar
    fuzzel
EOF
            ;;
        river)
            cat <<'EOF'
    foot
    waybar
    wofi
EOF
            ;;
        bspwm)
            cat <<'EOF'
    sxhkd
EOF
            ;;
    esac
}
