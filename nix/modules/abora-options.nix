{ lib, pkgs, config, ... }:
# ── Abora OS options module ───────────────────────────────────────────────────
# Provides the abora.* option namespace so abora-local.nix can be written
# as simple key-value pairs rather than raw NixOS expressions.
#
# This module is safe to import on older installs: it does nothing unless
# abora.user.name is set.
let
  cfg = config.abora;
  active = cfg.user.name != null;
  wallpaperDir =
    if builtins.pathExists ./wallpapers then
      ./wallpapers
    else
      ../../assets/wallpapers/collection;
  defaultWallpaperPath = "/run/current-system/sw/share/backgrounds/abora/${cfg.wallpaper}";
  defaultWallpaperUri = "file://${defaultWallpaperPath}";

  desktopLabel = {
    none         = "No desktop";
    gnome        = "GNOME";
    plasma       = "Plasma";
    hyprland     = "Hyprland";
    sway         = "Sway";
    xfce         = "XFCE";
    cinnamon     = "Cinnamon";
    mate         = "MATE";
    budgie       = "Budgie";
    lxqt         = "LXQt";
    pantheon     = "Pantheon";
    enlightenment = "Enlightenment";
    i3           = "i3";
    awesome      = "AwesomeWM";
    openbox      = "Openbox";
    niri         = "Niri";
    river        = "River";
    qtile        = "Qtile";
    bspwm        = "BSPWM";
    fluxbox      = "Fluxbox";
    icewm        = "IceWM";
    herbstluftwm = "Herbstluftwm";
    dwm          = "DWM";
  }.${cfg.desktop} or "Abora";

  is = d: active && cfg.desktop == d;
