# Installation

This page covers the normal Abora OS install flow for v2.5+ through Abora OS v4 Everest.

## Build The ISO

From the repo:

```sh
make iso
```

To boot the newest ISO in QEMU:

```sh
make qemu-fresh
```

## Live Boot

When the ISO starts, Abora should take over `tty1` and launch the live boot flow.

The live image should:

- start NetworkManager
- open the guided installer (MINT, see below)
- allow Wi-Fi setup through `nmtui` or `nmcli`
- provide a fallback live shell if the installer exits

### Getting a shell for diagnostics

`tty1` is owned directly by the installer process and never asks for a
login. If you need a shell (to run `dmesg`, `nmcli`, or `abora support-report`
before or during install), don't switch to another console — pick **Open
terminal** from the installer's first screen. It drops straight to a root
prompt on the same screen; run `abora-install` when you're ready to relaunch
the installer and continue where you left off.

The first screen also has **Debug installer**, which can tail
`/tmp/abora-install.log`, tail `/tmp/abora-config.log`, run
`abora hardware-test --with-report`, open `nmtui`, or create a redacted
`abora support-report` archive before any disk is touched.

Advanced users who want to compile Abora themselves can open **Build from
source** for the clone/check/build commands (`make doctor`, `make iso`, and
`make iso-all`) and then jump into a terminal.

If you are compiling from a GitHub checkout manually, the current short build
target is:

```sh
nix build .#nixosConfigurations.abora.config.system.build.toplevel
```

Older checkouts may only expose the live Cosmic target:

```sh
nix build .#nixosConfigurations.abora-live-cosmic.config.system.build.toplevel
```

If you do switch to another console (`tty2`–`tty6`), it's a normal login
prompt. Two accounts exist for exactly that case:

- `aboraos` — blank password (just press Enter)
- `root` — password `linux`, as a fallback if a blank password is rejected

## Installer Flow

The default guided installer is **MINT** (`mint abora install`), a small Go/Bubble Tea front-end that walks through every step and then hands the confirmed plan to the existing bash installer (`abora-installer.sh`) as its backend — the bash installer never went away, it's just the execution layer now instead of the thing you interact with directly. Run it manually with:

```sh
mint abora install --tty --pre-alpha
```

The flow is a step-by-step wizard, not a single linear pass — every screen (edition, hostname, timezone, disk layout, and so on) can be backed out of with `Esc` or the `← Back` list entry, re-showing the previous screen with whatever you already typed still filled in. Screens show a "Step X of Y" indicator so it's clear how far along you are.

The current flow includes:

- network setup
- hostname, username, keyboard, and password setup
- timezone selection: pick a region first (Americas, Europe, Africa, Asia, Australia & Oceania, or UTC), then search the real IANA timezones within it — states/regions with more than one zone (Indiana's eight, for example) all show up individually
- desktop profile selection
- starter app bundle selection
- optional dotfiles import for Hyprland and Other Environment installs
- ANIX and GitHub options
- disk selection
- final review
- generated-config validation before `nixos-install`
- install progress and clear logs

Prefer the older bash-only flow instead of MINT? Pass `--batch` (or `--reconfig`/`-r`) to the installer launcher:

```sh
abora-install --batch
```

Or run the bash installer directly, bypassing the MINT/backend choice entirely:

```sh
abora-installer
```

## Existing NixOS Systems

If you already run NixOS and want Abora without wiping the machine, use the
adoption path instead of the ISO installer. It keeps `/home`, users, existing
packages, and your current desktop config, then imports Abora modules with
`desktop = "none"` by default.

```sh
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
./abora adopt-nixos
sudo ./abora adopt-nixos --apply
sudo nixos-rebuild test
sudo nixos-rebuild switch
```

To opt into an Abora desktop profile during adoption:

```sh
sudo ./abora adopt-nixos --apply --desktop gnome
```

The command writes a backup under `/etc/nixos/abora-backups/` before changing
anything.

## After Install

When installation finishes:

1. reboot or power off from the installer
2. remove the ISO or boot the VM with `make qemu-disk`
3. boot into the installed system
4. confirm networking works
5. run `abora doctor`
6. run `anix quickstart`
7. run `tinypm sources`
8. run `sudo abora update` when ready to test updates

The installed system is intentionally lean. Extra diagnostics, VM guest agents,
and mobile broadband support are available through `abora config`, but are not
forced onto every machine.

## First Installed Commands

Use these after the first boot:

```sh
abora doctor
anix status
anix doctor
anix --gui
tinypm system
tinypm sources
```

For tiling desktop installs, you can import dotfiles again or test a local
dotfiles folder with:

```sh
abora dotfiles --dry-run ~/dotfiles
abora dotfiles ~/dotfiles
```

If ANIX basics are missing:

```sh
anix doctor --fix
```

## VM Notes

- `make qemu-fresh` deletes the old QEMU disk and starts a clean install test.
- `make qemu-disk` boots only the installed virtual hard drive.
- VMware and Hyper-V are worth checking on Windows hosts.
- If testing Hyper-V Generation 2, disable secure boot first.
- If testing VirtualBox, test default graphics settings before changing anything.

## Validation

Use the install checklist after a build:

- [Install Checklist](../install-checklist.md)

For recovery after install:

- [Recovery](Recovery.md)
