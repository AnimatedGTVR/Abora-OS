# Abora OS Roadmap

This roadmap tracks the current Abora direction after EVEREST 4.0 and the in-progress MINT/graphical-tools work toward the next release.

## EVEREST 4.0 Delivered

- five edition ISOs (Cosmic, Hyprland, GNOME, KDE, Other), each defaulting to a different desktop while still installing the full 23-profile matrix
- first-class GPU driver selection (`abora.gpu`: nouveau, nvidia, nvidia-open, amdgpu, intel, none), detected via `lspci` at install time
- ANIX v2: pluggable configuration languages (ANIX Native, MKO, ModuCPP) that all resolve to one Plan JSON, applied as a single transaction with per-setting ADD/CHANGE/SAME diffing
- everything from DENALI 3.14 carried forward — Omarchy-inspired installer, 23 desktop profiles, TinyPM v4, branding and hardware coverage

## In Progress Toward the Next Release

- **MINT** as the default guided installer front-end, handing the confirmed plan to the existing bash installer as its backend
- full step-indexed back navigation through the installer wizard — every screen can be undone with `Esc` or `← Back`, answers preserved
- real IANA timezone data (region-first, then fuzzy search) instead of a small hand-picked list — this was a real correctness gap: multi-zone regions like Indiana were only showing one of their eight actual zones
- `abora update --check` — query update availability without installing
- `abora welcome-gui` and `abora config-gui` — the first GTK4/libadwaita graphical tools, thin front-ends over the existing CLI so nothing they do is GUI-exclusive

## Near-Term Direction

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
