<p align="center">
  <img src="assets/Github/ReadME%20background.png" alt="Abora OS banner" width="94%">
</p>


<h1 align="center">Abora OS</h1>

<p align="center">
  A friendlier take on NixOS.
</p>

<p align="center">
  <a href="https://github.com/AnimatedGTVR/abora-os/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/AnimatedGTVR/abora-os?style=for-the-badge" alt="License">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/graphs/contributors">
    <img src="https://img.shields.io/github/contributors/AnimatedGTVR/abora-os?style=for-the-badge" alt="Contributors">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/releases/latest">
    <img src="https://img.shields.io/github/v/release/AnimatedGTVR/abora-os?style=for-the-badge&label=release" alt="Latest release">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/actions/workflows/build-iso.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/AnimatedGTVR/abora-os/build-iso.yml?style=for-the-badge&label=iso%20build" alt="ISO build status">
  </a>
</p>

<p align="center">
  <a href="https://www.aboraos.org/">Website</a>
  &nbsp;•&nbsp;
  <a href="docs/wiki/Home.md">Wiki</a>
  &nbsp;•&nbsp;
  <a href="RELEASE_NOTES.md">Release Notes</a>
  &nbsp;•&nbsp;
  <a href="SECURITY.md">Security</a>
  &nbsp;•&nbsp;
  <a href="docs/roadmap.md">Roadmap</a>
  &nbsp;•&nbsp;
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <strong>v3.0.0 Denali</strong>
</p>

---

Abora OS is a distro built for people who like what NixOS can do, but want the first experience to feel more welcoming.

It keeps the full NixOS base, then wraps it in a cleaner live image, a friendlier installer, and a stronger identity from boot to desktop.

---

## What Is Abora?

Abora is an attempt to make NixOS feel less distant.

Instead of dropping people into a system that feels like it was only built for people who already know the rules, Abora tries to smooth out the first steps. The goal is not to hide NixOS — the goal is to make it easier to approach, easier to install, and easier to live with.

## What You Get

- Terminal-first live boot and installer with a full welcome flow
- 22 desktop environments to choose from at install time
- Curated starter app bundles: Fan Favorites, Essentials, Social, Creator, Developer, Gaming, System
- 53 apps in the catalog across 6 categories
- Flatpak + Flathub enabled out of the box on every install
- Curated wallpaper pack seeded across all supported desktop sessions
- Dark-first desktop defaults across the full session matrix
- GNOME accent and theme auto-matching for Abora wallpapers
- Limine as the installed-system bootloader with Abora branding
- Reproducible ISO builds via Nix flakes
- `sudo nixos update` / `rollback` flow on installed systems
- Update channels: track `stable` releases or `unstable` (main branch)
- `abora config` command to view and change system settings without editing Nix
- ANIX v1 profile management with status, snapshots, diff/test/boot/switch/rollback workflows
- TinyPM v4 app layer with source status, repair, and Abora/ANIX bridges
- Omarchy-inspired Denali installer TUI
- Optional GitHub CLI integration for repos, dotfiles, and support workflows
- Abora branding across boot, desktop, and fastfetch

---

## Desktop Environments

Abora v3 ships with **22 desktop environments/window managers**, plus a no-desktop install, selectable at install time:

| Desktop | Type | Display Manager |
|---|---|---|
| GNOME | Full DE | GDM |
| KDE Plasma | Full DE | SDDM |
| Hyprland | Wayland compositor | SDDM (Wayland) |
| Sway | Wayland compositor | SDDM (Wayland) |
| Niri | Wayland compositor | SDDM (Wayland) |
| River | Wayland compositor | SDDM (Wayland) |
| XFCE | Full DE | LightDM |
| Cinnamon | Full DE | LightDM |
| MATE | Full DE | LightDM |
| Budgie | Full DE | LightDM |
| LXQt | Lightweight DE | SDDM |
| Pantheon | Full DE | LightDM |
| i3 | Tiling WM | LightDM |
| AwesomeWM | Tiling WM | LightDM |
| Openbox | Floating WM | LightDM |
| Qtile | Tiling WM | LightDM |
| BSPWM | Tiling WM | LightDM |
| Fluxbox | Floating WM | LightDM |
| IceWM | Floating WM | LightDM |
| Herbstluftwm | Tiling WM | LightDM |
| COSMIC | Full DE | COSMIC Greeter |
| MangoWM | Wayland compositor | SDDM (Wayland) |
| No desktop | Console-only | TTY |

---

## Installer

The installer is a terminal-first, keyboard-driven setup flow that runs directly from the live image.

### What the installer does

