{ lib, pkgs, config, ... }:
let
  # All paths below are relative to this file as it lives on the installed system
  # (beside installed-base.nix in /etc/nixos/abora/ or equivalent).  The
  # installer copies every required file via cp_required before the first
  # nixos-rebuild, so the ./x paths are always present.  Optional files that
  # the installer only copies when available fall back to null and their
  # environment.etc entries are guarded with lib.optionalAttrs.
  versionFile          = ./VERSION;
  titleFile            = ./title.txt;
  fastfetchLogoFile    = ./fastfetch-logo.txt;
  fastfetchConfigFile  = ./fastfetch-config.jsonc;
  uiScript             = ./ui.sh;
  configScript         = ./config.sh;
  aboraScript          = ./abora.sh;
  desktopScript        = ./desktop.sh;
  gamingScript         = ./gaming.sh;
  dotfilesImportScript = ./dotfiles-import.sh;
  doctorScript         = ./doctor.sh;
  checkFullScript      = ./check-full.sh;
  recoveryScript       = ./recovery.sh;
  welcomeScript        = ./welcome.sh;
  # New in this release; optional so systems mid-update (new installed-base.nix
  # synced before the new .py files finish copying) don't fail evaluation.
  welcomeGuiScript =
    if builtins.pathExists ./welcome-gui.py then ./welcome-gui.py else null;
  configGuiScript =
    if builtins.pathExists ./config-gui.py then ./config-gui.py else null;
  gamingWelcomeGuiScript =
    if builtins.pathExists ./gaming-welcome-gui.py then ./gaming-welcome-gui.py else null;
  anixScript           = ./anix.sh;
  optionsModule        = ./abora-options.nix;
  anixModule           = ./anix-module.nix;
  docsDir =
    if builtins.pathExists ./docs then ./docs else null;
  # ANIX v2 language adapter manifests (docs/wiki/ANIX-V2-Languages.md).
  # Populated the same way as docsDir above — the live ISO ships
  # assets/anix-languages/, and the installer's file-copy step is expected
  # to place a copy beside installed-base.nix as ./anix-languages before the
  # first nixos-rebuild. Absent until that copy step exists, so this stays
  # optional rather than a hard requirement.
  anixLanguagesDir =
    if builtins.pathExists ./anix-languages then ./anix-languages else null;
  appCatalogScript     = ./app-catalog.sh;
  appManagerScript     = ./apps.sh;
  customPackagesScript = ./custom-packages.sh;
  buildScript          = ./build.sh;
  adoptNixosScript     = ./adopt-nixos.sh;
  supportReportScript  = ./support-report.sh;
  hardwareTestScript   = ./hardware-test.sh;
  repairFlakePurityScript = ./repair-flake-purity.sh;
  wallpaperFile        = ./default-wallpaper.png;
  aboraLogoFile =
    if builtins.pathExists ./Abora-LOGO.png then ./Abora-LOGO.png else null;
  wallpaperDir         = ./wallpapers;
  wallpaperThemeDir    = ./themes;
  updateScript         = ./update.sh;
  themeSyncScript      = ./theme-sync.sh;
  sessionSetupScript   = ./session-setup.sh;
  desktopProfilesScript = ./desktop-profiles.sh;
  mangoConfigFile      = ./mango/config.conf;
  mangoConfigText      = builtins.readFile mangoConfigFile;
  moducppAnixTool      = ./tools/moducpp-anix;
  modularitySrc        = ./vendor/modularity;
  installerScript      = ./installer.sh;
  setupLauncherScript  = ./setup-launcher.sh;
  setupDesktopFile     = ./setup.desktop;
  plymouthDir          = ./plymouth;
  bootloaderDir        = ./bootloader;
  effectsDir =
    if builtins.pathExists ./effects then ./effects else null;
  limineWallpaperFile =
    if builtins.pathExists (bootloaderDir + "/limine-background.png") then
      bootloaderDir + "/limine-background.png"
    else
      bootloaderDir + "/background.png";
  tinypmDir            = ./tinypm;
  updateResolverDir    = ./update-resolver;
  planToolDir          = ./plan-tool;
  version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile versionFile);
  # TinyPM was rewritten from a bash multicall tree to a real Rust crate
  # (see TinyPM's own CLAUDE.md: "the old Bash runtime was removed"). The
  # installer copies the vendored source to /etc/nixos/abora/tinypm
  # (tinypmDir above), and this builds it the same way
  # nix/profiles/live.nix's tinypmPackage does for the live ISO. Only two
  # binaries exist now -- tinypm and grab -- replacing the old mkGrabCmd
  # multicall wrapper's much longer alias list (tiny/Parcel/search/term/
  # start/supdate/grab-add-repo/grab-de/syspm), none of which have a Rust
  # equivalent.
  tinypmPackage = pkgs.rustPlatform.buildRustPackage {
    pname = "tinypm";
    version = "0.8.1-alpha";
    src = tinypmDir;
    cargoLock.lockFile = tinypmDir + "/Cargo.lock";
    doCheck = false;
  };
  aboraApps = pkgs.writeShellScriptBin "abora-apps" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/apps.sh "$@"
  '';
  aboraCustomPackages = pkgs.writeShellScriptBin "abora-custom-packages" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/custom-packages.sh "$@"
  '';
  aboraConfig = pkgs.writeShellScriptBin "abora-config" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/config.sh "$@"
  '';
  aboraCommand = pkgs.writeShellScriptBin "abora" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/abora.sh "$@"
  '';
  aboraBuild = pkgs.writeShellScriptBin "abora-build" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/build.sh "$@"
  '';
  aboraAdoptNixos = pkgs.writeShellScriptBin "abora-adopt-nixos" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/adopt-nixos.sh "$@"
  '';
  aboraDesktop = pkgs.writeShellScriptBin "abora-desktop" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/desktop.sh "$@"
  '';
  aboraGaming = pkgs.writeShellScriptBin "abora-gaming" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/gaming.sh "$@"
  '';
  aboraDotfilesImport = pkgs.writeShellScriptBin "abora-dotfiles-import" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/dotfiles-import.sh "$@"
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
  aboraGuiPython = pkgs.python3.withPackages (ps: with ps; [ pygobject3 ]);
  aboraGuiGiPath = lib.makeSearchPath "lib/girepository-1.0" (with pkgs; [
    gtk4 libadwaita glib gdk-pixbuf (lib.getLib pango) harfbuzz graphene cairo gobject-introspection
  ]);
  aboraGuiLibPath = lib.makeLibraryPath (with pkgs; [
    gtk4 libadwaita glib gdk-pixbuf cairo
  ]);
  aboraWelcomeGui = pkgs.writeShellScriptBin "abora-welcome-gui" ''
    export GI_TYPELIB_PATH="${aboraGuiGiPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${aboraGuiLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export ABORA_UPDATE_SCRIPT="''${ABORA_UPDATE_SCRIPT:-/etc/abora/update.sh}"
    exec ${aboraGuiPython}/bin/python3 /etc/abora/welcome-gui.py "$@"
  '';
  aboraConfigGui = pkgs.writeShellScriptBin "abora-config-gui" ''
    export GI_TYPELIB_PATH="${aboraGuiGiPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${aboraGuiLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export ABORA_CONFIG_SCRIPT="''${ABORA_CONFIG_SCRIPT:-/etc/abora/config.sh}"
    exec ${aboraGuiPython}/bin/python3 /etc/abora/config-gui.py "$@"
  '';
  # Abora Welcome (aboraWelcomeGui above) covers the system in general;
  # this is a separate, dedicated app for games specifically -- your
  # gaming platforms at a glance, signing into Steam, and installing a
  # platform to get a game running through. See abora-gaming-welcome-gui.py.
  aboraGamingWelcomeGui = pkgs.writeShellScriptBin "abora-gaming-welcome-gui" ''
    export GI_TYPELIB_PATH="${aboraGuiGiPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${aboraGuiLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export ABORA_APPS_SCRIPT="''${ABORA_APPS_SCRIPT:-/etc/abora/apps.sh}"
    export ABORA_APP_CATALOG="''${ABORA_APP_CATALOG:-/etc/abora/app-catalog.sh}"
    exec ${aboraGuiPython}/bin/python3 /etc/abora/gaming-welcome-gui.py "$@"
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
  aboraRepairFlakePurity = pkgs.writeShellScriptBin "abora-repair-flake-purity" ''
    exec env ABORA_SYSTEM_CONFIG=/etc/nixos ${pkgs.bashInteractive}/bin/bash /etc/abora/repair-flake-purity.sh "$@"
  '';
  aboraInstaller = pkgs.writeShellScriptBin "abora-installer" ''
    exec env ABORA_INSTALLER=/etc/abora/installer.sh \
      ${pkgs.bashInteractive}/bin/bash /etc/abora/installer.sh "$@"
  '';
  aboraSetup = pkgs.writeShellScriptBin "abora-setup" ''
    exec env ABORA_INSTALLER=/etc/abora/installer.sh \
      ${pkgs.bashInteractive}/bin/bash /etc/abora/setup-launcher.sh "$@"
  '';
  aboraSetupDesktopPkg = pkgs.runCommandLocal "abora-setup-desktop" { } ''
    mkdir -p "$out/share/applications"
    cp ${setupDesktopFile} "$out/share/applications/abora-setup.desktop"
  '';
  aboraWelcomeDesktopPkg = pkgs.writeTextFile {
    name = "abora-welcome-desktop";
    destination = "/share/applications/abora-welcome.desktop";
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Abora Welcome
      Comment=First steps and update checks for Abora OS
      Exec=abora-welcome-gui
      Icon=distributor-logo
      Categories=System;Settings;
      Terminal=false
    '';
  };
  aboraConfigDesktopPkg = pkgs.writeTextFile {
    name = "abora-config-desktop";
    destination = "/share/applications/abora-config.desktop";
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Abora System Settings
      Comment=Edit your Abora OS system configuration
      Exec=abora-config-gui
      Icon=preferences-system
      Categories=System;Settings;
      Terminal=false
    '';
  };
  aboraGamingWelcomeDesktopPkg = pkgs.writeTextFile {
    name = "abora-gaming-welcome-desktop";
    destination = "/share/applications/abora-gaming-welcome.desktop";
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Abora Gaming
      Comment=Sign in and get a gaming platform ready
      Exec=abora-gaming-welcome-gui
      Icon=input-gaming
      Categories=System;Game;
      Terminal=false
    '';
  };
  aboraUpdate = pkgs.writeShellScriptBin "abora-update" ''
    exec env ABORA_UPDATE_COMMAND=abora-update ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
  '';
  aboraThemeSync = pkgs.writeShellScriptBin "abora-theme-sync" ''
    exec env ABORA_GSETTINGS_BIN=${pkgs.glib}/bin/gsettings ${pkgs.bashInteractive}/bin/bash /etc/abora/theme-sync.sh "$@"
  '';
  aboraSessionSetup = pkgs.writeShellScriptBin "abora-session-setup" ''
    exec env ABORA_GSETTINGS_BIN=${pkgs.glib}/bin/gsettings ABORA_THEME_SYNC_SCRIPT=/etc/abora/theme-sync.sh ${pkgs.bashInteractive}/bin/bash /etc/abora/session-setup.sh "$@"
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
  aboraWallpapersPackage = pkgs.runCommandLocal "abora-wallpapers" { } ''
    mkdir -p "$out/share/backgrounds/abora" "$out/share/abora/themes" "$out/share/gnome-background-properties"
    find ${wallpaperDir} -maxdepth 1 -type f -exec cp {} "$out/share/backgrounds/abora/" \;
    find ${wallpaperThemeDir} -maxdepth 1 -type f -exec cp {} "$out/share/abora/themes/" \;
    cat >"$out/share/gnome-background-properties/abora.xml" <<'EOF'
    <?xml version="1.0"?>
    <!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
    <wallpapers>
      <wallpaper deleted="false">
        <name>Abora Dark</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/abora-dark.svg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/abora-dark.svg</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#030812</pcolor>
        <scolor>#030812</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Abora Light</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/abora-light.svg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/abora-dark.svg</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#f2f9fe</pcolor>
        <scolor>#030812</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Alpine Glacier</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/alpine-glacier.jpg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/alpine-glacier.jpg</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#1a1030</pcolor>
        <scolor>#1a1030</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Tannheimer Mountains</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/tannheimer-mountains.jpg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/tannheimer-mountains.jpg</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#0b3a63</pcolor>
        <scolor>#0b3a63</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Titlis Alps</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/titlis-alps.jpg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/titlis-alps.jpg</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#0e4a7a</pcolor>
        <scolor>#0e4a7a</scolor>
      </wallpaper>
      <wallpaper deleted="false">
        <name>Aurora, Lofoten</name>
        <filename>/run/current-system/sw/share/backgrounds/abora/aurora-lofoten.jpg</filename>
        <filename-dark>/run/current-system/sw/share/backgrounds/abora/aurora-lofoten.jpg</filename-dark>
        <options>zoom</options>
        <shade_type>solid</shade_type>
        <pcolor>#081625</pcolor>
        <scolor>#081625</scolor>
      </wallpaper>
    </wallpapers>
    EOF
  '';
  aboraPlymouthTheme = pkgs.runCommandLocal "abora-plymouth-theme" { } ''
    install -Dm0644 ${plymouthDir + "/abora.plymouth"} $out/share/plymouth/themes/abora/abora.plymouth
    install -Dm0644 ${plymouthDir + "/abora.script"} $out/share/plymouth/themes/abora/abora.script
  '';
