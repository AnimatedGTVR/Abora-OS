{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
  mangoConfigText = builtins.readFile ../../assets/mango/config.conf;
in
{
  config = lib.mkIf (common.enabled "mangowm") {
    services.xserver = common.xserver;
    environment.systemPackages = with pkgs; [ mango foot waybar wofi ];
    environment.etc."mango/config.conf".text = mangoConfigText;
    services.displayManager = {
      defaultSession = "mango";
      autoLogin = common.autologin;
      sessionPackages = [ pkgs.mango ];
    };
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-wlr xdg-desktop-portal-gtk ];
      wlr.enable = true;
      config = {
        mango.default = lib.mkForce [ "wlr" "gtk" ];
        common.default = lib.mkForce [ "gtk" ];
      };
    };
    security.polkit.enable = true;
    programs.xwayland.enable = true;
  };
}
