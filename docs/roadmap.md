# Abora OS Roadmap

This roadmap tracks the current Abora direction after Abora OS v4 Everest and the in-progress MINT/graphical-tools work toward the next release.

## Abora OS v4 Everest Delivered

- five edition ISOs (Cosmic, Hyprland, GNOME, KDE, Other), each defaulting to a different desktop while still installing the full 23-profile matrix
- first-class GPU driver selection (`abora.gpu`: nouveau, nvidia, nvidia-open, amdgpu, intel, none), detected via `lspci` at install time
- ANIX v2: pluggable configuration languages (ANIX Native, MKO, ModuCPP) that all resolve to one Plan JSON, applied as a single transaction with per-setting ADD/CHANGE/SAME diffing
- everything from DENALI 3.14 carried forward — Omarchy-inspired installer, 23 desktop profiles, TinyPM v0.8, branding and hardware coverage

## In Progress Toward the Next Release

- **MINT** as the default guided installer front-end, handing the confirmed plan to the existing bash installer as its backend
- `abora welcome-gui` and `abora config-gui` — the first GTK4/libadwaita graphical tools, thin front-ends over the existing CLI so nothing they do is GUI-exclusive

## Recently Delivered

- real IANA timezone data (every real zoneinfo entry, fuzzy-searchable, e.g. `America/Indiana/Knox`) instead of a small hand-picked list, in both `abora-config-gui.py` and `abora-installer-gui.py` — this was a real correctness gap: multi-zone regions like Indiana were only showing one of their eight actual zones
- `abora update --check` — query update availability without installing, with machine-parseable output for the Welcome GUI's status card
- full step-indexed back navigation through the GTK installer wizard — every screen can be undone with `Esc` (new) or `← Back` (already existed), answers preserved since pages are built once and reused rather than recreated

## Near-Term Direction

- **importable Abora features for existing NixOS users** — `anix` and `branding` (fastfetch config/logo, title banner, logo image, default wallpaper) are standalone-importable `nixosModules`; `nix run github:AnimatedGTVR/Abora-OS#desktop-preview -- <profile>` prints Abora's exact desktop-profile config/package blocks to paste in by hand (shell-generated, can't be a declarative module); `nix run github:AnimatedGTVR/Abora-OS#hardware-test` runs Abora's hardware-readiness checks on any machine. None of this requires the installer or ISO (see `docs/wiki/ANIX-Standalone.md`). Most of the rest of the `abora` CLI (`abora-config`, `abora-desktop`, `abora-doctor`, etc.) is Abora-install-specific by nature — it reads/writes actual Abora system state — so it's not clear all of it *should* be extracted the same way; what's left here is auditing the remaining `installed-base` pieces case by case for which ones are genuinely portable, the way hardware-test and desktop-preview turned out to be
- keep expanding graphical coverage where it clearly helps first-time and non-terminal users, without ever making the CLI a second-class citizen — every GUI action should have an equivalent command
- extend MINT's guided flow to cover more of what the bash installer can already do, rather than duplicating logic between the two
- keep the desktop matrix green across all 23 profiles via `make check-desktops` as new GTK/libadwaita dependencies are added
- continue auditing scripts and the new Python/GTK tooling for the same class of bug found and fixed during this pass: environment variables silently dropped across privilege escalation (`pkexec`/`sudo`), which can cause a tool to act on the wrong config path instead of failing loudly
- improve hardware test coverage for Wi-Fi laptops, NVIDIA systems, BIOS boot, and UEFI boot
- document known install blockers immediately instead of letting users discover them late

## Release Direction

- keep GitHub releases as the primary public ISO distribution path
- attach ISO, checksums, manifest, release notes, and TinyPM package to release bundles
- require `make check`, `make check-desktops`, one full VM install, and one installed-system boot before publishing
- use `make iso` for fast ISO-only iteration, `make iso-all` before a release, `make release` only for full release bundles
