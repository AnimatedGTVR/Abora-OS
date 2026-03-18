{ lib, pkgs, version, ... }:
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
  environment.etc."calamares/settings.conf".source = pkgs.runCommand "abora-calamares-settings.conf" {} ''
    sed 's/^branding: nixos$/branding: abora/' \
      ${pkgs.calamares-nixos-extensions}/share/calamares/settings.conf > "$out"
  '';
  environment.etc."calamares/branding/abora/branding.desc".source = ../calamares/branding/branding.desc;
  environment.etc."calamares/branding/abora/show.qml".source = ../calamares/branding/show.qml;
  environment.etc."calamares/branding/abora/abora-logo.png".source = ../../assets/abora-logo.png;

  isoImage.isoName = lib.mkForce "abora-${version}-x86_64.iso";
}
