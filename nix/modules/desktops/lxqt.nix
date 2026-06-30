{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "lxqt") {
    services.xserver = common.xserver // {
      desktopManager.lxqt.enable = true;
    };
    services.displayManager = {
      defaultSession = "lxqt";
      autoLogin = common.autologin;
    };
    services.displayManager.sddm.enable = true;
  };
}
