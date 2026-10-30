<p align="center">
  <img src="assets/Abora-Text.png" alt="Abora OS" width="650">
</p>

<p align="center"><strong>A NixOS-based Linux distribution built to be easier to install, use, and understand.</strong></p>

<p align="center">
  <a href="https://aboraos.org"><img src="https://img.shields.io/badge/Website-aboraos.org-1677ff?style=for-the-badge" alt="Website"></a>
  <a href="https://github.com/Abora-OS/Abora-OS/releases"><img src="https://img.shields.io/github/v/release/Abora-OS/Abora-OS?style=for-the-badge&label=Download" alt="Latest release"></a>
  <a href="docs/README.md"><img src="https://img.shields.io/badge/Documentation-Read-30363d?style=for-the-badge" alt="Documentation"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/stars/Abora-OS/Abora-OS?style=flat-square&color=1677ff" alt="GitHub stars">
  <img src="https://img.shields.io/github/issues/Abora-OS/Abora-OS?style=flat-square&color=1677ff" alt="Open issues">
  <img src="https://img.shields.io/github/license/Abora-OS/Abora-OS?style=flat-square&color=1677ff" alt="License">
  <img src="https://img.shields.io/badge/Base-NixOS-5277C3?style=flat-square&logo=nixos&logoColor=white" alt="Based on NixOS">
</p>

Abora OS was created by **AnimatedGTVR** and is developed with help from community contributors.

## About Abora

Abora keeps NixOS's declarative configuration, reproducible builds, atomic upgrades, and rollbacks while providing a guided installer, practical defaults, a choice of desktops, and simpler management tools.

**v4.2 Solstice** is a safer, simpler Abora: one ISO and one installer where you pick the desktop, one command (`anix`) for everything, and system changes that roll back when they fail. Abora is still a young project: test important releases before installing them on your main machine.

<table>
  <tr>
    <td align="center"><strong>Approachable</strong><br>Guided installation and useful defaults.</td>
    <td align="center"><strong>Recoverable</strong><br>Failed changes roll back; <code>anix doctor</code> explains and repairs.</td>
    <td align="center"><strong>Flexible</strong><br>One ISO, your choice of desktop.</td>
  </tr>
  <tr>
    <td align="center"><strong>Declarative</strong><br>Reproducible system configuration.</td>
    <td align="center"><strong>Gaming Ready</strong><br>Optional Steam and Gamescope tools.</td>
    <td align="center"><strong>Open Source</strong><br>Built in public with community testing.</td>
  </tr>
</table>

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

- One ISO and a guided installer: pick your desktop, a Minimal install, or bring your own NixOS flake
- Choose your NixOS release: stable or unstable, at install time or later with `anix nixos`
- Stable and Edge release channels
- `anix` for updates, recovery, gaming, diagnostics, setup, profiles, generations, snapshots, and rollback (`abora` still works as an alias)
- ASA and ABT: system changes run as transactions and roll back when they fail
- `grab` and `anix package` to install apps from Nix, Flatpak, or Snap without editing your config
- Zen as the default browser, and optional Abora Labs experiments
- Many desktop environments from one shared base

## Pick your desktop

The installer asks which desktop to install. There is no live desktop session; the ISO is an installer only.

| Desktop | Best for |
| --- | --- |
| **COSMIC** | A modern desktop and the main Abora experience |
| **GNOME** | A focused and polished workflow |
| **KDE Plasma** | Deep customization and a familiar desktop |
| **XFCE** and **Cinnamon** | Traditional, lightweight desktops |
| **Hyprland** | Keyboard-driven tiling and custom setups |
| **None** | A command-line system you build up yourself |

Choosing **Minimal** also offers IceWM, LXQt, Lumina, Niri, Sway, Fluxbox, Openbox, or your own custom setup.

## Download and install

Download an ISO from [aboraos.org](https://aboraos.org) or [GitHub Releases](https://github.com/Abora-OS/Abora-OS/releases). Read the [installation guide](docs/wiki/Installation.md) before writing it to a USB drive.

Stable is intended for normal use. Edge receives unfinished changes first and may break:

| Channel | Purpose |
| --- | --- |
| **Stable** | Tested releases for normal use |
| **Edge** | New features and fixes for testers and contributors |

```sh
sudo anix channel set stable
sudo anix channel set edge
```

## Common commands

```sh
sudo anix update
anix doctor
anix recovery
anix setup
anix status
grab zen-browser
```

See [Abora Tools](docs/wiki/Abora-Tools.md), [Updating](docs/wiki/Updating-Abora.md), and [Recovery](docs/wiki/Recovery.md) for more.

## Build from source

```sh
git clone https://github.com/Abora-OS/Abora-OS.git
cd Abora-OS
make doctor
make check
make iso
```

Use `make qemu-fresh` for a clean VM install test and `make release` only when preparing the complete release bundle.

## Contributing

Bug reports, hardware tests, documentation fixes, artwork, and focused code changes are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), and report security problems through [SECURITY.md](SECURITY.md).

## Project links

- [Documentation](docs/README.md)
- [Release notes](RELEASE_NOTES.md)
- [Roadmap](docs/roadmap.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [License](LICENSE)
