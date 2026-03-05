# Abora OS Roadmap

## Phase 1

- produce a bootable Arch-based live ISO with Abora branding
- keep the package set small and easy to reason about
- define a stable KDE Plasma live environment baseline

## Phase 2

- add live-user defaults, autologin, and display-manager wiring
- refine Plasma defaults, theming, and first-run experience
- package Abora branding, configs, and desktop defaults cleanly

## Phase 3

- create an Abora package repository
- split packages into base, desktop, branding, and developer bundles
- automate ISO builds in CI

## Immediate next tasks

- validate the new archinstall-based installer flow end to end
- confirm installed systems receive Abora defaults and TinyPM correctly
- decide whether to stay with archinstall or replace it with a Calamares-based GUI later
- decide how much of KDE Gear ships in the first ISO
