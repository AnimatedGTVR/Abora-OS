# Abora OS v3.0.0 Denali

Abora OS v3.0.0 is the Denali release: a reliability, installer, hardware, and identity pass that turns the v2 base into a more complete Abora experience.

The focus for this release is simple: the installer should work, the installed system should boot, the terminal and desktop should look like Abora, and the release artifacts should be easy to publish.

---

## Highlights

### Remade Denali Installer

The installer has been rebuilt around a calmer terminal UI with bounded log output, clearer status messages, and safer failure handling.

- recent logs are kept compact so they do not run off screen
- long installs expose the current step and log path
- failed installs drop to a live shell with `/tmp/abora-install.log`
- config validation runs before `nixos-install`
- install completion verifies the system profile before declaring success
- the boot guard now detects an installed disk and guides users to boot it instead of relaunching the ISO

### Hardware Comes Up In The Live ISO

The live installer now enables the services and firmware users expect before install:

- NetworkManager
- Bluetooth and Blueman
- ModemManager
- redistributable and unfree firmware
- Intel and AMD microcode
- common Wi-Fi, Ethernet, Bluetooth, storage, and VM driver modules
- radio unblock at boot

### Abora OS 3.0 Branding

The installed system now reports itself as:

```text
Abora OS 3.0 (Denali)
```

This updates visible OS release metadata, issue text, installer copy, and the welcome surfaces that previously exposed NixOS/Yarara branding.

### Desktop And Terminal Polish

Denali adds the first pass of the Abora desktop identity:

- day/night mountain wallpapers
- dark-mode wallpaper pairing
- Papirus dark icon defaults
- larger app-grid icon sizing
- Konsole as the preferred terminal
- zsh with Spaceship prompt
- fastfetch with the Abora logo
- first-run zsh setup suppression so users do not see the zsh wizard

### Release Folder Cleanup

Generated files now land in a cleaner `out/` layout:

- `out/iso/`
- `out/packages/`
- `out/release/`
- `out/qemu/`
- `out/logs/`
- `out/nix/`

Release scripts, QEMU helpers, package generation, and metadata generation were updated for that layout.

### TinyPM v4 And ANIX v1

TinyPM remains vendored and packaged with the release. The v4 bundle includes the Abora-flavored TinyPM package, portable relative `vendor/tinypm/bin/` symlinks instead of machine-local absolute symlinks, package source reporting, repair shortcuts, and Abora/ANIX bridges.

ANIX is now shaped as a v1 profile manager with status, quickstart, docs, profile discovery, generation listing, diff/test/boot/switch/rollback workflows, local snapshots, doctor repair, and NixOS module options for packages, trusted users, store optimisation, and scheduled garbage collection.

---

## Release Assets

- `abora-2026.05.30-x86_64-v3.0.0.iso`
- `tinypm-v4.0.0-abora-v3.0.0.tar.gz`
- `SHA256SUMS-v3.0.0.txt`
- `RELEASE_MANIFEST-v3.0.0.txt`
- `RELEASE_NOTES-v3.0.0.md`

---

## Upgrade Notes

Existing Abora installs can try:

```sh
sudo nixos update
```

For the cleanest v3 Denali experience, especially from older installer builds, a fresh install is recommended.

After install in QEMU, boot the installed disk with:

```sh
make qemu-disk
```

For a clean installer test, use:

```sh
make qemu-fresh
```

---

## Known Limits

- The ISO is larger than earlier v2 builds because it now includes broader firmware and hardware support.
- Hardware support still depends on Linux kernel support for the exact device.
- Flatpak and app installs need network after first boot.
- Manual removal of the ISO may still be required on some VM setups if virtual media eject is blocked.

---

## Validation

Completed for this release:

- `./scripts/preflight.sh`
- `vendor/tinypm/scripts/e2e-smoke.sh`
- fresh ISO build for `2026.05.30`
- v4 TinyPM package generation
- v3 release manifest, release notes, and checksums

Before publishing broadly, still do one real boot/install smoke test in the target VM or hardware environment.
