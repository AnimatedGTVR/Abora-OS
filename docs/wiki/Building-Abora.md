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

## Build The Default ISO

```sh
make iso
```

`make iso` builds the default Cosmic edition ISO and copies it into `out/iso/`.

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
./scripts/check-desktops.sh
```
