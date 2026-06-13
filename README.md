<p align="center">
  <img src="assets/Github/ReadME%20background.png" alt="Abora OS banner" width="94%">
</p>

<h1 align="center">Abora OS</h1>

<p align="center">
  <strong>A NixOS-based distro with an easier installer, more desktop choices, and a cleaner first setup.</strong>
</p>

<p align="center">
  <a href="https://github.com/AnimatedGTVR/abora-os/releases/latest"><strong>Download</strong></a>
  ·
  <a href="https://www.aboraos.org/"><strong>Website</strong></a>
  ·
  <a href="docs/wiki/Home.md"><strong>Wiki</strong></a>
  ·
  <a href="RELEASE_NOTES.md"><strong>Release Notes</strong></a>
</p>

<p align="center">
  <a href="https://github.com/AnimatedGTVR/abora-os/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/AnimatedGTVR/abora-os?style=for-the-badge" alt="License">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/releases/latest">
    <img src="https://img.shields.io/github/v/release/AnimatedGTVR/abora-os?style=for-the-badge&label=release" alt="Latest release">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/actions/workflows/build-iso.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/AnimatedGTVR/abora-os/build-iso.yml?style=for-the-badge&label=iso%20build" alt="ISO build status">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/graphs/contributors">
    <img src="https://img.shields.io/github/contributors/AnimatedGTVR/abora-os?style=for-the-badge" alt="Contributors">
  </a>
</p>

<p align="center">
  <a href="SECURITY.md">Security</a>
  &nbsp;•&nbsp;
  <a href="docs/roadmap.md">Roadmap</a>
  &nbsp;•&nbsp;
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/v3.0.0-Denali-7cc7ff?style=for-the-badge">
  <img alt="Base" src="https://img.shields.io/badge/base-NixOS-5277C3?style=for-the-badge">
  <img alt="Desktop options" src="https://img.shields.io/badge/desktops-21-8bd5ff?style=for-the-badge">
  <img alt="Flatpak" src="https://img.shields.io/badge/Flatpak-ready-4A90D9?style=for-the-badge">
</p>

---

## Abora OS v3.0.0 — Denali

Abora OS is a NixOS-based distro made for people who want the power of NixOS without fighting the first install.

It keeps the NixOS base, but adds a better live image, a guided installer, desktop choices, app bundles, Abora tools, ANIX profiles, TinyPM, Flatpak support, wallpapers, theming, and boot branding.

Abora is not trying to replace NixOS or hide how it works. The goal is simpler: make the start less rough.

---

## What Abora Changes

NixOS is strong, but the first steps can be rough if you are not already used to flakes, rebuilds, generations, and config files.

Abora tries to make that part easier.

| NixOS can feel like... | Abora adds... |
|---|---|
| A blank live system | A cleaner boot and welcome flow |
| Manual setup right away | A guided terminal installer |
| One main desktop path | 21 desktop/window-manager choices |
| Long rebuild commands | Shorter `abora`, `anix`, and update commands |
| A plain first boot | Wallpapers, themes, apps, and branding |
| Recovery you have to figure out yourself | Snapshots, rollback helpers, and repair tools |

---

## Main Features

<table>
<tr>
<td width="50%" valign="top">

### Installer

- Terminal-first Denali installer
- Keyboard-driven menus
- Welcome screen before disk changes
- Timezone and keyboard detection
- Hostname, user, password, desktop, and app setup
- Optional GitHub CLI login
- Install summary before wiping the disk
- Live `nixos-install` progress
- Config validation before install
- Failure logs when something goes wrong

</td>
<td width="50%" valign="top">

### System

- Full NixOS base
- Reproducible ISO builds with Nix flakes
- Limine bootloader with Abora branding
- Stable and unstable update channels
- `sudo nixos update` and rollback flow
- Flatpak and Flathub enabled by default
- Dark-first desktop defaults
- Abora wallpapers across supported sessions
- GNOME accent and theme matching for Abora wallpapers

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Tools

- `abora config` for safer local changes
- `abora welcome`, `doctor`, `recovery`, and `setup`
- ANIX v1 profile management
- Snapshot, diff, test, boot, switch, and rollback workflows
- TinyPM v4 app/source layer
- Abora, ANIX, and TinyPM bridges
- Optional GitHub helper workflows

</td>
<td width="50%" valign="top">

