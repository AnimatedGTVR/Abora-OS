# Release Guide

This page covers the normal Abora release flow.

## Local ISO Build

```sh
make iso
```

Use this for fast installer and live-image iteration.

## Local Release Build

```sh
make release
```

Use this when preparing a full release bundle.

## What To Publish

The normal release bundle includes:

- `abora-<date>-x86_64-<version>.iso`
- `tinypm-*-abora-<version>.tar.gz`
- `SHA256SUMS-<version>.txt`
- `RELEASE_MANIFEST-<version>.txt`
- `RELEASE_NOTES-<version>.md`

## Tagging A Release

For the current DENALI 3.1.4 line:

```sh
git tag 3.1.4
git push origin 3.1.4
```

That triggers the GitHub release workflow for the tagged version.

## Before Publishing

Make sure these checks are done:

- `./scripts/check-scripts.sh`
- `./scripts/check-desktops.sh`
- the ISO builds successfully
- the live image boots
- the installer completes one real install
- the installed system boots without the ISO attached
- `abora doctor` works on the installed system
- `sudo nixos update` works on the installed system

More detailed lists:

- [Install Checklist](../install-checklist.md)
- [Release Checklist](../release-checklist.md)
