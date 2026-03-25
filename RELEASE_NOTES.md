# Abora OS v1.0.0

## Summary

Abora OS v1.0.0 is the first full Abora release built on a NixOS base.

## Highlights

- terminal-first live boot flow and installer
- on-demand Abora Welcome and Abora Center app session from the live boot
- branded bootloader, wallpapers, and Abora live assets
- Nix flake based ISO build pipeline (`flake.nix`)
- NixOS live image profile under `nix/profiles/live.nix`
- simplified ISO build scripts targeting Nix
- GitHub Actions updated to build via Nix

## Release assets

- `abora-<date>-x86_64-v1.0.0.iso`
- `SHA256SUMS-v1.0.0.txt`
- `RELEASE_MANIFEST-v1.0.0.txt`

## Known limitations

- wider bare-metal validation is still recommended after VM testing
- TinyPM V3 remains a separate Abora tool and is not part of the `v1.0.0` NixOS boot or installer path

## Validation focus

1. live ISO boots consistently
2. installer completes and bootable system is produced
3. release checksum artifact matches published ISO
