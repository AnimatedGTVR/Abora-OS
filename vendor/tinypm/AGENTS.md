# TinyPM Development Guide

TinyPM is a Rust crate producing `tinypm` and `grab`. Keep provider detection separate from transaction execution, preserve dry-run behavior, and record state changes atomically.

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test --locked
```

New providers require detection, command construction, availability checks, tests, and documentation. Never execute through a shell when an argument vector is sufficient.
