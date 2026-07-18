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
        moducpp-anix = final.callPackage ./nix/pkgs/moducpp-anix.nix {};
      };

	pkgs = import nixpkgs {
  inherit system;
  overlays = [ overlay ];

  config.allowUnfreePredicate = pkg:
    builtins.elem (nixpkgs.lib.getName pkg) [
      "modularity"
    ];
};

mkLive = liveEdition: nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit version liveEdition; };

  modules = [
    (nixpkgs.outPath + "/nixos/modules/installer/cd-dvd/iso-image.nix")
    ./nix/profiles/live.nix

    {
      nixpkgs = {
        overlays = [ overlay ];

        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "modularity"
          ];
      };
    }
  ];
};

    in {
      overlays.default = overlay;

      nixosModules = {
        installed-base = import ./nix/modules/installed-base.nix;
        anix = import ./nix/modules/anix.nix;
      };

      nixosConfigurations = {
        abora-live = mkLive "cosmic";
        abora-live-cosmic = mkLive "cosmic";
        abora-live-hyprland = mkLive "hyprland";
        abora-live-gnome = mkLive "gnome";
        abora-live-kde = mkLive "kde";
        abora-live-other = mkLive "other";
      };

      packages.${system} = {
        anix = pkgs.anix;

        iso = self.nixosConfigurations.abora-live-cosmic.config.system.build.isoImage;
        iso-cosmic = self.nixosConfigurations.abora-live-cosmic.config.system.build.isoImage;
        iso-hyprland = self.nixosConfigurations.abora-live-hyprland.config.system.build.isoImage;
        iso-gnome = self.nixosConfigurations.abora-live-gnome.config.system.build.isoImage;
        iso-kde = self.nixosConfigurations.abora-live-kde.config.system.build.isoImage;
        iso-other = self.nixosConfigurations.abora-live-other.config.system.build.isoImage;

        mango = pkgs.mango;
        modularity = pkgs.modularity;
        moducpp-anix = pkgs.moducpp-anix;

        default = self.nixosConfigurations.abora-live-cosmic.config.system.build.isoImage;
      };

      apps.${system}.anix = {
        type = "app";
        program = "${self.packages.${system}.anix}/bin/anix";

        meta = {
          description = "ANIX system management tool";
        };
      };
    };
}
