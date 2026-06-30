{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "xfce") {
    services.xserver = common.xserver // {
      desktopManager.xfce.enable = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "xfce";
      autoLogin = common.autologin;
    };
  };
}
