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
        scenefx-0_5 = final.callPackage ./nix/pkgs/scenefx-0_5.nix {};
        mango = final.callPackage ./nix/pkgs/mango.nix {};
        modularity = final.callPackage ./nix/pkgs/modularity.nix {};
        moducpp-anix = final.callPackage ./nix/pkgs/moducpp-anix.nix {};
        abora-update-resolver = final.callPackage ./nix/pkgs/abora-update-resolver.nix {};
        abora-plan-tool = final.callPackage ./nix/pkgs/abora-plan-tool.nix {};
        abora-desktop-preview = final.callPackage ./nix/pkgs/desktop-preview.nix {};
        abora-hardware-test = final.callPackage ./nix/pkgs/hardware-test.nix {};
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];

        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "modularity"
            "steam"
            "steam-original"
            "steam-run"
            "steam-unwrapped"
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
                  "steam"
                  "steam-original"
                  "steam-run"
                  "steam-unwrapped"
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
        branding = import ./nix/modules/branding.nix;
      };

      nixosConfigurations = {
        abora = mkLive "cosmic";
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
        abora-desktop-preview = pkgs.abora-desktop-preview;
        abora-hardware-test = pkgs.abora-hardware-test;

        default = self.nixosConfigurations.abora-live-cosmic.config.system.build.isoImage;
      };

      apps.${system} = {
        anix = {
          type = "app";
          program = "${self.packages.${system}.anix}/bin/anix";

          meta = {
            description = "ANIX system management tool";
          };
        };

        desktop-preview = {
          type = "app";
          program = "${self.packages.${system}.abora-desktop-preview}/bin/abora-desktop-preview";

          meta = {
            description = "Preview Abora OS's NixOS config/packages for a desktop profile, standalone";
          };
        };

        hardware-test = {
          type = "app";
          program = "${self.packages.${system}.abora-hardware-test}/bin/abora-hardware-test";

          meta = {
            description = "Check whether a machine looks ready for Abora OS hardware testing, standalone";
          };
        };
      };
    };
}
