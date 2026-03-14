# Calamares Plan

Abora is moving the visible installer path to Calamares while keeping the existing
Abora branding and package defaults.

## Current status

- GUI-first launcher exists now
- local `calamares` package exists under `packages/calamares/`
- Abora Calamares config package exists under `packages/abora-calamares-config/`
- the remaining work is validation and config hardening

## Migration steps

1. Validate that the local Calamares package builds in CI and boots in the ISO.
2. Validate that the Abora branding package loads cleanly in the live installer.
3. Test partitioning, users, bootloader, and post-install integration.
4. Remove any remaining temporary fallback language from user-facing docs once Calamares passes validation.
