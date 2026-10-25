<p align="center">
  <img src="assets/Abora-Text.png" alt="Abora OS" width="650">
</p>

<p align="center"><strong>A NixOS-based Linux distribution built to be easier to install, use, and understand.</strong></p>

<p align="center">
  <a href="https://aboraos.org"><img src="https://img.shields.io/badge/Website-aboraos.org-1677ff?style=for-the-badge" alt="Website"></a>
  <a href="https://github.com/AnimatedGTVR/Abora-OS/releases"><img src="https://img.shields.io/github/v/release/AnimatedGTVR/Abora-OS?style=for-the-badge&label=Download" alt="Latest release"></a>
  <a href="docs/wiki/Home.md"><img src="https://img.shields.io/badge/Documentation-Read-30363d?style=for-the-badge" alt="Documentation"></a>
</p>

<p align="center">
  <img src="assets/Images/v4.1-horizon-banner.png" alt="Abora OS Horizon" width="900">
</p>

Abora OS was created by **AnimatedGTVR** and is developed with help from community contributors.

## About Abora

Abora keeps NixOS's declarative configuration, reproducible builds, atomic upgrades, and rollbacks while providing a guided installer, practical defaults, several desktop editions, and simpler management tools.

Current editions include COSMIC, GNOME, KDE Plasma, Hyprland, and Other Desktops. Abora is still a young project: test important releases before installing them on your main machine.

## Screenshots

<table>
  <tr>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_03-54-02.png" alt="Abora Welcome" width="440"></td>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_03-56-03.png" alt="Abora Settings" width="440"></td>
  </tr>
  <tr>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_03-58-15.png" alt="Abora GNOME desktop" width="440"></td>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_05-32-15.png" alt="Abora COSMIC desktop" width="440"></td>
  </tr>
</table>

## Main features

- Guided installation and hardware-aware defaults
- Stable and Edge release channels
- `abora` tools for updates, recovery, gaming, diagnostics, and setup
- ANIX for profiles, generations, snapshots, and rollback
- Optional TinyPM application layer and Abora Labs experiments
- Multiple desktop environments from one shared base

## Download and install

Download an ISO from [aboraos.org](https://aboraos.org) or [GitHub Releases](https://github.com/AnimatedGTVR/Abora-OS/releases). Read the [installation guide](docs/wiki/Installation.md) before writing it to a USB drive.

Stable is intended for normal use. Edge receives unfinished changes first and may break:

```sh
sudo abora channel set stable
sudo abora channel set unstable
```

## Common commands

```sh
sudo abora update
abora doctor
abora recovery
abora setup
anix status
tinypm providers
```

See [Abora Tools](docs/wiki/Abora-Tools.md), [Updating](docs/wiki/Updating-Abora.md), and [Recovery](docs/wiki/Recovery.md) for more.

## Build from source

```sh
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
make doctor
make check
make iso
```

Use `make qemu-fresh` for a clean VM install test and `make release` only when preparing the complete release bundle.

## Contributing

Bug reports, hardware tests, documentation fixes, artwork, and focused code changes are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), and report security problems through [SECURITY.md](SECURITY.md).

## Project links

- [Documentation](docs/wiki/Home.md)
- [Release notes](RELEASE_NOTES.md)
- [Roadmap](docs/roadmap.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [License](LICENSE)
