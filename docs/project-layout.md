# Project Layout

This is the quick map of the Abora OS repo.

## Top level

- `README.md`: main project overview
- `RELEASE_NOTES.md`: source release notes used for the generated release bundle
- `VERSION`: current version string used by build and release tooling
- `LICENSE`: project license
- `Makefile`: the short command entrypoint for building, checking, and releasing
- `flake.nix` and `flake.lock`: Nix flake entrypoint and pinned dependencies

## Main directories

### `assets/`

Visual and branding files used by the live image and boot flow.

Important subfolders:

- `assets/bootloader/`
- `assets/plymouth/`

Important files:

- `assets/wallpaper.png`
- `assets/abora-title.txt`
- `assets/fastfetch-config.jsonc`
- `assets/fastfetch-logo.txt`

### `docs/`

Project docs that are useful during development and release work.

- `docs/install-checklist.md`
- `docs/release-checklist.md`
- `docs/roadmap.md`

### `nix/`

NixOS configuration used to build the live ISO.

Important paths:

- `nix/profiles/live.nix`
- `nix/modules/`

### `scripts/`

Shell scripts for the live environment, installer, ISO builds, release metadata, and QEMU booting.

Important files:

- `scripts/abora-boot.sh`
- `scripts/abora-installer.sh`
- `scripts/abora-center.sh`
- `scripts/abora-welcome.sh`
- `scripts/build-iso.sh`
- `scripts/release-metadata.sh`
- `scripts/run-qemu.sh`

### `vendor/`

Vendored external code that Abora uses directly.

Right now this mainly means:

- `vendor/tinypm/`

## Generated output

### `out/`

This is generated build output and should not be treated like source.

It can contain:

- built ISO files
- checksum files
- release manifests
- generated release notes
- QEMU disks
