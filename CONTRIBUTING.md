# Contributing to Abora OS

Contributions are welcome. Useful work includes bug reports, hardware and installer testing, documentation, artwork, and focused code fixes.

## Before changing code

1. Search existing issues and pull requests.
2. Discuss large features before implementing them.
3. Branch from `edge`; `stable` is for tested releases.
4. Keep each pull request focused on one purpose.

## Validate your change

```sh
make doctor
make check
make qemu-fresh
```

Explain what changed, why it matters, and how you tested it. Include logs for failures and screenshots only when they clarify interface changes.

## Commit and code rules

- Write specific commit messages such as `Fix installer disk validation`.
- Follow nearby style and keep Nix declarative.
- Keep shell as small glue; place substantial logic in the appropriate component.
- Never commit secrets, personal data, generated ISOs, or build outputs.
- Preserve rollback and recovery paths when changing installation, updates, boot, or storage.

All contributors must follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security reports belong in [SECURITY.md](SECURITY.md).
