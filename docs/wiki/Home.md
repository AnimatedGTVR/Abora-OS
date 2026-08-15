# Abora OS Wiki

Welcome to the Abora OS wiki.

Abora is a distro project built on top of NixOS with one main goal: make NixOS easier to approach without hiding the power underneath.

## Start Here

- [Installation](Installation.md)
- [Updating Abora](Updating-Abora.md)
- [Building Abora](Building-Abora.md)
- [Release Guide](Release-Guide.md)
- [Abora Tools](Abora-Tools.md)
- [Abora Gaming](Abora-Gaming.md)
- [Recovery](Recovery.md)
- [TinyPM v0.8](TinyPM-V4.md)
- [ANIX v1](ANIX-V1.md)
- [ANIX v2 Languages](ANIX-V2-Languages.md)
- [ANIX standalone](ANIX-Standalone.md)
- [FAQ](FAQ.md)

## Current Version

**Abora OS v4 Everest** is the current alpha release line.

- Abora OS v4 Everest introduces multi-edition ISOs (Cosmic, Hyprland, GNOME, KDE, Other), ANIX v2 with pluggable configuration languages (Native, MKO, ModuCPP), and first-class GPU driver support (`abora.gpu`: nouveau/nvidia/nvidia-open/amdgpu/intel).
- DENALI 3.14 shipped the Omarchy-inspired TUI installer, stronger install validation, Abora branding across boot and desktop, ANIX v1, and TinyPM v0.8.
- v2.5 delivered the installer reliability, NetworkManager, desktop matrix, QEMU helpers, and release-command cleanup work that v3 built on.

## What Abora Adds To NixOS

- a focused live boot flow
- a guided installer with network setup, desktop selection, and GPU driver selection
- branded bootloader, Plymouth, wallpaper, and Fastfetch defaults
- installed commands for welcome, doctor, recovery, config, desktop selection, setup, and updates
- TinyPM-flavored app commands: `grab`, `search`, `term`, `start`, `supdate`, and Abora/ANIX system bridges
- ANIX helper workflows for snapshots, rollback, profile switching, and pluggable configuration languages

## Tool Split

- Abora commands handle distro setup, recovery, health checks, and installed-system configuration.
- ANIX handles NixOS profiles, snapshots, rebuild previews, rollback, and friendly system settings.
- TinyPM handles apps, package sources, and bridges into Abora/ANIX when useful.

## Useful Links

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Website](https://www.aboraos.org/)
- [Roadmap](../roadmap.md)
- [Install Checklist](../install-checklist.md)
- [Release Checklist](../release-checklist.md)
