{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "budgie") {
    services.xserver = common.xserver // {
      desktopManager.budgie.enable = true;
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "budgie-desktop";
      autoLogin = common.autologin;
    };
  };
}
