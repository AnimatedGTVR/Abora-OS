# Abora OS

Abora OS is an Arch Linux based distribution project built around KDE Plasma. The current work in this repository is focused on the distro track: an `archiso` profile, package selection, branding, and the path toward a bootable live ISO.

## Repository layout

- `assets/`: branding and visual assets
- `distro/archiso/`: first Abora OS `archiso` profile
- `packages/`: local Arch packages built into the Abora ISO
- `scripts/build-iso.sh`: wrapper around `mkarchiso`
- `scripts/rebuild-vm.sh`: one-command rebuild flow for the Arch build VM
- `docs/roadmap.md`: short-term distro roadmap
- `docs/install-checklist.md`: live/install validation checklist
- `docs/release-checklist.md`: release gate checklist
- `docs/calamares-plan.md`: Calamares installer notes
- `RELEASE_NOTES.md`: current release notes

## Current Abora OS direction

- base distro: Arch Linux
- image builder: `archiso`
- desktop target: KDE Plasma
- display stack: Plasma on Wayland by default
- initial live environment strategy: ship a usable Plasma-based image first
- package policy: keep the default system lean, graphical, and developer-friendly

## What exists now

- an `archiso` profile with Abora branding files
- the standard Calamares package in the live ISO package list
- an `Install Abora OS` launcher that opens Calamares
- an `abora-defaults` package for installed-system branding and first-boot checks
- a local package wrapper for TinyPM that installs into the ISO
- a first-pass Plasma-based package manifest for a live image
- a build script that calls `mkarchiso`
- planning docs for the next distro milestones

## Release version

Current release track:

- `VERSION`: Abora distro version string
- GitHub ISO build uploads the ISO plus `SHA256SUMS-<version>.txt`
- `RELEASE_NOTES.md`: release summary and known limitations

## Build prerequisites

For the ISO:

- Arch Linux host or compatible environment
- `archiso`
- root privileges for `mkarchiso`

## Local commands

Build the ISO:

```sh
./scripts/build-iso.sh
```

In the Arch build VM, use the one-command rebuild helper:

```sh
./scripts/rebuild-vm.sh
```

`rebuild-vm.sh` handles build-disk mount, pacman cache bind-mount, repo update, and ISO build in one run.

No local Arch VM:

Use the GitHub Actions workflow `Build Abora ISO` from the Actions tab. It builds the ISO in an Arch container and uploads `out/*.iso` as a downloadable artifact.

## Release validation

Use [install-checklist.md](/home/animated/.abora/docs/install-checklist.md) before calling a build releasable.
Use [release-checklist.md](/home/animated/.abora/docs/release-checklist.md) before publishing 0.1.0.
