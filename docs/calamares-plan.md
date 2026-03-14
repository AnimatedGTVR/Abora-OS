# Calamares Plan

Abora is moving the visible installer path to Calamares while keeping the existing
Abora branding and package defaults.

## Current status

- GUI-first launcher exists now
- standard repo `calamares` package is used in the ISO package list
- Abora Calamares config package exists under `packages/abora-calamares-config/`
- the remaining work is validation and config hardening

## Migration steps

1. Validate that the standard Calamares package boots in the ISO.
2. Validate that the Abora branding package loads cleanly in the live installer.
3. Test partitioning, users, bootloader, and post-install integration.
4. Remove any remaining temporary fallback language from user-facing docs once Calamares passes validation.
