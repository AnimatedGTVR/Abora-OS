{ lib, config, options, pkgs, ... }:
let
  cfg = config.anix;
  hasAboraOptions = options ? abora && options.abora ? desktop && options.abora ? wallpaper;
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
        "budgie" "lxqt" "pantheon" "i3" "awesome"
        "openbox" "niri" "river" "qtile" "bspwm" "fluxbox" "icewm"
        "herbstluftwm" "cosmic" "mangowm"
      ]);
      default = null;
      description = "Optional desktop override (requires Abora OS for full effect).";
    };

    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional wallpaper filename (requires Abora OS).";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra system packages managed through the ANIX layer.";
    };

    fonts = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra font packages managed through the ANIX layer.";
    };

    allowUnfree = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow unfree packages such as Discord or Steam.";
    };

    experimentalNix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nix-command and flakes.";
    };

    shell = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "bash" "zsh" "fish" ]);
      default = null;
      description = "Default shell for normal users where possible.";
    };

    services = {
      bluetooth = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Bluetooth support.";
      };

      printing = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable printing support.";
      };

      openssh = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the OpenSSH server.";
      };

      flatpak = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Flatpak.";
      };

      audio = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable PipeWire audio.";
      };
    };

    power = {
      thermald = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable thermald when available.";
      };

      tlp = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable TLP laptop power management.";
      };
    };

    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra users allowed to use trusted Nix features.";
    };

    autoOptimiseStore = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable automatic Nix store optimisation.";
    };

    garbageCollect = {
      enable = lib.mkEnableOption "scheduled Nix store garbage collection";

      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "Systemd calendar expression for Nix garbage collection.";
      };

      options = lib.mkOption {
        type = lib.types.str;
        default = "--delete-older-than 14d";
        description = "Options passed to nix-collect-garbage by the scheduled job.";
      };
    };

    tinypm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Auto-install TinyPM into each user's home directory on their first
          login via a systemd user service. TinyPM provides the grab, search,
          term, start, and supdate commands for managing Flatpak, Nix, and
          Snap packages on Abora OS.
        '';
      };

      flavor = lib.mkOption {
        type = lib.types.str;
        default = "abora";
        description = "TinyPM flavor to use during the per-user installation.";
      };
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
    (lib.mkIf (cfg.desktop != null && hasAboraOptions) {
      abora.desktop = lib.mkForce cfg.desktop;
    })
    (lib.mkIf (cfg.wallpaper != null && hasAboraOptions) {
      abora.wallpaper = lib.mkForce cfg.wallpaper;
    })
    (lib.mkIf (cfg.packages != [ ]) {
      environment.systemPackages = cfg.packages;
    })
    {
      nixpkgs.config.allowUnfree = cfg.allowUnfree;
      nix.settings.auto-optimise-store = cfg.autoOptimiseStore;
    }
    (lib.mkIf cfg.experimentalNix {
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
    })
    (lib.mkIf (cfg.fonts != [ ]) {
      fonts.packages = cfg.fonts;
    })
    (lib.mkIf (cfg.shell != null) {
      programs.${cfg.shell}.enable = true;
      users.defaultUserShell = pkgs.${cfg.shell};
    })
    {
      hardware.bluetooth.enable = cfg.services.bluetooth;
      services.printing.enable = cfg.services.printing;
      services.flatpak.enable = cfg.services.flatpak;
    }
    (lib.mkIf cfg.services.openssh {
      services.openssh.enable = true;
    })
    (lib.mkIf cfg.services.audio {
      services.pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = true;
      };
    })
    (lib.mkIf cfg.power.thermald {
      services.thermald.enable = lib.mkDefault true;
    })
    (lib.mkIf cfg.power.tlp {
      services.tlp.enable = true;
    })
    (lib.mkIf (cfg.trustedUsers != [ ]) {
      nix.settings.trusted-users = cfg.trustedUsers;
    })
    (lib.mkIf cfg.garbageCollect.enable {
      nix.gc = {
        automatic = true;
        dates = cfg.garbageCollect.dates;
        options = cfg.garbageCollect.options;
      };
    })
    (lib.mkIf cfg.tinypm.enable {
      # On first login, install TinyPM into the user's home directory.
      # A stamp file prevents reinstallation on subsequent logins.
      systemd.user.services.tinypm-init = {
        description = "TinyPM first-login user setup";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart =
            let
              script = pkgs.writeShellScript "tinypm-user-init" ''
                stamp_dir="''${XDG_STATE_HOME:-''${HOME}/.local/state}/tinypm"
                stamp="''${stamp_dir}/anix-init-done"
                [ -f "''${stamp}" ] && exit 0
                src="/etc/abora/tinypm"
                [ -f "''${src}/install.sh" ] || exit 0
                TINYPM_FLAVOR="${cfg.tinypm.flavor}" \
                  ${pkgs.bash}/bin/bash "''${src}/install.sh" \
                    --flavor "${cfg.tinypm.flavor}" --yes --native nix \
                  >/dev/null 2>&1 || true
                mkdir -p "''${stamp_dir}"
                touch "''${stamp}"
              '';
            in
              "${script}";
        };
      };
    })
  ]);
}
