{ lib, config, ... }:
let
  common = import ./common.nix { inherit config; };
in
{
  config = lib.mkIf (common.enabled "none") {
    services.getty.autologinUser = common.cfg.user.name;
  };
}
