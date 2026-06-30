{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "bspwm") {
    services.xserver = common.xserver // {
      windowManager.bspwm.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+bspwm";
      autoLogin = common.autologin;
    };
    environment.systemPackages = [ pkgs.sxhkd ];
  };
}
