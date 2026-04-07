# Abora OS v2.0.0-dev

## Summary

Abora OS v2.0.0-dev is the active development snapshot for the next big Abora release.
The goal is to push Abora closer to a full desktop OS identity while keeping the NixOS base approachable for normal users.

## Highlights

- terminal-first live boot flow and installer
- installer-first welcome and pre-install setup screens instead of separate helper apps
- hardware summary and support report flow for moving from VM testing to real machines
- curated app management for installed systems with essentials, fan favorites, and developer picks
- curated wallpapers that seed themselves across the supported desktop sessions
- dark-first defaults across the supported desktop session matrix
- GNOME wallpaper/theme matching that auto-updates accent/style for Abora wallpapers
- Limine bootloader path for installed systems
- simple installed-system commands like `sudo nixos update` and `sudo nixos rollback`
- optional GitHub CLI support for repo, dotfiles, and support workflows
- branded bootloader, wallpapers, and Abora live assets
- Nix flake based ISO build pipeline (`flake.nix`)
- NixOS live image profile under `nix/profiles/live.nix`
- simplified ISO build scripts targeting Nix
- GitHub Actions updated to build via Nix
- TinyPM V3 can now be published as a GitHub Packages container through GHCR

## Release assets

- `abora-<date>-x86_64-v2.0.0-dev.iso`
- `SHA256SUMS-v2.0.0-dev.txt`
- `RELEASE_MANIFEST-v2.0.0-dev.txt`

## Known limitations

- wider bare-metal validation is still recommended after VM testing
- TinyPM V3 remains a separate Abora tool and is not part of the `v2` NixOS boot or installer path

## Validation focus

1. live ISO boots consistently
2. installer completes and bootable system is produced
3. supported desktop profiles evaluate cleanly with `./scripts/check-desktops.sh`
4. release checksum artifact matches published ISO
