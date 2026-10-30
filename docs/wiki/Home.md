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
- [ASA: safe system changes](ASA.md)
- [Packages](Packages.md)
- [ANIX v1](ANIX-V1.md)
- [ANIX v2 Languages](ANIX-V2-Languages.md)
- [ANIX standalone](ANIX-Standalone.md)
- [FAQ](FAQ.md)

## Current Version

**Abora OS v4.2 Solstice** is the current alpha release line.

- Abora OS v4.2 Solstice is about a safer, simpler Abora: `anix` as the one command, transactions that roll back failed system changes ([ASA](ASA.md)), `anix doctor` with explanations and repairs, `anix package` instead of TinyPM, and clearer installer failures.
- Abora OS v4.1 Horizon focused on installer and update reliability, community tools, ANIX Native and ModuCPP, and first-class GPU driver support (`abora.gpu`: nouveau/nvidia/nvidia-open/amdgpu/intel).
- DENALI 3.14 shipped the Omarchy-inspired TUI installer, stronger install validation, Abora branding across boot and desktop, ANIX v1, and TinyPM v0.8.
- v2.5 delivered the installer reliability, NetworkManager, desktop matrix, QEMU helpers, and release-command cleanup work that v3 built on.

## What Abora Adds To NixOS

- a focused live boot flow
- a guided installer with network setup, desktop selection, and GPU driver selection
- branded bootloader, Plymouth, wallpaper, and Fastfetch defaults
- installed commands for welcome, doctor, recovery, config, desktop selection, setup, and updates
- `anix package` to install any nixpkgs package without a rebuild, and `abora apps` for Flatpak
- ANIX helper workflows for snapshots, rollback, profile switching, and pluggable configuration languages

## Tool Split

Since 4.2 Solstice, **`anix` is the one Abora command**. It covers what used to be split between two:

- system tasks: `anix update`, `anix doctor`, `anix recovery`, `anix welcome`, `anix apps`, `anix gaming`, `anix config`, ...
- NixOS config: profiles, snapshots, rebuild previews, rollback, `anix set` / `anix enable`
- packages: `anix package install` (no rebuild), `anix package add` (in the config), `anix apps` for Flatpak

`abora` still works as the old name for the same command, so `abora update` and `anix update` do the same
thing and existing scripts and habits keep working. See [Abora Tools](Abora-Tools.md).

## Useful Links

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Website](https://www.aboraos.org/)
- [Roadmap](../roadmap.md)
- [Install Checklist](../install-checklist.md)
- [Release Checklist](../release-checklist.md)
