# Abora OS v3.0.0 Denali Changelog

Abora v3 Denali is the installer, identity, and tooling release.

## Installer

- Rebuilt around an Omarchy-inspired TUI: large Abora wordmark, compact boxed UI, numbered menus
- Live install progress with log panel and elapsed timer
- Config validation runs before `nixos-install` — bad configs fail early
- Failed installs drop to a live shell with `/tmp/abora-install.log`
- Bootloader verified before declaring success
- QEMU install auto-powers off and guides users to boot with `make qemu-disk`

## Desktops

- 21 desktop environments selectable at install time
- COSMIC Desktop added to the supported matrix
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

- App catalog is now 52 apps across 6 categories.
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
