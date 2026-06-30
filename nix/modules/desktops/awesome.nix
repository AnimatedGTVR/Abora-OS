{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "awesome") {
    services.xserver = common.xserver // {
      windowManager.awesome.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "none+awesome";
      autoLogin = common.autologin;
    };
  };
}