in
{
  options.abora = {
    # ── Identity ────────────────────────────────────────────────────────────

    hostname = lib.mkOption {
      type    = lib.types.str;
      default = "abora";
      description = "The machine hostname.";
    };

    timezone = lib.mkOption {
      type    = lib.types.str;
      default = "UTC";
      example = "America/New_York";
      description = "System timezone (see /usr/share/zoneinfo for valid values).";
    };

    keyboard = {
      console = lib.mkOption {
        type    = lib.types.str;
        default = "us";
        description = "Console keymap used in TTYs (e.g. us, de, fr).";
      };
      xkb = lib.mkOption {
        type    = lib.types.str;
        default = "us";
        description = "X11/Wayland keyboard layout (e.g. us, de, fr).";
      };
    };

    # ── User ────────────────────────────────────────────────────────────────

    user = {
      name = lib.mkOption {
        type    = lib.types.nullOr lib.types.str;
        default = null;
        description = "Primary user account name. Setting this activates the full Abora config.";
      };
      hashedPassword = lib.mkOption {
        type    = lib.types.str;
        default = "";
        description = "Hashed password for the primary user. Generate with: mkpasswd";
      };
    };

    # ── Desktop ─────────────────────────────────────────────────────────────

    desktop = lib.mkOption {
      type = lib.types.enum [
        "none" "gnome" "plasma" "hyprland" "sway" "xfce" "cinnamon" "mate"
        "budgie" "lxqt" "pantheon" "enlightenment" "i3"
        "awesome" "openbox" "niri" "river" "qtile" "bspwm" "fluxbox"
        "icewm" "herbstluftwm" "dwm"
      ];
      default     = "gnome";
      description = "Desktop environment or window manager to enable.";
    };

    # ── Hardware ────────────────────────────────────────────────────────────

    disk = lib.mkOption {
      type    = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/sda";
      description = "Install disk for the Limine bootloader (e.g. /dev/sda, /dev/nvme0n1).";
    };

    stateVersion = lib.mkOption {
      type    = lib.types.str;
      default = "26.05";
      description = "NixOS state version. Set once at install time — do not change afterwards.";
    };

    wallpaper = lib.mkOption {
      type = lib.types.enum (builtins.attrNames (builtins.readDir wallpaperDir));
      default = "oceandusk.png";
      description = "Default wallpaper file shipped with Abora.";
    };
  };

  # ── Config ─────────────────────────────────────────────────────────────────
  # Nothing below applies unless abora.user.name is set.

  config = lib.mkMerge [

    # Always apply these with mkDefault so they lose to any direct override.
      {
        networking.hostName = lib.mkDefault cfg.hostname;
        time.timeZone       = lib.mkDefault cfg.timezone;
        console.keyMap      = lib.mkDefault cfg.keyboard.console;
        environment.variables.ABORA_DEFAULT_WALLPAPER = lib.mkDefault defaultWallpaperPath;
      }

    # Everything else requires abora.user.name to be set.
    (lib.mkIf active (lib.mkMerge [

      # ── Common ─────────────────────────────────────────────────────────
      {
        system.nixos.variantName = lib.mkOverride 900 "Abora ${desktopLabel} Edition";
        system.nixos.variant_id  = lib.mkOverride 900 cfg.desktop;

        system.stateVersion = cfg.stateVersion;

        security.sudo.wheelNeedsPassword = true;

        users.users.${cfg.user.name} = {
          isNormalUser = true;
          description  = "Abora User";
          createHome   = true;
          extraGroups  = [ "wheel" "networkmanager" "audio" "video" ];
          hashedPassword = cfg.user.hashedPassword;
        };
      }

      # ── Bootloader ─────────────────────────────────────────────────────
      (lib.mkIf (cfg.disk != null) {
        boot.loader.grub.enable = lib.mkForce false;
        boot.loader.limine = {
          enable              = true;
          biosSupport         = true;
          biosDevice          = cfg.disk;
          efiSupport          = true;
          efiInstallAsRemovable = true;
        };
      })

      # ── GNOME ──────────────────────────────────────────────────────────
      (lib.mkIf (is "none") {
        services.getty.autologinUser = cfg.user.name;
      })

      # ── GNOME ──────────────────────────────────────────────────────────
      (lib.mkIf (is "gnome") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        services.displayManager.gdm.enable   = true;
        services.desktopManager.gnome.enable = true;
        services.desktopManager.gnome.extraGSettingsOverrides = ''
          [org.gnome.desktop.background]
          picture-uri='${defaultWallpaperUri}'
          picture-uri-dark='${defaultWallpaperUri}'
          picture-options='zoom'
          color-shading-type='solid'
          primary-color='#081223'
          secondary-color='#081223'

          [org.gnome.desktop.interface]
          accent-color='blue'
          color-scheme='prefer-dark'
        '';
        services.displayManager.autoLogin.enable = true;
        services.displayManager.autoLogin.user   = cfg.user.name;
        services.displayManager.defaultSession   = "gnome";
        services.gnome.gnome-keyring.enable      = true;
      })

      # ── Plasma ─────────────────────────────────────────────────────────
      (lib.mkIf (is "plasma") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        services.displayManager = {
          defaultSession      = "plasma";
          autoLogin.enable    = true;
          autoLogin.user      = cfg.user.name;
        };
        services.displayManager.sddm.enable     = true;
        services.desktopManager.plasma6.enable  = true;
      })

      # ── Hyprland ───────────────────────────────────────────────────────
      (lib.mkIf (is "hyprland") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        services.displayManager = {
          defaultSession   = "hyprland-uwsm";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.displayManager.sddm = {
          enable         = true;
          wayland.enable = true;
        };
        programs.hyprland = {
          enable          = true;
          withUWSM        = true;
          xwayland.enable = true;
        };
        xdg.portal.enable       = true;
        xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      })

      # ── Sway ───────────────────────────────────────────────────────────
      (lib.mkIf (is "sway") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        programs.sway = {
          enable               = true;
          wrapperFeatures.gtk  = true;
        };
        services.displayManager = {
          defaultSession   = "sway";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.displayManager.sddm = {
          enable         = true;
          wayland.enable = true;
        };
        xdg.portal.enable       = true;
        xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      })

      # ── XFCE ───────────────────────────────────────────────────────────
      (lib.mkIf (is "xfce") {
        services.xserver = {
          enable                    = true;
          xkb.layout                = cfg.keyboard.xkb;
          desktopManager.xfce.enable = true;
        };
        services.displayManager = {
          defaultSession   = "xfce";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── Cinnamon ───────────────────────────────────────────────────────
      (lib.mkIf (is "cinnamon") {
        services.xserver = {
          enable                         = true;
          xkb.layout                     = cfg.keyboard.xkb;
          desktopManager.cinnamon.enable = true;
        };
        services.displayManager = {
          defaultSession   = "cinnamon";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── MATE ───────────────────────────────────────────────────────────
      (lib.mkIf (is "mate") {
        services.xserver = {
          enable                     = true;
          xkb.layout                 = cfg.keyboard.xkb;
          desktopManager.mate.enable = true;
        };
        services.displayManager = {
          defaultSession   = "mate";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── Budgie ─────────────────────────────────────────────────────────
      (lib.mkIf (is "budgie") {
        services.xserver = {
          enable                       = true;
          xkb.layout                   = cfg.keyboard.xkb;
          desktopManager.budgie.enable = true;
        };
        services.displayManager = {
          defaultSession   = "budgie-desktop";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── LXQt ───────────────────────────────────────────────────────────
      (lib.mkIf (is "lxqt") {
        services.xserver = {
          enable                     = true;
          xkb.layout                 = cfg.keyboard.xkb;
          desktopManager.lxqt.enable = true;
        };
        services.displayManager = {
          defaultSession   = "lxqt";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.displayManager.sddm.enable = true;
      })

      # ── Pantheon ───────────────────────────────────────────────────────
      (lib.mkIf (is "pantheon") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        services.displayManager = {
          defaultSession   = "pantheon-wayland";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable      = true;
        services.xserver.desktopManager.pantheon.enable     = true;
      })

      # ── Enlightenment ──────────────────────────────────────────────────
      (lib.mkIf (is "enlightenment") {
        services.xserver = {
          enable                              = true;
          xkb.layout                          = cfg.keyboard.xkb;
          desktopManager.enlightenment.enable = true;
        };
        services.displayManager = {
          defaultSession   = "enlightenment";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── AwesomeWM ──────────────────────────────────────────────────────
      (lib.mkIf (is "awesome") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.awesome.enable       = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "none+awesome";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── i3 ─────────────────────────────────────────────────────────────
      (lib.mkIf (is "i3") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.i3.enable            = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "none+i3";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── Openbox ────────────────────────────────────────────────────────
      (lib.mkIf (is "openbox") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.openbox.enable       = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "none+openbox";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── Niri ───────────────────────────────────────────────────────────
      (lib.mkIf (is "niri") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        programs.niri.enable = true;
        services.displayManager = {
          defaultSession   = "niri";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.displayManager.sddm = {
          enable         = true;
          wayland.enable = true;
        };
        xdg.portal.enable       = true;
        xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      })

      # ── River ──────────────────────────────────────────────────────────
      (lib.mkIf (is "river") {
        services.xserver = {
          enable     = true;
          xkb.layout = cfg.keyboard.xkb;
        };
        programs.river = {
          enable          = true;
          xwayland.enable = true;
        };
        services.displayManager = {
          defaultSession   = "river";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.displayManager.sddm = {
          enable         = true;
          wayland.enable = true;
        };
        xdg.portal.enable       = true;
        xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      })

      # ── Qtile ──────────────────────────────────────────────────────────
      (lib.mkIf (is "qtile") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.qtile.enable         = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "none+qtile";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── BSPWM ──────────────────────────────────────────────────────────
      (lib.mkIf (is "bspwm") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.bspwm.enable         = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "none+bspwm";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
        environment.systemPackages = [ pkgs.sxhkd ];
      })

      # ── Fluxbox ────────────────────────────────────────────────────────
      (lib.mkIf (is "fluxbox") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.fluxbox.enable       = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "fluxbox";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── IceWM ──────────────────────────────────────────────────────────
      (lib.mkIf (is "icewm") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.icewm.enable         = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "icewm-session";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── Herbstluftwm ───────────────────────────────────────────────────
      (lib.mkIf (is "herbstluftwm") {
        services.xserver = {
          enable                                = true;
          xkb.layout                            = cfg.keyboard.xkb;
          windowManager.herbstluftwm.enable     = true;
          desktopManager.runXdgAutostartIfNone  = true;
        };
        services.displayManager = {
          defaultSession   = "none+herbstluftwm";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

      # ── DWM ────────────────────────────────────────────────────────────
      (lib.mkIf (is "dwm") {
        services.xserver = {
          enable                             = true;
          xkb.layout                         = cfg.keyboard.xkb;
          windowManager.dwm.enable           = true;
          desktopManager.runXdgAutostartIfNone = true;
        };
        services.displayManager = {
          defaultSession   = "none+dwm";
          autoLogin.enable = true;
          autoLogin.user   = cfg.user.name;
        };
        services.xserver.displayManager.lightdm.enable = true;
      })

    ])) # end mkIf active
  ];
}
