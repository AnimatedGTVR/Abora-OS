<p align="center">
  <img src="assets/Github/ReadME%20background.png" alt="Abora OS banner" width="94%">
</p>

<p align="center">
  <img src="assets/Github/Abora-Logo.png" alt="Abora OS logo" width="110">
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
  <strong>v2.0.0</strong>
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
- 23 desktop environments to choose from at install time
- Curated starter app bundles: Fan Favorites, Essentials, Social, Creator, Developer
- Curated wallpaper pack seeded across all supported desktop sessions
- Dark-first desktop defaults across the full session matrix
- GNOME accent and theme auto-matching for Abora wallpapers
- Limine as the installed-system bootloader with Abora branding
- Reproducible ISO builds via Nix flakes
- `sudo nixos update` / `rollback` flow on installed systems
- Optional GitHub CLI integration for repos, dotfiles, and support workflows
- Abora branding across boot, desktop, and fastfetch

---

## Desktop Environments

Abora v2 ships with **23 desktop environments** selectable at install time:

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
| LXDE | Lightweight DE | LightDM |
| Enlightenment | Full DE | LightDM |
| i3 | Tiling WM | LightDM |
| AwesomeWM | Tiling WM | LightDM |
| Openbox | Floating WM | LightDM |
| Qtile | Tiling WM | LightDM |
| BSPWM | Tiling WM | LightDM |
| Fluxbox | Floating WM | LightDM |
| IceWM | Floating WM | LightDM |
| Herbstluftwm | Tiling WM | LightDM |
| DWM | Tiling WM | LightDM |

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
- Dumps a full support report on failure

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
make qemc
```

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

That writes the ISO, TinyPM package, checksums, release manifest, and release notes into `out/`.

Other targets:

```sh
make metadata        # refresh release metadata only
make tinypm-package  # TinyPM package by itself
make tinypm-image    # TinyPM container image locally
```

To publish a release:

```sh
git tag v2.0.0
git push origin v2.0.0
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
