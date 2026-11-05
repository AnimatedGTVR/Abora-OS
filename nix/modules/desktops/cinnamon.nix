{ lib, config, pkgs, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "cinnamon") {
    services.xserver = common.xserver // {
      desktopManager.cinnamon.enable = true;
      displayManager.lightdm.enable = true;
    };
    environment.cinnamon.excludePackages = with pkgs; [ onboard gucharmap ];
    services.displayManager = {
      defaultSession = "cinnamon";
      autoLogin = common.autologin;
    };
  };
}
