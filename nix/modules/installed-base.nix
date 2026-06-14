{ lib, pkgs, ... }:
let
  versionFile =
    if builtins.pathExists ./VERSION then
      ./VERSION
    else
      ../../VERSION;
  titleFile =
    if builtins.pathExists ./title.txt then
      ./title.txt
    else
      ../../assets/abora-title.txt;
  fastfetchLogoFile =
    if builtins.pathExists ./fastfetch-logo.txt then
      ./fastfetch-logo.txt
    else
      ../../assets/fastfetch-logo.txt;
  fastfetchConfigFile =
    if builtins.pathExists ./fastfetch-config.jsonc then
      ./fastfetch-config.jsonc
    else
      ../../assets/fastfetch-config.jsonc;
  uiScript =
    if builtins.pathExists ./ui.sh then
      ./ui.sh
    else
      ../../scripts/abora-ui.sh;
  configScript =
    if builtins.pathExists ./config.sh then
      ./config.sh
    else
      ../../scripts/abora-config.sh;
  aboraScript =
    if builtins.pathExists ./abora.sh then
      ./abora.sh
    else
      ../../scripts/abora.sh;
  desktopScript =
    if builtins.pathExists ./desktop.sh then
      ./desktop.sh
    else
      ../../scripts/abora-desktop.sh;
  doctorScript =
    if builtins.pathExists ./doctor.sh then
      ./doctor.sh
    else
      ../../scripts/abora-doctor.sh;
  checkFullScript =
    if builtins.pathExists ./check-full.sh then
      ./check-full.sh
    else
      ../../scripts/abora-check-full.sh;
  recoveryScript =
    if builtins.pathExists ./recovery.sh then
      ./recovery.sh
    else
      ../../scripts/abora-recovery.sh;
  welcomeScript =
    if builtins.pathExists ./welcome.sh then
      ./welcome.sh
    else
      ../../scripts/abora-welcome.sh;
  anixScript =
    if builtins.pathExists ./anix.sh then
      ./anix.sh
    else
      ../../scripts/anix.sh;
  optionsModule =
    if builtins.pathExists ./abora-options.nix then
      ./abora-options.nix
    else if builtins.pathExists ../../nix/modules/abora-options.nix then
      ../../nix/modules/abora-options.nix
    else
      null;
  anixModule =
    if builtins.pathExists ./anix-module.nix then
      ./anix-module.nix
    else if builtins.pathExists ../../nix/modules/anix.nix then
      ../../nix/modules/anix.nix
    else
      null;
  docsDir =
    if builtins.pathExists ./docs then
      ./docs
    else if builtins.pathExists ../../docs then
      ../../docs
    else
      null;
  appCatalogScript =
    if builtins.pathExists ./app-catalog.sh then
      ./app-catalog.sh
    else
      ../../scripts/abora-app-catalog.sh;
  appManagerScript =
    if builtins.pathExists ./apps.sh then
      ./apps.sh
    else
      ../../scripts/abora-apps.sh;
  supportReportScript =
    if builtins.pathExists ./support-report.sh then
      ./support-report.sh
    else
      ../../scripts/abora-support-report.sh;
  hardwareTestScript =
    if builtins.pathExists ./hardware-test.sh then
      ./hardware-test.sh
    else
      ../../scripts/abora-hardware-test.sh;
  wallpaperFile =
    if builtins.pathExists ./default-wallpaper.png then
      ./default-wallpaper.png
    else
      ../../assets/wallpapers/collection/Daytime-MNT.jpg;
  aboraLogoFile =
    if builtins.pathExists ./Abora-LOGO.png then
      ./Abora-LOGO.png
    else if builtins.pathExists ../../assets/Abora-LOGO.png then
      ../../assets/Abora-LOGO.png
    else
      null;
  wallpaperDir =
    if builtins.pathExists ./wallpapers then
      ./wallpapers
    else
      ../../assets/wallpapers/collection;
  wallpaperThemeDir =
    if builtins.pathExists ./themes then
      ./themes
    else
      ../../assets/wallpaper-themes;
  updateScript =
    if builtins.pathExists ./update.sh then
      ./update.sh
    else
      ../../scripts/abora-update.sh;
  themeSyncScript =
    if builtins.pathExists ./theme-sync.sh then
      ./theme-sync.sh
    else
      ../../scripts/abora-theme-sync.sh;
  sessionSetupScript =
    if builtins.pathExists ./session-setup.sh then
      ./session-setup.sh
    else
      ../../scripts/abora-session-setup.sh;
  desktopProfilesScript =
    if builtins.pathExists ./desktop-profiles.sh then
      ./desktop-profiles.sh
    else
      ../../scripts/abora-desktop-profiles.sh;
  installerScript =
    if builtins.pathExists ./installer.sh then
      ./installer.sh
    else
      ../../scripts/abora-installer.sh;
  setupLauncherScript =
    if builtins.pathExists ./setup-launcher.sh then
      ./setup-launcher.sh
    else
      ../../scripts/abora-setup-launcher.sh;
  setupDesktopFile =
    if builtins.pathExists ./setup.desktop then
      ./setup.desktop
    else
      ../../scripts/abora-setup.desktop;
  plymouthDir =
    if builtins.pathExists ./plymouth then
      ./plymouth
    else
      ../../assets/plymouth;
  bootloaderDir =
    if builtins.pathExists ./bootloader then
      ./bootloader
    else
      ../../assets/bootloader;
  effectsDir =
    if builtins.pathExists ./effects then
      ./effects
    else
      ../../assets/Effects;
  limineWallpaperFile =
    if builtins.pathExists (bootloaderDir + "/limine-background.png") then
      bootloaderDir + "/limine-background.png"
    else
      bootloaderDir + "/background.png";
  tinypmDir =
    if builtins.pathExists ./tinypm then
      ./tinypm
    else if builtins.pathExists ../../vendor/tinypm then
      ../../vendor/tinypm
    else
      throw "Abora TinyPM payload is missing. Expected ./tinypm beside installed-base.nix or ../../vendor/tinypm in the source tree.";
  version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile versionFile);
  mkGrabCmd = name: pkgs.writeShellScriptBin name ''
    exec env TINYPM_FLAVOR=abora ${pkgs.bashInteractive}/bin/bash /etc/abora/tinypm/${name} "$@"
  '';
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
    variantName = lib.mkDefault "Abora OS DENALI 3.1.4";
    extraOSReleaseArgs = {
      LOGO = "abora";
      VERSION = "DENALI 3.1.4";
      VERSION_ID = "3.1.4";
      VERSION_CODENAME = "denali";
      PRETTY_NAME = "Abora OS DENALI 3.1.4";
      HOME_URL = "https://www.aboraos.org/";
      SUPPORT_URL = "https://github.com/AnimatedGTVR/abora-os/issues";
      BUG_REPORT_URL = "https://github.com/AnimatedGTVR/abora-os/issues";
      ANSI_COLOR = "0;38;2;80;220;255";
    };
  };

  nixpkgs.config.allowUnfree = lib.mkDefault true;

  nixpkgs.overlays = [
    (final: prev: {
      mango = final.callPackage (
        if builtins.pathExists ./pkgs/mango.nix
        then ./pkgs/mango.nix
        else ../../nix/pkgs/mango.nix
      ) {};
      modularity = final.callPackage (
        if builtins.pathExists ./pkgs/modularity.nix
        then ./pkgs/modularity.nix
        else ../../nix/pkgs/modularity.nix
      ) {};
    })
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_6_6;
  boot.initrd.systemd.enable = lib.mkDefault true;
  boot.initrd.verbose = lib.mkDefault false;
  boot.kernelParams = lib.mkDefault [
    "quiet"
    "splash"
    "udev.log_level=3"
    "systemd.show_status=auto"
  ];
  boot.consoleLogLevel = lib.mkDefault 3;
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
  boot.kernelModules = lib.mkDefault [
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
  networking.modemmanager.enable = lib.mkDefault true;
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

  services.qemuGuest.enable = lib.mkDefault true;
  services.spice-vdagentd.enable = lib.mkDefault true;
  virtualisation.vmware.guest.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86;
  virtualisation.virtualbox.guest.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86;
  virtualisation.hypervGuest.enable =
    lib.mkDefault (pkgs.stdenv.hostPlatform.isx86 || pkgs.stdenv.hostPlatform.isAarch64);

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
    anixCommand
    aboraConfig
    aboraDesktop
    aboraDoctor
    aboraHardwareTest
    aboraRecovery
    aboraSupportReport
    aboraUpdate
    aboraWelcome
    aboraWallpapersPackage
    aboraInstaller
    aboraSetup
    aboraSetupDesktopPkg
    aboraSessionSetup
    aboraThemeSync
    bashInteractive
    curl
    dmidecode
    ethtool
    feh
    fastfetch
    gh
    git
    htop
    iw
    kdePackages.konsole
    linux-firmware
    modemmanager
    nixosCommand
    pciutils
    mpg123
    smartmontools
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
  ];

  programs.zsh = {
    enable = true;
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
      "abora/desktop.sh" = {
        source = desktopScript;
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
      "abora/support-report.sh" = {
        source = supportReportScript;
        mode = "0755";
      };
      "abora/hardware-test.sh" = {
        source = hardwareTestScript;
        mode = "0755";
      };
      "abora/default-wallpaper.png".source = wallpaperFile;
      "abora/title.txt".source = titleFile;
      "abora/fastfetch-logo.txt".source = fastfetchLogoFile;
      "abora/fastfetch-config.jsonc".source = fastfetchConfigFile;
      "abora/effects/v3StartingAbora.mp3".source = effectsDir + "/v3StartingAbora.mp3";
      "abora/desktop-profiles.sh" = {
        source = desktopProfilesScript;
        mode = "0755";
      };
      "abora/pkgs/mango.nix".source = ../../nix/pkgs/mango.nix;
      "abora/pkgs/modularity.nix".source = ../../nix/pkgs/modularity.nix;
      "abora/tinypm".source = tinypmDir;
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
        Abora OS DENALI ${version}

          grab <app>          install an app  (flatpak, nix, or snap)
          search <app>        find apps across all sources
          term <app>          remove an installed app
          supdate             upgrade all installed apps

          abora welcome       first steps and quick actions
          abora doctor        check system health
          abora recovery      rollback and repair tools
          sudo nixos update   rebuild and switch the system
      '';
      "profile.d/abora-welcome.sh".text = ''
        if [ -n "''${PS1:-}" ] && [ -z "''${ABORA_WELCOME_SHOWN:-}" ] && command -v abora-welcome >/dev/null 2>&1; then
          export ABORA_WELCOME_SHOWN=1
          if [ ! -f "$HOME/.cache/abora/welcome-seen" ]; then
            mkdir -p "$HOME/.cache/abora"
            touch "$HOME/.cache/abora/welcome-seen"
            abora-welcome status || true
            printf '  Run %s for first-step actions.\n\n' "abora welcome"
          fi
        fi
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
        Abora OS DENALI 3.1.4
      '';
      "issue.net".text = ''
        Abora OS DENALI 3.1.4
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
    // lib.optionalAttrs (optionsModule != null) {
      "abora/abora-options.nix".source = optionsModule;
    }
    // lib.optionalAttrs (anixModule != null) {
      "abora/anix-module.nix".source = anixModule;
    }
    // lib.optionalAttrs (docsDir != null) {
      "abora/docs".source = docsDir;
    }
    // lib.optionalAttrs (aboraLogoFile != null) {
      "abora/Abora-LOGO.png".source = aboraLogoFile;
    };

  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";

  programs.bash.interactiveShellInit = ''
    [[ $SHLVL -eq 1 ]] && fastfetch -c /etc/xdg/fastfetch/config.jsonc
  '';
}
