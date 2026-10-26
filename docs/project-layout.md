# Project Layout

This is the quick map of the Abora OS repo for the Abora OS v4.2 Solstice release.

## Top Level

- `README.md`: main project overview
- `RELEASE_NOTES.md`: release notes source
- `VERSION`: current version string used by build and release tooling
- `LICENSE`: project license
- `Makefile`: command entrypoint for building, checking, QEMU testing, and releasing
- `flake.nix` and `flake.lock`: Nix flake entrypoint and pinned dependencies

## Architecture

Abora is six layers. Each lives in its own place, and a layer only calls the ones below it in this table.

| Layer | Where | Language | What it is |
| --- | --- | --- | --- |
| CLI | `scripts/core/anix.sh` (`anix`; `abora.sh` is its old name) | Shell | the one user-facing command; routes Abora system commands to their tools |
| GUI | `scripts/*/*-gui.py` (welcome, config, gaming, feedback) | Python (GTK4) | front-ends; every action is also a CLI command |
| Safety and recovery (ASA) | `scripts/safety/` (ABT), `scripts/support/` (doctor, recovery, support report) | Python | transactions, health checks and repairs ([ASA](wiki/ASA.md)) |
| Tools | `scripts/apps/`, `scripts/config/`, `scripts/support/abora-update.sh` | Shell, Python | apps, settings, desktops, updates |
| Installer | `scripts/install/` (the TUI, drawn with gum), `tools/abora-installer/` (launcher and disk engine: `abora-installer disk erase/existing/mount`) | Shell, Rust | live boot, install, adopt an existing NixOS |
| System config | `nix/` | Nix | the live ISO and the installed system |

Shared code today: `scripts/core/abora-ui.sh` for shell (UI, `abora_abt_prefix`) and
`scripts/support/abora_core.py` for Python (UI, redaction).

### Languages

Abora's tools are mostly shell and Python today. They are being split up by job, starting after 4.2:

| Language | Job | Rule of thumb |
| --- | --- | --- |
| **Rust** | anything that can damage the system: the installer's partitioning engine, ABT, `anix`'s config editing | if a bug could brick or wipe a machine, Rust |
| **Go** | anything that talks to the network or the user, and read-only diagnostics: the updater, the doctor's checks, the support report, plan validation, the installer's screens | otherwise, Go |
| **Nix** | system config | |
| **Shell** | glue only: wrappers at the old `/etc/abora/*.sh` paths, systemd units, one-line launchers | no logic, no data structures |
| **Python** | the existing GTK apps, until they are ported | no new tools |

Not used: C#/.NET (the two C# tools are replaced by Go), and Java/Kotlin (a JVM is too heavy for an installer or
recovery tool). Zig and C++ are allowed only where a job clearly needs them (for example Pancake, the desktop
environment planned for Abora). Isora is a separate project (a sandboxed language for game mods) and is not part of
the system.

Two constraints apply to every port. Systems already installed call tools by their old names (`/etc/abora/doctor.sh`,
`anix.sh`, ...), so each port keeps a thin shell wrapper at the old path. And a compiled tool has to be built, not
copied, so Abora needs a binary cache or users compile on `anix update`.

### Stable, new, and experimental

