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
  updateScript =
    if builtins.pathExists ./update.sh then
      ./update.sh
    else
      ../../scripts/abora-update.sh;
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
  version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile versionFile);
  aboraUpdate = pkgs.writeShellScriptBin "abora-update" ''
    exec env ABORA_UPDATE_COMMAND=abora-update ${pkgs.bashInteractive}/bin/bash /etc/abora/update.sh "$@"
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
  boot.plymouth = {
    enable = lib.mkDefault true;
    theme = "abora";
    themePackages = [ aboraPlymouthTheme ];
  };

  networking.networkmanager.enable = lib.mkDefault true;
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  security.polkit.enable = lib.mkDefault true;
  services.udisks2.enable = lib.mkDefault true;
  services.openssh.enable = lib.mkDefault true;
  security.rtkit.enable = lib.mkDefault true;
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    alsa.support32Bit = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  services.qemuGuest.enable = true;
  virtualisation.vmware.guest.enable = pkgs.stdenv.hostPlatform.isx86;
  virtualisation.hypervGuest.enable =
    pkgs.stdenv.hostPlatform.isx86 || pkgs.stdenv.hostPlatform.isAarch64;

  environment.systemPackages = with pkgs; [
    aboraUpdate
    bashInteractive
    curl
    fastfetch
    git
    htop
    nixosCommand
    updateCommand
    upgradeCommand
    wget
  ];

  environment.etc =
    {
      "abora/VERSION".source = versionFile;
      "abora/title.txt".source = titleFile;
      "abora/fastfetch-logo.txt".source = fastfetchLogoFile;
      "abora/fastfetch-config.jsonc".source = fastfetchConfigFile;
      "abora/update.sh" = {
        source = updateScript;
        mode = "0755";
      };
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
    );

  environment.shellAliases.fastfetch = "fastfetch -c /etc/xdg/fastfetch/config.jsonc";
}
