{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "fluxbox") {
    services.xserver = common.xserver // {
      windowManager.fluxbox.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+fluxbox";
      autoLogin = common.autologin;
    };
  };
}