| Status | What |
| --- | --- |
| **Stable** | the installer TUI, the desktop profiles, `anix` config/profiles/snapshots/rollback, `abora update`, `abora apps`, the support tools |
| **New in 4.2** (alpha until the [release gate](next-release-plan.md#release-gate) passes) | `anix` as the one command, `anix package install`, the whole-system `anix doctor`, ABT transactions |
| **Experimental** (not part of the installed system unless chosen) | Abora Labs (`automation/abora_labs`, opt-in at install), `experiments/` (language comparisons, never shipped), ANIX v2 languages beyond ANIX Native and ModuCPP |

## Main Directories

### `assets/`

Visual and branding files used by the live image, boot flow, wallpapers, and desktop defaults.

Important subfolders:

- `assets/bootloader/`
- `assets/plymouth/`
- `assets/wallpapers/collection/`
- `assets/wallpaper-themes/`
- `assets/Effects/`

Important files:

- `assets/abora-title.txt`
- `assets/fastfetch-config.jsonc`
- `assets/fastfetch-logo.txt`

### `docs/`

Project docs for development, installation, release work, and wiki publishing.

- `docs/install-checklist.md`
- `docs/hardware-testing.md`
- `docs/release-checklist.md`
- `docs/bug-report-template.md`
- `docs/roadmap.md`
- `docs/wiki/`

### `nix/`

NixOS configuration used to build the live ISO and installed system modules.

Important paths:

- `nix/profiles/live.nix`: live ISO profile, live boot service, bundled installer assets
- `nix/modules/installed-base.nix`: installed Abora base module
- `nix/modules/abora-options.nix`: Abora option layer used by installed configs
- `nix/modules/desktops/`: one module per supported desktop or window manager
- `nix/modules/anix.nix`: ANIX NixOS module
- `nix/pkgs/`: authoritative package definitions loaded by the flake and installed-system overlay

Desktop support is split by environment:

- `nix/modules/desktops/default.nix`: imports the desktop module set
- `nix/modules/desktops/common.nix`: shared helpers for active desktop checks, keyboard layout, autologin, and wallpaper URIs
- `nix/modules/desktops/gnome.nix`, `plasma.nix`, `hyprland.nix`, `mangowm.nix`, etc.: per-desktop configuration

Add a desktop by adding a module under `nix/modules/desktops/`, importing it from `default.nix`, adding the option value to `nix/modules/abora-options.nix`, and updating `scripts/abora-desktop-profiles.sh` so the installer/reconfiguration path matches the module behavior.

Packages are defined once under `nix/pkgs/` and loaded with flake-relative `callPackage` imports from `flake.nix`. Installed systems copy those same package files into `/etc/nixos/abora/pkgs/`, where `installed-base.nix` uses the same `callPackage` pattern. Do not duplicate package derivations in modules.

### `scripts/`

Shell scripts for the live environment, installer, installed commands, ISO builds, release metadata, checks, and QEMU booting.

Important files:

- `scripts/abora-boot.sh`: live stage-one boot handoff
- `scripts/abora-installer.sh`: Omarchy-inspired installer and reconfiguration TUI
- `scripts/abora-setup-launcher.sh`: installed desktop launcher for `abora setup`
- `scripts/abora-setup.desktop`: installed desktop entry
- `scripts/abora-desktop-profiles.sh`: supported desktop profile definitions
- `scripts/abora-session-setup.sh`: first-session defaults
- `scripts/support/`: doctor, recovery, welcome, support report, full check, and hardware test (Python)
- `scripts/safety/`: ABT, the transaction engine of ASA (`abora-abt`)
- `scripts/check-scripts.py`: repo script and runtime sanity checks
- `scripts/check-all-files.py`: broad syntax, links, YAML, JSON, and docs sweep
- `scripts/check-desktops.py`: evaluates every supported desktop profile
- `scripts/build-iso.py`: ISO-only build path
- `scripts/release-metadata.py`: checksums, manifest, and release notes
- `scripts/run-qemu.py`: QEMU ISO, fresh-disk, disk-only, and serial helpers

### `vendor/`

Vendored external code that Abora uses directly.


## Generated Output

### `out/`

Generated build output. Do not treat this as source.

It can contain:

- `out/iso/`: built ISO files
- `out/packages/`: the ANIX release tarball and other generated packages
- `out/release/`: checksum files, release manifests, and generated release notes
- `out/qemu/`: QEMU disks and firmware state
- `out/logs/`: QEMU serial logs and build logs
- `out/nix/`: Nix build result symlinks

## Development Workflow

Run these before opening a PR:

```sh
make check
make check-all
make check-desktops
nix flake check --no-build --no-write-lock-file
nix build --no-link .#nixosConfigurations.abora-live.config.system.build.toplevel
```

GitHub Actions run the same core gates: script checks, Nix formatting, targeted ShellCheck, flake evaluation, and a live-system toplevel build. Full ISO/release builds remain in the dedicated ISO workflows.
