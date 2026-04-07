# Building Abora

This page covers local builds for Abora OS.

## Requirements

- Nix with `nix-command` and `flakes`

## Build The ISO

```sh
cd /home/animated/abora-os
make iso
```

## Boot The ISO In QEMU

```sh
cd /home/animated/abora-os
make qemc
```

## Build The Full Release Bundle

```sh
cd /home/animated/abora-os
make release
```

That writes the release bundle into `out/`, including:

- the ISO
- checksums
- release manifest
- release notes
- the TinyPM V3 release tarball

## Refresh Only Metadata

```sh
make metadata
```

## Useful Checks

```sh
./scripts/check-scripts.sh
```

```sh
./scripts/rebuild-vm.sh
```
