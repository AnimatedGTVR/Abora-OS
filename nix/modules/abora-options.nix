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
  wallpaperDir = ./wallpapers;
  bundledWallpaperNames = [
    "alpine-glacier.jpg"
    "tannheimer-mountains.jpg"
    "titlis-alps.jpg"
    "aurora-lofoten.jpg"
  ];
  discoveredWallpaperNames =
    builtins.attrNames (builtins.readDir wallpaperDir);
  wallpaperNames =
    lib.unique (bundledWallpaperNames ++ discoveredWallpaperNames);
  defaultWallpaperPath = "/run/current-system/sw/share/backgrounds/abora/${cfg.wallpaper}";

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
    cosmic       = "COSMIC";
    mangowm      = "MangoWM";
  }.${cfg.desktop} or "Abora";

in
{
  imports = import ./desktops/default.nix;

  options.abora = {
    # ── Identity ────────────────────────────────────────────────────────────

    hostname = lib.mkOption {
      type    = lib.types.str;
      default = "abora";
      description = "The machine hostname.";
    };

    locale = lib.mkOption {
      type    = lib.types.str;
      default = "en_US.UTF-8";
      example = "de_DE.UTF-8";
      description = "System locale (e.g. en_US.UTF-8, de_DE.UTF-8, fr_FR.UTF-8).";
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
        "budgie" "lxqt" "pantheon" "i3"
        "awesome" "openbox" "niri" "river" "qtile" "bspwm" "fluxbox"
        "icewm" "herbstluftwm" "cosmic" "mangowm"
      ];
      default     = "cosmic";
      description = "Desktop environment or window manager to enable.";
    };

    # ── Hardware ────────────────────────────────────────────────────────────

    disk = lib.mkOption {
      type    = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/sda";
      description = "Install disk for the Limine bootloader (e.g. /dev/sda, /dev/nvme0n1).";
    };

    gpu = lib.mkOption {
      type = lib.types.enum [ "nouveau" "nvidia" "nvidia-open" "amdgpu" "intel" "none" ];
      default = "none";
      description = ''
        GPU driver selection. This module only accepts a resolved, concrete
        value — pure Nix evaluation cannot safely probe real hardware, so
        detecting "auto" happens one layer up, in the installer or
        `abora config set gpu auto`, both of which run lspci on the actual
        target machine and write the resolved value here.

        - nouveau: open-source NVIDIA driver (the safe default for NVIDIA
          hardware, since it needs no license acceptance).
        - nvidia: proprietary NVIDIA driver.
        - nvidia-open: NVIDIA's open-source kernel modules (Turing and newer GPUs).
        - amdgpu: open-source AMD driver (also the kernel default; setting it
          explicitly just makes the choice visible to `abora config`).
        - intel: open-source Intel driver (also already the kernel default).
        - none: skip Abora's GPU wiring entirely; configure hardware.* yourself.
      '';
    };

    stateVersion = lib.mkOption {
      type    = lib.types.str;
      default = "26.05";
      description = "NixOS state version. Set once at install time — do not change afterwards.";
    };

    wallpaper = lib.mkOption {
      type = lib.types.enum wallpaperNames;
      default = "titlis-alps.jpg";
      description = "Default wallpaper file shipped with Abora.";
    };

    gaming = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Abora's optional gaming layer.";
      };
      steam = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Steam with 32-bit graphics support.";
      };
      bigPictureShortcut = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install a Steam Big Picture launcher.";
      };
      bigPictureAutostart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Start Steam Big Picture automatically after desktop login.";
      };
      gamescopeSession = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install a Steam Big Picture Gamescope session entry.";
      };
      controllerSupport = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Steam/controller udev support when available.";
      };
      mangohud = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install MangoHud for FPS/performance overlays.";
      };
      gamemode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GameMode performance tuning.";
      };
      vulkanTools = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Vulkan diagnostic tools for gaming readiness checks.";
      };
      launchers = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install common desktop game launchers when present in nixpkgs.";
      };
    };

    extras = {
      diagnostics = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install extra hardware/network diagnostic tools such as dmidecode, ethtool, htop, and smartmontools.";
      };
      virtualizationGuests = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable QEMU, SPICE, VMware, VirtualBox, and Hyper-V guest integration.";
      };
      mobileBroadband = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ModemManager for cellular/mobile broadband devices.";
      };
    };
  };

  # ── Config ─────────────────────────────────────────────────────────────────
  # Nothing below applies unless abora.user.name is set.

  config = lib.mkMerge [

    # Always apply these with mkDefault so they lose to any direct override.
      {
        networking.hostName  = lib.mkDefault cfg.hostname;
        time.timeZone        = lib.mkDefault cfg.timezone;
        i18n.defaultLocale   = lib.mkDefault cfg.locale;
        console.keyMap       = lib.mkDefault cfg.keyboard.console;
        environment.variables.ABORA_DEFAULT_WALLPAPER = lib.mkDefault defaultWallpaperPath;
      }

    # Everything else requires abora.user.name to be set.
    (lib.mkIf active (lib.mkMerge [

      # ── Common ─────────────────────────────────────────────────────────
      {
        # OS release args (PRETTY_NAME etc.) live in installed-base.nix only.

        system.nixos.variantName = lib.mkOverride 900 "Abora ${desktopLabel} Edition";
        system.nixos.variant_id  = lib.mkOverride 900 cfg.desktop;

        system.stateVersion = cfg.stateVersion;

        security.sudo.wheelNeedsPassword = true;

        users.users.${cfg.user.name} = {
          isNormalUser = true;
          description  = "Abora User";
          createHome   = true;
          shell        = pkgs.zsh;
          extraGroups  = [ "wheel" "networkmanager" "audio" "video" ];
          hashedPassword = cfg.user.hashedPassword;
        };

        # NixOS treats an empty hashedPassword as "login without password"
        # (see nixos/modules/config/users-groups.nix's allowsLogin), not as
        # "unset" -- so leaving this at its default would silently build a
        # passwordless wheel-group account instead of failing loudly.
        assertions = [
          {
            assertion = cfg.user.hashedPassword != "";
            message = "abora.user.hashedPassword is empty while abora.user.name is set (\"${cfg.user.name}\"). An empty hash means NixOS allows login without a password. Generate one with: mkpasswd";
          }
        ];
      }

      # ── GPU ────────────────────────────────────────────────────────────
      # amdgpu and intel (i915/xe) are already the kernel's own default
      # drivers, so those two branches exist mainly to make the choice
      # explicit to `abora config get gpu` rather than to change behavior.
      (lib.mkIf (cfg.gpu == "nouveau") {
        services.xserver.videoDrivers = lib.mkDefault [ "nouveau" ];
      })
      (lib.mkIf (cfg.gpu == "nvidia" || cfg.gpu == "nvidia-open") {
        services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];
        hardware.nvidia = {
          modesetting.enable = true;
          open = cfg.gpu == "nvidia-open";
          nvidiaSettings = true;
          package = config.boot.kernelPackages.nvidiaPackages.stable;
        };
      })
      (lib.mkIf (cfg.gpu == "amdgpu") {
        services.xserver.videoDrivers = lib.mkDefault [ "amdgpu" ];
      })
      (lib.mkIf (cfg.gpu == "intel") {
        services.xserver.videoDrivers = lib.mkDefault [ "modesetting" ];
      })

      # ── Gaming ─────────────────────────────────────────────────────────
      (lib.mkIf cfg.gaming.enable (let
        pkgIf = enabled: name:
          lib.optionals (enabled && builtins.hasAttr name pkgs) [ pkgs.${name} ];
        steamBigPictureCommand = pkgs.writeShellScriptBin "abora-steam-big-picture" ''
          if command -v steam >/dev/null 2>&1; then
            steam -gamepadui "$@" || exec steam -bigpicture "$@"
          else
            echo "Steam is not installed. Enable abora.gaming.steam, then rebuild." >&2
            exit 1
          fi
        '';
        steamBigPictureDesktop = pkgs.writeTextFile {
          name = "abora-steam-big-picture-desktop";
          destination = "/share/applications/abora-steam-big-picture.desktop";
          text = ''
            [Desktop Entry]
            Type=Application
            Name=Steam Big Picture
            Comment=Open Steam in controller-friendly Big Picture mode
            Exec=abora-steam-big-picture
            Icon=steam
            Categories=Game;
            Terminal=false
          '';
        };
        gamescopeSessionDesktop = pkgs.writeTextFile {
          name = "abora-steam-gamescope-session";
          destination = "/share/wayland-sessions/abora-steam-gamescope.desktop";
          text = ''
            [Desktop Entry]
            Name=Abora Gaming
            Comment=Steam Big Picture through Gamescope
            Exec=gamescope -e -- abora-steam-big-picture
            Type=Application
          '';
        };
      in lib.mkMerge [
        {
          hardware.graphics.enable = lib.mkDefault true;
          hardware.graphics.enable32Bit = lib.mkDefault true;

          environment.systemPackages =
            [ steamBigPictureCommand ]
            ++ lib.optionals cfg.gaming.bigPictureShortcut [ steamBigPictureDesktop ]
            ++ lib.optionals cfg.gaming.gamescopeSession [ gamescopeSessionDesktop ]
            ++ pkgIf cfg.gaming.gamescopeSession "gamescope"
            ++ pkgIf cfg.gaming.mangohud "mangohud"
            ++ pkgIf cfg.gaming.vulkanTools "vulkan-tools"
            ++ pkgIf cfg.gaming.launchers "heroic"
            ++ pkgIf cfg.gaming.launchers "lutris"
            ++ pkgIf cfg.gaming.launchers "bottles"
            ++ pkgIf cfg.gaming.launchers "protonup-qt";
        }
        (lib.mkIf cfg.gaming.steam {
          programs.steam.enable = lib.mkDefault true;
        })
        (lib.mkIf cfg.gaming.gamemode {
          programs.gamemode.enable = lib.mkDefault true;
        })
        (lib.mkIf cfg.gaming.controllerSupport {
          hardware.steam-hardware.enable = lib.mkDefault true;
        })
        (lib.mkIf cfg.gaming.bigPictureAutostart {
          environment.etc."xdg/autostart/abora-steam-big-picture.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=Steam Big Picture
            Comment=Open Steam in controller-friendly Big Picture mode
            Exec=abora-steam-big-picture
            Icon=steam
            Categories=Game;
            Terminal=false
            X-GNOME-Autostart-enabled=true
          '';
        })
      ]))

      # ── Bootloader ─────────────────────────────────────────────────────
      (lib.mkIf (cfg.disk != null) {
        boot.loader.grub.enable = lib.mkForce false;
        boot.loader.timeout = lib.mkDefault 5;
        boot.loader.limine = {
          enable              = true;
          enableEditor        = false;
          maxGenerations      = lib.mkDefault 8;
          biosSupport         = true;
          biosDevice          = cfg.disk;
          efiSupport          = true;
          efiInstallAsRemovable = true;
        };
      })

    ])) # end mkIf active
  ];
}
