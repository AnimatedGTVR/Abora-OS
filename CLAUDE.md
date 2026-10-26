# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Abora OS is a NixOS-based Linux distribution that wraps NixOS in a friendlier live image, installer TUI, and OS management CLI layer. The repo builds to a bootable ISO via Nix flakes. Current development release: **SOLSTICE 4.2**.

## Branch Policy

**NEVER create a new long-lived branch.** Abora OS runs on exactly two branches:

1. **`stable`** — only for changes that have been completely tested and are believed fixed, even if some edge cases remain unknown. This is what ships.
2. **`edge`** — nightly/untested pushes. This is the newest code, not yet verified.

Every change lands on one of these two. Short-lived feature/fix branches may still be used for a single in-progress change, but merge them into `edge` (or `stable` once fully verified) and delete them immediately after — never leave a third branch sitting around, and never treat one as a persistent parallel line of development.

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
make release          # Build ISO + ANIX package + checksums + release notes
make metadata         # Refresh release metadata only (no ISO rebuild)
```

Direct script equivalents (same as Make targets):
```sh
./scripts/check-scripts.py   # What `make check` runs
./scripts/check-desktops.py  # What `make check-desktops` runs
./scripts/preflight.py       # What `make preflight` runs
./scripts/rebuild-vm.py      # Rebuild in the VM workspace
```

Before pushing any change, run `make check` — it validates bash syntax, executability, required file presence, git tracking, nix flake evaluation, and several ANIX/release-metadata runtime behaviors.

## Architecture

### Build System

`flake.nix` is the Nix entrypoint. It pins `nixpkgs/nixos-26.05`, exposes `nixosModules` (installed-base, anix), and produces the `abora-live` ISO. The only NixOS configuration used at build time is `nix/profiles/live.nix`.

`scripts/build-iso.py` calls `nix build` targeting `#packages.x86_64-linux.iso-<edition>` and copies the result to `out/iso/`.

