# ANIX v1

ANIX v1 is the Abora/NixOS profile manager.

It is meant to make common NixOS tasks approachable without hiding the real system underneath. ANIX edits a small `anix.nix` layer, snapshots `/etc/nixos`, and calls the normal NixOS rebuild tools.

## Core Commands

- `anix status`
- `anix profiles`
- `anix generations`
- `anix init`
- `anix show`
- `anix edit`
- `anix set <key> <value>`
- `anix diff nix [profile]`
- `anix test nix [profile]`
- `anix boot nix [profile]`
- `anix switch nix <profile> [--now]`
- `anix rollback nix [profile] [--now]`
- `anix save [message]`
- `anix gc old`
- `anix doctor`

## What ANIX Manages

- hostname
- timezone
- console and desktop keyboard layout
- Abora desktop profile
- Abora wallpaper
- optional system packages
- optional Nix trusted users
- optional scheduled Nix garbage collection
- local Git snapshots of `/etc/nixos`

## Safety Model

ANIX snapshots dirty config before risky operations, runs dry-builds before interactive switches, and keeps rollback on the standard NixOS generation path.

Use `anix switch nix <profile>` for a normal profile switch.
Use `anix boot nix <profile>` when you want the profile prepared for next boot without switching immediately.
Use `anix test nix <profile>` when you want a temporary activation.
