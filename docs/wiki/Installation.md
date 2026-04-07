# Installation

This page covers the normal Abora OS install flow.

## Build The ISO

From the repo:

```sh
cd /home/animated/abora-os
make iso
```

To boot the newest ISO in QEMU:

```sh
make qemc
```

## Live Boot

When the ISO starts, Abora should take you to the terminal-first boot flow.

From there you can:

- start the installer
- open a live shell
- reboot or power off

## Installer Flow

The installer is interactive.

It begins with:

- a welcome step before any disk action
- a pre-install setup screen for keyboard, desktop, and starter app bundle

You will be asked for:

- install target disk
- hostname
- username
- password
- desktop choice
- any optional install settings exposed by the current release

## After Install

When the installation finishes:

1. remove the ISO
2. reboot the VM or machine
3. boot into the installed system
4. confirm networking works
5. run `sudo nixos update`

## VM Notes

Abora is tested mainly in QEMU first, but Windows-host VM checks also matter.

- VMware and Hyper-V are worth checking on Windows hosts
- if testing Hyper-V Generation 2, disable secure boot first
- if testing VirtualBox, test default graphics settings before changing anything

## Validation

Use the install checklist after a build:

- [Install Checklist](../install-checklist.md)
