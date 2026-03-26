# Abora OS Roadmap

## v1.0.1 Delivered

- NixOS-based live ISO baseline
- live and installer configs moved to the 26.05 state version baseline
- reproducible flake-based builds
- branded live boot and installer flow
- optional ecosystem tooling can land after `v1.0.1` when NixOS package mapping is ready

## Post-v1 Focus

- validate installer success across more BIOS and UEFI targets
- add automated VM smoke tests after ISO build
- improve installed-system polish after first boot

## Longer Term

- split Abora functionality into reusable NixOS modules
- add release-channel strategy and binary cache direction
- optimize CI build time and artifact publishing

## Release direction

- keep GitHub releases as the primary public ISO distribution path
- attach ISO, checksums, manifest, and release notes to each tagged release
