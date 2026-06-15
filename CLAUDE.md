# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Abora OS is a NixOS-based Linux distribution that wraps NixOS in a friendlier live image, installer TUI, and OS management CLI layer. The repo builds to a bootable ISO via Nix flakes. Current release: **DENALI 3.1.4**.

## Common Commands

```sh
make iso              # Build the ISO (requires nix with flakes)
make qemu             # Boot latest ISO in QEMU (graphical)
make qemu-fresh       # Delete old QEMU disk and boot ISO (clean install test)
make qemu-disk        # Boot the installed QEMU hard drive (post-install testing)
make qemu-serial      # Headless QEMU, output in terminal
make check            # Run repo script checks (syntax + runtime tests)
make check-desktops   # Validate all desktop profiles against nixpkgs
make preflight        # Full release preflight checks
make release          # Build ISO + TinyPM package + checksums + release notes
make metadata         # Refresh release metadata only (no ISO rebuild)
```

Direct script equivalents (same as Make targets):
```sh
./scripts/check-scripts.sh   # What `make check` runs
./scripts/check-desktops.sh  # What `make check-desktops` runs
./scripts/preflight.sh       # What `make preflight` runs
./scripts/rebuild-vm.sh      # Rebuild in the VM workspace
```

Before pushing any change, run `make check` — it validates bash syntax, executability, required file presence, git tracking, nix flake evaluation, and several ANIX/release-metadata runtime behaviors.

## Architecture

### Build System

`flake.nix` is the Nix entrypoint. It pins `nixpkgs/nixos-26.05`, exposes `nixosModules` (installed-base, anix), and produces the `abora-live` ISO. The only NixOS configuration used at build time is `nix/profiles/live.nix`.

`scripts/build-iso.sh` calls `nix build` targeting `#packages.x86_64-linux.iso` and copies the result to `out/iso/`.

Generated output goes in `out/` (never treat as source — it's gitignored).

### Nix Modules

- `nix/profiles/live.nix` — live ISO profile; defines all CLI wrappers (`abora`, `anix`, `abora-install`, etc.) as derivations pointing into `/etc/abora/`. This is where scripts are wired to system commands.
- `nix/modules/installed-base.nix` — installed Abora base module; installs scripts into `/etc/abora/` on a real system, looking up each script from the repo root with a local-override fallback pattern.
- `nix/modules/abora-options.nix` — Abora NixOS option declarations (`abora.hostname`, `abora.desktop`, etc.).
- `nix/modules/anix.nix` — ANIX NixOS module.

### Scripts Layer

All user-facing tools are shell scripts in `scripts/`. They are installed verbatim into the system — there is no compilation step. The live image's Nix derivations exec them via `bash /etc/abora/<script>.sh`.

Key scripts:

| Script | Purpose |
|---|---|
| `abora.sh` | Top-level dispatcher for all `abora <subcommand>` calls |
| `abora-installer.sh` | Omarchy-inspired Denali installer TUI (runs as root on the live image) |
| `abora-boot.sh` | Stage-one live boot handoff |
| `abora-desktop-profiles.sh` | Sourced library; `abora_desktop_config_block` / `abora_desktop_package_block` functions used by installer and check-desktops |
| `abora-session-setup.sh` | First-session desktop defaults |
| `anix.sh` | ANIX CLI — profile switching, rollback, snapshots, config management |
| `abora-ui.sh` | Shared UI primitives (colors, `abora_banner`, `abora_kv`, etc.) sourced by all other scripts |
| `build-iso.sh` | ISO build wrapper around `nix build` |
| `release-metadata.sh` | Generates checksums, release manifest, and release notes into `out/release/` |
| `run-qemu.sh` | QEMU runner — respects `ABORA_QEMU_FRESH`, `ABORA_QEMU_BOOT`, `ABORA_QEMU_NOGRAPHIC` |

### UI Library Convention

All scripts source `abora-ui.sh` (or `/etc/abora/ui.sh` on-system) for shared primitives. The env var `ABORA_UI_LIB` overrides the path — `check-scripts.sh` tests scripts in isolation by passing a non-existent path and verifying the fallback inline UI activates correctly.

### ANIX

`scripts/anix.sh` reads config from `ANIX_SYSTEM_CONFIG` (defaults to `/etc/nixos`) and writes settings to `anix.nix` in that directory. Profile names map to flake output names (e.g., `anix switch nix gaming` → `nixos-rebuild switch --flake /etc/nixos#gaming`). `ANIX_NO_SUDO=1` and `ANIX_ASSUME_YES=1` env vars are used in tests to bypass sudo and prompts.

### TinyPM

`vendor/tinypm/` is a vendored copy of TinyPM v4. It provides `grab`, `search`, `term`, `start`, `supdate`, and Abora/ANIX/Nix bridge commands. Packaging happens via `scripts/package-tinypm.sh` → `out/packages/`.

### Desktop Profiles

`scripts/abora-desktop-profiles.sh` is a sourced library (not a standalone script). It defines two functions per desktop: `abora_desktop_config_block` (NixOS service/session config) and `abora_desktop_package_block` (packages). The split is important — `check-scripts.sh` explicitly tests that config blocks do not contain `environment.systemPackages`.

### Installed System Config

After installation, user-facing config lives in `/etc/nixos/abora-local.nix`. The `abora config` command (backed by `scripts/abora-config.sh`) reads and modifies this file without requiring Nix knowledge. `user` and `disk` keys are intentionally read-only through that CLI.

## Key Conventions

- All scripts use `set -euo pipefail` and locate the repo root via `CDPATH= cd -- "$(dirname -- "$0")/.." && pwd`.
- The `out/` directory is generated — never commit files there.
- `VERSION` file drives the version string used everywhere (build, ISO filename, release metadata).
- Scripts must be executable (`chmod +x`) — `check-scripts.sh` enforces this.
- Desktop profile additions require changes in `abora-desktop-profiles.sh` (the library), `abora-installer.sh` (installer menu), `anix.sh` (`valid_desktops` array), and `nix/modules/installed-base.nix`.
