# Abora OS v3.0.0 Denali — Overview

This file is an overview of the Abora project covering what each release delivered and where the project stands now.

## Current Version

**v3.0.0 Denali** — the current stable release.

Abora OS is built on top of NixOS. The goal is not to hide NixOS; the goal is to make NixOS feel approachable from the first boot onward.

## What v2 Added

The v2 era moved Abora from a branded NixOS build into something closer to a complete operating-system experience.

### Guided Install Path

The live image focuses on a guided installer instead of dropping users into raw setup work.

The installer owns:

- network setup
- identity and password setup
- desktop choice
- starter app bundle choice
- optional GitHub setup
- disk selection
- final review
- generated config validation
- install progress and logs

### Desktop Coverage

Abora v2 expanded beyond a single desktop target.

The desktop matrix includes GNOME, Plasma, Hyprland, Sway, XFCE, Cinnamon, MATE, Budgie, LXQt, Pantheon, i3, AwesomeWM, Openbox, Niri, River, Qtile, BSPWM, Fluxbox, IceWM, Herbstluftwm, and COSMIC.

`scripts/check-desktops.sh` evaluates these profiles before release so broken profile options are caught early.

### Branding and First Login

Abora v2 brought together:

- bootloader assets
- Plymouth theme
- wallpaper collection
- Fastfetch identity
- dark-first desktop defaults
- GNOME wallpaper/accent sync

### Management Tools

Installed systems include:

- `abora welcome`
- `abora doctor`
- `abora recovery`
- `abora config`
- `abora desktop`
- `abora setup`
- `sudo nixos update`
- ANIX helper commands
- TinyPM-flavored app commands

### Support and Testing

Abora v2 added support-report and hardware-readiness tooling, plus release docs for VM and hardware testing.

## What v2.5 Delivered

v2.5 focused on making installs reliable.

- NetworkManager is forced on in the live installer
- Wi-Fi setup works through `nmtui` and `nmcli`
- installer failures show useful logs
- generated config is validated before `nixos-install`
- bootloader files are checked before claiming success
- wallpaper packaging no longer breaks on changed directories
- GNOME package/config duplication was fixed
- current nixpkgs LightDM and GNOME option paths were fixed
- all desktop profiles evaluate, including Openbox
- `make iso` only builds the ISO
- `make release` builds ISO, TinyPM package, and metadata
- QEMU helpers support fresh install disks, disk-only boot, and serial mode
- setup launcher assets are copied into both the live ISO and installed config tree

## What v3 Denali Delivered

v3 Denali is the identity, installer, and tooling release.

- Omarchy-inspired TUI installer with compact boxed fields and live install progress
- large Abora wordmark in the installer header
- install validation before long builds
- post-install `abora setup` reconfiguration
- ANIX v1 profile manager shipped: snapshots, diff/test/boot/switch/rollback workflows, doctor repair, NixOS module options
- TinyPM v4 shipped: first-class Abora/ANIX/NixOS awareness, source reporting, repair shortcuts
- COSMIC desktop added to the supported matrix
- Abora branding across boot, desktop, and fastfetch
- Limine as the installed-system bootloader with Abora branding

## Build and Release Commands

```sh
make iso
make qemu-fresh
make qemu-disk
make release
make metadata
make tinypm-package
```

`make iso` is for fast ISO iteration. `make release` is for the full release bundle.

## Testing State

In good shape:

- ISO build
- script checks (`make check`)
- desktop profile evaluation (`make check-desktops`)
- QEMU fresh/disk boot helpers
- installer config validation
- support report tooling
- hardware-readiness preflight testing

Still needs wider coverage:

- more bare-metal Wi-Fi laptops
- more BIOS systems
- more NVIDIA systems
- more Windows-host VM checks
- longer post-install update and rollback testing

## Docs

Core docs:

- `README.md`
- `RELEASE_NOTES.md`
- `docs/roadmap.md`
- `docs/install-checklist.md`
- `docs/hardware-testing.md`
- `docs/release-checklist.md`
- `docs/project-layout.md`

Wiki docs:

- `docs/wiki/Home.md`
- `docs/wiki/Installation.md`
- `docs/wiki/Updating-Abora.md`
- `docs/wiki/Building-Abora.md`
- `docs/wiki/Release-Guide.md`
- `docs/wiki/Abora-Tools.md`
- `docs/wiki/Recovery.md`
- `docs/wiki/TinyPM-V4.md`
- `docs/wiki/ANIX-V1.md`
- `docs/wiki/FAQ.md`
