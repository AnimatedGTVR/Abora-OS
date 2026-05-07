{ lib, config, options, ... }:
let
  cfg = config.anix;
in
{
  options.anix = {
    enable = lib.mkEnableOption "ANIX, a simple configuration layer for NixOS";

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional hostname override.";
    };

    timezone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional timezone override (e.g. America/New_York).";
    };

    keyboard.console = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional console keymap (e.g. us, de, fr).";
    };

    keyboard.xkb = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional graphical keyboard layout (e.g. us, de, fr).";
    };

    desktop = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "none" "gnome" "plasma" "hyprland" "sway" "xfce" "cinnamon" "mate"
        "budgie" "lxqt" "pantheon" "enlightenment" "i3" "awesome"
        "openbox" "niri" "river" "qtile" "bspwm" "fluxbox" "icewm"
        "herbstluftwm"
      ]);
      default = null;
      description = "Optional desktop override (requires Abora OS for full effect).";
    };

    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional wallpaper filename (requires Abora OS).";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.hostname != null) {
      networking.hostName = lib.mkForce cfg.hostname;
    })
    (lib.mkIf (cfg.timezone != null) {
      time.timeZone = lib.mkForce cfg.timezone;
    })
    (lib.mkIf (cfg.keyboard.console != null) {
      console.keyMap = lib.mkForce cfg.keyboard.console;
    })
    (lib.mkIf (cfg.keyboard.xkb != null) {
      services.xserver.xkb.layout = lib.mkForce cfg.keyboard.xkb;
    })
    # desktop and wallpaper only take effect when running under Abora OS
    (lib.mkIf (cfg.desktop != null && options ? abora) {
      abora.desktop = lib.mkForce cfg.desktop;
    })
    (lib.mkIf (cfg.wallpaper != null && options ? abora) {
      abora.wallpaper = lib.mkForce cfg.wallpaper;
    })
  ]);
}
