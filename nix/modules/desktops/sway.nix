{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "sway") {
    services.xserver = common.xserver;
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };
    services.displayManager = {
      defaultSession = "sway";
      autoLogin = common.autologin;
    };
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-wlr xdg-desktop-portal-gtk ];
      config = {
        sway.default = lib.mkForce [ "wlr" "gtk" ];
        common.default = lib.mkForce [ "gtk" ];
      };
    };
  };
}