in
{
  system.nixos = {
    distroId = "abora";
    distroName = "Abora OS";
    vendorId = "abora";
    vendorName = "Abora OS";
    label = version;
    variant_id = lib.mkDefault "system";
    variantName = lib.mkDefault "Abora OS v4 Everest";
    extraOSReleaseArgs = lib.mapAttrs (_: lib.mkDefault) {
      LOGO = "abora";
      VERSION = "v4 Everest";
      VERSION_ID = "4";
      VERSION_CODENAME = "everest";
      PRETTY_NAME = "Abora OS v4 Everest";
      HOME_URL = "https://www.aboraos.org/";
      SUPPORT_URL = "https://github.com/AnimatedGTVR/Abora-OS/issues";
      BUG_REPORT_URL = "https://github.com/AnimatedGTVR/Abora-OS/issues";
      ANSI_COLOR = "0;38;2;80;220;255";
    };
  };

  nixpkgs.config.allowUnfree = lib.mkDefault true;

  nixpkgs.overlays = [
    (final: prev: {
      scenefx-0_5 = final.callPackage ./pkgs/scenefx-0_5.nix {};
      mango = final.callPackage ./pkgs/mango.nix {};
      modularity = final.callPackage ./pkgs/modularity.nix { inherit modularitySrc; };
      moducpp-anix = final.callPackage ./pkgs/moducpp-anix.nix {
        moducppAnixSrc = moducppAnixTool;
      };
      abora-update-resolver = final.callPackage ./pkgs/abora-update-resolver.nix {
        resolverSrc = updateResolverDir;
      };
      abora-plan-tool = final.callPackage ./pkgs/abora-plan-tool.nix {
        toolSrc = planToolDir;
      };
    })
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.initrd.systemd.enable = lib.mkDefault true;
  boot.initrd.verbose = lib.mkDefault false;
  boot.kernelParams = lib.mkDefault [
    "quiet"
    "splash"
    "udev.log_level=3"
    "systemd.show_status=auto"
  ];
  boot.consoleLogLevel = lib.mkDefault 3;
  boot.initrd.kernelModules = lib.mkDefault [
    "loop"
    "overlay"
    "squashfs"
    "isofs"
  ];
  boot.initrd.availableKernelModules = lib.mkDefault [
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
  # Let udev autoload optional NIC/Bluetooth drivers from detected hardware.
  # Preloading a broad hardware list can make systemd-modules-load fail on
  # machines that do not support one of the optional drivers.
  boot.kernelModules = [];
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;
  boot.loader.limine.style.wallpapers = [ limineWallpaperFile ];
  boot.plymouth = {
    enable = lib.mkDefault true;
    theme = "abora";
    themePackages = [ aboraPlymouthTheme ];
  };

  hardware.enableAllFirmware = lib.mkDefault true;
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
  hardware.bluetooth = {
    enable = lib.mkDefault true;
    powerOnBoot = lib.mkDefault true;
  };
  networking.networkmanager = {
    enable = lib.mkDefault true;
    wifi.powersave = lib.mkDefault false;
    ethernet.macAddress = lib.mkDefault "preserve";
    wifi.macAddress = lib.mkDefault "preserve";
  };
  networking.modemmanager.enable = lib.mkDefault config.abora.extras.mobileBroadband;
  security.polkit.enable = lib.mkDefault true;
  services.udisks2.enable = lib.mkDefault true;
  services.blueman.enable = lib.mkDefault true;
  services.fwupd.enable = lib.mkDefault true;
  services.openssh.enable = lib.mkDefault false;
  security.rtkit.enable = lib.mkDefault true;
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    alsa.support32Bit = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  services.flatpak.enable = lib.mkDefault true;
  xdg.portal.enable = lib.mkDefault true;
  xdg.portal.extraPortals = lib.mkDefault (with pkgs; [ xdg-desktop-portal-gtk ]);

  # Add Flathub automatically once the network is up.
  systemd.services.abora-flatpak-setup = {
    description     = "Add Flathub remote for Flatpak";
    after           = [ "network-online.target" "flatpak.service" ];
    wants           = [ "network-online.target" ];
    wantedBy        = [ "multi-user.target" ];
    serviceConfig   = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo || true
    '';
  };

  services.qemuGuest.enable = lib.mkDefault config.abora.extras.virtualizationGuests;
  services.spice-vdagentd.enable = lib.mkDefault config.abora.extras.virtualizationGuests;
  virtualisation.vmware.guest.enable =
    lib.mkDefault (config.abora.extras.virtualizationGuests && pkgs.stdenv.hostPlatform.isx86);
  virtualisation.virtualbox.guest.enable =
    lib.mkDefault (config.abora.extras.virtualizationGuests && pkgs.stdenv.hostPlatform.isx86);
  virtualisation.hypervGuest.enable =
    lib.mkDefault (config.abora.extras.virtualizationGuests && (pkgs.stdenv.hostPlatform.isx86 || pkgs.stdenv.hostPlatform.isAarch64));

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    inter
    jetbrains-mono
    nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig = {
    enable = lib.mkDefault true;
    defaultFonts = {
      sansSerif = lib.mkDefault [ "Inter" "Noto Sans" ];
      serif     = lib.mkDefault [ "Noto Serif" ];
      monospace = lib.mkDefault [ "JetBrains Mono" "Noto Sans Mono" ];
      emoji     = lib.mkDefault [ "Noto Color Emoji" ];
    };
  };

  environment.variables = {
    XCURSOR_THEME = lib.mkDefault "Adwaita";
    XCURSOR_SIZE  = lib.mkDefault "24";
    TERMINAL      = lib.mkDefault "konsole";
    TERM_PROGRAM  = lib.mkDefault "konsole";
  };

  environment.systemPackages = with pkgs; [
    tinypmPackage
    abora-update-resolver
    abora-plan-tool
    aboraApps
    aboraCustomPackages
    aboraAdoptNixos
    aboraBuild
    aboraCommand
    aboraCheckFull
    anixCommand
    aboraConfig
    aboraDesktop
    aboraGaming
    aboraDotfilesImport
    aboraDoctor
    aboraHardwareTest
    aboraRecovery
    aboraRepairFlakePurity
    aboraSupportReport
    aboraUpdate
    aboraWelcome
    aboraWelcomeGui
    aboraWelcomeDesktopPkg
    aboraConfigGui
    aboraConfigDesktopPkg
    aboraGamingWelcomeGui
    aboraGamingWelcomeDesktopPkg
    aboraWallpapersPackage
    aboraInstaller
    aboraSetup
    aboraSetupDesktopPkg
    aboraSessionSetup
    aboraThemeSync
    bashInteractive
    curl
    feh
    fastfetch
    git
    iw
    jq
    libnotify
    moducpp-anix
    kdePackages.konsole
    linux-firmware
    nixosCommand
    pciutils
    mpg123
    updateCommand
    upgradeCommand
    rollbackCommand
    spaceship-prompt
    starship
    usbutils
    wget
    papirus-icon-theme
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    xdg-utils
    xterm
    zenity
    swaybg
    zsh
  ] ++ lib.optionals config.abora.extras.diagnostics (with pkgs; [
    dmidecode
    ethtool
    htop
    smartmontools
  ]) ++ lib.optionals config.abora.extras.mobileBroadband (with pkgs; [
    modemmanager
  ]);

  # Purely a desktop notification nudge (--notify --quiet); does not install
  # anything itself. Silently no-ops via `command -v` if TinyPM was never
  # installed for this user (anix tinypm install), so this timer is safe to
  # ship unconditionally on every desktop profile.
  systemd.user.services.tinypm-update-check = {
    description = "Check for TinyPM updates";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bashInteractive}/bin/bash -lc 'command -v tinypm >/dev/null 2>&1 && tinypm check-update --notify --quiet || true'";
    };
  };

  systemd.user.timers.tinypm-update-check = {
    description = "Notify when TinyPM updates are available";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };

  programs.zsh = {
    enable = true;
    # Only seeds a .zshrc when the user has NONE of the four zsh dotfiles at
    # all -- a user who already has any one of them (even just a bare
    # .zshenv) is treated as having their own zsh setup, so this never
    # overwrites or fights with dotfiles a user (or abora-dotfiles-import)
    # already put in place.
    shellInit = ''
      if [[ -o interactive ]]; then
        abora_zdotdir="''${ZDOTDIR:-''${HOME:-}}"
        if [[ -n "$abora_zdotdir" && -d "$abora_zdotdir" && -w "$abora_zdotdir" \
          && ! -e "$abora_zdotdir/.zshenv" \
          && ! -e "$abora_zdotdir/.zprofile" \
          && ! -e "$abora_zdotdir/.zshrc" \
          && ! -e "$abora_zdotdir/.zlogin" ]]; then
          {
            print -r -- "# Abora OS zsh profile."
            print -r -- "# System-wide prompt and fastfetch setup live in /etc/zshrc."
          } > "$abora_zdotdir/.zshrc" 2>/dev/null || true
        fi
        unset abora_zdotdir
      fi
    '';
    interactiveShellInit = ''
      export FASTFETCH_CONFIG="/etc/xdg/fastfetch/config.jsonc"
      export ABORA_FASTFETCH_LOGO="/etc/xdg/fastfetch/abora-logo.txt"

      if [[ -o interactive && -z "''${ABORA_FASTFETCH_SHOWN:-}" && "''${SHLVL:-1}" -eq 1 ]]; then
        export ABORA_FASTFETCH_SHOWN=1
        command fastfetch --logo-type file --logo-source "$ABORA_FASTFETCH_LOGO" -c "$FASTFETCH_CONFIG" 2>/dev/null || true
        print
      fi
    '';
    promptInit = ''
      fpath=(${pkgs.spaceship-prompt}/share/zsh/site-functions $fpath)
      autoload -Uz promptinit
      promptinit

      SPACESHIP_PROMPT_ORDER=(
        user host dir git package node python rust golang docker nix_shell
        exec_time line_sep jobs exit_code char
      )
      SPACESHIP_USER_SHOW=always
      SPACESHIP_HOST_SHOW=always
      SPACESHIP_DIR_TRUNC=3
      SPACESHIP_PROMPT_ADD_NEWLINE=true
      SPACESHIP_CHAR_SYMBOL="➜"
      SPACESHIP_CHAR_SUFFIX=" "
      prompt spaceship
    '';
  };

  users.defaultUserShell = pkgs.zsh;

  environment.etc =
    {
      "abora/VERSION".source = versionFile;
      "abora/ui.sh" = {
        source = uiScript;
        mode = "0644";
      };
      "abora/config.sh" = {
        source = configScript;
        mode = "0755";
      };
      "abora/abora.sh" = {
        source = aboraScript;
        mode = "0755";
      };
      "abora/build.sh" = {
        source = buildScript;
        mode = "0755";
      };
      "abora/adopt-nixos.sh" = {
        source = adoptNixosScript;
        mode = "0755";
      };
      "abora/desktop.sh" = {
        source = desktopScript;
        mode = "0755";
      };
      "abora/gaming.sh" = {
        source = gamingScript;
        mode = "0755";
      };
      "abora/dotfiles-import.sh" = {
        source = dotfilesImportScript;
        mode = "0755";
      };
      "abora/doctor.sh" = {
        source = doctorScript;
        mode = "0755";
      };
      "abora/check-full.sh" = {
        source = checkFullScript;
        mode = "0755";
      };
      "abora/recovery.sh" = {
        source = recoveryScript;
        mode = "0755";
      };
      "abora/welcome.sh" = {
        source = welcomeScript;
        mode = "0755";
      };
      "abora/anix.sh" = {
        source = anixScript;
        mode = "0755";
      };
      "abora/app-catalog.sh" = {
        source = appCatalogScript;
        mode = "0755";
      };
      "abora/apps.sh" = {
        source = appManagerScript;
        mode = "0755";
      };
      "abora/custom-packages.sh" = {
        source = customPackagesScript;
        mode = "0755";
      };
      "abora/support-report.sh" = {
        source = supportReportScript;
        mode = "0755";
      };
      "abora/hardware-test.sh" = {
        source = hardwareTestScript;
        mode = "0755";
      };
      "abora/repair-flake-purity.sh" = {
        source = repairFlakePurityScript;
        mode = "0755";
      };
      "abora/default-wallpaper.png".source = wallpaperFile;
      "abora/title.txt".source = titleFile;
      "abora/fastfetch-logo.txt".source = fastfetchLogoFile;
      "abora/fastfetch-config.jsonc".source = fastfetchConfigFile;
      "abora/desktop-profiles.sh" = {
        source = desktopProfilesScript;
        mode = "0755";
      };
      "abora/mango/config.conf".source = mangoConfigFile;
      "mango/config.conf".text = lib.mkDefault mangoConfigText;
      "abora/tinypm".source = tinypmDir;
      "abora/update-resolver".source = updateResolverDir;
      "abora/plan-tool".source = planToolDir;
      "abora/vendor/modularity".source = modularitySrc;
      # The generated /etc/nixos/flake.nix pins its nixpkgs input to
      # "path:/etc/abora/nixpkgs". Expose the build-time nixpkgs source here so
      # that path resolves on the installed system (the live ISO does the same).
      # Without this, `anix apply` / nixos-rebuild fail to fetch the flake input.
      "abora/nixpkgs".source = pkgs.path;
      "abora/installer.sh" = {
        source = installerScript;
        mode = "0755";
      };
      "abora/setup-launcher.sh" = {
        source = setupLauncherScript;
        mode = "0755";
      };
      "abora/setup.desktop".source = setupDesktopFile;
      "abora/session-setup.sh" = {
        source = sessionSetupScript;
        mode = "0755";
      };
      "abora/update.sh" = {
        source = updateScript;
        mode = "0755";
      };
      "abora/theme-sync.sh" = {
        source = themeSyncScript;
        mode = "0755";
      };
      "motd".text = ''
        Abora OS v4 Everest

          grab <app>          install an app  (flatpak, nix, or snap)
          search <app>        find apps across all sources
          term <app>          remove an installed app
          supdate             upgrade all installed apps

          abora welcome       first steps and quick actions
          abora gaming        gaming layer status and Steam Big Picture helper
          abora doctor        check system health
          abora recovery      rollback and repair tools
          sudo abora update   rebuild and switch the system
      '';
      "profile.d/abora-welcome.sh".text = ''
        abora_welcome_conf="''${XDG_CONFIG_HOME:-''${HOME}/.config}/abora/welcome.conf"
        if [ -n "''${PS1:-}" ] \
          && [ -z "''${ABORA_WELCOME_SHOWN:-}" ] \
          && { [ ! -f "$abora_welcome_conf" ] || ! grep -qx 'show_on_startup=false' "$abora_welcome_conf"; } \
          && command -v abora-welcome >/dev/null 2>&1; then
          export ABORA_WELCOME_SHOWN=1
          if [ ! -f "$HOME/.cache/abora/welcome-seen" ]; then
            mkdir -p "$HOME/.cache/abora"
            touch "$HOME/.cache/abora/welcome-seen"
            abora-welcome status || true
            printf '  Run %s for first-step actions.\n\n' "abora welcome"
          fi
        fi
        unset abora_welcome_conf
      '';
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
        gtk-application-prefer-dark-theme=0
        gtk-theme-name=Adwaita
        gtk-icon-theme-name=Papirus
      '';
      "xdg/gtk-4.0/settings.ini".text = ''
        [Settings]
        gtk-application-prefer-dark-theme=0
        gtk-theme-name=Adwaita
        gtk-icon-theme-name=Papirus
      '';
      "xdg/qt5ct/qt5ct.conf".text = ''
        [Appearance]
        color_scheme_path=/run/current-system/sw/share/qt5ct/colors/airy.conf
        custom_palette=true
        icon_theme=Papirus
        standard_dialogs=default
        style=Fusion
      '';
      "xdg/qt6ct/qt6ct.conf".text = ''
        [Appearance]
        color_scheme_path=/run/current-system/sw/share/qt6ct/colors/airy.conf
        custom_palette=true
        icon_theme=Papirus
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
      "abora/plymouth/abora.plymouth".source = plymouthDir + "/abora.plymouth";
      "abora/plymouth/abora.script".source = plymouthDir + "/abora.script";
      "xdg/fastfetch/config.jsonc".source = fastfetchConfigFile;
      "xdg/fastfetch/abora-logo.txt".source = fastfetchLogoFile;
      "skel/.config/fastfetch/config.jsonc".source = fastfetchConfigFile;
      "skel/.config/fastfetch/abora-logo.txt".source = fastfetchLogoFile;
      "skel/.zshrc".text = ''
        # Abora OS terminal profile. System-wide setup lives in /etc/zshrc.
      '';
      "skel/.config/konsolerc".text = ''
        [Desktop Entry]
        DefaultProfile=Abora.profile

        [KonsoleWindow]
        RememberWindowSize=false
      '';
      "skel/.local/share/konsole/Abora.profile".text = ''
        [Appearance]
        ColorScheme=Abora
        Font=JetBrainsMono Nerd Font,11,-1,5,50,0,0,0,0,0

        [General]
        Command=${pkgs.zsh}/bin/zsh
        Name=Abora
        Parent=FALLBACK/

        [Scrolling]
        HistoryMode=2
      '';
      "skel/.local/share/konsole/Abora.colorscheme".text = ''
        [Background]
        Color=5,10,18

        [BackgroundIntense]
        Color=8,18,30

        [Color0]
        Color=8,13,22

        [Color1]
        Color=255,90,113

        [Color2]
        Color=88,214,141

        [Color3]
        Color=255,214,102

        [Color4]
        Color=71,168,255

        [Color5]
        Color=181,137,255

        [Color6]
        Color=78,226,232

        [Color7]
        Color=226,238,248

        [Foreground]
        Color=232,244,255

        [ForegroundIntense]
        Color=255,255,255

        [General]
        Blur=true
        ColorRandomization=false
        Description=Abora
        Opacity=0.84
      '';
      "issue".text = ''
        Abora OS v4 Everest
      '';
      "issue.net".text = ''
        Abora OS v4 Everest
      '';
    }
    // builtins.listToAttrs (
      map (name: {
        name = "abora/bootloader/${name}";
        value.source = bootloaderDir + "/${name}";
      }) (builtins.attrNames (builtins.readDir bootloaderDir))
    )
    // builtins.listToAttrs (
      map (name: {
        name = "abora/wallpapers/${name}";
        value.source = wallpaperDir + "/${name}";
      }) (builtins.attrNames (builtins.readDir wallpaperDir))
    )
    // builtins.listToAttrs (
      map (name: {
        name = "abora/themes/${name}";
        value.source = wallpaperThemeDir + "/${name}";
      }) (builtins.attrNames (builtins.readDir wallpaperThemeDir))
    )
    // {
      "abora/desktops".source = ./desktops;
    }
    // {
      "abora/abora-options.nix".source = optionsModule;
    }
    // {
      "abora/anix-module.nix".source = anixModule;
    }
    // lib.optionalAttrs (docsDir != null) {
      "abora/docs".source = docsDir;
    }
    // lib.optionalAttrs (anixLanguagesDir != null) {
      "abora/anix-languages".source = anixLanguagesDir;
      "anix/languages".source = anixLanguagesDir;
    }
    // lib.optionalAttrs (aboraLogoFile != null) {
      "abora/Abora-LOGO.png".source = aboraLogoFile;
    }
    // lib.optionalAttrs (effectsDir != null) {
      "abora/effects/v3StartingAbora.mp3".source = effectsDir + "/v3StartingAbora.mp3";
    }
    // lib.optionalAttrs (welcomeGuiScript != null) {
      "abora/welcome-gui.py".source = welcomeGuiScript;
      "xdg/autostart/abora-welcome-gui.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Abora Welcome
        Comment=First steps and update checks for Abora OS
        Exec=sh -c 'conf="''${XDG_CONFIG_HOME:-$HOME/.config}/abora/welcome.conf"; if [ -f "$conf" ] && grep -qx "show_on_startup=false" "$conf"; then exit 0; fi; test -f "$HOME/.cache/abora/welcome-seen" || exec abora-welcome-gui'
        Icon=distributor-logo
        X-GNOME-Autostart-enabled=true
        NoDisplay=true
      '';
    }
    // lib.optionalAttrs (configGuiScript != null) {
      "abora/config-gui.py".source = configGuiScript;
    }
    // lib.optionalAttrs (gamingWelcomeGuiScript != null) {
      "abora/gaming-welcome-gui.py".source = gamingWelcomeGuiScript;
    };

  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";

  programs.bash.interactiveShellInit = ''
    [[ $SHLVL -eq 1 ]] && fastfetch -c /etc/xdg/fastfetch/config.jsonc
  '';
}
