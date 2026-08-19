{ lib, config, options, pkgs, ... }:
let
  cfg = config.anix;
  # This ANIX module can be imported standalone (e.g. by a plain NixOS system
  # that isn't Abora), so it must never assume abora-options.nix is also
  # imported. hasAboraOptions probes for that module's option paths before
  # ever touching config.abora.* below, so anix.desktop/anix.wallpaper are
  # simply no-ops rather than eval errors on a non-Abora system.
  hasAboraOptions = options ? abora && options.abora ? desktop && options.abora ? wallpaper;
  hasAboraGamingOptions = options ? abora && options.abora ? gaming;
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

    gaming = {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable Abora's optional gaming layer when available.";
      };

      bigPictureShortcut = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable the Steam Big Picture launcher when Abora gaming is available.";
      };

      bigPictureAutostart = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Start Steam Big Picture at desktop login when Abora gaming is available.";
      };

      gamescopeSession = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable the Abora Gaming Gamescope session when available.";
      };

      vulkanTools = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Install Vulkan diagnostic tools when Abora gaming is available.";
      };
    };

    power = {
      thermald = lib.mkOption {
        type = lib.types.bool;
        # thermald is Intel's laptop-specific thermal daemon -- it detects
        # non-mobile hardware and correctly refuses to do anything useful
        # there, but exits nonzero doing so, and `nixos-rebuild switch`
        # treats any failed unit as a hard activation error. Defaulting
        # this to true meant every desktop-class Abora install had a
        # perpetually-failing thermald.service, and every `nixos-rebuild
        # switch` -- including `abora update`'s -- failed with "Rebuilding
        # Abora ... failed (exit 4)" because of it. Reproduced on real
        # desktop hardware: thermald logged "Non mobile ... THD engine"
        # errors and the whole update aborted, existing config left
        # untouched. Opt-in now, matching the description below; laptop
        # users can `anix enable thermald`.
        default = false;
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
          Historical option, kept only so existing `anix.tinypm.enable`
          settings in installed systems' abora-local.nix still evaluate.
          TinyPM was rewritten from a bash multicall tree (with its own
          per-user "flavor" install step) into a real Rust crate that
          ships as an ordinary system package -- see
          nix/profiles/live.nix's `tinypmPackage`. There is no longer a
          per-user install step for this option to gate: `tinypm`/`grab`
          are on PATH for every user as soon as the system is built, the
          same as any other systemPackages entry. This option no longer
          does anything.
        '';
      };

      flavor = lib.mkOption {
        type = lib.types.str;
        default = "abora";
        description = ''
          Historical option, kept only for eval compatibility with
          existing configs -- the Rust TinyPM has no flavor/branding
          system. Unused.
        '';
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
    # desktop and wallpaper only take effect when abora-options.nix (part of
    # nixosModules.installed-base) is also imported -- a standalone
    # `nixosModules.anix`-only system has nowhere for these to apply to.
    # That's an easy trap for exactly the standalone-import use case this
    # module exists for (see docs/wiki/ANIX-Standalone.md), so make the
    # no-op visible instead of silent rather than just documenting it here.
    (lib.mkIf (cfg.desktop != null && hasAboraOptions) {
      abora.desktop = lib.mkForce cfg.desktop;
    })
    (lib.mkIf (cfg.wallpaper != null && hasAboraOptions) {
      abora.wallpaper = lib.mkForce cfg.wallpaper;
    })
    (lib.mkIf (cfg.gaming.enable != null && hasAboraGamingOptions) {
      abora.gaming.enable = lib.mkForce cfg.gaming.enable;
    })
    (lib.mkIf (cfg.gaming.bigPictureShortcut != null && hasAboraGamingOptions) {
      abora.gaming.bigPictureShortcut = lib.mkForce cfg.gaming.bigPictureShortcut;
    })
    (lib.mkIf (cfg.gaming.bigPictureAutostart != null && hasAboraGamingOptions) {
      abora.gaming.bigPictureAutostart = lib.mkForce cfg.gaming.bigPictureAutostart;
    })
    (lib.mkIf (cfg.gaming.gamescopeSession != null && hasAboraGamingOptions) {
      abora.gaming.gamescopeSession = lib.mkForce cfg.gaming.gamescopeSession;
    })
    (lib.mkIf (cfg.gaming.vulkanTools != null && hasAboraGamingOptions) {
      abora.gaming.vulkanTools = lib.mkForce cfg.gaming.vulkanTools;
    })
    (lib.mkIf (cfg.desktop != null && !hasAboraOptions) {
      warnings = [
        "anix.desktop is set to \"${cfg.desktop}\" but has no effect here: it requires abora-options.nix (part of nixosModules.installed-base) to also be imported. On a standalone anix-only system, configure your desktop environment through normal NixOS options instead."
      ];
    })
    (lib.mkIf (cfg.wallpaper != null && !hasAboraOptions) {
      warnings = [
        "anix.wallpaper is set to \"${cfg.wallpaper}\" but has no effect here: it requires abora-options.nix (part of nixosModules.installed-base) to also be imported."
      ];
    })
    (lib.mkIf ((cfg.gaming.enable != null || cfg.gaming.bigPictureShortcut != null || cfg.gaming.bigPictureAutostart != null || cfg.gaming.gamescopeSession != null || cfg.gaming.vulkanTools != null) && !hasAboraGamingOptions) {
      warnings = [
        "anix.gaming.* is set but has no effect here: it requires abora-options.nix (part of nixosModules.installed-base) to also be imported."
      ];
    })
    # config.abora.gaming.enable (not just cfg.gaming.enable, which is only
    # this module's own anix.gaming.enable input) is checked here -- the
    # common real sequence is "installer sets abora.gaming.enable = true in
    # abora-local.nix, then later `anix enable gaming.vulkan` only sets
    # anix.gaming.vulkanTools" -- leaving anix.gaming.enable at its null
    # default even though gaming genuinely is on and vulkanTools genuinely
    # does get force-applied below. Without this check the warning fired on
    # every rebuild in that entirely normal, working configuration.
    (lib.mkIf (hasAboraGamingOptions && cfg.gaming.enable != true &&
      config.abora.gaming.enable != true &&
      (cfg.gaming.bigPictureShortcut != null || cfg.gaming.bigPictureAutostart != null ||
       cfg.gaming.gamescopeSession != null || cfg.gaming.vulkanTools != null)) {
      warnings = [
        "anix.gaming.* sub-options are set but anix.gaming.enable is not true, so abora.gaming.enable stays off (unless something else turns it on) -- every gaming package/service these sub-options would configure is gated behind abora.gaming.enable and won't be installed."
      ];
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
    # cfg.tinypm.enable/flavor are intentionally unused now -- see their
    # option descriptions above. There is no per-user tinypm-init service
    # anymore: TinyPM ships system-wide via nix/profiles/live.nix's
    # tinypmPackage, the same as any other systemPackages entry.
  ]);
}
