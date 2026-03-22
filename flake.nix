{
  description = "Abora OS (NixOS base)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/812b3986fd1568f7a858f97fcf425ad996ba7d25";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      version = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./VERSION);
    in {
      nixosConfigurations.abora-live = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit version; };
        modules = [
          (nixpkgs.outPath + "/nixos/modules/installer/cd-dvd/iso-image.nix")
          ./nix/profiles/live.nix
        ];
      };

      packages.${system}.iso = self.nixosConfigurations.abora-live.config.system.build.isoImage;
      defaultPackage.${system} = self.packages.${system}.iso;
    };
}
