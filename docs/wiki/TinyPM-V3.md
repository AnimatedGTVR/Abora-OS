# TinyPM V3

TinyPM V3 is part of the wider Abora ecosystem.

In the v2.5 and v3 Denali work, TinyPM is vendored into the repo and packaged with Abora release bundles. Installed systems expose the Abora-flavored commands when the installed base module is present.

## Main Commands

- `grab`
- `search`
- `term`
- `start`
- `supdate`
- `tinypm`

## Project Location

The vendored repo inside Abora lives here:

`vendor/tinypm`

## Current NixOS Reality

TinyPM works as a friendlier package/app command layer. It is not a full replacement for declarative NixOS configuration.

For permanent system-level changes, Abora still uses NixOS modules, the local flake, ANIX helpers, and `sudo nixos update`.

## Local Checks

To check the current repo copy:

```sh
cd /home/animated/abora-os
vendor/tinypm/tinypm --version
```

Release packaging is handled by:

```sh
make tinypm-package
```
