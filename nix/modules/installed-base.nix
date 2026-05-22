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
      ../../assets/wallpapers/collection/oceandusk.png;
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
    else
      ../../vendor/tinypm;
  version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile versionFile);
  tinypmPackage = pkgs.runCommandLocal "abora-tinypm" { } ''
    cp -r ${tinypmDir}/. $out
    chmod -R u+w $out
    for cmd in grab search term start supdate tinypm; do
      [ -f "$out/$cmd" ] && chmod +x "$out/$cmd"
    done
  '';
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
    variantName = lib.mkDefault "Abora ${version}";
  };

  nixpkgs.config.allowUnfree = lib.mkDefault true;

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
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;
  boot.loader.limine.style.wallpapers = [ limineWallpaperFile ];
  boot.plymouth = {
    enable = lib.mkDefault true;
    theme = "abora";
    themePackages = [ aboraPlymouthTheme ];
  };

  networking.networkmanager.enable = lib.mkDefault true;
  security.polkit.enable = lib.mkDefault true;
  services.udisks2.enable = lib.mkDefault true;
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
  };

  environment.systemPackages = with pkgs; [
    (mkGrabCmd "grab")
    (mkGrabCmd "search")
    (mkGrabCmd "term")
    (mkGrabCmd "start")
    (mkGrabCmd "supdate")
    aboraApps
    aboraCommand
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
    nixosCommand
    pciutils
    mpg123
    smartmontools
    updateCommand
    upgradeCommand
    rollbackCommand
    usbutils
    wget
    papirus-icon-theme
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    xdg-utils
    xterm
    swaybg
  ];

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
      "abora/tinypm".source = tinypmPackage;
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
        Abora OS ${version} — Denali

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
      "abora/plymouth/abora.plymouth".source = plymouthDir + "/abora.plymouth";
      "abora/plymouth/abora.script".source = plymouthDir + "/abora.script";
      "xdg/fastfetch/config.jsonc".source = fastfetchConfigFile;
      "skel/.config/fastfetch/config.jsonc".source = fastfetchConfigFile;
      "issue".text = ''
        Abora OS ${version}
      '';
      "issue.net".text = ''
        Abora OS ${version}
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
    };

  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";
}
