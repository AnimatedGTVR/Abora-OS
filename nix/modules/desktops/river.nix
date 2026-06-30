{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "river") {
    services.xserver = common.xserver;
    programs.river = {
      enable = true;
      xwayland.enable = true;
    };
    services.displayManager = {
      defaultSession = "river";
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
        river.default = lib.mkForce [ "wlr" "gtk" ];
        common.default = lib.mkForce [ "gtk" ];
      };
    };
  };
}
