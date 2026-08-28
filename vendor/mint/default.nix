{ pkgs }:

pkgs.buildGoModule rec {
  pname = "gum";
  version = "0.15.2-abora";

  src = ./.;

  vendorHash = null;

  ldflags = [ "-s" "-w" "-X=main.Version=${version}" ];
}
