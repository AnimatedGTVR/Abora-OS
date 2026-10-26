{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  # Not services.xserver.desktopManager.lumina: at Abora's nixpkgs pin that module
  # still asks for libsForQt5.kwindowsystem, which nixpkgs removed, so it fails to
  # evaluate. This is the same setup without it.
  config = lib.mkIf (common.enabled "lumina") {
    services.xserver = common.xserver // {
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      sessionPackages = [ pkgs.lumina.lumina ];
      defaultSession = "Lumina-DE";
      autoLogin = common.autologin;
    };
    environment.systemPackages = (with pkgs; [ fluxbox numlockx qt5.qtsvg xscreensaver ])
      ++ pkgs.lumina.corePackages;
    environment.pathsToLink = [ "/share/lumina" ];
  };
}
