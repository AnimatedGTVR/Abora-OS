{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "openbox") {
    services.xserver = common.xserver // {
      windowManager.openbox.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+openbox";
      autoLogin = common.autologin;
    };
  };
}
