
<p align="center">
  <img src="assets/Github/ReadME%20background.png" alt="Abora OS banner" width="100%">
</p>

<h1 align="center">Abora OS</h1>

<p align="center">
  NixOS made simpler for everyday users.
</p>

<p align="center">
  <a href="https://github.com/AnimatedGTVR/abora-os/releases/latest">
    <img src="https://img.shields.io/github/v/release/AnimatedGTVR/abora-os?style=for-the-badge&label=release" alt="Latest release">
  </a>
  <a href="https://github.com/AnimatedGTVR/abora-os/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/AnimatedGTVR/abora-os?style=for-the-badge" alt="License">
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

Abora OS is our attempt to make NixOS feel a lot less intimidating.
It keeps the NixOS base, but gives it a cleaner live image, a simpler install flow,
and Abora's own look across the bootloader, wallpapers, and fastfetch setup.

Current public release: `v1.0.1`

## What Abora Includes

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

## Repo Docs

- [CONTRIBUTING.md](CONTRIBUTING.md) for the day-to-day workflow
- [docs/project-layout.md](docs/project-layout.md) for the repo map
- [docs/install-checklist.md](docs/install-checklist.md) for install testing
- [docs/release-checklist.md](docs/release-checklist.md) for release validation
- [docs/roadmap.md](docs/roadmap.md) for the current direction

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
