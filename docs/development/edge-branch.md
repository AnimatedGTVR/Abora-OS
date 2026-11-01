# Edge branch

Edge is Abora OS's development channel. Changes here can be incomplete, experimental, or temporarily broken.

## Before testing

- Back up important files and keep a known-good NixOS generation available.
- Read recent commits and open issues before updating.
- Prefer a VM or spare machine for installer and bootloader testing.
- Record the Abora version, Nixpkgs revision, kernel version, and relevant logs when reporting a regression.

## Reporting issues

For ordinary regressions, open an issue with reproduction steps, expected behavior, actual behavior, and the
affected desktop or hardware. Avoid posting passwords, tokens, or other sensitive logs.

Do **not** open a public issue for a suspected security vulnerability. Follow
[SECURITY.md](../../SECURITY.md) and use GitHub Private Vulnerability Reporting, when available, so users are
not exposed before a fix is ready.

Stable releases are intended for regular use; Edge is for testing changes before they are considered for Stable.
