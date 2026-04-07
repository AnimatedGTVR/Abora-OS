# TinyPM V3

TinyPM V3 is still part of the wider Abora ecosystem, but it is separate from the main `v2.0.0-dev` boot and installer flow.

## What It Is

TinyPM V3 is a beginner-friendly package wrapper powered by Parcel.

Main commands:

- `grab`
- `tinypm`
- `Parcel --version`
- `syspm`

## Project Location

The vendored repo inside Abora lives here:

`vendor/tinypm`

## Current NixOS Reality

TinyPM does work on NixOS, but not as a full declarative system-package manager.

Right now it is better understood as a user-side tool that can work with the Nix backend, rather than a full replacement for editing declarative NixOS configuration.

## Local Checks

To check the current repo copy:

```sh
cd /home/animated/abora-os
vendor/tinypm/tinypm --version
vendor/tinypm/scripts/e2e-smoke.sh
```
