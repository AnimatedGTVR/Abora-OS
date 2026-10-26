# Installation

This page covers the normal Abora OS install flow for v2.5+ through Abora OS v4.2 Solstice.

Horizon can optionally install the Abora Labs workspace manager. Leave it off
for a normal product installation. Enabling it does not download Labs during
the install; after first boot, `abora labs install` requires an explicit `LABS`
confirmation before cloning the experimental workspace.

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
- open the installer (see below)
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

Abora has one installer: a terminal UI (`abora-installer.sh`, menus drawn with
[gum](https://github.com/charmbracelet/gum)). The live ISO starts it on `tty1`; from a live shell, run
`abora-install`. The live ISO is an installer only: desktop editions set which desktop gets installed, and
there's no live desktop session.

Menus have a **Back** entry where a choice can be changed, and nothing is written to disk before the final review.

The current flow includes:

- network setup
- hostname, username, keyboard, and password setup
- timezone: typed, with suggestions (see [Typing a timezone](#typing-a-timezone))
- desktop profile selection
- starter app bundle selection
- optional dotfiles import for Hyprland and Other Environment installs
- ANIX and GitHub options
- disk selection
- final review
- generated-config validation before `nixos-install`
- install progress and clear logs

For scripted installs, pass `--batch`; to reconfigure an installed system, `--reconfig` (or `-r`):

```sh
abora-install --batch
```

### Installing your own NixOS flake

After network setup the installer asks what to install: **Abora OS**, or **My own NixOS flake**. The second
installs your NixOS configuration instead of Abora's. Abora still handles the disk, the hardware and the
password; your configuration decides everything else (desktop, packages, users, bootloader).

1. Enter the flake, for example `github:you/nixos-config#laptop`. GitHub, GitLab, SourceHut, `git+https://`,
   `git+ssh://` and `https://` work. The part after `#` names the `nixosConfigurations` entry; leave it out
   to pick from a list. Local paths are refused because the installed system couldn't find them again, so
   push the flake somewhere first. For a private repository, set up a key from **Open terminal**, then use `git+ssh://`.
2. The installer evaluates the configuration **before touching any disk** and refuses it if:
   - it isn't `x86_64-linux`
   - it enables no bootloader
   - its bootloader doesn't match how this machine boots (systemd-boot on a BIOS machine, or BIOS-only GRUB on a UEFI one)
   - it needs a BIOS-boot partition the chosen disk mode won't create

   It warns about other mounts, such as `/home` on a disk that isn't in this machine, because boot would stop in
   emergency mode waiting for them. Fix and push the configuration, then choose **Check again**.
3. Choose the disk as usual (erase or dual-boot), and a password. Users your configuration leaves without a
   password get this one. Users that already have one keep it.

The installed `/etc/nixos/flake.nix` is a small wrapper. It takes your configuration as the input `config` and
adds `abora-machine.nix`, which imports `hardware-configuration.nix` and sets `/` and `/boot` to the partitions
the installer created. Rebuild with `sudo nixos-rebuild switch --flake /etc/nixos#abora`. To pick up new commits
of your configuration, run `sudo nix flake update config --flake /etc/nixos` first. To rebuild from your own repo
instead, copy `abora-machine.nix` and `hardware-configuration.nix` into it and import `abora-machine.nix` from
that host, or the machine won't find its disks (see `/etc/nixos/README-abora.md`).

Abora's own tools (`abora`, `anix`, updates) are not part of such an install unless your configuration imports them.

Batch installs set `config_source=flake`, `flake_url` and `flake_host` in the params file.

### Typing a timezone

The installer asks for the timezone as text. It accepts
`UTC`, or an IANA `Region/City` name such as `Europe/Berlin`, `America/New_York` or `Asia/Tokyo`, in any
capitalization. The common US abbreviations (`EST`, `PST`, `Eastern`, ...) work too. A city on its own, such
as `Berlin` or `new york`, lists the matching names to choose from instead of being rejected.

## If The Install Fails

The installer stops, says why in plain language ("Likely cause"), and shows a **What failed** block with
the exact failing build, the path whose hash didn't match, and the expected and actual hashes. The same
lines, plus the build log of the failed package (`nix log`), go into `/tmp/abora-install.log`.

`/tmp` is lost when the live system reboots, so keep the log first:

- **Save logs to a USB drive** in the failure menu copies the install log, the config log and a redacted
  support report onto any FAT, exFAT, NTFS or ext4 USB stick (not the Abora install stick itself).
- If the target disk was already mounted, a copy is also written to its root as
  `abora-install-failed-<date>.log`.
- From the live shell: `abora support-report --output-dir /path/to/usb`.

A hash mismatch can mean three different things, and the "Likely cause" line says which:

| What the log says | What it usually means | What to do |
| --- | --- | --- |
| `hash mismatch importing path`, `NAR hash mismatch in input 'path:/nix/store/...'`, `is corrupt` | a package copied from the USB stick (or the cache) was damaged | check the ISO against `SHA256SUMS`, write the USB stick again or use another, run a memory test |
| `hash mismatch in fixed-output derivation`, or a `github:` input | a pinned download changed upstream, or something on the network altered it | try again on another network; report it with the log if it repeats |
| `NAR hash mismatch in input path:/mnt/etc/nixos` | an installer bug | report it with the log |

## Existing NixOS Systems

If you already run NixOS and want Abora without wiping the machine, use the
adoption path instead of the ISO installer. It keeps `/home`, users, existing
packages, and your current desktop config, then imports Abora modules with
`desktop = "none"` by default.

The easiest way to start it is a single command — it clones the repo (or
updates an existing checkout) and hands off to the real wizard, which asks
a couple of questions and shows the exact plan before touching anything:

```sh
curl -sSL https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/scripts/abora-adopt-bootstrap.sh | bash
```

That's equivalent to cloning yourself and running the wizard directly:

```sh
git clone https://github.com/Abora-OS/Abora-OS.git
cd Abora-OS
./abora adopt-nixos
```

Either way, the wizard asks for a desktop profile (blank keeps your current
one) and whether to enable Abora Gaming, shows the plan, and only writes
anything after you confirm — re-running with `sudo` itself, if needed, once
you say yes. Prefer scripting it instead? Every wizard question has a flag:

```sh
sudo ./abora adopt-nixos --apply --desktop gnome --gaming
sudo nixos-rebuild test
sudo nixos-rebuild switch
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
7. run `anix package list`
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
anix package list
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
