<p align="center">
  <img src="/assets/Abora-Text.png" alt="Abora OS" width="650">
</p>

<div align="center">

### A NixOS-based Linux distribution built to be easier to install, use, and understand.

<br/>

<a href="https://aboraos.org">
  <img height="28" src="https://img.shields.io/badge/Website-aboraos.org-f0f0f0?style=for-the-badge" alt="Website">
</a>
<a href="https://deepwiki.com/AnimatedGTVR/Abora-OS">
  <img height="28" src="https://img.shields.io/badge/Ask%20DeepWiki-Abora%20OS-0ea5e9?style=for-the-badge" alt="Ask DeepWiki">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS">
  <img height="28" src="https://img.shields.io/badge/GitHub-Abora--OS-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub">
</a>

<br/>
<br/>

<a href="https://github.com/AnimatedGTVR/Abora-OS/stargazers">
  <img height="22" src="https://img.shields.io/github/stars/AnimatedGTVR/Abora-OS?style=flat-square&label=Stars" alt="GitHub Stars">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS/issues">
  <img height="22" src="https://img.shields.io/github/issues/AnimatedGTVR/Abora-OS?style=flat-square&label=Issues" alt="Issues">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS/releases">
  <img height="22" src="https://img.shields.io/github/v/release/AnimatedGTVR/Abora-OS?style=flat-square&label=Release" alt="Latest Release">
</a>
<a href="LICENSE">
  <img height="22" src="https://img.shields.io/badge/License-See%20LICENSE-3b82f6?style=flat-square" alt="License">
</a>

</div>

---

> [!IMPORTANT]
> Want to leave a feature recommendation? Do it!


## Quick Links

- [Official Website](https://aboraos.org)
- [GitHub Releases](https://github.com/AnimatedGTVR/Abora-OS/releases)
- [Documentation](https://deepwiki.com/AnimatedGTVR/Abora-OS)
- [Issue Tracker](https://github.com/AnimatedGTVR/Abora-OS/issues)
- [Discussions](https://github.com/AnimatedGTVR/Abora-OS/discussions)
- [Contributing Guide](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Release Notes](RELEASE_NOTES.md)
- [Roadmap](ROADMAP.md)
- [License](LICENSE)

## Screenshots

<div align="center">

<img src="/assets/Images/v4/screenshot-2026-07-27_03-54-02.png" width="410" alt="Abora Welcome on GNOME">
<img src="/assets/Images/v4/screenshot-2026-07-27_03-56-03.png" width="410" alt="Abora System Settings">
<img src="/assets/Images/v4/screenshot-2026-07-27_03-58-15.png" width="410" alt="fastfetch on GNOME">
<img src="/assets/Images/v4/screenshot-2026-07-27_05-32-15.png" width="410" alt="fastfetch on COSMIC">

</div>

## What is Abora OS?

Abora OS is a Linux distribution based on NixOS.

It keeps the parts that make NixOS useful, including system rollbacks, reproducible configurations, and declarative system management, while providing a more approachable starting point.

Abora includes its own defaults, desktop choices, installer work, and tools designed to make common system tasks easier to understand.

It is built for people who want the power of NixOS without needing to create their entire setup from scratch before they can use it.

## Why Abora?

- Easier installation and setup
- Declarative system configuration
- Reproducible builds
- Atomic upgrades
- System rollback support
- Multiple desktop environments
- Abora-specific defaults and tooling
- Stable and Edge release channels
- ANIX system management tools

## Release Lines

Abora uses two release channels, similar to the stable and unstable split used by NixOS.

### Stable

Stable contains tagged and tested releases.

Examples include:

```txt
2.5
3.0
3.14
4.0
```

This is the default channel and the recommended choice for most users.

### Edge

Edge follows active development from `main`.

New installer work, desktop changes, ANIX changes, and fixes arrive here first. Edge may contain unfinished features or bugs.

Switch to Edge:

```sh
sudo abora channel set unstable
```

Return to Stable:

```sh
sudo abora channel set stable
```

> [!WARNING]
> Edge builds are intended for development and testing. Use Stable when reliability matters.

## Features

### Core

- Built on NixOS
- Declarative system management
- Reproducible system configuration
- Atomic upgrades
- System rollback support

### Desktop Experience

- Multiple desktop options
- Abora-specific defaults
- Custom branding and artwork
- Guided installation
- Tools for common system tasks

### Development

- Stable and Edge release channels
- Custom installer development
- ANIX tooling
- Open-source development

## ANIX

ANIX is Abora's command-line tool for common system management tasks.

```bash
anix update
anix switch
anix rollback
anix status
```

> [!NOTE]
> ANIX does not replace NixOS. It makes common commands easier to remember and use.

## Download

Abora OS can be downloaded from the official website or from GitHub Releases.

<div align="center">

<a href="https://aboraos.org">
  <img src="https://img.shields.io/badge/Download-Abora%20OS-f0f0f0?style=for-the-badge" alt="Download Abora OS">
</a>
<a href="https://github.com/AnimatedGTVR/Abora-OS/releases">
  <img src="https://img.shields.io/badge/GitHub-Releases-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub Releases">
</a>

</div>

## Building

Clone the repository:

```bash
git clone https://github.com/AnimatedGTVR/Abora-OS.git
cd Abora-OS
```

Build the ISO:

```bash
make iso
```

Boot the latest ISO in QEMU:

```bash
make qemc
```

Run the project checks:

```bash
make check
```

Build the complete release bundle:

```bash
make release
```

Refresh release metadata without rebuilding the ISO:

```bash
make metadata
```

The release bundle is generated in `out/` and includes the ISO, checksums, release manifest, and release notes.

## Repository Layout

- [`assets/`](assets/) contains branding, wallpapers, bootloader artwork, screenshots, and fastfetch assets.
- [`docs/`](docs/) contains documentation, release notes, validation information, and roadmap files.
- [`nix/`](nix/) contains the live image configuration.
- [`scripts/`](scripts/) contains installer logic, boot flow, build helpers, and release tooling.
- [`vendor/tinypm/`](vendor/tinypm/) contains the vendored TinyPM v4 project.
- [`docs/project-layout.md`](docs/project-layout.md) contains a more detailed repository layout guide.

## Contributing

Contributions are welcome.

Useful ways to help include:

- Reporting bugs
- Testing desktop environments
- Testing the installer
- Improving documentation
- Working on ANIX
- Cleaning up existing code
- Submitting fixes and improvements

Before opening a pull request, please read:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)

Open an issue before starting a large change so it can be discussed first. Smaller fixes can usually be submitted directly through a pull request.

## License

Abora OS is open-source software.

See the [LICENSE](LICENSE) file for the full license terms.
