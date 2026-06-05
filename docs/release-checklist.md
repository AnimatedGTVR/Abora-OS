# Abora Release Checklist

Use this after a local release build or after the GitHub ISO workflow succeeds.

## Build Output

- run `make iso` for ISO-only validation
- run `make release` only when preparing the full release bundle
- verify the ISO exists in `out/iso/`
- verify the checksum in `out/release/SHA256SUMS-<version>.txt`
- confirm `out/release/RELEASE_MANIFEST-<version>.txt` matches the published ISO and TinyPM package
- confirm the artifact name and ISO filename match the intended version

## Repository Checks

- run `./scripts/check-scripts.sh`
- run `./scripts/check-desktops.sh`
- confirm the setup launcher files are tracked by Git so flakes can include them
- confirm `make -n iso` only runs `./scripts/build-iso.sh`
- confirm `make -n release` runs ISO, TinyPM package, and metadata steps

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
- confirm installer progress reaches the install phase
- confirm generated config validation runs before `nixos-install`
- confirm install failure screens show `/tmp/abora-install.log`
- remove the ISO or boot with `make qemu-disk`
- confirm the installed system boots without relaunching the live installer
- confirm login and networking work
- on GNOME, confirm Abora wallpapers appear in `Settings -> Appearance`
- confirm the default wallpaper is applied on first login for the chosen desktop
- confirm `abora setup` opens the installed reconfiguration launcher

## Release Gate

- if tagging from GitHub, review the draft release created by the workflow
- if install test passes, publish ISO, checksums, manifest, release notes, and TinyPM package
- if install test fails, do not publish; fix the blocker first
