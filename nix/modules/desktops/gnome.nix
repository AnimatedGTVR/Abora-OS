{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "gnome") {
    services.xserver = common.xserver;
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;
    services.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.background]
      picture-uri='${common.defaultWallpaperUri}'
      picture-uri-dark='${common.defaultDarkWallpaperUri}'
      picture-options='zoom'
      color-shading-type='solid'
      primary-color='#081223'
      secondary-color='#081223'

      [org.gnome.desktop.interface]
      accent-color='teal'
      color-scheme='prefer-light'
      font-name='Inter 11'
      document-font-name='Inter 11'
      monospace-font-name='JetBrains Mono 10'
      icon-theme='Papirus'
      gtk-theme='Adwaita'

      [org.gnome.desktop.wm.preferences]
      button-layout='appmenu:minimize,maximize,close'
      titlebar-font='Inter Bold 11'
      num-workspaces=4

      [org.gnome.mutter]
      edge-tiling=true
      dynamic-workspaces=false

      [org.gnome.shell]
      enabled-extensions=['dash-to-dock@micxgx.gmail.com', 'blur-my-shell@aunetx', 'appindicatorsupport@rgcjonas.gmail.com', 'caffeine@patapon.info']
      favorite-apps=['org.gnome.Nautilus.desktop', 'org.kde.konsole.desktop', 'org.mozilla.firefox.desktop', 'org.gnome.Settings.desktop']

      [org.gnome.desktop.default-applications.terminal]
      exec='konsole'
      exec-arg='-e'

      [org.gnome.shell.extensions.dash-to-dock]
      dock-position='BOTTOM'
      extend-height=false
      dock-fixed=false
      autohide=true
      autohide-in-fullscreen=true
      intellihide=true
      transparency-mode='FIXED'
      background-opacity=0.75
      dash-max-icon-size=56
      show-apps-at-top=false
      show-trash=false
      show-mounts=false
      custom-theme-shrink=false
      running-indicator-style='DOTS'

      [org.gnome.shell.extensions.blur-my-shell]
      blur-dash=true
      blur-panel=true
      blur-overview=true
      sigma=20
      brightness=0.7

      [org.gnome.Terminal.Legacy.Settings]
      theme-variant='light'
    '';
    services.displayManager.autoLogin = common.autologin;
    services.displayManager.defaultSession = "gnome";
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gnome-initial-setup.enable = lib.mkForce false;
  };
}
