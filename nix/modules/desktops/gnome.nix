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
      accent-color='blue'
      color-scheme='prefer-dark'
      icon-theme='Papirus-Dark'
    '';
    services.displayManager.autoLogin = common.autologin;
    services.displayManager.defaultSession = "gnome";
    services.gnome.gnome-keyring.enable = true;
  };
}