Generated output goes in `out/` (never treat as source — it's gitignored).

### Nix Modules

- `nix/profiles/live.nix` — live ISO profile; defines all CLI wrappers (`abora`, `anix`, `abora-install`, etc.) as derivations pointing into `/etc/abora/`. This is where scripts are wired to system commands.
- `nix/modules/installed-base.nix` — installed Abora base module; installs scripts into `/etc/abora/` on a real system, looking up each script from the repo root with a local-override fallback pattern.
- `nix/modules/abora-options.nix` — Abora NixOS option declarations (`abora.hostname`, `abora.desktop`, etc.).
- `nix/modules/anix.nix` — ANIX NixOS module.

### Scripts Layer

User-facing tools are shell or Python scripts in `scripts/`. They are installed verbatim into the system — there is no compilation step. The live image's Nix derivations exec them via `bash /etc/abora/<script>.sh`, or `python3` for the Python ones. The support tools in `scripts/support/` (doctor, recovery, welcome, support-report, check-full, hardware-test) are Python but are installed under their old `/etc/abora/*.sh` names, so 4.0 systems can still `abora update` (see `scripts/README.md`); their tests are `scripts/support/tests/support.test.py`.

Key scripts:

| Script | Purpose |
|---|---|
| `abora.sh` | Top-level dispatcher for all `abora <subcommand>` calls |
| `abora-installer.sh` | Omarchy-inspired installer TUI (runs as root on the live image) |
| `abora-boot.sh` | Stage-one live boot handoff |
| `abora-desktop-profiles.sh` | Sourced library; `abora_desktop_config_block` / `abora_desktop_package_block` functions used by installer and check-desktops |
| `abora-session-setup.sh` | First-session desktop defaults |
| `anix.sh` | ANIX CLI — profile switching, rollback, snapshots, config management |
| `abora-ui.sh` | Shared UI primitives (colors, `abora_banner`, `abora_kv`, etc.) sourced by all other scripts |
| `build-iso.py` | ISO build wrapper around `nix build` |
| `release-metadata.py` | Generates checksums, release manifest, and release notes into `out/release/` |
| `run-qemu.py` | QEMU runner — respects `ABORA_QEMU_FRESH`, `ABORA_QEMU_BOOT`, `ABORA_QEMU_NOGRAPHIC` |

### UI Library Convention

All shell scripts source `abora-ui.sh` (or `/etc/abora/ui.sh` on-system) for shared primitives; the Python support tools each carry an identical inline port of the ones they use. The env var `ABORA_UI_LIB` overrides the path — the test suites run scripts in isolation by passing a non-existent path and verifying the fallback inline UI activates correctly.

### ANIX

`scripts/anix.sh` reads config from `ANIX_SYSTEM_CONFIG` (defaults to `/etc/nixos`) and writes settings to `anix.nix` in that directory. Profile names map to flake output names (e.g., `anix switch nix gaming` → `nixos-rebuild switch --flake /etc/nixos#gaming`). `ANIX_NO_SUDO=1` and `ANIX_ASSUME_YES=1` env vars are used in tests to bypass sudo and prompts.

### Vanta tools

`tools/abora-update/` is the Vanta core of `abora update` (release channel resolution and the downgrade guard so far), called by `scripts/abora-update.sh` through the CLI the removed C# `abora-update-resolver` had. `tools/abora-update-resolver/` and `nix/pkgs/abora-update-resolver*` are placeholders kept only because 4.0/4.1 updaters require those paths (`scripts/release/legacy-required-paths.txt`); don't delete them. It runs on the Vanta interpreter packaged in `nix/pkgs/vanta.nix` (pinned to a Vanta commit) and ships as `nix/pkgs/abora-update.nix`. Unit tests: `vanta run tools/abora-update/tests.vanta` (also run by `make check` when a new-enough Vanta is found).

### Plan tool

`tools/abora-plan-tool/` (Rust, rewritten from C# in 4.2 with the same name and CLI) validates ANIX Plan JSON and turns `.anix` files into it for `anix validate-plan/diff-plan/apply-plan/run`. `make check` builds it with cargo for the anix suite.

### Packages (TinyPM was removed in 4.2)

`anix package install/uninstall/search/upgrade/try/keep` installs nixpkgs packages into the user's Nix profile with `--inputs-from /etc/nixos`, so they use the system's pinned nixpkgs and need no config edit or rebuild. `anix package add/remove` stays the declarative path (`anix.packages` in `anix.nix`). Tests use `ANIX_NIX_BIN` to point at a fake `nix`. `anix.tinypm.*` options remain as no-ops so pre-4.2 `anix.nix` files still evaluate. Docs: `docs/wiki/Packages.md`.

### ASA / ABT (4.2)

`scripts/safety/abora-abt.py` (installed as `/etc/abora/abt.py`, command `abora-abt`) runs a system change as a transaction: PLAN → VALIDATE → SNAPSHOT → APPLY → VERIFY → ROLLBACK on failure. Shell tools get it through `abora_abt_prefix` in `abora-ui.sh` (empty when `abora-abt` is absent or `ABORA_NO_ABT=1`); anix, abora-config, abora-apps and the updater's final switch use it. Tests: `scripts/safety/tests/abt.test.py` (fake system profile). Docs: `docs/wiki/ASA.md`.

### Doctor (4.2)

`anix doctor` on Abora is `scripts/support/abora-doctor.py`: a list of checks producing findings (id, area, status, explanation, optional repair), `--json`, `repair [<id>]`. It runs anix.sh's own config checks with `ANIX_DOCTOR_LAYER_ONLY=1`; on plain NixOS those are the whole doctor.

### Desktop Profiles

`scripts/abora-desktop-profiles.sh` is a sourced library (not a standalone script). It defines two functions per desktop: `abora_desktop_config_block` (NixOS service/session config) and `abora_desktop_package_block` (packages). The split is important — `scripts/config/tests/desktop.test.sh` explicitly tests that config blocks do not contain `environment.systemPackages`.

### Installed System Config

After installation, user-facing config lives in `/etc/nixos/abora-local.nix`. The `abora config` command (backed by `scripts/abora-config.sh`) reads and modifies this file without requiring Nix knowledge. `user` and `disk` keys are intentionally read-only through that CLI.

## Key Conventions

- **Languages:** new system tools are not written in shell. Rust is for anything that can damage the system (disks, boot, generations, config writes), Go for network, diagnostics and user-facing screens, shell for glue only. No new C#/.NET. See `docs/project-layout.md`.

- All scripts use `set -euo pipefail` and locate the repo root via `CDPATH= cd -- "$(dirname -- "$0")/.." && pwd`.
- The `out/` directory is generated — never commit files there.
- `VERSION` file drives the version string used everywhere (build, ISO filename, release metadata).
- Scripts must be executable (`chmod +x`) — `make check` enforces this.
- Desktop profile additions require changes in `abora-desktop-profiles.sh` (the library), `abora-installer.sh` (installer menu), `anix.sh` (`valid_desktops` array), and `nix/modules/installed-base.nix`.
