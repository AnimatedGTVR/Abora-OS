# Abora Development Guide

Abora OS is a NixOS-based distribution with a guided installer, desktop editions, and management tools. AnimatedGTVR leads project direction, architecture, review, and releases.

## Branches

- `stable`: tested releases
- `edge`: active development

Use short-lived branches for changes and target `edge`.

## Checks

```sh
make doctor
make check
make qemu-fresh
```

Use `make iso` for the default image, `make iso-all` for all editions, and `make release` only for release preparation.

## Boundaries

- `nix/`: system modules, live image, desktop profiles
- `scripts/install/`: installer and adoption
- `scripts/config/`: configuration and desktop tools
- `scripts/support/`: update, recovery, diagnostics, feedback
- `automation/abora_labs/`: experimental comparison framework
- `vendor/`: separately maintained bundled components

Keep Nix declarative, shell small, user-visible errors actionable, and destructive operations explicit. Preserve installation safety, logs, generations, and rollback. Update tests and documentation with behavior changes.
