{ lib, pkgs, version, ... }:
let
  aboraCenter = pkgs.writeShellScriptBin "abora-center" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/center.sh "$@"
  '';
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
  aboraWelcome = pkgs.writeShellScriptBin "abora-welcome" ''
    exec ${pkgs.bashInteractive}/bin/bash /etc/abora/welcome.sh "$@"
  '';
  aboraCenterDesktop = pkgs.makeDesktopItem {
    name = "abora-center";
    desktopName = "Abora Center";
    comment = "Abora live tools and installer hub";
    exec = "abora-center";
    terminal = false;
    categories = [ "System" "Settings" "Utility" ];
  };
  aboraWelcomeDesktop = pkgs.makeDesktopItem {
    name = "abora-welcome";
    desktopName = "Abora Welcome";
    comment = "Abora live session welcome screen";
    exec = "abora-welcome";
    terminal = false;
    categories = [ "System" "Utility" ];
  };
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
    aboraCenter
    aboraCenterDesktop
    aboraUpdate
    aboraWelcome
    aboraWelcomeDesktop
    bashInteractive
    dosfstools
    e2fsprogs
    fastfetch
    git
    curl
    wget
    htop
    iproute2
    kbd
    nixosCommand
    openssl
    parted
    util-linux
    updateCommand
    upgradeCommand
    whois
    openbox
    xauth
    xinit
    xorg-server
    xsetroot
    xterm
    zenity
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
      "abora/default-wallpaper.png".source = ../../assets/wallpaper.png;
      "abora/title.txt".source = ../../assets/abora-title.txt;
      "abora/VERSION".source = ../../VERSION;
      "abora/fastfetch-logo.txt".source = ../../assets/fastfetch-logo.txt;
      "abora/fastfetch-config.jsonc".source = ../../assets/fastfetch-config.jsonc;
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
      "abora/launch-gui.sh" = {
        source = ../../scripts/abora-launch-gui.sh;
        mode = "0755";
      };
      "abora/center.sh" = {
        source = ../../scripts/abora-center.sh;
        mode = "0755";
      };
      "abora/installer.sh" = {
        source = ../../scripts/abora-installer.sh;
        mode = "0755";
      };
      "abora/installed-base.nix".source = ../../nix/modules/installed-base.nix;
      "abora/update.sh" = {
        source = ../../scripts/abora-update.sh;
        mode = "0755";
      };
      "abora/welcome.sh" = {
        source = ../../scripts/abora-welcome.sh;
        mode = "0755";
      };
    }
    // builtins.listToAttrs (
      map
        (name: {
          name = "abora/bootloader/${name}";
          value.source = ../../assets/bootloader + "/${name}";
        })
        (builtins.attrNames (builtins.readDir ../../assets/bootloader))
    );

  services.xserver.enable = false;
  services.qemuGuest.enable = true;
  virtualisation.vmware.guest.enable = pkgs.stdenv.hostPlatform.isx86;
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
  isoImage.prependToMenuLabel = "Boot ";
  isoImage.appendToMenuLabel = "";
  isoImage.configurationName = "Live";
  isoImage.splashImage = ../../assets/bootloader/background.png;
  isoImage.grubTheme = null;
  isoImage.syslinuxTheme = ''
    MENU RESOLUTION 800 600
    MENU CLEAR
    MENU WIDTH 76
    MENU MARGIN 0
    MENU ROWS 6
    MENU VSHIFT 10
    MENU HSHIFT 0
    MENU TABMSGROW 18
    MENU CMDLINEROW 19
    MENU TIMEOUTROW 21
    MENU HELPMSGROW 22
    MENU HELPMSGENDROW 22

    MENU COLOR BORDER       30;40      #00000000    #00000000   none
    MENU COLOR SCREEN       37;40      #00000000    #00000000   none
    MENU COLOR TABMSG       30;40      #CC0A1426    #00000000   none
    MENU COLOR TIMEOUT      1;30;40    #FF0A1426    #00000000   none
    MENU COLOR TIMEOUT_MSG  30;40      #FF0A1426    #00000000   none
    MENU COLOR CMDMARK      1;30;40    #FF0A1426    #00000000   none
    MENU COLOR CMDLINE      30;40      #FF0A1426    #00000000   none
    MENU COLOR TITLE        1;37;40    #00000000    #00000000   none
    MENU COLOR UNSEL        30;40      #FF0A1426    #00000000   none
    MENU COLOR SEL          7;30;40    #FF0A1426    #992A4F86   std
  '';
}
