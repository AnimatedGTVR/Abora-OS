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
xfce
cinnamon
mate
budgie
lxqt
i3
openbox
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
    elif grep -q 'windowManager\.i3\.enable = true;' "$file"; then
        printf 'i3\n'
    elif grep -q 'windowManager\.openbox\.enable = true;' "$file"; then
        printf 'openbox\n'
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
    esac
}
