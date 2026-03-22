# Abora Release Checklist

Use this after the GitHub ISO workflow succeeds.

## Build output

- download the ISO artifact
- verify the checksum in `SHA256SUMS-<version>.txt`
- confirm the artifact name and ISO filename match the intended release

## Live boot

- boot the ISO in a VM
- confirm the boot menu launches on `tty1`
- confirm Fastfetch shows the Abora ASCII logo

## Install test

- complete one full install onto a blank virtual disk
- remove the ISO and reboot the installed system
- confirm login prompt and networking work

## Release gate

- if install test passes, publish ISO + checksums + `RELEASE_NOTES.md`
- if install test fails, do not publish; fix blocker first
