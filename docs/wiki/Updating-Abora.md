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
- `anix save`: local `/etc/nixos` snapshot
- `anix rollback nix`: rollback through NixOS generations

## Notes

- this is meant for installed Abora systems
- it follows the Abora/NixOS flake-based path
- it is not the same thing as using classic NixOS channels by hand
