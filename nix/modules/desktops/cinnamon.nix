{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "cinnamon") {
    services.xserver = common.xserver // {
      desktopManager.cinnamon.enable = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "cinnamon";
      autoLogin = common.autologin;
    };
  };
}
