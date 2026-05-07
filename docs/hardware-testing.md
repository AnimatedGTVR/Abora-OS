# Abora Hardware Testing

Use this when moving from VM testing to real machines.

## Before You Start

- rebuild the ISO locally with `make iso`
- verify the current checksum
- write the ISO to known-good USB media
- keep a second machine or phone nearby for notes, GitHub device login, and recovery searches
- run `abora-hardware-test --with-report` on the machine first when possible

## Quick Preflight

Before you spend time writing a USB, run:

```sh
abora-hardware-test --with-report
```

or from the repo:

```sh
./scripts/abora-hardware-test.sh --with-report
```

This does not replace a real Abora boot, but it does catch obvious problems:

- whether the machine is real hardware or still a VM
- whether UEFI is available
- whether internal install disks are visible
- whether graphics, Ethernet, Wi-Fi, Bluetooth, and audio hardware show up
- whether Abora's support-report tooling works on that machine

## Machines To Cover

- UEFI desktop
- UEFI laptop
- older BIOS system if available
- NVMe storage
- SATA SSD or HDD
- Intel graphics
- AMD graphics
- NVIDIA graphics if available
- Wi-Fi laptop
- Bluetooth laptop

## Live Boot Checks

- system boots from USB without manual kernel edits
- boot menu appears correctly
- installer opens correctly
- hardware summary looks sane
- `abora-support-report` creates a report archive
- internal disks are detected correctly
- USB install media is not confused with the target disk
- Ethernet works if connected
- Wi-Fi hardware appears in `ip -br link` or `iw dev`
- keyboard and touchpad work
- display brightness works on laptops
- audio devices appear
- `abora-hardware-test --with-report` completes from the live session
- `abora-support-report` includes hardware, boot, network, and Abora version details

## Installer Checks

- names step works
- password step works
- optional GitHub device login can be skipped cleanly
- device login works from another device if tested
- extra packages/setup step shows the right disk, desktop, and bundle
- support report can be saved from inside the installer
- install completes without fatal errors
- failure screen shows recent logs and support report path if something breaks
- generated `/mnt/etc/nixos/abora-local.nix` uses the v2.5 `abora.*` option format
- generated flake imports `abora-options.nix`, `anix-module.nix`, and `abora-local.nix`

## First Boot Checks

- installed system boots without the USB attached
- Limine boots cleanly
- login works
- first interactive shell shows the one-time `abora-welcome status`
- networking works
- Flathub is configured after first boot
- `abora welcome` opens the first-step quick actions
- `abora doctor` reports Abora health
- `abora recovery` opens rollback, rebuild, repair, and report actions
- `abora desktop list` shows supported desktop profiles
- `abora config` shows hostname, timezone, keyboard, desktop, wallpaper, user, disk, and state version
- `abora config set hostname <test-name>` updates `abora-local.nix`
- `abora config set desktop <profile>` validates known desktop profiles
- `abora config set wallpaper <name>` validates shipped wallpaper names
- `sudo nixos update` works
- rollback works if an update is tested
- default wallpaper is applied
- dark mode defaults are applied for the chosen desktop
- GNOME wallpaper switching still updates accent/style on Abora wallpapers

## ANIX v1 Checks

- `anix show` handles a missing config with a clear `anix init` prompt
- `anix init` creates `/etc/nixos/anix.nix` seeded from the installed Abora config
- `anix switch nix <profile>` dry-builds a named flake config before switching
- `anix switch nix stable`, `minimal`, `gaming`, `creator`, and `developer` resolve to flake outputs
- `anix rollback nix` uses the previous NixOS generation
- `anix rollback nix <profile>` dry-builds a named flake config before switching back
- `anix save` creates a local Git snapshot of `/etc/nixos`
- `anix save` warns when possible secrets are present in config files
- `anix config set snapshots.push true` is opt-in and does not push by default
- `anix doctor` reports flake, Git, generation, and ANIX config health
- `anix set hostname <test-name>` updates `anix.hostname`
- `anix set timezone <zone>` updates `anix.timezone`
- `anix set keyboard <layout>` updates the console keyboard
- `anix set keyboard.xkb <layout>` updates the graphical keyboard
- `anix wallpapers` lists the shipped wallpaper filenames
- `anix set wallpaper <name>` validates shipped wallpaper names
- `anix set desktop none` is accepted for a console-only test
- `anix apply` rebuilds the normal Abora flake target

## Laptop Checks

- suspend and resume
- lid close/open behavior
- battery reporting
- brightness keys
- audio output and microphone
- Wi-Fi reconnect after resume
- Bluetooth pairing

## Bug Report

If something goes wrong, collect:

```sh
abora-support-report
journalctl -b --no-pager
```

If the installer failed, also keep:

- `/tmp/abora-generate-config.log`
- `/tmp/abora-install.log`

Attach the generated `abora-support-*.tar.gz` archive to your report when possible.
