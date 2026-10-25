# Contributing to TinyPM

Keep changes focused and include tests for provider resolution, command construction, state, or CLI behavior as appropriate.

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test --locked
```

Do not add network access to tests or weaken dry-run, confirmation, transaction, and rollback safeguards.
