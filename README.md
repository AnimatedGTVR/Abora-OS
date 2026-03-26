# Abora OS

Abora OS is a distro project built around a NixOS live image.
The goal is simple: make NixOS feel easier to approach without sanding off what makes it powerful.

Current public release: `v1.0.1`

Website: [aboraos.org](https://www.aboraos.org/)

## Why Abora

- NixOS made simpler for everyday users
- terminal-first live boot and installer
- Abora Welcome and Abora Center right in the boot menu
- reproducible ISO builds with Nix flakes
- custom Abora branding across the bootloader, wallpaper, and fastfetch setup

## Project docs

- [CONTRIBUTING.md](CONTRIBUTING.md) for the day-to-day workflow
- [docs/project-layout.md](docs/project-layout.md) for the repo map
- [docs/install-checklist.md](docs/install-checklist.md) for install testing
- [docs/release-checklist.md](docs/release-checklist.md) for release validation
- [docs/roadmap.md](docs/roadmap.md) for the current direction

## Build prerequisites

- Nix with flakes (`nix-command` + `flakes`)

## Build and test

Build the ISO, then boot it in QEMU:

```sh
cd /home/animated/abora-os

make iso
make qemc
```

## Installed system

For the normal distro-style update command, use:

```sh
sudo nixos update
```

If you want the short Abora aliases, these work too:

```sh
update
upgrade
```

All of these commands do the Abora/NixOS thing for you:
- they sync the latest Abora project files into `/etc/nixos/abora/`
- they update the local flake and rebuild the system
- older installer-generated Abora installs get migrated into that layout automatically

## Release flow

When you want the full release bundle locally:

```sh
cd /home/animated/abora-os

make release
```

That drops the ISO, TinyPM V3 package, checksum file, release manifest, and GitHub-ready release notes into `out/`.

If you want to build the TinyPM V3 container package locally too:

```sh
make tinypm-image
```

That image keeps the full TinyPM project inside the container at `/opt/tinypm/project`.

The GitHub Packages workflow publishes that image to:

```text
ghcr.io/<your-github-owner>/abora-tinypm
```

When it is time to publish on GitHub:

```sh
git tag v1.0.1
git push origin v1.0.1
```

That triggers the release workflow, builds the current `v1.0.1` ISO, and opens a draft GitHub release with the matching files attached.

If you just want to refresh the release notes, checksums, and manifest without rebuilding the ISO:

```sh
make metadata
```

If you want the TinyPM V3 release package by itself:

```sh
make tinypm-package
```

Inside the live image:

- the installer starts from the terminal-first boot flow
- `Abora Welcome` and `Abora Center` can be opened from the boot menu
- running `abora-welcome` or `abora-center` from the live shell launches a temporary GUI app session when needed
- TinyPM V3 is still a separate Abora tool and is not part of the `v1.0.1` boot or installer flow

Run script checks:

```sh
./scripts/check-scripts.sh
```

Rebuild in VM workspace:

```sh
./scripts/rebuild-vm.sh
```

## CI builds

The `Build Abora ISO` workflow builds the release bundle and uploads:

- `out/*.iso`
- `out/tinypm-*.tar.gz`
- `out/SHA256SUMS-*.txt`

The `Publish TinyPM Package` workflow pushes the TinyPM V3 container package to GitHub Packages through GHCR.

## Release validation

- [docs/install-checklist.md](docs/install-checklist.md)
- [docs/release-checklist.md](docs/release-checklist.md)

## License

Abora OS is licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
