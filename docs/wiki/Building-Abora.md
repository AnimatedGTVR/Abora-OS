# Building Abora

This page covers local builds for Abora OS.

## Requirements

- Nix with `nix-command` and `flakes`
- QEMU for local VM tests

Not sure your machine has all of that, or want it checked automatically
instead of guessing? Run:

```sh
make doctor
```

It checks git, Nix (installed, flakes/nix-command enabled, daemon actually
reachable), QEMU, free disk space, and OS/architecture, and tells you what
to do about anything missing.

`check-desktops` and the full release preflight also need an importable
nixpkgs source. If Nix is installed but the daemon/store is unavailable, the
desktop matrix will stop before evaluating profiles instead of hanging or
printing a long Nix stack trace. Fix the daemon/store first, or point the
check at a known nixpkgs checkout/source path:

```sh
ABORA_NIXPKGS_PATH=/nix/store/...-source ./scripts/check-desktops.sh
```

## Build The Default ISO

```sh
make iso
```

`make iso` builds the default Cosmic edition ISO and copies it into `out/iso/`.

## Build Abora From Source

If you want to compile Abora yourself from a fresh checkout:

```sh
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
nix build .#nixosConfigurations.abora.config.system.build.toplevel
```

On older checkouts that do not have the short `abora` flake alias yet, use:

```sh
nix build .#nixosConfigurations.abora-live-cosmic.config.system.build.toplevel
```

The friendly wrapper does the same thing and can clone the checkout for you
when you are not already inside one. It also falls back to the older
`abora-live-cosmic` target automatically if needed:

```sh
./abora build --from-source
```

On an installed Abora system, the same helper is available without `./`:

```sh
abora build --from-source
```

## Adopt Abora On Existing NixOS

To add Abora to a normal NixOS install without reinstalling or wiping `/home`:

```sh
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
./abora adopt-nixos
sudo ./abora adopt-nixos --apply
sudo nixos-rebuild test
sudo nixos-rebuild switch
```

The adoption path backs up `/etc/nixos`, imports Abora with
`abora.user.name = null`, and defaults to `abora.desktop = "none"` so existing
users, applications, and desktop settings stay in charge.

## Build Every Edition ISO

```sh
make iso-all
```

`make iso-all` builds the Cosmic, Hyprland, GNOME, KDE Plasma, and Other
Desktops edition ISOs.

## Boot The ISO In QEMU

```sh
make qemu
```

For clean install testing, use a fresh disk:

```sh
make qemu-fresh
```

After installing, boot the virtual hard drive without attaching the ISO:

```sh
make qemu-disk
```

For terminal-only QEMU output:

```sh
make qemu-serial
```

## Build The Full Release Bundle

```sh
make release
```

`make release` builds:

- all five edition ISOs
- the TinyPM release tarball
- the ANIX standalone tarball
- checksums
- release manifest
- generated release notes

## Refresh Only Metadata

```sh
make metadata
```

## Useful Checks

```sh
./scripts/check-scripts.sh
./scripts/check-all-files.sh
./scripts/check-desktops.sh
```

Run `make doctor` first if `check-desktops` cannot find nixpkgs or reports
that the Nix daemon/store is unavailable.
