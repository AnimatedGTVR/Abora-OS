# Updating Abora

Abora keeps the NixOS base, but gives installed systems simpler update commands.

## Normal Update Command

On an installed Abora system, use:

```sh
sudo nixos update
```

Short aliases also work:

```sh
update
upgrade
```

## What It Does

The Abora update flow:

- syncs the latest Abora project files into `/etc/nixos/abora/`
- updates the local flake
- can offer a local ANIX snapshot before rebuilding
- rebuilds the system
- keeps older installer-generated Abora installs closer to the current layout

## Related Tools

- `abora doctor`: check system health
- `abora recovery`: rollback, rebuild, repair, and support actions
- `abora setup`: installed reconfiguration launcher
- `anix status`: show profile, generation, and snapshot state
- `anix save`: local `/etc/nixos` snapshot
- `anix diff nix <profile>`: preview profile changes
- `anix test nix <profile>`: test-activate a profile
- `anix rollback nix`: rollback through NixOS generations
- `tinypm sources`: show app/package source status

## Notes

- this is meant for installed Abora systems
- it follows the Abora/NixOS flake-based path
- it is not the same thing as using classic NixOS channels by hand

## Safer Update Habit

Before a larger update:

```sh
anix save "before update"
anix status
sudo nixos update
```

If the update is not good:

```sh
anix generations
anix rollback nix
```