- Opens with a welcome menu before anything touches the disk
- Auto-detects timezone and keyboard layout, with a dedicated locale step to correct either
- Lets you pick hostname, username, password, and desktop environment
- Offers a starter app bundle selection (or none at all)
- Optional GitHub CLI login step for post-install workflows
- Shows a bordered install summary before wiping the disk
- Displays live progress during `nixos-install`
- validates generated config before `nixos-install`
- shows useful logs on failure

### Keyboard shortcuts

Menu navigation supports arrow keys **and number keys** — press `1`–`9` to jump to any item instantly.

### Disk layout

Every install creates a GPT with:
- 1 MiB BIOS boot partition
- 512 MiB EFI system partition
- ext4 root partition using the rest of the disk

---

## Quick Start

Build the ISO, then boot it in QEMU:

```sh
make iso
make qemu-fresh
```

After installing in QEMU, boot the virtual hard drive without the ISO:

```sh
make qemu-disk
```

---

## Configuring an Installed System

After installation, local system settings live in `/etc/nixos/abora-local.nix`:

```nix
abora.hostname = "my-pc";
abora.timezone = "America/New_York";
abora.desktop  = "gnome";
```

The `abora config` command lets you view and change settings without editing the file directly:

```sh
abora config                         # show all current settings
abora config set hostname   my-pc
abora config set timezone   America/New_York
abora config set desktop    hyprland
abora config apply                   # rebuild to apply changes
```

Note: `user` and `disk` are read-only through `abora config` for safety — edit `abora-local.nix` directly for those.

---

## ANIX Layer

ANIX is the human layer for NixOS and Abora: a safer OS-management CLI that hides the rebuild and flake syntax without replacing the NixOS machinery underneath.

Use it like this:

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

ANIX maps friendly profile names to real flake configs, so `anix switch nix gaming` becomes the safe version of `sudo nixos-rebuild switch --flake /etc/nixos#gaming`.

Snapshots stay local by default. `anix save` creates a Git commit in the user's `/etc/nixos` config repo, warns about possible secrets, and recommends moving real keys/passwords to `sops-nix` or `agenix`. Pushing snapshots is opt-in:

```sh
anix config set snapshots.push true
```

ANIX still writes simple settings to `/etc/nixos/anix.nix` and rebuilds the normal Abora flake. It does not replace NixOS or Abora; it gives beginners a cleaner front layer for profile switching, rollback, recovery, desktop choice, wallpaper changes, and system health checks.

---

## TinyPM v4

TinyPM is the app/package layer. Use it for installs, source checks, and app updates:

```sh
grab firefox
tinypm sources
tinypm system
tinypm repair
tinypm anix status
tinypm abora doctor
```

TinyPM v4 prefers Nix on Abora and NixOS-family systems, while still supporting Flatpak, Snap, and common native package managers.

---

## Abora Management Tools

Abora also includes a small OS management layer:

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

Updates offer a local ANIX snapshot before rebuilding, so users have a recovery point before changing the system.

---

## Update Channels

Installed systems can track either the `stable` channel (latest tagged release) or `unstable` (main branch):

```sh
nixos channel          # show current channel
nixos channel list     # list available channels
nixos channel set stable
nixos channel set unstable
```

---

## Flatpak

Flatpak is enabled on every Abora install and the Flathub remote is added automatically on first boot — no manual setup needed.

---

## Updating an Installed System

On an installed Abora system:

```sh
sudo nixos update    # pull latest and rebuild
sudo nixos rollback  # return to the previous generation
```

Shorter aliases also work:

```sh
update
upgrade
rollback
```

These commands sync the latest Abora project files into `/etc/nixos/abora/`, update the local flake, and rebuild the system.

---

## Release Flow

Build the full release bundle:

```sh
make release
```

That writes the ISO, TinyPM package, checksums, release manifest, and release notes into the organized `out/` folders.

Other targets:

```sh
make metadata        # refresh release metadata only
make tinypm-package  # TinyPM package by itself
make tinypm-image    # TinyPM container image locally
```

To publish the v3 line:

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

- [Wiki home](docs/wiki/Home.md)
- [Installation guide](docs/wiki/Installation.md)
- [Updating Abora](docs/wiki/Updating-Abora.md)
- [Abora tools](docs/wiki/Abora-Tools.md)
- [Recovery](docs/wiki/Recovery.md)
- [ANIX v1](docs/wiki/ANIX-V1.md)
- [TinyPM v4](docs/wiki/TinyPM-V4.md)
- [Building Abora](docs/wiki/Building-Abora.md)
- [Release notes](RELEASE_NOTES.md)
- [Security policy](SECURITY.md)
- [Contributing guide](CONTRIBUTING.md)
- [Project layout](docs/project-layout.md)
- [Roadmap](docs/roadmap.md)

---

## License

Abora OS is licensed under the GNU General Public License v3.0 or later.
See [LICENSE](LICENSE).
