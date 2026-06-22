# Abora OS Wiki

Welcome to the Abora OS wiki.

Abora is a distro project built on top of NixOS with one main goal: make NixOS easier to approach without hiding the power underneath.

## Start Here

- [Installation](Installation.md)
- [Updating Abora](Updating-Abora.md)
- [Building Abora](Building-Abora.md)
- [Release Guide](Release-Guide.md)
- [Abora Tools](Abora-Tools.md)
- [Recovery](Recovery.md)
- [TinyPM v4](TinyPM-V4.md)
- [ANIX v1](ANIX-V1.md)
- [ANIX standalone](ANIX-Standalone.md)
- [FAQ](FAQ.md)

## Current Version

**DENALI 3.14** is the current stable release.

- DENALI 3.14 shipped the Omarchy-inspired TUI installer, stronger install validation, Abora branding across boot and desktop, ANIX v1, and TinyPM v4.
- v2.5 delivered the installer reliability, NetworkManager, desktop matrix, QEMU helpers, and release-command cleanup work that v3 built on.

## What Abora Adds To NixOS

- a focused live boot flow
- a guided installer with network setup and desktop selection
- branded bootloader, Plymouth, wallpaper, and Fastfetch defaults
- installed commands for welcome, doctor, recovery, config, desktop selection, setup, and updates
- TinyPM-flavored app commands: `grab`, `search`, `term`, `start`, `supdate`, and Abora/ANIX system bridges
- ANIX helper workflows for snapshots, rollback, and profile switching

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
