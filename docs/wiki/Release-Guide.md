# Release Guide

This page covers the normal Abora release flow.

## Local Release Build

```sh
cd /home/animated/abora-os
make release
```

## What To Publish

The normal release bundle includes:

- `abora-<date>-x86_64-<version>.iso`
- `SHA256SUMS-<version>.txt`
- `RELEASE_MANIFEST-<version>.txt`
- `RELEASE_NOTES-<version>.md`

## Tagging A Release

```sh
git tag v2.0.0-dev
git push origin v2.0.0-dev
```

That triggers the GitHub release workflow for the tagged version.

## Before Publishing

Make sure these checks are done:

- the ISO builds successfully
- the live image boots
- the installer completes one real install
- the installed system boots without the ISO attached
- `sudo nixos update` works on the installed system

More detailed lists:

- [Install Checklist](../install-checklist.md)
- [Release Checklist](../release-checklist.md)
