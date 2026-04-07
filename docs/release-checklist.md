# Abora Release Checklist

Use this after the GitHub ISO workflow succeeds or after a local release build.

## Build output

- download the ISO artifact
- verify the checksum in `SHA256SUMS-<version>.txt`
- confirm `RELEASE_MANIFEST-<version>.txt` matches the published ISO
- confirm the artifact name and ISO filename match the intended release

## Live boot

- boot the ISO in a VM
- confirm the boot menu launches on `tty1`
- confirm Fastfetch shows the Abora ASCII logo
- confirm the installer launches from the boot menu
- confirm the installer welcome and pre-install setup screens render correctly
- confirm the hardware summary and support report actions work
- confirm the wallpaper pack is present in the live image

## Install test

- complete one full install onto a blank virtual disk
- remove the ISO and reboot the installed system
- confirm login prompt and networking work
- run `./scripts/check-desktops.sh` on the repo before tagging
- review `docs/hardware-testing.md` before moving to bare-metal tests
- on GNOME, confirm Abora wallpapers appear in `Settings -> Appearance`
- confirm the default wallpaper is applied on first login for the chosen desktop
## Release gate

- if tagging from GitHub, review the draft release created by the workflow
- if install test passes, publish ISO + checksums + manifest + release notes
- if install test fails, do not publish; fix blocker first
