# Contributing to TinyPM

TinyPM is built for people who want one predictable package workflow across
Linux distributions.

## Expectations

- Beginner-friendly output by default
- Cross-distro compatible provider behavior
- Flatpak and Snap should be optional
- Package-changing commands belong to `grab`; `tinypm` remains read-only
- Provider processes use argument vectors, never interpolated shell source
- Package-changing behavior must support `--dry-run`

Run the complete verification suite before submitting changes:

```console
make release-check
```

`release-check` formats-checks, lints all targets and features, runs the locked
test suite, audits `Cargo.lock`, verifies the publishable crate, and builds both
optimized binaries. Install the pinned audit tool first with
`cargo install cargo-audit --version 0.22.2 --locked`.

CI additionally enforces Rust 1.85, checks x86_64 and ARM64 GNU/musl targets,
and tests provider detection in representative distribution containers.

Please keep changes readable and predictable.
