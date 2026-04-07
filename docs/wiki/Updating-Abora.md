# Updating Abora

Abora keeps the NixOS base, but gives installed systems a simpler update command.

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
- rebuilds the system
- migrates older installer-generated Abora installs into the current layout

## Notes

- this is meant for installed Abora systems
- it follows the Abora/NixOS flake-based path
- it is not the same thing as using classic NixOS channels by hand
