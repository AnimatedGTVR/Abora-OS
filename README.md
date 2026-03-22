# Abora OS

## Update
Thank you all for over 500 clones!
Abora also has a website:
# [The-website!](https://www.aboraos.org/)
Note: The website may be slightly outdated and is currently being updated.

Abora OS now uses a **NixOS base** for live ISO builds.

## Repository layout

- `assets/`: branding and visual assets
- `nix/`: NixOS profile and modules for Abora live image
- `flake.nix`: Nix flake entrypoint for ISO builds
- `scripts/build-iso.sh`: builds the ISO via `nix build`
- `scripts/rebuild-vm.sh`: pull + rebuild helper for a build VM
- `scripts/check-scripts.sh`: script sanity checks
- `docs/`: roadmap and release validation docs

## Build prerequisites

- Nix with flakes (`nix-command` + `flakes`)

## Local commands

Build ISO:

```sh
./scripts/build-iso.sh
```

Run script checks:

```sh
./scripts/check-scripts.sh
```

Rebuild in VM workspace:

```sh
./scripts/rebuild-vm.sh
```

## CI builds

GitHub Actions workflow `Build Abora ISO` builds the ISO and uploads:

- `out/*.iso`
- `out/SHA256SUMS-*.txt`

## Release validation

- [docs/install-checklist.md](docs/install-checklist.md)
- [docs/release-checklist.md](docs/release-checklist.md)
