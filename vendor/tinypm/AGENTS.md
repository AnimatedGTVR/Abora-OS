# TinyPM Rust development guide

TinyPM is a Rust package-manager frontend. The current version is
`0.8.1-alpha`; the planned stable release is `0.10.0`.

## Verification

```console
make release-check
```

CI additionally checks the Rust 1.85 minimum, GNU/musl cross-targets, and
provider detection in representative distribution containers.

## Architecture

- `src/main.rs` and `src/bin/grab.rs` own the process boundaries.
- `src/cli.rs` parses commands and preserves the install-first `grab` UX.
- `src/provider.rs` detects providers and builds typed command specifications.
- All external commands must use argument vectors. Never construct a command
  through a shell or interpolate package names into shell source.
- Package-changing behavior must support `--dry-run`.

The old Bash runtime was removed. Refer to Git history when checking legacy
behavior; do not add shell execution or shell-sourced runtime modules.
