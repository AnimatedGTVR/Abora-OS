{ config, pkgs, lib, ... }:

let
  isoDerivation = pkgs.runCommand "abora-iso" { buildInputs = [ pkgs.xorriso ]; } ''
    mkdir -p iso-root
    echo "Abora OS" > iso-root/README
    ${pkgs.xorriso}/bin/xorriso -as mkisofs -o $out iso-root
  '';
in
{
  options.isoImage = {
    isoName = lib.mkOption {
      type = lib.types.str;
      default = "abora-${config.system.nixos.version or "dev"}-x86_64.iso";
      description = "Name of the generated ISO image file.";
    };
  };

  config = {
    system.build.isoImage = isoDerivation;
  };
}
