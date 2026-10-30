<p align="center">
  <img src="assets/Abora-Text.png" alt="Abora OS" width="650">
</p>

<h3 align="center">Linux you can understand. A system you can rebuild.</h3>

<p align="center">
  A NixOS-based Linux distribution focused on simplicity, flexibility, and recovery.
</p>

<p align="center">
  <a href="https://aboraos.org"><img src="https://img.shields.io/badge/Website-Visit-1677ff?style=for-the-badge" alt="Website"></a>
  <a href="https://github.com/AnimatedGTVR/Abora-OS/releases"><img src="https://img.shields.io/badge/Download-Releases-238636?style=for-the-badge" alt="Download"></a>
  <a href="docs/README.md"><img src="https://img.shields.io/badge/Documentation-Read-30363d?style=for-the-badge" alt="Documentation"></a>
  <a href="https://aboraos.org/security"><img src="https://img.shields.io/badge/Security-Center-d97706?style=for-the-badge" alt="Security"></a>
</p>

<p align="center">
  <a href="https://github.com/AnimatedGTVR/Abora-OS/stargazers">⭐ Star on GitHub</a> ·
  <a href="https://github.com/AnimatedGTVR/Abora-OS/issues">Report a Bug</a> ·
  <a href="https://github.com/AnimatedGTVR/Abora-OS/pulls">Contribute</a> ·
  <a href="docs/roadmap.md">Roadmap</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Base-NixOS-5277C3?style=flat-square" alt="NixOS">
  <img src="https://img.shields.io/badge/Channels-Stable%20%7C%20Edge-30363d?style=flat-square" alt="Channels">
  <img src="https://img.shields.io/badge/v4.2-In%20Development-d97706?style=flat-square" alt="v4.2 in development">
</p>

---

## Welcome to Abora

**Abora OS** is an independent, open-source Linux distribution created by **AnimatedGTVR** and developed with help from community contributors.

Built on NixOS, Abora combines declarative configuration, reproducible builds, and rollback capabilities with guided installation, desktop flexibility, and approachable system management.

**Our goal is to make Linux easier to install, understand, customize, and recover — without sacrificing control.**

## What Abora offers

| Feature | Description |
| --- | --- |
| **Desktop Freedom** | COSMIC, GNOME, KDE Plasma, Hyprland, XFCE, and more |
| **NixOS Foundation** | Declarative configuration and reproducible builds |
| **ANIX** | Tools for system management, updates, and recovery |
| **Rollback** | Restore previous system generations |
| **Package Management** | Nix and optional application sources |
| **Gaming** | Optional Steam and gaming utilities |
| **Release Channels** | Stable for releases, Edge for development |

## Screenshots

<table>
  <tr>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_03-54-02.png" alt="Abora Welcome" width="440"></td>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_03-56-03.png" alt="Abora Settings" width="440"></td>
  </tr>
  <tr>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_03-58-15.png" alt="Abora GNOME" width="440"></td>
    <td><img src="assets/Images/v4/screenshot-2026-07-27_05-32-15.png" alt="Abora COSMIC" width="440"></td>
  </tr>
</table>

## Meet ANIX

ANIX is Abora's system management tooling, designed to simplify common administration tasks.

```bash
sudo anix update
anix doctor
anix recovery
anix status
```

The existing `abora` command remains supported.

Learn more in [Abora Tools](docs/wiki/Abora-Tools.md).

## What's next? v4.2 Solstice

**Currently in development — not yet released.**

Solstice focuses on improving Abora's foundations:

- **Unified ISO** — One installer with desktop selection.
- **Installer overhaul** — Better partitioning, reliability, and configuration.
- **ASA + ABT** — Safer system changes and transaction-based recovery.
- **ANIX improvements** — More consistent system management.
- **Rust and Go tooling** — Gradually replacing complex Shell implementations.
- **Better diagnostics** — Clearer errors, recovery, and troubleshooting.

Follow development through the [roadmap](docs/roadmap.md) and [pull requests](https://github.com/AnimatedGTVR/Abora-OS/pulls).

## Download Abora

Get the latest released version from the [official website](https://aboraos.org) or [GitHub Releases](https://github.com/AnimatedGTVR/Abora-OS/releases).

| Channel | Purpose |
| --- | --- |
| **Stable** | Tested releases intended for normal use |
| **Edge** | Experimental changes and development testing |

Read the [installation guide](docs/wiki/Installation.md) before installing.

## Build from source

```bash
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS

make doctor
make check
make iso
```

Use `make qemu-fresh` to test an installation in a virtual machine.

## Contributing

Abora is developed in the open. Code contributions, testing, documentation, design, and bug reports are welcome.

Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

For security reports, see [SECURITY.md](SECURITY.md).

## Project links

- [Website](https://aboraos.org)
- [Documentation](docs/README.md)
- [Security Center](https://aboraos.org/security)
- [Release Notes](RELEASE_NOTES.md)
- [Roadmap](docs/roadmap.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [License](LICENSE)

---

<p align="center">
  <strong>Built for people who want to understand their system — not fight it.</strong>
</p>

<p align="center">
  Made with care by the Abora OS community.
</p>
