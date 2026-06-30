{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "niri") {
    services.xserver = common.xserver;
    programs.niri.enable = true;
    services.displayManager = {
      defaultSession = "niri";
      autoLogin = common.autologin;
    };
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config = {
        niri.default = lib.mkForce [ "gtk" ];
        common.default = lib.mkForce [ "gtk" ];
      };
    };
  };
}
