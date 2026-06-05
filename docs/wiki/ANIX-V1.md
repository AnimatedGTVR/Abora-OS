# ANIX v1

ANIX v1 is the Abora/NixOS profile manager.

It is meant to make common NixOS tasks approachable without hiding the real system underneath. ANIX edits a small `anix.nix` layer, snapshots `/etc/nixos`, and calls the normal NixOS rebuild tools.

## Mental Model

ANIX does three things:

- keeps beginner-facing settings in `/etc/nixos/anix.nix`
- snapshots `/etc/nixos` with Git before risky changes
- wraps `nixos-rebuild` with friendlier commands

ANIX is not a replacement for NixOS. It is a safer front door for Abora and other NixOS-family installs.

## First Run

```sh
anix quickstart
anix status
anix doctor
```

`anix quickstart` creates the ANIX config if it is missing and prepares local snapshot history.

On a desktop session, you can also start the graphical helper:

```sh
anix --gui
```

The GUI uses Zenity when available and falls back to a terminal menu when launched outside a graphical session.

## Core Commands

| Command | Purpose |
|---|---|
| `anix status` | Show config, flake, generation, Git, and snapshot state |
| `anix --gui` | Open the graphical ANIX launcher, with terminal fallback |
| `anix quickstart` | Create ANIX config and prepare local snapshots |
| `anix docs` | Show local documentation paths |
| `anix profiles` | List flake profiles under `nixosConfigurations` |
| `anix generations` | Show recent system generations |
| `anix init` | Create `/etc/nixos/anix.nix` |
| `anix show` | Show current ANIX settings |
| `anix edit` | Open `anix.nix` in `$EDITOR` or `$VISUAL` |
| `anix set <key> <value>` | Change a simple ANIX setting |
| `anix diff nix [profile]` | Dry-build and compare package closure changes |
| `anix test nix [profile]` | Test-activate a profile without making it boot default |
| `anix boot nix [profile]` | Build a profile for the next boot |
| `anix switch nix <profile> [--now]` | Switch to a named flake profile |
| `anix rollback nix [profile] [--now]` | Roll back generation or switch to a profile |
| `anix save [message]` | Save a local Git snapshot |
| `anix gc old` | Remove old generations after confirmation |
| `anix doctor` | Check the Nix/Abora management layer |
| `anix doctor --fix` | Create missing safe basics |

## Settings

These keys can be changed with `anix set`:

```sh
anix set hostname my-pc
anix set timezone America/New_York
anix set keyboard us
anix set keyboard.xkb us
anix set desktop hyprland
anix set wallpaper Daytime-MNT.jpg
```

## ANIX Nix Options

Inside `anix.nix`, ANIX v1 supports:

```nix
anix.enable = true;
anix.hostname = "my-pc";
anix.timezone = "America/New_York";
anix.keyboard.console = "us";
anix.keyboard.xkb = "us";
anix.desktop = "gnome";
anix.wallpaper = "Daytime-MNT.jpg";
anix.packages = with pkgs; [ git curl vim ];
anix.trustedUsers = [ "root" "@wheel" ];
anix.autoOptimiseStore = true;
anix.garbageCollect.enable = true;
anix.garbageCollect.dates = "weekly";
anix.garbageCollect.options = "--delete-older-than 14d";
```

## Profile Workflow

List available profiles:

```sh
anix profiles
```

Preview changes:

```sh
anix diff nix gaming
```

Temporarily test a profile:

```sh
anix test nix gaming
```

Prepare a profile for next boot:

```sh
anix boot nix gaming
```

Switch now:

```sh
anix switch nix gaming
```

Skip the confirmation prompt:

```sh
anix switch nix gaming --now
```

## Rollback Workflow

Use the previous generation:

```sh
anix rollback nix
```

Switch back to a named profile:

```sh
anix rollback nix stable
```

Show recent generations:

```sh
anix generations
```

## Snapshots

ANIX snapshots are local Git commits in `/etc/nixos`.

```sh
anix save "before gaming profile"
```

Snapshots stay local by default. To push after each snapshot:

```sh
anix config set snapshots.push true
```

ANIX warns when it sees likely secrets. Real secrets should live in `sops-nix`, `agenix`, or another secrets system.

## Recovery

When something feels wrong:

```sh
anix status
anix doctor
anix generations
anix rollback nix
```

If basics are missing:

```sh
anix doctor --fix
```

For broader Abora repair options:

```sh
abora recovery
```

## Environment Overrides

Useful for testing or advanced installs:

| Variable | Purpose |
|---|---|
| `ANIX_SYSTEM_CONFIG` | Override `/etc/nixos` |
| `ANIX_CONFIG_FILE` | Override the ANIX config path |
| `ANIX_FLAKE_CONFIG_NAME` | Override the default flake profile |
| `ANIX_ASSUME_YES=1` | Skip confirmations |
| `ANIX_NO_SUDO=1` | Do not escalate through sudo |
| `ANIX_GENERATION_LIMIT` | Limit generation list output |

## Release Checks

Maintainers should run:

```sh
./scripts/check-scripts.sh
./scripts/check-desktops.sh
vendor/tinypm/scripts/e2e-smoke.sh
```
