# TinyPM 0.8.1-alpha release checklist

## Automated gates

- [x] Formatting, Clippy warnings, unit tests, integration tests, and docs tests
- [x] Rust 1.85 minimum supported version
- [x] x86_64 and ARM64 GNU/musl compilation
- [x] RustSec dependency audit with warnings denied
- [x] Publishable Rust crate rebuild
- [x] Four release archives with SHA-256 checksums
- [x] Packaged binary version, layout, and executable-role smoke tests
- [x] Provider detection and install/remove/update dry-run plans in Ubuntu,
  Fedora, Arch, Alpine, and openSUSE containers
- [x] Tag and Cargo version equality before publication

## Manual release gates

- [x] Run non-mutating `tinypm doctor`, `providers`, `search`, `info`, and
  `check` commands on representative real machines.
- [x] Run `grab --dry-run` for install, remove, and update on each native
  provider available to the release testers.
- [x] Perform one real install, removal, and confirmed undo on at least APT,
  DNF, Pacman, APK, and Zypper systems.
- [x] Confirm progress rendering and authentication prompts in an interactive
  terminal, plus stable output through a pipe.
- [x] Review `CHANGELOG.md`, replace “unreleased” with the release date, and
  confirm the documented alpha limitations remain accurate.
- [x] Start from a clean committed worktree and run `make release-check`.
- [ ] Create and push the exact tag `v0.8.1-alpha`; verify the generated GitHub
  prerelease contains four archives and four matching checksum files.

## Validation evidence

- 2026-08-12, Arch Linux x86_64: automatic Pacman detection, healthy doctor,
  provider registry, search, package metadata, positive/negative availability,
  install/remove/update dry-run plans, and piped `--no-progress` output passed.
- 2026-08-12, Arch Linux x86_64 pseudo-terminal: animated install progress,
  provider output, completion state, and stable redirected output passed with a
  disposable provider fixture; no system packages were changed.
- 2026-08-12, disposable Alpine 3.22 x86_64 container: real `tree`
  installation, removal, confirmed undo, provider-state verification, three
  durable history records, and final managed-package state passed. No host
  packages were changed.
- 2026-08-12, disposable Ubuntu 24.04, Fedora 42, Arch Linux, and openSUSE
  Tumbleweed x86_64 containers: the same real `tree` install/remove/undo flow,
  native package-state verification, three-record history, and final managed
  state passed for APT, DNF, Pacman, and Zypper. No host packages were changed.
