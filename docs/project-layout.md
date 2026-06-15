# Project Layout

This is the quick map of the Abora OS repo for the DENALI 3.1.4 release.

## Top Level

- `README.md`: main project overview
- `RELEASE_NOTES.md`: release notes source
- `VERSION`: current version string used by build and release tooling
- `LICENSE`: project license
- `Makefile`: command entrypoint for building, checking, QEMU testing, and releasing
- `flake.nix` and `flake.lock`: Nix flake entrypoint and pinned dependencies

## Main Directories

### `assets/`

Visual and branding files used by the live image, boot flow, wallpapers, and desktop defaults.

Important subfolders:

- `assets/bootloader/`
- `assets/plymouth/`
- `assets/wallpapers/collection/`
- `assets/wallpaper-themes/`
- `assets/Effects/`

Important files:

- `assets/abora-title.txt`
- `assets/fastfetch-config.jsonc`
- `assets/fastfetch-logo.txt`

### `docs/`

Project docs for development, installation, release work, and wiki publishing.

- `docs/install-checklist.md`
- `docs/hardware-testing.md`
- `docs/release-checklist.md`
- `docs/roadmap.md`
- `docs/wiki/`

### `nix/`

NixOS configuration used to build the live ISO and installed system modules.

Important paths:

- `nix/profiles/live.nix`: live ISO profile, live boot service, bundled installer assets
- `nix/modules/installed-base.nix`: installed Abora base module
- `nix/modules/abora-options.nix`: Abora option layer used by installed configs
- `nix/modules/anix.nix`: ANIX NixOS module

### `scripts/`

Shell scripts for the live environment, installer, installed commands, ISO builds, release metadata, checks, and QEMU booting.

Important files:

- `scripts/abora-boot.sh`: live stage-one boot handoff
- `scripts/abora-installer.sh`: Omarchy-inspired Denali installer and reconfiguration TUI
- `scripts/abora-setup-launcher.sh`: installed desktop launcher for `abora setup`
- `scripts/abora-setup.desktop`: installed desktop entry
- `scripts/abora-desktop-profiles.sh`: supported desktop profile definitions
- `scripts/abora-session-setup.sh`: first-session defaults
- `scripts/abora-support-report.sh`: support archive generation
- `scripts/check-scripts.sh`: repo script and runtime sanity checks
- `scripts/check-desktops.sh`: evaluates every supported desktop profile
- `scripts/build-iso.sh`: ISO-only build path
- `scripts/package-tinypm.sh`: TinyPM release package path
- `scripts/release-metadata.sh`: checksums, manifest, and release notes
- `scripts/run-qemu.sh`: QEMU ISO, fresh-disk, disk-only, and serial helpers

### `vendor/`

Vendored external code that Abora uses directly.

- `vendor/tinypm/`: TinyPM v4 source used for Abora `grab`, `search`, `term`, `start`, `supdate`, and Abora/ANIX/Nix system bridges

## Generated Output

### `out/`

Generated build output. Do not treat this as source.

It can contain:

- `out/iso/`: built ISO files
- `out/packages/`: TinyPM release tarballs and other generated packages
- `out/release/`: checksum files, release manifests, and generated release notes
- `out/qemu/`: QEMU disks and firmware state
- `out/logs/`: QEMU serial logs and build logs
- `out/nix/`: Nix build result symlinks
