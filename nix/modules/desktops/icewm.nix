{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "icewm") {
    services.xserver = common.xserver // {
      windowManager.icewm.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+icewm";
      autoLogin = common.autologin;
    };
  };
}