### Desktop Choice

- 21 desktop environments/window managers
- Full desktop, tiling, Wayland, lightweight, and console-only installs
- Starter app bundles for different setups
- 53 apps in the catalog across 6 categories
- Abora branding across boot, desktop, fastfetch, and recovery tools

</td>
</tr>
</table>

---

## Desktop Environments

Abora v3 includes **21 desktop environments/window managers**, plus a no-desktop install for console-only systems.

| Desktop | Type | Display Manager |
|---|---|---|
| GNOME | Full DE | GDM |
| KDE Plasma | Full DE | SDDM |
| COSMIC | Full DE | COSMIC Greeter |
| XFCE | Full DE | LightDM |
| Cinnamon | Full DE | LightDM |
| MATE | Full DE | LightDM |
| Budgie | Full DE | LightDM |
| LXQt | Lightweight DE | SDDM |
| Pantheon | Full DE | LightDM |
| Hyprland | Wayland compositor | SDDM (Wayland) |
| Sway | Wayland compositor | SDDM (Wayland) |
| Niri | Wayland compositor | SDDM (Wayland) |
| River | Wayland compositor | SDDM (Wayland) |
| i3 | Tiling WM | LightDM |
| AwesomeWM | Tiling WM | LightDM |
| Qtile | Tiling WM | LightDM |
| BSPWM | Tiling WM | LightDM |
| Herbstluftwm | Tiling WM | LightDM |
| Openbox | Floating WM | LightDM |
| Fluxbox | Floating WM | LightDM |
| IceWM | Floating WM | LightDM |
| No desktop | Console-only | TTY |

---

## Quick Start

Build the ISO:

```sh
make iso
```

Boot it in QEMU:

```sh
make qemu-fresh
```

After installing in QEMU, boot the virtual disk without the ISO:

```sh
make qemu-disk
```

---

## Installer Flow

The Denali installer is built around a simple terminal flow. It is still keyboard-first, but it gives you the choices before touching the disk.

```text
Welcome
  └─ Locale
      └─ User setup
          └─ Desktop selection
              └─ Starter apps
                  └─ Optional GitHub CLI
                      └─ Install summary
                          └─ NixOS install
                              └─ Reboot
```

### Navigation

Arrow keys work normally. Number keys can also jump straight to menu items.

```text
1-9    Jump to menu item
↑ ↓    Move selection
Enter  Confirm
Esc    Back/cancel where supported
```

### Disk Layout

Every install creates a GPT layout:

| Partition | Size | Purpose |
|---|---:|---|
| BIOS boot | 1 MiB | Legacy boot support |
| EFI system | 512 MiB | UEFI boot |
| Root | Remaining space | ext4 system root |

---

## Installed System Configuration

After installation, local settings live here:

```text
/etc/nixos/abora-local.nix
```

Example:

```nix
abora.hostname = "my-pc";
abora.timezone = "America/New_York";
abora.desktop  = "gnome";
```

Use `abora config` for common changes without opening the Nix file by hand:

```sh
abora config
abora config set hostname my-pc
abora config set timezone America/New_York
abora config set desktop hyprland
abora config apply
```

> [!NOTE]
> `user` and `disk` are read-only through `abora config` for safety. Edit `abora-local.nix` directly only when you actually mean to change those values.

---

## ANIX v1

ANIX is the human-facing layer for Abora and NixOS.

It gives users shorter commands for profiles, rebuilds, rollbacks, snapshots, wallpapers, desktop changes, and system checks. Underneath that, it still uses the normal NixOS system.

```sh
anix init
anix quickstart
anix --gui
anix status
anix profiles
anix generations
anix show
anix diff nix gaming
anix test nix gaming
anix boot nix gaming
anix switch nix gaming
anix rollback nix
anix rollback nix minimal
anix save
anix doctor
anix doctor --fix
anix set hostname my-pc
anix set wallpaper bluehorizon.png
anix set desktop none
anix wallpapers
anix apply
```

Friendly profile names map to real flake configs. For example:

```sh
anix switch nix gaming
```

