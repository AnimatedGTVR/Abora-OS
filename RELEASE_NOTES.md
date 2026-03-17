# Abora OS 0.2.0

## Summary

Abora OS 0.2.0 migrates the distro base from Arch to NixOS.

## Highlights

- Nix flake based ISO build pipeline (`flake.nix`)
- NixOS live image profile under `nix/profiles/live.nix`
- pre-desktop extension prompt module (`nix/modules/live-extensions.nix`)
- simplified ISO build scripts targeting Nix
- GitHub Actions updated to build via Nix

## Known limitations

- TinyPM extension install path depends on network availability and source compatibility
- installer behavior should still be validated end-to-end on multiple VM targets

## Validation focus

1. live ISO boots consistently
2. pre-desktop extension prompt behaves correctly (install/skip/timeout)
3. installer completes and bootable system is produced
4. release checksum artifact matches published ISO
