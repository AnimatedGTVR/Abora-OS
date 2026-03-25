# Abora OS

## Update
Thank you all for over 700 clones!
Abora also has a website: [aboraos.org](https://www.aboraos.org/).

Abora OS is a little distro project built around a NixOS live image.

`v1.0.0` is the first proper public release.

The goal was not to make something huge on day one. The goal was to make something real: a live image that boots, an installer that works, a release you can actually publish, and a system that already feels like Abora instead of a pile of placeholders.

Website: [aboraos.org](https://www.aboraos.org/)

## Why Abora

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

## Local commands

Build the ISO, then throw it into QEMU:

```sh
cd /home/animated/abora-os

make iso
make qemc
```

## Release flow

When you want the full release bundle locally:

```sh
cd /home/animated/abora-os

make release
```

That drops the ISO, TinyPM V3 package, checksum file, release manifest, and GitHub-ready release notes into `out/`.

When it is time to push the big button on GitHub:

```sh
git tag v1.0.0
git push origin v1.0.0
```

That triggers the release workflow, builds the current `v1.0.0` ISO, and opens a draft GitHub release with the matching files attached.

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
- TinyPM V3 is still a separate Abora tool and is not part of the `v1.0.0` boot or installer flow

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

## Release validation

- [docs/install-checklist.md](docs/install-checklist.md)
- [docs/release-checklist.md](docs/release-checklist.md)

## License

Abora OS is licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
