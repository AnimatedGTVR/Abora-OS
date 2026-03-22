{ lib, pkgs, version, ... }:
{
  networking.hostName = "abora";
  system.nixos.tags = [ "abora" "nixos-base" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
    parted
    util-linux
    whois
  ];

  environment.variables = {
    ABORA_VERSION = version;
  };

  environment.etc."abora/README".text = ''
    Abora OS live image
    Base: Abora OS
  '';

  environment.etc."abora/default-wallpaper.png".source = ../../assets/wallpaper.png;
  environment.etc."abora/title.txt".source = ../../assets/abora-title.txt;

  services.xserver.enable = false;
  services.getty.autologinUser = "root";

  environment.shellAliases.fastfetch = "fastfetch --logo-type file-raw --logo /etc/abora/title.txt";

  environment.etc."profile.d/abora-live.sh".text = ''
    if [ "$USER" = "root" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ] && [ -z "''${ABORA_BOOT_MENU:-}" ]; then
      export ABORA_BOOT_MENU=1
      exec /etc/abora/boot.sh
    fi
  '';

  environment.etc."abora/boot.sh".source = ../../scripts/abora-boot.sh;
  environment.etc."abora/boot.sh".mode = "0755";
  environment.etc."abora/installer.sh".source = ../../scripts/abora-installer.sh;
  environment.etc."abora/installer.sh".mode = "0755";

  isoImage.isoName = lib.mkForce "abora-${version}-x86_64.iso";
  isoImage.appendToMenuLabel = " Live";
}
