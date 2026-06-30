{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "hyprland") {
    services.xserver = common.xserver;
    services.displayManager = {
      defaultSession = "hyprland-uwsm";
      autoLogin = common.autologin;
    };
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    programs.hyprland = {
      enable = true;
      withUWSM = true;
      xwayland.enable = true;
    };
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-hyprland xdg-desktop-portal-gtk ];
      config = {
        hyprland.default = lib.mkForce [ "hyprland" "gtk" ];
        hyprland-uwsm.default = lib.mkForce [ "hyprland" "gtk" ];
        common.default = lib.mkForce [ "gtk" ];
      };
    };
  };
}