is the safer front-end for:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#gaming
```

### Snapshots

Snapshots stay local by default. `anix save` creates a Git commit in the user's `/etc/nixos` config repo, warns about possible secrets, and recommends moving real keys/passwords to `sops-nix` or `agenix`.

Pushing snapshots is opt-in:

```sh
anix config set snapshots.push true
```

---

## TinyPM v4

TinyPM is the app/package layer used by Abora.

On Abora and other NixOS-family systems, TinyPM prefers Nix. It can still work with Flatpak, Snap, and common native package managers where supported.

```sh
grab firefox
tinypm sources
tinypm system
tinypm repair
tinypm anix status
tinypm abora doctor
```

TinyPM v4 is mainly for:

- Simple app installs
- Checking package sources
- Repairing broken sources
- Showing Abora and ANIX package status
- Making package management less annoying for new users

---

## Abora Commands

Abora includes a small command layer for first boot, recovery, desktop switching, and maintenance.

```sh
abora welcome          # first-step status and quick actions
abora doctor           # check Flatpak, themes, boot assets, updates, ANIX
abora recovery         # rollback, rebuild, repair Flathub, collect reports
abora setup            # installed reconfiguration launcher
abora desktop list     # list desktop profiles
abora desktop set gnome
anix status            # profile, generation, and snapshot state
tinypm sources         # package source status
make preflight         # maintainer release checks
```

Fresh installs expose named flake profiles for ANIX:

```sh
anix switch nix stable
anix switch nix minimal
anix switch nix gaming
anix switch nix creator
anix switch nix developer
```

Before updating, Abora can create a local ANIX snapshot so there is a recovery point before the system changes.

---

## Update Channels

Installed systems can follow either the tagged release line or the main branch.

| Channel | Purpose |
|---|---|
| `stable` | Latest tagged Abora release |
| `unstable` | Main branch / newest changes |

```sh
nixos channel
nixos channel list
nixos channel set stable
nixos channel set unstable
```

---

## Updating Abora

On an installed Abora system:

```sh
sudo nixos update
sudo nixos rollback
```

Short aliases are also available:

```sh
update
upgrade
rollback
```

These commands sync the latest Abora project files into `/etc/nixos/abora/`, update the local flake, and rebuild the system.

---

## Flatpak

Flatpak is enabled on every Abora install, and Flathub is added automatically on first boot.

No extra setup is needed.

---

## Release Flow

Build the full release bundle:

```sh
make release
```

This writes the ISO, TinyPM package, checksums, release manifest, and release notes into the organized `out/` folders.

Other release targets:

```sh
make metadata        # refresh release metadata only
make tinypm-package  # TinyPM package by itself
make tinypm-image    # TinyPM container image locally
```

Publish the v3 line:

```sh
git tag v3.0.0
git push origin v3.0.0
```

---

## Development

Run script checks:

```sh
./scripts/check-scripts.sh
```

Validate all desktop environment configs against nixpkgs:

```sh
./scripts/check-desktops.sh
```

Rebuild in the VM workspace:

```sh
./scripts/rebuild-vm.sh
```

---

## Documentation

| Guide | Description |
|---|---|
| [Wiki home](docs/wiki/Home.md) | Main documentation landing page |
| [Installation guide](docs/wiki/Installation.md) | Installing Abora OS |
| [Updating Abora](docs/wiki/Updating-Abora.md) | Update and rollback flow |
| [Abora tools](docs/wiki/Abora-Tools.md) | Abora management commands |
| [Recovery](docs/wiki/Recovery.md) | Repair and rollback help |
| [ANIX v1](docs/wiki/ANIX-V1.md) | ANIX profile system |
| [TinyPM v4](docs/wiki/TinyPM-V4.md) | TinyPM package layer |
| [Building Abora](docs/wiki/Building-Abora.md) | Build instructions |
| [Release notes](RELEASE_NOTES.md) | Version history |
| [Security policy](SECURITY.md) | Vulnerability reporting |
| [Contributing guide](CONTRIBUTING.md) | How to help |
| [Project layout](docs/project-layout.md) | Repository structure |
| [Roadmap](docs/roadmap.md) | Planned work |

---

## Project Goal

Abora is my attempt to make NixOS easier to start with.

It keeps the rebuilds, generations, rollbacks, declarative config, and package power that make NixOS useful. It just adds a better first install, a more complete live image, easier commands, and defaults that do not feel empty.

That is the point of Abora: same base, better first experience.

---

## License

Abora OS is licensed under the **GNU General Public License v3.0 or later**.

See [LICENSE](LICENSE) for details.
