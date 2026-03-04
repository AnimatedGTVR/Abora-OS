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

- add `airootfs` overlay files for users, sudo, and live session defaults
- add SDDM and Plasma session defaults to the live image
- decide how much of KDE Gear ships in the first ISO
- add installer strategy documentation
