# Abora Release Checklist

Use this after a local release build or after the GitHub ISO workflow succeeds.

## Build Output

- run `make iso` for quick Cosmic ISO validation
- run `make iso-all` to build Cosmic, Hyprland, GNOME, KDE, and Other edition ISOs
- run `make release` only when preparing the full release bundle
- verify the edition ISOs exist in `out/iso/`
- verify the checksum in `out/release/SHA256SUMS-<version>.txt`
- confirm `out/release/RELEASE_MANIFEST-<version>.txt` matches every published ISO plus the TinyPM and ANIX packages
- confirm each artifact name and ISO filename match the intended version

## Repository Checks

- run `./scripts/check-scripts.sh`
- run `./scripts/check-desktops.sh`
- confirm the setup launcher files are tracked by Git so flakes can include them
- confirm `make -n iso` builds the default Cosmic ISO
- confirm `make -n iso-all` builds all five edition ISOs
- confirm `make -n release` runs all edition ISOs, TinyPM package, ANIX package, and metadata steps

## Live Boot

- boot the ISO in a VM with `make qemu-fresh`
- confirm the live boot flow takes over `tty1`
- confirm NetworkManager is running before the network step
- confirm `nmtui` opens from the installer
- confirm Fastfetch shows the Abora logo in the live shell
- confirm the Omarchy-inspired installer welcome screen renders correctly
- confirm the wallpaper pack is present in the live image

## Install Test

- complete one full install onto a blank virtual disk
- confirm the installer's GPU step detects a driver (nouveau/amdgpu/intel/none under QEMU) and lets it be overridden
- confirm installer progress reaches the install phase
- confirm generated config validation runs before `nixos-install`
- confirm install failure screens show `/tmp/abora-install.log`
- remove the ISO or boot with `make qemu-disk`
- confirm the installed system boots without relaunching the live installer
- confirm login and networking work
- on GNOME, confirm Abora wallpapers appear in `Settings -> Appearance`
- confirm the default wallpaper is applied on first login for the chosen desktop
- confirm `abora setup` opens the installed reconfiguration launcher
- confirm `abora config` shows the installed GPU driver and `abora config set gpu <value>` updates it

## Release Gate

- if tagging from GitHub, review the draft release created by the workflow
- if install test passes, publish all edition ISOs, checksums, manifest, release notes, TinyPM package, and ANIX package
- if install test fails, do not publish; fix the blocker first
