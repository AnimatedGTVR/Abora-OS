{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "herbstluftwm") {
    services.xserver = common.xserver // {
      windowManager.herbstluftwm.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+herbstluftwm";
      autoLogin = common.autologin;
    };
  };
}
