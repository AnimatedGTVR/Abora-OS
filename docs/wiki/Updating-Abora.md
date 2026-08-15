# Updating Abora

Abora uses a flake-based update flow for installed systems.

## Normal Update

On an installed Abora system, run:

```sh
sudo abora update
```

These aliases run the same updater:

```sh
update
upgrade
abora-update
nixos update
```

## Checking Without Updating

To see whether an update is available without fetching anything or touching the system:

```sh
abora update --check
```

This resolves your channel and compares it against the installed version, same as a normal update would, but stops there — no rebuild, no root needed. `abora welcome-gui` uses this under the hood for its status card.

If update checks fail with network, DNS, or cache errors, run:

```sh
abora network
abora support-report
```

## What The Updater Does

The update helper:

- resolves the selected Abora channel
- fetches the latest Abora project files into `/etc/nixos/.abora-upstream`
- syncs the installed Abora files under `/etc/nixos/abora/`
- optionally offers a local ANIX snapshot before rebuilding
- updates the flake inputs
- runs `nixos-rebuild switch`

## Channels

Abora OS v4 Everest is currently an alpha release line, so new installs
default to `unstable`, which tracks the `edge` branch. `stable` remains
available for final tagged releases and older installed systems.

Show the current channel:

```sh
abora channel
```

List channels:

```sh
abora channel list
```

Switch channels:

```sh
sudo abora channel set stable
sudo abora channel set demo
sudo abora channel set unstable
```

- `stable` tracks the latest tagged Abora release
- `demo` tracks tagged demo/dev builds for the installed release line
- `unstable` tracks the `edge` branch and is the v4 Everest alpha default

Abora's development branch is `edge`. If an older config or test command asks
for `main`, use `edge` instead:

```sh
sudo ABORA_REPO_REF=edge abora update
```

## Pre-Alpha Builds

Pre-alpha builds are unfinished development versions intended for testing and feedback only. They may fail to boot, break applications, lose data, or require manual recovery.

Preview the selected pre-alpha ref without changing the system:

```sh
sudo abora install pre-alpha --dry-run
```

Install the default pre-alpha ref after the risk prompt:

```sh
sudo abora install pre-alpha
```

Install a specific branch or tag:

```sh
sudo abora install pre-alpha --ref my-test-branch
```

This is a one-shot path. It does not save your update channel as pre-alpha, and it requires typing `I ACCEPT THE RISK` exactly.

## Safer Update Habit

Before a larger update:

```sh
anix save "before update"
anix status
sudo abora update
```

## Rollback

If the update is not good:

```sh
sudo abora rollback
```

Or with ANIX:

```sh
anix generations
anix rollback nix
```

## Related Tools

- `abora doctor`: check system health
- `abora recovery`: rollback, rebuild, repair, and support actions
- `abora setup`: installed reconfiguration launcher
- `anix status`: show profile, generation, and snapshot state
- `anix save`: local `/etc/nixos` snapshot
- `anix diff nix <profile>`: preview profile changes
- `anix test nix <profile>`: test-activate a profile
- `tinypm sources`: show app/package source status

## Notes

- This is for installed Abora systems.
- It does not use classic manual NixOS channel updates.
- If the updater fails while fetching files, check the reported git error first.
