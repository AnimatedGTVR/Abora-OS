{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "qtile") {
    services.xserver = common.xserver // {
      windowManager.qtile.enable = true;
      desktopManager.runXdgAutostartIfNone = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "qtile";
      autoLogin = common.autologin;
    };
  };
}
