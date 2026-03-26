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
  •
  <a href="RELEASE_NOTES.md">Release Notes</a>
  •
  <a href="docs/roadmap.md">Roadmap</a>
  •
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  Current public release: <code>v1.0.1</code>
</p>

Abora OS is a distro project built for people who like what NixOS can do, but want the first experience to feel more welcoming.

It keeps the NixOS base, then gives it a cleaner live image, a simpler path to installation, and a stronger identity across the whole boot-to-desktop experience.

## Important Documentation

- [Release notes](RELEASE_NOTES.md)
- [Contributing guide](CONTRIBUTING.md)
- [Project layout](docs/project-layout.md)
- [Install checklist](docs/install-checklist.md)
- [Release checklist](docs/release-checklist.md)
- [Roadmap](docs/roadmap.md)

## What Is Abora?

Abora is an attempt to make NixOS feel less distant.

Instead of dropping people straight into a system that feels like it was only made for people who already know the rules, Abora tries to smooth out the first steps. The goal is not to hide NixOS. The goal is to make it easier to approach, easier to install, and easier to live with.

## Why Abora?

### A Softer First Step

Abora is built around the idea that an operating system should invite people in. The live image, installer flow, and update path are meant to feel understandable instead of hostile.

### NixOS, Without the Cold Start

Under the hood, Abora still rides on NixOS. You still get reproducible builds, flake-based workflows, and a system that can be rebuilt cleanly. Abora just tries to package that power in a way that feels more like a real distro and less like homework.

### A Real Identity

Abora is not trying to be a blank shell. It has its own bootloader styling, wallpapers, fastfetch setup, and project voice so it feels like a complete operating system rather than a thin wrapper.

### Built to Keep Growing

Abora `v1.0.1` is the current public release, but the point is bigger than one ISO. The project is meant to keep evolving into a cleaner, more welcoming NixOS experience over time.

## What You Get

- a terminal-first live boot and installer
- Abora Welcome and Abora Center from the boot menu
- reproducible ISO builds with Nix flakes
- a local `sudo nixos update` flow for installed systems
- Abora branding across the boot experience

## Quick Start

Build the ISO, then boot it in QEMU:

```sh
cd /home/animated/abora-os
make iso
make qemc
```

## Updating an Installed System

On an installed Abora system, use:

```sh
sudo nixos update
```

If you want the shorter aliases, these work too:

```sh
update
upgrade
```

Those commands:

- sync the latest Abora project files into `/etc/nixos/abora/`
- update the local flake and rebuild the system
- migrate older installer-generated Abora installs into the current layout

## Release Flow

Build the full release bundle locally:

```sh
cd /home/animated/abora-os
make release
```

That writes the ISO, TinyPM V3 package, checksums, release manifest, and GitHub-ready release notes into `out/`.

If you only want to refresh release metadata:

```sh
make metadata
```

If you want the TinyPM V3 package by itself:

```sh
make tinypm-package
```

If you want the TinyPM V3 container package locally:

```sh
make tinypm-image
```

The GitHub Packages workflow publishes that image to:

```text
ghcr.io/<your-github-owner>/abora-tinypm
```

When it is time to publish a release on GitHub:

```sh
git tag v1.0.1
git push origin v1.0.1
```

## Live Image Notes

- the installer starts from the terminal-first boot flow
- `Abora Welcome` and `Abora Center` can be opened from the boot menu
- running `abora-welcome` or `abora-center` from the live shell launches a temporary GUI app session when needed
- TinyPM V3 is still a separate Abora tool, not part of the `v1.0.1` boot or installer flow

Run script checks with:

```sh
./scripts/check-scripts.sh
```

Rebuild in the VM workspace with:

```sh
./scripts/rebuild-vm.sh
```

## License

Abora OS is licensed under the GNU General Public License v3.0 or later.
See [LICENSE](LICENSE).
