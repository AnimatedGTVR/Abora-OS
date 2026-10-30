# Abora Updater Remake

The v4.2 updater should replace the current shell implementation with one small, testable updater. Shell may
remain as a compatibility launcher for systems upgrading from v4.0 or v4.1.

## Public behavior

- Both `abora update` and `anix update` invoke the same updater.
- **Stable** follows signed, immutable release tags.
- **Edge** follows nightly builds from the `edge` branch.
- Old `unstable`, `demo`, and `dev` channel values migrate to Edge with a clear message.
- Downgrades require an explicit release selection and confirmation.
- Every update has check, download, verify, build, activate, verify, and rollback phases.

## Safety requirements

- Download into a staging directory without changing `/etc/nixos`.
- Verify the repository owner, selected ref, release manifest, and expected files before installation.
- Never silently fall from Stable to Edge when tags cannot be fetched.
- Build the new system before replacing installed Abora files.
- Make file installation atomic and preserve user-owned configuration.
- Activate through ABT and return to the previous NixOS generation when verification fails.
- Preserve enough state to resume an interrupted download safely.
- Print one useful failure report with the failed phase, command status, log location, and recovery action.

## Migration

The first replacement release must still contain the inert paths required by the updater shipped in v4.0 and
v4.1. Once that release is broadly available, a later release can remove the ModuCPP and Modularity placeholders
and the legacy shell updater. This avoids stranding existing installations during the cleanup.

## Release gate

Tests must cover Stable and Edge resolution, an unavailable release service, invalid manifests, partial files,
low disk space, failed builds, failed services after activation, interrupted updates, rollback, explicit
downgrades, and direct upgrades from v4.0 and v4.1.
