{ pkgs, version, ... }:
{
  imports = [
    ../modules/live-extensions.nix
  ];

  networking.hostName = "abora";
  system.nixos.tags = [ "abora" "nixos-base" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    fastfetch
    git
    curl
    wget
    htop
  ];

  environment.variables = {
    ABORA_VERSION = version;
  };

  environment.etc."abora/README".text = ''
    Abora OS live image
    Base: NixOS
  '';

  environment.etc."abora/default-wallpaper.png".source = ../../assets/wallpaper.png;

  isoImage.isoName = "abora-${version}-x86_64.iso";
}
