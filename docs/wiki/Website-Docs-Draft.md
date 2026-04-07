# Abora OS v2 Overview Draft

This file is a temporary all-in-one draft for the Abora website and docs.

It is meant to answer three questions in one place:

- what Abora `v2.0.0-dev` offers
- what changed compared to the `v1` era
- what new docs now exist around the project

## Current Snapshot

Current development version:

`v2.0.0-dev`

Abora OS is still built on top of NixOS, but the `v2` direction is to make that base feel much less intimidating.

The goal is not to hide NixOS.

The goal is to make NixOS feel more like a real operating system from the first boot onward.

## What Abora v2 Offers

### 1. A Simpler First Install Path

Abora `v2` keeps the live environment focused on the installer instead of scattering setup across separate helper apps.

The installer flow now starts with:

- a welcome screen
- names and account setup
- password setup
- optional GitHub device login
- extra packages and setup
- a final review step
- installation

The current installer flow is designed to feel more guided than raw NixOS while still staying terminal-friendly.

### 2. Optional GitHub Login During Install

Abora `v2` includes optional GitHub device login support directly in the installer.

That means:

- no browser is needed on the machine running the installer
- the user can authenticate from another device at `github.com/login/device`
- the login can be skipped cleanly
- if used, the GitHub auth config can be copied into the installed system

This makes GitHub integration feel built into the setup flow without turning GitHub into a required part of the OS.

### 3. Curated Starter App Bundles

Instead of making the user think about package names right away, Abora `v2` lets the installer seed a starter app bundle during setup.

Current bundle choices include:

- no starter apps
- fan favorites
- essentials
- social
- creator
- developer

This is part of the larger `v2` direction of making software setup feel closer to a normal distro experience.

### 4. Broader Desktop Coverage

Abora `v2` is no longer centered around just one polished desktop path.

The current supported desktop matrix includes:

- GNOME
- KDE Plasma
- Hyprland
- XFCE
- Cinnamon
- MATE
- Budgie
- LXQt
- i3
- Openbox

The repo also includes checks to make sure these desktop profiles still evaluate cleanly as part of development.

### 5. Dark-First Desktop Defaults

Abora `v2` pushes a darker visual identity across the supported desktop sessions.

That includes:

- dark-first defaults across the supported desktop matrix
- seeded default wallpapers
- wallpaper handling through the system itself instead of a custom wallpaper app
- GNOME accent and style syncing when Abora wallpapers are selected

The goal is that Abora feels like one project across multiple desktops, not a random bundle of sessions.

### 6. Curated Wallpaper Pack

Abora `v2` now ships a curated wallpaper collection instead of relying on a single old wallpaper.

Current named wallpapers include:

- `astronautwallpaper`
- `bluehorizon`
- `cobaltbloom`
- `glacierreflection`
- `midnightflow`
- `oceandusk`

These wallpapers are paired with matching theme metadata, and the system seeds them across supported desktops.

### 7. Stronger Boot Identity

Abora `v2` continues the boot branding work with:

- a styled live boot background
- a dedicated Limine background for installed systems
- refreshed GRUB theme styling for the live environment
- a clearer installed-system Limine path

The installed system is now centered around Limine as the newer bootloader direction for Abora `v2`.

### 8. Simpler Update and Recovery Commands

Abora `v2` keeps the NixOS rebuild model underneath, but presents it with simpler commands.

Installed systems support:

```sh
sudo nixos update
sudo nixos rollback
```

Shorter aliases also exist:

```sh
update
upgrade
rollback
```

These commands are meant to make the update and rollback story feel more like a distro feature and less like a manual Nix workflow.

### 9. Better Support and Test Tooling

Abora `v2` adds support and preflight tools that did not exist in the earlier project state.

Current tools include:

- `abora-support-report`
- `abora-hardware-test --with-report`

`abora-support-report` creates an archive with hardware and log information.

`abora-hardware-test` is a hardware-readiness pass for a real machine before someone spends time writing a USB and doing a bare-metal test.

It is not a replacement for real hardware booting, but it gives Abora a much better preflight story than before.

### 10. Improved Release and Build Workflow

Abora `v2` continues using Nix flakes and now has a clearer release pipeline around that base.

Important local commands include:

```sh
make iso
make qemc
make release
make metadata
make tinypm-package
make tinypm-image
```

The release bundle includes:

- the ISO
- release notes
- checksums
- a release manifest
- TinyPM V3 release packaging

## What Changed From v1

The `v2` era is not just a version bump.

It changes the shape of the project.

### Installer Direction Changed

Earlier Abora work still leaned on separate helper apps and a simpler boot-to-install path.

Abora `v2` folds the welcome/setup experience into the installer itself.

That means:

- `Abora Welcome` and `Abora Center` are no longer the main user-facing path before install
- the installer itself now owns the guided flow
- starter apps and optional GitHub setup are part of installation instead of bolted on afterward

### Desktop Scope Expanded

`v1` was more about getting the system installed and branded.

`v2` is broader:

- more desktop profiles
- more consistent defaults
- more attention to first login behavior
- better wallpaper and theme seeding

### Bootloader Work Moved Forward

`v2` moves installed Abora systems toward Limine and continues refining the live boot visuals instead of staying on a plain default boot flow.

### Updates and Recovery Became More Important

The `v2` direction treats update and rollback as first-class user features.

That is a major step in making Abora feel more like a real desktop distro and less like “just a NixOS config project.”

### Hardware and Support Tooling Improved

Abora `v2` now includes:

- a hardware summary path inside the installer
- a support-report generator
- a hardware-readiness tester

That gives the project a much better testing and support story than `v1`.

## New and Updated Docs

Abora now has a much larger documentation set than the earlier project state.

### Core Repo Docs

- `README.md`
- `RELEASE_NOTES.md`
- `SECURITY.md`
- `CONTRIBUTING.md`

### Test and Release Docs

- `docs/install-checklist.md`
- `docs/hardware-testing.md`
- `docs/release-checklist.md`
- `docs/project-layout.md`
- `docs/roadmap.md`

### Wiki Docs

- `docs/wiki/Home.md`
- `docs/wiki/Installation.md`
- `docs/wiki/Updating-Abora.md`
- `docs/wiki/Building-Abora.md`
- `docs/wiki/Release-Guide.md`
- `docs/wiki/TinyPM-V3.md`
- `docs/wiki/FAQ.md`
- `docs/wiki/_Sidebar.md`

### This File

- `docs/wiki/Website-Docs-Draft.md`

This draft exists to keep the whole `v2` story in one file for website and public-doc planning.

## Current v2 Testing State

What is in good shape now:

- ISO builds
- desktop profile evaluation checks
- installer flow
- update and rollback commands
- support report generation
- hardware-readiness preflight testing
- VM-based install testing

What is still honest to say:

- wider bare-metal validation is still needed
- `v2.0.0-dev` is a development snapshot, not a finished stable release
- TinyPM V3 remains part of the wider Abora ecosystem, not the main `v2` boot or installer path

## Short Version

Abora `v2` is the point where the project starts acting less like a collection of NixOS customizations and more like a real operating system with:

- a guided installer
- broader desktop support
- dark-first theming
- curated wallpaper and app setup
- simpler update and rollback commands
- better support tooling
- stronger release and testing docs

That is the main shift from the `v1` era into the `v2` era.
