# Changelog

## 0.8.1-alpha (2026-08-12)

This release replaces the retired Bash implementation with a ground-up Rust
codebase and resets TinyPM's pre-stable version line.

### Added

- Separate `grab` and `tinypm` executables: `grab` changes packages, while
  `tinypm` is restricted to inspection, diagnostics, and TinyPM state.
- Support for APT, DNF, Pacman, APK, Zypper, XBPS, Portage, eopkg, swupd,
  slackpkg, opkg, URPMI, Guix, Moss/AerynOS, TazPkg/SliTaz, prt-get/CRUX,
  Flatpak, Snap, Nix, and Homebrew.
- Expanded derivative detection across APT, DNF, Pacman, APK, and Zypper
  distribution families.
- Published provider-by-provider validation levels through `tinypm providers`
  and `tinypm doctor`, plus acceptance criteria for adding further managers
  without guessing unsafe command behavior.
- Standards-compliant `/usr/lib/os-release` fallback for stateless systems.
- Distribution-aware native provider detection with Flatpak and Snap as
  universal fallbacks and explicit provider overrides.
- Package installation, removal, updates, search, metadata, availability
  checks, installed-package listing, alias explanations, and dry-run plans.
- Durable JSONL transaction history, managed-package views, reversal previews,
  confirmed undo through `grab`, file locking, and legacy alpha record support.
- Machine-readable JSON for checks, explanations, diagnostics, provider lists,
  history, managed packages, and undo previews.
- Diagnostics retain an explicitly requested provider's identity, validation
  level, and missing executable list even when that provider is unavailable.
- Interactive progress animation with stable noninteractive output.
- Generated Bash, Zsh, Fish, Elvish, and PowerShell completions.
- Rust 1.85 minimum-version enforcement and x86_64/ARM64 GNU and musl builds.
- Checksum, archive-layout, executable-role, and packaged-binary release tests.
- Disposable Alpine end-to-end testing of real install, removal, transaction
  history, managed state, and confirmed undo behavior.
- Locked-dependency auditing against RustSec advisories, including warnings for
  unmaintained, unsound, and yanked crates.

### Safety

- Package names are validated before provider execution.
- Root-required providers use `sudo`, then `doas`, and fail clearly when no
  elevation helper is available.
- Batch operations continue safely after individual failures and record only
  successful package changes.
- Already-installed and already-absent packages are skipped when the provider
  offers a reliable installed-state query.

### Alpha limitations

- Provider commands still need broader testing on real distributions.
- Package metadata and search output retain each provider's native format.
- The archive installation process is manual; the old Bash installer is not
  part of the Rust architecture.

## 0.10.0

Planned as the first stable Rust release after alpha feedback and broader
real-distribution validation.
