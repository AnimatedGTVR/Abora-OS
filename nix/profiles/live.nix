{ lib, pkgs, version, ... }:
let
  aboraApps = pkgs.writeShellScriptBin "abora-apps" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/apps.sh "$@"
  '';
  aboraConfig = pkgs.writeShellScriptBin "abora-config" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/config.sh "$@"
  '';
  aboraCommand = pkgs.writeShellScriptBin "abora" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/abora.sh "$@"
  '';
  aboraDesktop = pkgs.writeShellScriptBin "abora-desktop" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/desktop.sh "$@"
  '';
  aboraDoctor = pkgs.writeShellScriptBin "abora-doctor" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/doctor.sh "$@"
  '';
  aboraCheckFull = pkgs.writeShellScriptBin "abora-check-full" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/check-full.sh "$@"
  '';
  aboraRecovery = pkgs.writeShellScriptBin "abora-recovery" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/recovery.sh "$@"
  '';
  aboraWelcome = pkgs.writeShellScriptBin "abora-welcome" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/welcome.sh "$@"
  '';
  anixCommand = pkgs.writeShellScriptBin "anix" ''
    exec env ANIX_SYSTEM_CONFIG=/etc/nixos ANIX_FLAKE_CONFIG_NAME=abora ${pkgs.bashInteractive}/bin/bash /etc/abora/anix.sh "$@"
  '';
  aboraSupportReport = pkgs.writeShellScriptBin "abora-support-report" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/support-report.sh "$@"
  '';
  aboraHardwareTest = pkgs.writeShellScriptBin "abora-hardware-test" ''
    exec env ABORA_SUPPORT_REPORT_SCRIPT=/etc/abora/support-report.sh ${pkgs.bashInteractive}/bin/bash /etc/abora/hardware-test.sh "$@"
  '';
  aboraInstall = pkgs.writeShellScriptBin "abora-install" ''
    if [ "$(id -u)" -ne 0 ]; then
      sudo_bin=/run/wrappers/bin/sudo
      if [ ! -x "$sudo_bin" ]; then
        sudo_bin=sudo
      fi
      exec "$sudo_bin" \
        TERM="''${TERM:-linux}" \
        ABORA_DESKTOP_PROFILES_LIB=/etc/abora/desktop-profiles.sh \
        ABORA_APP_CATALOG_LIB=/etc/abora/app-catalog.sh \
        ${pkgs.bashInteractive}/bin/bash /etc/abora/installer.sh "$@"
    fi
    exec env \
      TERM="''${TERM:-linux}" \
      ABORA_DESKTOP_PROFILES_LIB=/etc/abora/desktop-profiles.sh \
      ABORA_APP_CATALOG_LIB=/etc/abora/app-catalog.sh \
      ${pkgs.bashInteractive}/bin/bash /etc/abora/installer.sh "$@"
  '';
  aboraSetup = pkgs.writeShellScriptBin "abora-setup" ''
    exec env ABORA_INSTALLER=/etc/abora/installer.sh \
      ABORA_SETUP_MODE=install \
      ${pkgs.bashInteractive}/bin/bash /etc/abora/setup-launcher.sh "$@"
  '';
  aboraSetupDesktopPkg = pkgs.runCommandLocal "abora-setup-desktop" { } ''
    mkdir -p "$out/share/applications"
    cp ${../../scripts/abora-setup.desktop} "$out/share/applications/abora-setup.desktop"
  '';
  aboraUpdate = pkgs.writeShellScriptBin "abora-update" ''
    exec env ABORA_UPDATE_COMMAND=abora-update ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
  '';
  aboraSessionSetup = pkgs.writeShellScriptBin "abora-session-setup" ''
    exec env ABORA_GSETTINGS_BIN=${pkgs.glib}/bin/gsettings ABORA_THEME_SYNC_SCRIPT=/etc/abora/theme-sync.sh ${pkgs.bashInteractive}/bin/bash /etc/abora/session-setup.sh "$@"
  '';
  aboraThemeSync = pkgs.writeShellScriptBin "abora-theme-sync" ''
    exec env ABORA_GSETTINGS_BIN=${pkgs.glib}/bin/gsettings ${pkgs.bashInteractive}/bin/bash /etc/abora/theme-sync.sh "$@"
  '';
  nixosCommand = pkgs.writeShellScriptBin "nixos" ''
    exec env ABORA_UPDATE_COMMAND=nixos ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
  '';
  updateCommand = pkgs.writeShellScriptBin "update" ''
    exec env ABORA_UPDATE_COMMAND=update ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
  '';
  upgradeCommand = pkgs.writeShellScriptBin "upgrade" ''
    exec env ABORA_UPDATE_COMMAND=upgrade ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
  '';
  rollbackCommand = pkgs.writeShellScriptBin "rollback" ''
    exec env ABORA_UPDATE_COMMAND=rollback ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
  '';
  aboraGrubTheme = pkgs.runCommandLocal "abora-grub-theme" { } ''
    mkdir -p "$out"
    cp -r ${pkgs.nixos-grub2-theme}/* "$out/"
    chmod -R u+w "$out"
    cp ${../../assets/bootloader/background.png} "$out/background.png"
    cp ${../../assets/bootloader/theme.txt} "$out/theme.txt"
  '';
  aboraPlymouthTheme = pkgs.runCommandLocal "abora-plymouth-theme" { } ''
    mkdir -p "$out/share/plymouth/themes/abora"
    cp ${../../assets/plymouth/abora.plymouth} "$out/share/plymouth/themes/abora/abora.plymouth"
    cp ${../../assets/plymouth/abora.script} "$out/share/plymouth/themes/abora/abora.script"
  '';
  wallpaperDir = ../../assets/wallpapers/collection;
  wallpaperThemeDir = ../../assets/wallpaper-themes;
  tinypmDir = ../../vendor/tinypm;
  aboraWallpapersPackage = pkgs.runCommandLocal "abora-wallpapers" { } ''
    mkdir -p "$out/share/backgrounds/abora" "$out/share/abora/themes" "$out/share/gnome-background-properties"
    find ${wallpaperDir} -maxdepth 1 -type f -exec cp {} "$out/share/backgrounds/abora/" \;
    find ${wallpaperThemeDir} -maxdepth 1 -type f -exec cp {} "$out/share/abora/themes/" \;
    cat >"$out/share/gnome-background-properties/abora.xml" <<'EOF'
    <?xml version="1.0"?>
    <!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
    <wallpapers>
      <wallpaper deleted="false">
        <name>Mountain (Day/Night)</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/Daytime-MNT.jpg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/NightTime-MNT.png</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#1a2a1a</pcolor>
        <scolor>#0a0e1a</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Ocean Dusk</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/oceandusk.png</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/oceandusk.png</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#07111f</pcolor>
        <scolor>#07111f</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Blue Horizon</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/bluehorizon.png</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/bluehorizon.png</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#081223</pcolor>
        <scolor>#081223</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Astronaut Wallpaper</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/astronautwallpaper.png</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/astronautwallpaper.png</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#0b1020</pcolor>
        <scolor>#0b1020</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Glacier Reflection</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/glacierreflection.png</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/glacierreflection.png</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#0b1625</pcolor>
        <scolor>#0b1625</scolor>
      </wallpaper>
    </wallpapers>
    EOF
  '';
  mkGrabCmd = name: pkgs.writeShellScriptBin name ''
    exec env TINYPM_FLAVOR=abora ${pkgs.bashInteractive}/bin/bash /etc/abora/tinypm/${name} "$@"
  '';
in
{
  system.stateVersion = "26.05";
  nixpkgs.config.allowUnfree = true;
  networking.hostName = "abora";
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager = {
    enable = lib.mkForce true;
    wifi.backend = "wpa_supplicant";
    wifi.powersave = false;
    ethernet.macAddress = "preserve";
    wifi.macAddress = "preserve";
  };
  networking.modemmanager.enable = true;
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  security.sudo.enable = true;
  security.polkit.enable = true;
  services.blueman.enable = true;
  services.dbus.enable = true;
  services.udisks2.enable = true;
  services.fwupd.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.printing.enable = true;
  hardware.sane.enable = true;
  system.nixos.tags = [ "abora" "nixos-base" ];
  system.nixos = {
    distroId = "abora";
    distroName = "Abora OS";
    vendorId = "abora";
    vendorName = "Abora OS";
    variant_id = "live";
    variantName = "Abora OS DENALI 3.14 Live Image";
    label = version;
    extraOSReleaseArgs = {
      LOGO = "abora";
      VERSION = "DENALI 3.14";
      VERSION_ID = "3.14";
      VERSION_CODENAME = "denali";
      PRETTY_NAME = "Abora OS DENALI 3.14";
      HOME_URL = "https://www.aboraos.org/";
      SUPPORT_URL = "https://github.com/AnimatedGTVR/abora-os/issues";
      BUG_REPORT_URL = "https://github.com/AnimatedGTVR/abora-os/issues";
      ANSI_COLOR = "0;38;2;80;220;255";
    };
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-substitution-jobs = 32;
    http-connections = 128;
    max-jobs = "auto";
    cores = 0;
  };
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];
  boot.kernelPackages = pkgs.linuxPackages_6_6;
  boot.initrd.systemd.enable = true;
  boot.initrd.verbose = false;
  boot.initrd.availableKernelModules = [
    "ahci"
    "ata_piix"
    "nvme"
    "sd_mod"
    "sr_mod"
    "usb_storage"
    "uas"
    "xhci_pci"
    "ehci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];
  boot.kernelModules = [
    "btusb"
    "bluetooth"
    "iwlwifi"
    "ath9k"
    "ath10k_pci"
    "ath11k_pci"
    "brcmfmac"
    "rtw88_pci"
    "rtw89_pci"
    "r8169"
    "e1000e"
    "igb"
    "tg3"
    "atlantic"
    "alx"
  ];
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "udev.log_level=3"
    "rd.udev.log_level=3"
    "systemd.log_level=notice"
    "rd.systemd.log_level=notice"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "vt.global_cursor_default=0"
  ];
  boot.plymouth = {
    enable = true;
    theme = "abora";
    themePackages = [ aboraPlymouthTheme ];
  };

  environment.systemPackages = with pkgs; [
    # ── Abora installer toolchain ────────────────────────────────────────────
    (mkGrabCmd "tinypm")
    (mkGrabCmd "tiny")
    (mkGrabCmd "Parcel")
    (mkGrabCmd "grab")
    (mkGrabCmd "search")
    (mkGrabCmd "term")
    (mkGrabCmd "start")
    (mkGrabCmd "supdate")
    aboraApps
    aboraCommand
    aboraCheckFull
    aboraInstall
    anixCommand
    aboraConfig
    aboraDesktop
    aboraDoctor
    aboraHardwareTest
    aboraRecovery
    aboraSessionSetup
    aboraSetup
    aboraSetupDesktopPkg
    aboraSupportReport
    aboraUpdate
    aboraWelcome
    aboraWallpapersPackage
    aboraThemeSync
    nixosCommand
    updateCommand
    upgradeCommand
    rollbackCommand

    # ── Shell / UI ───────────────────────────────────────────────────────────
    bashInteractive
    fastfetch   # shown in the live welcome banner
    htop
    kdePackages.konsole
    newt        # provides nmtui for Wi-Fi setup
    xterm       # tiny fallback so the Start Abora launcher can always open
    zenity      # graphical ANIX helper when launched from a desktop

    # ── Disk & filesystem ────────────────────────────────────────────────────
    dosfstools  # mkfs.vfat
    e2fsprogs   # mkfs.ext4
    parted
    util-linux  # wipefs, lsblk, mount …

    # ── Boot management ──────────────────────────────────────────────────────
    efibootmgr
    eject

    # ── Networking ───────────────────────────────────────────────────────────
    curl
    iproute2
    iputils
    iw
    networkmanager
    wget

    # ── Crypto / security ────────────────────────────────────────────────────
    openssl

    # ── Hardware inspection ──────────────────────────────────────────────────
    pciutils
    usbutils

    # ── Nix tooling (needed by nixos-install / flake ops) ───────────────────
    git
    xdg-utils

    # ── Keyboard ─────────────────────────────────────────────────────────────
    kbd
  ];

  environment.variables = {
    ABORA_VERSION = version;
    ABORA_NIXPKGS_PATH = pkgs.path;
    ABORA_ZONEINFO_PATH = "${pkgs.tzdata}/share/zoneinfo";
  };

  environment.etc =
    {
      "abora/README".text = ''
        Abora OS ${version} live image
        Base: Abora OS
      '';
      "abora/app-catalog.sh" = {
        source = ../../scripts/abora-app-catalog.sh;
        mode = "0755";
      };
      "abora/apps.sh" = {
        source = ../../scripts/abora-apps.sh;
        mode = "0755";
      };
      "abora/abora.sh" = {
        source = ../../scripts/abora.sh;
        mode = "0755";
      };
      "abora/desktop.sh" = {
        source = ../../scripts/abora-desktop.sh;
        mode = "0755";
      };
      "abora/doctor.sh" = {
        source = ../../scripts/abora-doctor.sh;
        mode = "0755";
      };
      "abora/check-full.sh" = {
        source = ../../scripts/abora-check-full.sh;
        mode = "0755";
      };
      "abora/recovery.sh" = {
        source = ../../scripts/abora-recovery.sh;
        mode = "0755";
      };
      "abora/welcome.sh" = {
        source = ../../scripts/abora-welcome.sh;
        mode = "0755";
      };
      "abora/default-wallpaper.png".source = ../../assets/wallpapers/collection/Daytime-MNT.jpg;
      "abora/Abora-LOGO.png".source = ../../assets/Abora-LOGO.png;
      "abora/title.txt".source = ../../assets/abora-title.txt;
      "abora/VERSION".source = ../../VERSION;
      "abora/fastfetch-logo.txt".source = ../../assets/fastfetch-logo.txt;
      "abora/fastfetch-config.jsonc".source = ../../assets/fastfetch-config.jsonc;
      "abora/effects/v3StartingAbora.mp3".source = ../../assets/Effects/v3StartingAbora.mp3;
      "abora/desktop-profiles.sh" = {
        source = ../../scripts/abora-desktop-profiles.sh;
        mode = "0755";
      };
      "abora/support-report.sh" = {
        source = ../../scripts/abora-support-report.sh;
        mode = "0755";
      };
      "abora/hardware-test.sh" = {
        source = ../../scripts/abora-hardware-test.sh;
        mode = "0755";
      };
      "abora/plymouth/abora.plymouth".source = ../../assets/plymouth/abora.plymouth;
      "abora/plymouth/abora.script".source = ../../assets/plymouth/abora.script;
      "abora/nixpkgs".source = pkgs.path;
      "xdg/fastfetch/config.jsonc".source = ../../assets/fastfetch-config.jsonc;
      "xdg/fastfetch/abora-logo.txt".source = ../../assets/fastfetch-logo.txt;
      "issue".text = ''
        Abora OS DENALI 3.14
      '';
      "issue.net".text = ''
        Abora OS DENALI 3.14
      '';
      "profile.d/abora-live.sh".text = ''
        if [ -z "$ABORA_LIVE_GREETED" ]; then
          export ABORA_LIVE_GREETED=1
          printf '\n'
          printf '\033[1;36m  ◈  ABORA OS \033[0;37m${version}\033[0m  —  Live Shell\033[0m\n'
          printf '\033[90m  ─────────────────────────────────────────────\033[0m\n'
          printf '\n'
          printf '  \033[1;37mabora-install\033[0m        Start the installer\n'
          printf '  \033[90mabora-install --force\033[0m  Force-restart installer\n'
          printf '\n'
          printf '  \033[90mType a command or press Ctrl+D to power off.\033[0m\n'
          printf '\n'
        fi
      '';
      "abora/boot.sh" = {
        source = ../../scripts/abora-boot.sh;
        mode = "0755";
      };
      "abora/installer.sh" = {
        source = ../../scripts/abora-installer.sh;
        mode = "0755";
      };
      "abora/setup-launcher.sh" = {
        source = ../../scripts/abora-setup-launcher.sh;
        mode = "0755";
      };
      "abora/setup.desktop".source = ../../scripts/abora-setup.desktop;
      "abora/installed-base.nix".source = ../../nix/modules/installed-base.nix;
      "abora/pkgs/mango.nix".source = ../../nix/pkgs/mango.nix;
      "abora/pkgs/modularity.nix".source = ../../nix/pkgs/modularity.nix;
      "abora/tinypm".source = tinypmDir;
      "abora/docs".source = ../../docs;
      "abora/abora-options.nix".source  = ../../nix/modules/abora-options.nix;
      "abora/ui.sh" = {
        source = ../../scripts/abora-ui.sh;
        mode   = "0644";
      };
      "abora/config.sh" = {
        source = ../../scripts/abora-config.sh;
        mode   = "0755";
      };
      "abora/anix.sh" = {
        source = ../../scripts/anix.sh;
        mode = "0755";
      };
      "abora/anix-module.nix".source = ../../nix/modules/anix.nix;
      "abora/session-setup.sh" = {
        source = ../../scripts/abora-session-setup.sh;
        mode = "0755";
      };
      "abora/theme-sync.sh" = {
        source = ../../scripts/abora-theme-sync.sh;
        mode = "0755";
      };
      "abora/update.sh" = {
        source = ../../scripts/abora-update.sh;
        mode = "0755";
      };
      "xdg/autostart/abora-theme-sync.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Abora Theme Sync
        Comment=Match GNOME accent colors to Abora wallpapers
        Exec=abora-theme-sync
        OnlyShowIn=GNOME;
        X-GNOME-Autostart-enabled=true
        NoDisplay=true
      '';
      "xdg/gtk-3.0/settings.ini".text = ''
        [Settings]
        gtk-application-prefer-dark-theme=1
        gtk-theme-name=Adwaita-dark
        gtk-icon-theme-name=Papirus-Dark
      '';
      "xdg/gtk-4.0/settings.ini".text = ''
        [Settings]
        gtk-application-prefer-dark-theme=1
        gtk-theme-name=Adwaita-dark
        gtk-icon-theme-name=Papirus-Dark
      '';
      "xdg/qt5ct/qt5ct.conf".text = ''
        [Appearance]
        color_scheme_path=/run/current-system/sw/share/qt5ct/colors/darker.conf
        custom_palette=true
        icon_theme=Papirus-Dark
        standard_dialogs=default
        style=Fusion
      '';
      "xdg/qt6ct/qt6ct.conf".text = ''
        [Appearance]
        color_scheme_path=/run/current-system/sw/share/qt6ct/colors/darker.conf
        custom_palette=true
        icon_theme=Papirus-Dark
        standard_dialogs=default
        style=Fusion
      '';
      "xdg/autostart/abora-session-setup.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Abora Session Setup
        Comment=Apply Abora defaults for the current desktop session
        Exec=abora-session-setup
        X-GNOME-Autostart-enabled=true
        NoDisplay=true
      '';
    }
    // builtins.listToAttrs (
      map
        (name: {
          name = "abora/bootloader/${name}";
          value.source = ../../assets/bootloader + "/${name}";
        })
        (builtins.attrNames (builtins.readDir ../../assets/bootloader))
    )
    // builtins.listToAttrs (
      map
        (name: {
          name = "abora/wallpapers/${name}";
          value.source = ../../assets/wallpapers/collection + "/${name}";
        })
        (builtins.attrNames (builtins.readDir ../../assets/wallpapers/collection))
    )
    // builtins.listToAttrs (
      map
        (name: {
          name = "abora/themes/${name}";
          value.source = ../../assets/wallpaper-themes + "/${name}";
        })
        (builtins.attrNames (builtins.readDir ../../assets/wallpaper-themes))
    );

  services.xserver.enable = false;
  systemd.services.ModemManager = {
    enable = lib.mkForce true;
    wantedBy = lib.mkForce [ "multi-user.target" ];
  };
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  virtualisation.vmware.guest.enable = pkgs.stdenv.hostPlatform.isx86;
  virtualisation.virtualbox.guest.enable = pkgs.stdenv.hostPlatform.isx86;
  virtualisation.hypervGuest.enable =
    pkgs.stdenv.hostPlatform.isx86 || pkgs.stdenv.hostPlatform.isAarch64;
  systemd.settings.Manager = {
    ReserveVT = 2;
  };
  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";

  programs.bash.interactiveShellInit = ''
    [[ $SHLVL -eq 1 ]] && fastfetch -c /etc/xdg/fastfetch/config.jsonc
  '';

  systemd.services."getty@tty1".enable = lib.mkForce false;
  systemd.services.NetworkManager = {
    enable = lib.mkForce true;
    wantedBy = lib.mkForce [ "multi-user.target" ];
  };
  systemd.services.abora-unblock-radios = {
    description = "Unblock wireless and Bluetooth radios for the Abora installer";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.util-linux}/bin/rfkill unblock all || true
      ${pkgs.systemd}/bin/udevadm trigger --action=add --subsystem-match=net || true
      ${pkgs.systemd}/bin/udevadm trigger --action=add --subsystem-match=bluetooth || true
      ${pkgs.systemd}/bin/udevadm settle || true
    '';
  };
  systemd.services.abora-boot = {
    description = "Abora OS installer boot";
    wantedBy    = [ "multi-user.target" ];
    wants       = [ "NetworkManager.service" ];
    # Conflict with both the static and auto-vt getty on tty1 so neither
    # can race with us for the terminal.
    conflicts = [ "getty@tty1.service" "autovt@tty1.service" ];
    # Start after network is up and sessions are ready.
    # plymouth-quit.service sends the quit signal to Plymouth;
    # we also call `plymouth quit` in ExecStartPre as a belt-and-suspenders.
    after = [
      "NetworkManager.service"
      "systemd-user-sessions.service"
      "plymouth-quit.service"
      "getty@tty1.service"
      "autovt@tty1.service"
    ];
    environment = {
      TERM                         = "linux";
      ABORA_VERSION                = version;
      ABORA_NIXPKGS_PATH           = "/etc/abora/nixpkgs";
      ABORA_ZONEINFO_PATH          = "${pkgs.tzdata}/share/zoneinfo";
      ABORA_DESKTOP_PROFILES_LIB   = "/etc/abora/desktop-profiles.sh";
      ABORA_APP_CATALOG_LIB        = "/etc/abora/app-catalog.sh";
    };
    serviceConfig = {
      Type   = "simple";
      # Quit Plymouth before we take the TTY — avoids framebuffer race.
      # The leading '-' tells systemd to ignore a non-zero exit code.
      ExecStartPre  = "-${pkgs.plymouth}/bin/plymouth quit --wait";
      ExecStart     = "${pkgs.bashInteractive}/bin/bash /etc/abora/boot.sh";
      # Never restart automatically. If the installer exits or crashes, the
      # boot script drops to a live shell; restarting this service can relaunch
      # the installer and feel like an install loop.
      Restart       = "no";
      RestartSec    = "2";
      StandardInput  = "tty-force";
      StandardOutput = "tty";
      StandardError  = "tty";
      TTYPath        = "/dev/tty1";
      TTYReset       = true;
      TTYVHangup     = true;
      # Do NOT set TTYVTDisallocate — it releases the VT on exit which breaks
      # the fallback live shell and makes restarts unable to re-acquire tty1.
    };
  };

  image.fileName = lib.mkForce "abora-${version}-x86_64.iso";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  isoImage.squashfsCompression = lib.mkForce "zstd -Xcompression-level 15";
  isoImage.prependToMenuLabel = "";
  isoImage.appendToMenuLabel = "";
  isoImage.configurationName = null;
  isoImage.splashImage = ../../assets/bootloader/background.png;
  isoImage.grubTheme = aboraGrubTheme;
  isoImage.syslinuxTheme = ''
    MENU RESOLUTION 800 600
    MENU CLEAR
    MENU WIDTH 46
    MENU MARGIN 0
    MENU ROWS 4
    MENU VSHIFT 8
    MENU HSHIFT 18
    MENU TABMSGROW 17
    MENU CMDLINEROW 18
    MENU TIMEOUTROW 19
    MENU HELPMSGROW 20
    MENU HELPMSGENDROW 20

    MENU COLOR BORDER       37;40      #00000000    #00000000   none
    MENU COLOR SCREEN       37;40      #00000000    #00000000   none
    MENU COLOR TABMSG       37;40      #D8E2F2      #00000000   none
    MENU COLOR TIMEOUT      1;37;40    #F3F6FB      #00000000   none
    MENU COLOR TIMEOUT_MSG  37;40      #D8E2F2      #00000000   none
    MENU COLOR CMDMARK      1;37;40    #F3F6FB      #00000000   none
    MENU COLOR CMDLINE      37;40      #D8E2F2      #00000000   none
    MENU COLOR TITLE        1;37;40    #00000000    #00000000   none
    MENU COLOR UNSEL        37;40      #D8E2F2      #00000000   none
    MENU COLOR SEL          1;30;47    #1B2539      #F3F6FB     std
  '';
}
