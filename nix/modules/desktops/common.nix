{ config, ... }:
let
  cfg = config.abora;
in
{
  inherit cfg;

  active = cfg.user.name != null;
  enabled = name: cfg.user.name != null && cfg.desktop == name;

  defaultWallpaperPath = "/run/current-system/sw/share/backgrounds/abora/${cfg.wallpaper}";
  defaultWallpaperUri = "file:///run/current-system/sw/share/backgrounds/abora/${cfg.wallpaper}";
  defaultDarkWallpaper =
    if cfg.wallpaper == "Daytime-MNT.jpg" then
      "NightTime-MNT.png"
    else
      cfg.wallpaper;
  defaultDarkWallpaperUri =
    "file:///run/current-system/sw/share/backgrounds/abora/${
      if cfg.wallpaper == "Daytime-MNT.jpg" then "NightTime-MNT.png" else cfg.wallpaper
    }";

  autologin = {
    enable = true;
    user = cfg.user.name;
  };

  xserver = {
    enable = true;
    xkb.layout = cfg.keyboard.xkb;
  };
}
