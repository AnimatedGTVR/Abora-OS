# ANIX Standalone

ANIX can be used outside Abora on plain NixOS systems.

## Flake Install

Add this repository as an input and use both the module and package:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    abora.url = "github:AnimatedGTVR/abora-os";
  };

  outputs = { nixpkgs, abora, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        abora.nixosModules.anix
        ({ pkgs, ... }: {
          environment.systemPackages = [ abora.packages.${pkgs.system}.anix ];
        })
        ./anix.nix
      ];
    };
  };
}
```

Then create an `anix.nix` layer such as:

```nix
{ pkgs, ... }: {
  anix.enable = true;
  anix.hostname = "my-host";
  anix.timezone = "UTC";
  anix.shell = "zsh";
}
```

After rebuilding, you can use:

```sh
anix init
anix status
anix apply
anix doctor
```

## Package Only

If you just want the CLI in your current profile:

```sh
nix profile install github:AnimatedGTVR/abora-os#anix
```

That installs the standalone `anix` command with bundled docs, bundled TinyPM source, and the ANIX module at:

```text
share/anix/anix-module.nix
```

## Release Tarball

This repository can also build a portable ANIX tarball:

```sh
make anix-package
```

The tarball includes:

- `bin/anix`
- `share/anix/anix-module.nix`
- ANIX and TinyPM docs
- bundled TinyPM source for `anix tinypm install`

You can unpack it and run:

```sh
./install.sh
```
