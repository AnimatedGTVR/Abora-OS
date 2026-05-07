{ lib, config, ... }:
let
  cfg = config.anix;
  desktopType = lib.types.nullOr (lib.types.enum [
    "none" "gnome" "plasma" "hyprland" "sway" "xfce" "cinnamon" "mate"
    "budgie" "lxqt" "pantheon" "lxde" "enlightenment" "i3" "awesome"
    "openbox" "niri" "river" "qtile" "bspwm" "fluxbox" "icewm"
    "herbstluftwm" "dwm"
  ]);
in
{
  options.anix = {
    enable = lib.mkEnableOption "ANIX, a simple layer on top of Abora/NixOS";

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional hostname override applied through the ANIX layer.";
    };

    timezone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional timezone override applied through the ANIX layer.";
    };

    keyboard.console = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional console keymap override applied through the ANIX layer.";
    };

    keyboard.xkb = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional graphical keyboard layout override applied through the ANIX layer.";
    };

    desktop = lib.mkOption {
      type = desktopType;
      default = null;
      description = "Optional desktop override applied through the ANIX layer.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.hostname != null) {
      abora.hostname = lib.mkForce cfg.hostname;
    })
    (lib.mkIf (cfg.timezone != null) {
      abora.timezone = lib.mkForce cfg.timezone;
    })
    (lib.mkIf (cfg.keyboard.console != null) {
      abora.keyboard.console = lib.mkForce cfg.keyboard.console;
    })
    (lib.mkIf (cfg.keyboard.xkb != null) {
      abora.keyboard.xkb = lib.mkForce cfg.keyboard.xkb;
    })
    (lib.mkIf (cfg.desktop != null) {
      abora.desktop = lib.mkForce cfg.desktop;
    })
  ]);
}
