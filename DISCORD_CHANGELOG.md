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
