{ lib, pkgs, version, ... }:
let
  aboraApps = pkgs.writeShellScriptBin "abora-apps" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/apps.sh "$@"
  '';
  aboraSupportReport = pkgs.writeShellScriptBin "abora-support-report" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/support-report.sh "$@"
  '';
  aboraHardwareTest = pkgs.writeShellScriptBin "abora-hardware-test" ''
    exec env ABORA_SUPPORT_REPORT_SCRIPT=/etc/abora/support-report.sh ${pkgs.bashInteractive}/bin/bash /etc/abora/hardware-test.sh "$@"
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
  wallpaperDir = ../../assets/wallpapers/collection;
  wallpaperThemeDir = ../../assets/wallpaper-themes;
  aboraWallpapersPackage = pkgs.runCommandLocal "abora-wallpapers" { } ''
    mkdir -p "$out/share/backgrounds/abora" "$out/share/abora/themes" "$out/share/gnome-background-properties"
    cp ${wallpaperDir}/* "$out/share/backgrounds/abora/"
    cp ${wallpaperThemeDir}/* "$out/share/abora/themes/"
    cat >"$out/share/gnome-background-properties/abora.xml" <<'EOF'
    <?xml version="1.0"?>
    <!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
    <wallpapers>
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
in
{
  system.stateVersion = "26.05";
  networking.hostName = "abora";
  system.nixos.tags = [ "abora" "nixos-base" ];
  system.nixos = {
    distroId = "abora";
    distroName = "Abora OS";
    vendorId = "abora";
    vendorName = "Abora OS";
    variant_id = "live";
    variantName = "Abora OS ${version} Live Image";
    label = version;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];
  boot.initrd.verbose = false;
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "loglevel=3"
    "udev.log_level=3"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "vt.global_cursor_default=0"
  ];

  environment.systemPackages = with pkgs; [
    aboraApps
    aboraHardwareTest
    aboraSessionSetup
    aboraSupportReport
    aboraUpdate
    aboraWallpapersPackage
    aboraThemeSync
    bashInteractive
    dosfstools
    e2fsprogs
    feh
    fastfetch
    git
    curl
    dmidecode
    ethtool
    wget
    gh
    htop
    iproute2
    iw
    kbd
    pciutils
    nixosCommand
    openssl
    parted
    smartmontools
    usbutils
    util-linux
    updateCommand
    upgradeCommand
    rollbackCommand
    whois
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    xdg-utils
    swaybg
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
      "abora/default-wallpaper.png".source = ../../assets/wallpapers/collection/oceandusk.png;
      "abora/title.txt".source = ../../assets/abora-title.txt;
      "abora/VERSION".source = ../../VERSION;
      "abora/fastfetch-logo.txt".source = ../../assets/fastfetch-logo.txt;
      "abora/fastfetch-config.jsonc".source = ../../assets/fastfetch-config.jsonc;
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
      "issue".text = ''
        Abora OS ${version}
      '';
      "issue.net".text = ''
        Abora OS ${version}
      '';
      "abora/boot.sh" = {
        source = ../../scripts/abora-boot.sh;
        mode = "0755";
      };
      "abora/installer.sh" = {
        source = ../../scripts/abora-installer.sh;
        mode = "0755";
      };
      "abora/installed-base.nix".source = ../../nix/modules/installed-base.nix;
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
      '';
      "xdg/gtk-4.0/settings.ini".text = ''
        [Settings]
        gtk-application-prefer-dark-theme=1
        gtk-theme-name=Adwaita-dark
      '';
      "xdg/qt5ct/qt5ct.conf".text = ''
        [Appearance]
        color_scheme_path=/run/current-system/sw/share/qt5ct/colors/darker.conf
        custom_palette=true
        icon_theme=Adwaita
        standard_dialogs=default
        style=Fusion
      '';
      "xdg/qt6ct/qt6ct.conf".text = ''
        [Appearance]
        color_scheme_path=/run/current-system/sw/share/qt6ct/colors/darker.conf
        custom_palette=true
        icon_theme=Adwaita
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

  systemd.services."getty@tty1".enable = lib.mkForce false;
  systemd.services.abora-boot = {
    description = "Abora live boot menu";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    conflicts = [ "getty@tty1.service" ];
    before = [ "getty@tty1.service" ];
    environment = {
      ABORA_NIXPKGS_PATH = "/etc/abora/nixpkgs";
      ABORA_ZONEINFO_PATH = "${pkgs.tzdata}/share/zoneinfo";
    };

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.bashInteractive}/bin/bash /etc/abora/boot.sh";
      Restart = "always";
      RestartSec = "0";
      StandardInput = "tty-force";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
    };
  };

  image.fileName = lib.mkForce "abora-${version}-x86_64.iso";
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
