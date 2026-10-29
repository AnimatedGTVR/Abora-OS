# Release Guide

This page covers the normal Abora release flow.

## Local ISO Build

```sh
make iso
```

This builds the one universal Abora installer ISO into `out/iso/`. It has no
editions and no live desktop: the installer asks which desktop to install, so
there is only ever one image to build, boot and test.

## Local Release Build

```sh
make release
```

Use this when preparing a full release bundle. It builds the ISO, the ANIX
package, checksums, manifest, and generated release notes.

## What To Publish

The normal release bundle includes:

- `abora-<date>-x86_64-<version>.iso`
- `anix-*-abora-<version>.tar.gz`
- `SHA256SUMS-<version>.txt`
- `RELEASE_MANIFEST-<version>.txt`
- `RELEASE_NOTES-<version>.md`

## Tagging A Release

For the current Abora OS v4.2 Solstice line:

```sh
git tag v4.2
git push origin v4.2
```

That triggers the GitHub release workflow for the tagged version.

## Before Publishing

Make sure these checks are done:

- `make doctor`
- `./scripts/check-scripts.py`
- `./scripts/check-all-files.py`
- `./scripts/check-desktops.py`
- the ISO builds successfully
- the ISO boots to the installer
- the installer completes one real install, for each desktop you ship (COSMIC, GNOME, KDE Plasma, Hyprland, and so on)
- the installed system boots without the ISO attached
- `abora doctor` works on the installed system
- `sudo abora update` works on the installed system

More detailed lists:

- [Install Checklist](../install-checklist.md)
- [Release Checklist](../release-checklist.md)
