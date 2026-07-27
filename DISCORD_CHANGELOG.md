# Abora OS 2026.7.27 Changelog

Release-day polish for Abora OS 2026.7.27: the MINT installer, graphical system tools, ANIX v2, TinyPM v4, update checks, and multi-edition desktop support.

## Installer

- The default guided installer is now **MINT**, a Go/Bubble Tea front-end that hands the confirmed install plan to the existing bash installer as its backend — `abora-installer` (the bash-only flow) is still there if you want it, now reachable via `abora-install --batch`
- Every installer screen can be backed out of with `Esc` or a `← Back` list entry, previous answers preserved, instead of the old one-way linear flow
- "Step X of Y" progress indicator on every screen
- Timezone selection is now region-first (Americas, Europe, Africa, Asia, Australia & Oceania, UTC), then a fuzzy-searchable list of the real IANA zones in that region — states/regions with more than one zone (Indiana's eight, for example) all show up individually instead of just one
- `abora update --check` — see whether an update is available without installing it

## New: Graphical Tools

- `abora welcome-gui` — status card (desktop, wallpaper, update channel, Flathub), update check/install, and the same quick actions as `abora welcome`. Opens once automatically on first desktop login, always reachable afterward
- `abora config-gui` — graphical settings editor for hostname, timezone, keyboard, desktop, wallpaper, and GPU driver; thin front-end over `abora config`, so nothing it does is GUI-exclusive
- Both are GTK4/libadwaita apps that force a light theme by default

---

# Abora OS v4 Foundation

Abora OS 2026.7.27 is the multi-edition release: five ready-made ISOs, a second-generation ANIX with pluggable configuration languages, and real GPU driver support.

## Multi-Edition ISOs

- Five editions, each defaulting to a different desktop: Cosmic, Hyprland, GNOME, KDE, and Other (console-first, pick from all 23 profiles)
- Every edition still installs the full desktop matrix — the edition only decides the live session's default
- `make iso-all` builds every edition for release validation

## GPU Driver Support

- New `abora.gpu` option: `nouveau`, `nvidia`, `nvidia-open`, `amdgpu`, `intel`, or `none`
- Installer detects your GPU vendor via `lspci`; NVIDIA hardware defaults to the license-free `nouveau` driver, with proprietary `nvidia`/`nvidia-open` as explicit opt-ins
- Change anytime: `abora config set gpu nvidia && abora config apply`
- `abora-hardware-test` points at the GPU step when it detects NVIDIA hardware

## ANIX v2 — Pluggable Configuration Languages

- Configs can now be written in ANIX Native (`.anix`), MKO (`.mko`, the MAKO project's language), or ModuCPP (`.moducpp`)
- Every adapter resolves to the same Plan JSON, applied as one transaction
- `anix language list` / `anix language use` / `anix run` / `anix diff-plan` / `anix validate-plan` / `anix apply-plan`
- `anix diff-plan` labels each setting ADD, CHANGE, or SAME before you apply anything, regardless of source language

## Carried Forward From DENALI 3.14

- 23 desktop environments, evaluated in CI via `make check-desktops`
- 7 starter app bundles at install time
- TinyPM v4 app layer (`grab`, `tinypm sources`, `tinypm system`, `tinypm repair`)
- Omarchy-inspired TUI installer, Limine bootloader, Plymouth splash, Abora wallpaper pack
- NetworkManager, Bluetooth, ModemManager, redistributable firmware, Intel/AMD microcode
- Flathub added automatically on first boot

---

# Abora OS DENALI 3.1.4 Changelog

Abora DENALI 3.1.4 is the installer, identity, and tooling release.

## Installer

- Rebuilt around an Omarchy-inspired TUI: large Abora wordmark, compact boxed UI, numbered menus
- Live install progress with log panel and elapsed timer
- Config validation runs before `nixos-install` — bad configs fail early
- Failed installs drop to a live shell with `/tmp/abora-install.log`
- Bootloader verified before declaring success
- QEMU install auto-powers off and guides users to boot with `make qemu-disk`

## Developer Tools

- Modularity game engine editor added to the Developer app bundle
- Available via `grab modularity` or selectable at install time in the Developer bundle
- Backed by a custom Nix derivation with bundled PhysX, Vulkan, and Mono support

## Desktops

- 22 desktop environments selectable at install time
- COSMIC Desktop added to the supported matrix
- MangoWM added — lightweight Wayland compositor (dwm-style, wlroots-based)
- Desktop profile matrix fully evaluated in CI with `make check-desktops`
- Dark-first defaults and Abora wallpapers applied across all sessions

## Branding

- Abora wordmark in the installer header
- Limine bootloader with Abora branding on installed systems
- Plymouth splash theme
- Abora wallpaper pack: Mountain Day/Night, Ocean Dusk, Blue Horizon, Astronaut, Glacier Reflection
- Fastfetch with Abora logo on first shell open
- Papirus Dark icon defaults
- zsh with Spaceship prompt

## ANIX v1

- `anix status` — profile, generation, and snapshot state
- `anix quickstart` — first-run init and setup
- `anix profiles` / `anix generations` — see what is available
- `anix diff nix <profile>` — preview changes before applying
- `anix test nix <profile>` — temp-activate a profile
- `anix boot nix <profile>` — queue for next boot
- `anix switch nix <profile>` — apply now
- `anix rollback nix` — roll back a generation
- `anix save` — local Git snapshot of `/etc/nixos`
- `anix doctor` / `anix doctor --fix` — health checks and auto-repair
- `anix set` / `anix apply` — friendly config edits without touching Nix
- `anix --gui` — graphical helper via zenity

## TinyPM v4

- First-class Abora, ANIX, and NixOS awareness
- `tinypm sources` — show native/Flatpak/Snap availability
- `tinypm system` — Abora/NixOS/ANIX bridge status
- `tinypm repair` — repair-focused doctor checks
- `tinypm anix <command>` / `tinypm abora <command>` — forward to ANIX or Abora
- Portable relative symlinks — no machine-local absolute paths

## System

- NetworkManager on in the live image with radio unblock at boot
- Bluetooth, ModemManager, and Blueman ready before install
- Redistributable firmware, Intel/AMD microcode, and common Wi-Fi/Ethernet/BT drivers included
- Flathub added automatically on first boot
- `sudo nixos update` / `rollback` / `update` / `upgrade` aliases on installed systems
- `abora config set` / `abora config apply` — change settings without editing Nix

## Testing

- `make check` — script syntax, executability, runtime ANIX behaviors
- `make check-desktops` — all desktop profiles evaluated against nixpkgs
- `make qemu-fresh` — clean install test
- `make qemu-disk` — installed system boot test

---

# Abora OS v2.5.0 Changelog

Abora v2.5 is a quality-of-life release focused on making the installed system easier to manage.

## New

- Added `abora welcome` for first-step status and quick actions.
- Added `abora doctor` to check Abora system health.
- Added `abora recovery` for rollback, rebuild, Flathub repair, and support reports.
- Added `abora desktop list` and `abora desktop set <profile>`.
- Added a top-level `abora` command router.
- Added a one-time first-shell welcome status after install.
- Added `make preflight` for release checks.

## ANIX

- Added profile switching:
  ```sh
  anix switch nix gaming
  ```
- Added rollback helpers:
  ```sh
  anix rollback nix
  anix rollback nix minimal
  ```
- Added local snapshots:
  ```sh
  anix save
  ```
- Added `anix doctor`.
- Added named flake profiles: `stable`, `minimal`, `gaming`, `creator`, `developer`.
- Snapshots stay local by default.
- ANIX warns before saving files that look like they may contain secrets.

## Apps

- App catalog is now 53 apps across 6 categories.
- New Gaming category: Steam, Lutris, Heroic, Bottles, MangoHud, GameMode.
- New System category: GParted, Disks, Timeshift, Flameshot, btop, Mission Center.
- Added more picks like Chromium, Bitwarden, Discord, Slack, Zoom, RawTherapee, Zed, tmux, Alacritty, Ghostty, Lazygit, and Docker.

## System

- Flatpak is enabled by default.
- Flathub is added automatically on first boot when networking is available.
- Updates can track `stable` or `unstable`.
- Updates now offer to save an ANIX snapshot before rebuilding.
- Abora tools now share the same terminal UI style.

## Testing

- Run `make preflight` before release.
- Hardware testing should cover `abora welcome`, `abora doctor`, `abora recovery`, `abora desktop`, `anix switch`, and `anix rollback`.
