{
  description = "Abora OS (NixOS base)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./VERSION);

      overlay = final: prev: {
        anix = final.callPackage ./nix/pkgs/anix.nix {};
        mango = final.callPackage ./nix/pkgs/mango.nix {};
        modularity = final.callPackage ./nix/pkgs/modularity.nix {};
      };

      pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
    in {
      overlays.default = overlay;

      nixosModules = {
        installed-base = import ./nix/modules/installed-base.nix;
        anix = import ./nix/modules/anix.nix;
      };

      nixosConfigurations.abora-live = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit version; };
        modules = [
          (nixpkgs.outPath + "/nixos/modules/installer/cd-dvd/iso-image.nix")
          ./nix/profiles/live.nix
          { nixpkgs.overlays = [ overlay ]; }
        ];
      };

      packages.${system} = {
        anix  = pkgs.anix;
        iso   = self.nixosConfigurations.abora-live.config.system.build.isoImage;
        mango = pkgs.mango;
        modularity = pkgs.modularity;
      };
      apps.${system}.anix = {
        type = "app";
        program = "${self.packages.${system}.anix}/bin/anix";
      };
      defaultPackage.${system} = self.packages.${system}.iso;
    };
}
