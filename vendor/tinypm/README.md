# TinyPM 0.8.1-alpha

TinyPM is a Rust application layer with two commands: `tinypm` inspects packages and providers, while `grab` performs transactions.

```sh
cargo build --locked
cargo test --locked
cargo run --bin tinypm -- providers
cargo run --bin grab -- --dry-run add firefox
```

TinyPM detects Nix, Flatpak, APT, DNF, Pacman, Zypper, APK, Homebrew, Snap, and other supported providers. Transactions are recorded so supported operations can be inspected or undone. This is alpha software; preview commands and review the chosen provider before applying changes.
