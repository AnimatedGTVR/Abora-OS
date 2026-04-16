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
  limineWallpaperFile =
    if builtins.pathExists (bootloaderDir + "/limine-background.png") then
      bootloaderDir + "/limine-background.png"
    else
      bootloaderDir + "/background.png";
  version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile versionFile);
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

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];

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
  boot.loader.grub.splashImage = lib.mkForce (bootloaderDir + "/background.png");
  boot.loader.limine.style.wallpapers = [ limineWallpaperFile ];
  boot.plymouth = {
    enable = lib.mkDefault true;
    theme = "abora";
    themePackages = [ aboraPlymouthTheme ];
  };

  networking.networkmanager.enable = lib.mkDefault true;
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
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

  services.qemuGuest.enable = lib.mkDefault true;
  services.spice-vdagentd.enable = lib.mkDefault true;
  virtualisation.vmware.guest.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86;
  virtualisation.virtualbox.guest.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86;
  virtualisation.hypervGuest.enable =
    lib.mkDefault (pkgs.stdenv.hostPlatform.isx86 || pkgs.stdenv.hostPlatform.isAarch64);

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
  ];
  fonts.fontconfig = {
    enable = lib.mkDefault true;
    defaultFonts = {
      sansSerif = lib.mkDefault [ "Noto Sans" ];
      serif     = lib.mkDefault [ "Noto Serif" ];
      monospace = lib.mkDefault [ "Noto Sans Mono" ];
      emoji     = lib.mkDefault [ "Noto Color Emoji" ];
    };
  };

  environment.variables = {
    XCURSOR_THEME = lib.mkDefault "Adwaita";
    XCURSOR_SIZE  = lib.mkDefault "24";
  };

  environment.systemPackages = with pkgs; [
    aboraApps
    aboraHardwareTest
    aboraSupportReport
    aboraUpdate
    aboraWallpapersPackage
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
      "abora/desktop-profiles.sh" = {
        source = desktopProfilesScript;
        mode = "0755";
      };
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
    );

  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";
}
