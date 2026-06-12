# Building Abora

This page covers local builds for Abora OS.

## Requirements

- Nix with `nix-command` and `flakes`
- QEMU for local VM tests

## Build Only The ISO

```sh
make iso
```

`make iso` only builds the ISO and copies it into `out/`.

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

- the ISO
- the TinyPM release tarball
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
