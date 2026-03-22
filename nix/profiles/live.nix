{ lib, pkgs, version, ... }:
{
  networking.hostName = "abora";
  system.nixos.tags = [ "abora" "nixos-base" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];

  environment.systemPackages = with pkgs; [
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
    openssl
    parted
    util-linux
    whois
  ];

  environment.variables = {
    ABORA_VERSION = version;
    ABORA_NIXPKGS_PATH = pkgs.path;
  };

  environment.etc."abora/README".text = ''
    Abora OS live image
    Base: Abora OS
  '';

  environment.etc."abora/default-wallpaper.png".source = ../../assets/wallpaper.png;
  environment.etc."abora/title.txt".source = ../../assets/abora-title.txt;
  environment.etc."abora/nixpkgs".source = pkgs.path;

  services.xserver.enable = false;
  environment.shellAliases.fastfetch = "fastfetch --logo-type file-raw --logo /etc/abora/title.txt";

  environment.etc."abora/boot.sh".source = ../../scripts/abora-boot.sh;
  environment.etc."abora/boot.sh".mode = "0755";
  environment.etc."abora/installer.sh".source = ../../scripts/abora-installer.sh;
  environment.etc."abora/installer.sh".mode = "0755";

  systemd.services."getty@tty1".enable = lib.mkForce false;
  systemd.services.abora-boot = {
    description = "Abora live boot menu";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    conflicts = [ "getty@tty1.service" ];
    before = [ "getty@tty1.service" ];
    environment = {
      ABORA_NIXPKGS_PATH = "/etc/abora/nixpkgs";
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

  isoImage.isoName = lib.mkForce "abora-${version}-x86_64.iso";
  isoImage.appendToMenuLabel = " Live";
}
