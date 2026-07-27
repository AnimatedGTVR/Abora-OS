# Release Guide

This page covers the normal Abora release flow.

## Local ISO Build

```sh
make iso
```

Use this for fast installer and live-image iteration on the default Cosmic
edition.

To build every release edition:

```sh
make iso-all
```

This builds:

- Cosmic Edition
- Hyprland Edition
- GNOME Edition
- KDE Plasma Edition
- Other Desktops Edition

## Local Release Build

```sh
make release
```

Use this when preparing a full release bundle. It builds all five edition ISOs,
the TinyPM package, the ANIX package, checksums, manifest, and generated release
notes.

## What To Publish

The normal release bundle includes:

- `abora-cosmic-<date>-x86_64-<version>.iso`
- `abora-hyprland-<date>-x86_64-<version>.iso`
- `abora-gnome-<date>-x86_64-<version>.iso`
- `abora-kde-<date>-x86_64-<version>.iso`
- `abora-other-<date>-x86_64-<version>.iso`
- `tinypm-*-abora-<version>.tar.gz`
- `anix-*-abora-<version>.tar.gz`
- `SHA256SUMS-<version>.txt`
- `RELEASE_MANIFEST-<version>.txt`
- `RELEASE_NOTES-<version>.md`

## Tagging A Release

For the current Abora OS 2026.7.27 line:

```sh
git tag 4.0
git push origin 4.0
```

That triggers the GitHub release workflow for the tagged version.

## Before Publishing

Make sure these checks are done:

- `./scripts/check-scripts.sh`
- `./scripts/check-desktops.sh`
- every edition ISO builds successfully
- at least the default Cosmic live image boots
- the installer completes one real install
- the installed system boots without the ISO attached
- `abora doctor` works on the installed system
- `sudo abora update` works on the installed system

More detailed lists:

- [Install Checklist](../install-checklist.md)
- [Release Checklist](../release-checklist.md)
