# Installation

> Back up important files before changing partitions. Edge and pre-release images are intended for testing.

## Install from an ISO

1. Download the correct ISO from [GitHub Releases](https://github.com/AnimatedGTVR/Abora-OS/releases).
2. Verify its SHA-256 checksum.
3. Write it to a USB drive with a trusted image-writing tool.
4. Boot the USB in UEFI mode.
5. Follow the installer and carefully confirm the target disk, partition mode, user, timezone, desktop, and GPU choice.
6. Remove the USB after installation and boot the installed system.

The main editions are COSMIC, GNOME, KDE Plasma, Hyprland, and Other Desktops. The installer can also be started in its older batch mode:

```sh
abora-install --batch
```

## Existing NixOS Systems

Use the adoption wizard when you want Abora tooling without erasing an existing NixOS installation:

```sh
git clone --branch edge https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
./abora adopt-nixos
```

Review the plan before applying it. The tool backs up the existing configuration under `/etc/nixos/abora-backups/`.

## First boot

```sh
abora doctor
anix status
tinypm providers
sudo abora update
```

If installation fails, keep `/tmp/abora-install.log` and `/tmp/abora-config.log`, then follow the [bug report template](../bug-report-template.md).
