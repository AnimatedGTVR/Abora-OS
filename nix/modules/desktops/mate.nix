{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "mate") {
    services.xserver = common.xserver // {
      desktopManager.mate.enable = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "mate";
      autoLogin = common.autologin;
    };
  };
}
