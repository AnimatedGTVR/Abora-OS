# Installation

This page covers the normal Abora OS install flow for v2.5+ and v3 Denali.

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
- open the Denali installer
- allow Wi-Fi setup through `nmtui` or `nmcli`
- provide a fallback live shell if the installer exits

## Installer Flow

The installer is interactive and keyboard-first.

The current flow includes:

- network setup
- hostname, username, timezone, keyboard, and password setup
- desktop profile selection
- starter app bundle selection
- ANIX and GitHub options
- disk selection
- final review
- generated-config validation before `nixos-install`
- install progress and clear logs

## After Install

When installation finishes:

1. reboot or power off from the installer
2. remove the ISO or boot the VM with `make qemu-disk`
3. boot into the installed system
4. confirm networking works
5. run `abora doctor`
6. run `anix quickstart`
7. run `tinypm sources`
8. run `sudo nixos update` when ready to test updates

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
