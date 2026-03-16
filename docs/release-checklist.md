# Abora 0.1.0 Release Checklist

Use this after the GitHub ISO workflow succeeds.

## Build output

- download the ISO artifact
- verify the checksum in `SHA256SUMS-<version>.txt`
- confirm the artifact name and ISO name match the intended release

## Live boot

- boot the ISO in a VM
- confirm it reaches Plasma
- confirm `Install Abora OS` appears on the desktop
- run `abora-doctor`

## Install test

- launch `Install Abora OS`
- complete one full install onto a blank virtual disk
- remove the ISO and reboot the installed system
- confirm Plasma, SDDM, networking, and wallpaper all work

## Release gate

- if the install test passes, publish the ISO, checksum file, and `RELEASE_NOTES.md`
- if the install test fails, do not publish 0.1.0; fix the blocker first
