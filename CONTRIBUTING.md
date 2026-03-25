# Contributing to Abora OS

Thanks for checking out Abora OS.

This repo is still pretty small, so the best way to help is to keep changes focused, test what you touch, and avoid sneaking in unrelated cleanup with feature work.

## Before you change anything

Make sure you can build and boot the current ISO:

```sh
cd /home/animated/abora-os

make iso
make qemc
```

If you only want the quick checks:

```sh
cd /home/animated/abora-os

make check
```

## Main folders

If you are new to the repo, start here:

- `assets/` for branding, wallpapers, bootloader art, and fastfetch assets
- `docs/` for release notes, install validation, and roadmap docs
- `nix/` for the live image configuration
- `scripts/` for the boot flow, installer, build helpers, and release tooling
- `vendor/tinypm/` for the vendored TinyPM V3 project

There is also a more detailed layout guide in [docs/project-layout.md](docs/project-layout.md).

## Common tasks

Build the ISO:

```sh
make iso
```

Build the full release bundle:

```sh
make release
```

Refresh release metadata without rebuilding the ISO:

```sh
make metadata
```

Boot the latest ISO in QEMU:

```sh
make qemc
```

## Before pushing

Try to keep the branch clean enough that someone else can understand what changed.

Good rule of thumb:

- one feature or fix per commit
- update docs if the workflow changed
- do not leave broken release notes or mismatched version strings behind
- run `make check` before pushing

If `git push origin main` is rejected because the remote moved first, the safe flow is:

```sh
git add -A
git commit -m "Describe your change"
git pull --rebase origin main
git push origin main
```

## Release notes

The release bundle is generated into `out/` and includes:

- ISO
- checksums
- release manifest
- release notes

Tagged GitHub releases are handled by the release workflow.
