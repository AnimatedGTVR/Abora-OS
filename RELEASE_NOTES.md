# Abora OS v1.0.1

## Summary

Abora OS v1.0.1 continues the first stable Abora release line and updates the NixOS baseline from 25.11 to 26.05 for the live image and generated installer config.
The bigger goal for Abora is to make NixOS feel simpler and more approachable for normal users.

## Highlights

- terminal-first live boot flow and installer
- on-demand Abora Welcome and Abora Center app session from the live boot
- simple installed-system update commands like `sudo nixos update` that sync the latest Abora files first
- branded bootloader, wallpapers, and Abora live assets
- Nix flake based ISO build pipeline (`flake.nix`)
- NixOS live image profile under `nix/profiles/live.nix`
- simplified ISO build scripts targeting Nix
- GitHub Actions updated to build via Nix
- TinyPM V3 can now be published as a GitHub Packages container through GHCR

## Release assets

- `abora-<date>-x86_64-v1.0.1.iso`
- `SHA256SUMS-v1.0.1.txt`
- `RELEASE_MANIFEST-v1.0.1.txt`

## Known limitations

- wider bare-metal validation is still recommended after VM testing
- TinyPM V3 remains a separate Abora tool and is not part of the `v1.0.1` NixOS boot or installer path

## Validation focus

1. live ISO boots consistently
2. installer completes and bootable system is produced
3. release checksum artifact matches published ISO
