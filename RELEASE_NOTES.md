# Abora OS 0.1.0

## Summary

Abora OS 0.1.0 is the first release track of the distro scaffold.

It currently provides:

- an Arch-based live ISO
- KDE Plasma live environment defaults
- a GUI-first Abora installer launcher targeting Calamares
- Abora defaults and first-boot helper tooling

## Included highlights

- Abora-branded wallpaper and Plasma defaults
- `Install Abora OS` desktop launcher
- graphical installer entry flow through KDialog
- `abora-doctor` for early validation
- GitHub Actions ISO builds with checksum output

## Known limitations

- Calamares integration is newly packaged and still needs a real boot/install validation pass
- installed-system behavior still needs one full end-to-end validation pass
- package selection is intentionally lean for the first release
- Abora local packages are currently built into the ISO process rather than hosted in a public package repository

## Recommended release validation

Before calling 0.1.0 usable, confirm:

1. live boot works
2. installer completes successfully
3. installed system reboots into Plasma
4. `abora-doctor --report` looks clean on the installed system
