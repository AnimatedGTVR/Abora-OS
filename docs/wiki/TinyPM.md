# TinyPM

TinyPM is Abora's optional application layer. `tinypm` searches and inspects packages; `grab` performs package transactions through an available provider.

```sh
tinypm search "$QUERY"
tinypm info "$PACKAGE"
tinypm check "$PACKAGE"
tinypm explain "$PACKAGE"
tinypm providers
tinypm doctor
grab add "$PACKAGE"
grab remove "$PACKAGE"
grab update
grab undo --yes
```

On Abora and NixOS, TinyPM prefers Nix for native packages. It may also detect Flatpak or host-native providers. Preview a transaction with `--dry-run` and select a provider with `--provider`.

TinyPM manages applications; ANIX manages system profiles and generations; `abora` manages distro-specific setup, updates, diagnostics, and recovery.
