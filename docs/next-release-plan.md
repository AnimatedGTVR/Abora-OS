# Next Release Plan: v4.2 Solstice

Goal: make Abora easier to maintain and safer to recover.

## Required work

- define one clear role for Abora, ANIX, TinyPM, and Labs
- consolidate shared configuration, logging, hardware detection, and recovery logic
- improve `abora doctor` with useful explanations and safe repair suggestions
- preserve logs and exact Nix failures when installation or update fails
- test automatic, manual, and existing-partition installation
- test update, failed-update rollback, desktop selection, networking, and GPU setup
- remove outdated documentation and mark experiments clearly

## Release gate

All main ISOs must build and boot. At least one clean installation per main edition must reach first boot, pass `abora doctor`, update successfully, and roll back successfully. Known limitations must be documented before release.
