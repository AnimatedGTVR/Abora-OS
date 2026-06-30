{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "i3") {
    services.xserver = common.xserver // {
      windowManager.i3.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+i3";
      autoLogin = common.autologin;
    };
  };
}
