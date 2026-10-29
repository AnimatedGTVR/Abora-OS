# Abora OS Documentation

This documentation covers installing, using, testing, recovering, building, and releasing Abora OS. Commands and behavior can differ between Stable and Edge, so check your version with `abora version` before following development instructions.

## Users

- [Installation](wiki/Installation.md): ISO installation, partition choices, desktop selection, and adoption on an existing NixOS system
- [Updating Abora](wiki/Updating-Abora.md): channels, update checks, normal updates, disk-full recovery, and rollback
- [Abora Tools](wiki/Abora-Tools.md): `anix` and `abora`, diagnostics, configuration, desktop management, and support commands
- [Recovery](wiki/Recovery.md): generations, rebuilds, networking, support reports, and live-ISO recovery
- [Abora Gaming](wiki/Abora-Gaming.md): Steam, Wine, Gamescope, GameMode, MangoHud, and cache repair
- [Packages](wiki/Packages.md): `grab`, `anix package`, Flatpak, and what replaced TinyPM
- [FAQ](wiki/FAQ.md): stability, hardware, installation, and troubleshooting

## Safety and ANIX

- [ASA and ABT](wiki/ASA.md): how system changes are checked, applied, verified, and rolled back
- [ANIX v1](wiki/ANIX-V1.md): current system-management commands
- [ANIX v2 Languages](wiki/ANIX-V2-Languages.md): language adapters and development direction
- [ANIX on existing NixOS](wiki/ANIX-Standalone.md): adoption and configuration guidance

## Testers

- [Hardware testing](hardware-testing.md): real-machine coverage and evidence to collect
- [Install checklist](install-checklist.md): live image, installer, VM, and first-boot validation
- [Bug report template](bug-report-template.md): reproducible reports with useful logs
- [Screenshot checklist](screenshots.md): current release imagery and privacy checks

## Contributors and maintainers

- [Contributing](../CONTRIBUTING.md): workflow, validation, commits, and code style
- [Project layout](project-layout.md): source-tree responsibilities
- [How the installer works](wiki/Installer.md): the screens, the Rust engine, what it writes, and how to test it
- [Building Abora](wiki/Building-Abora.md): ISO and VM builds
- [Release guide](wiki/Release-Guide.md): normal release workflow
- [Release checklist](release-checklist.md): required release gates
- [Next release plan](next-release-plan.md): current engineering priorities
- [Roadmap](roadmap.md): planned release direction

## Abora Labs

Labs compares experimental implementations under shared specifications and test vectors:

- [Overview](labs/README.md)
- [Architecture](labs/architecture.md)
- [CLI reference](labs/cli.md)
- [Manifest reference](labs/manifest.md)

## Policies and history

- [Security policy](../SECURITY.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Release notes](../RELEASE_NOTES.md)
- [Wallpaper credits](../assets/wallpapers/CREDITS.md)

Use Stable documentation for normal systems. Edge documentation may describe features that have not reached a release.
