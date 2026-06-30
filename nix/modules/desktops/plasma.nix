{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "plasma") {
    services.xserver = common.xserver;
    services.displayManager = {
      defaultSession = "plasma";
      autoLogin = common.autologin;
    };
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
  };
}
