{ lib, pkgs, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "pantheon") {
    services.xserver = common.xserver // {
      displayManager.lightdm.enable = true;
    };
    services.displayManager = {
      defaultSession = "pantheon-wayland";
      autoLogin = common.autologin;
    };
    services.desktopManager.pantheon.enable = true;
    environment.etc."xdg/gtk-4.0/settings.ini".source =
      lib.mkForce "${pkgs.pantheon.elementary-default-settings}/etc/gtk-4.0/settings.ini";
  };
}
