# Abora Release Checklist

Use this after a local release build or after the GitHub ISO workflow succeeds.

## Build Output

- run `make iso` for quick Cosmic ISO validation
- run `make iso-all` to build Cosmic, Hyprland, GNOME, KDE, and Other edition ISOs
- run `make release` only when preparing the full release bundle
- verify the edition ISOs exist in `out/iso/`
- verify the checksum in `out/release/SHA256SUMS-<version>.txt`
- confirm `out/release/RELEASE_MANIFEST-<version>.txt` matches every published ISO plus the TinyPM and ANIX packages
- confirm each artifact name and ISO filename match the intended version

## Repository Checks

- run `make doctor` and fix any Nix daemon/store or nixpkgs source failures first
- run `./scripts/check-scripts.sh`
- run `./scripts/check-all-files.sh`
- run `./scripts/check-desktops.sh`
- confirm `docs/screenshots.md` matches the current installer flow
- confirm the setup launcher files are tracked by Git so flakes can include them
- confirm `make -n iso` builds the default Cosmic ISO
- confirm `make -n iso-all` builds all five edition ISOs
- confirm `make -n release` runs all edition ISOs, TinyPM package, ANIX package, and metadata steps
- confirm the GitHub ISO workflow publishes the edition ISOs and the release workflow uploads the smaller artifacts from `out/packages/` and `out/release/`

## Live Boot

- boot the ISO in a VM with `make qemu-fresh`
- confirm the live boot flow takes over `tty1`
- confirm MINT renders with color and shows the packaged Abora logo
- confirm NetworkManager is running before the network step
- confirm `nmtui` opens from the installer
- confirm Fastfetch shows the Abora logo in the live shell
- confirm the Omarchy-inspired installer welcome screen renders correctly
- confirm the wallpaper pack is present in the live image
- confirm `abora gaming status` runs in the live shell

## Install Test

- complete one full install onto a blank virtual disk
- confirm the installer's GPU step detects a driver (nouveau/amdgpu/intel/none under QEMU) and lets it be overridden
- confirm preflight failure screens expose Network tools, Debug tools, Open terminal, and retry
- confirm installer progress reaches the install phase
- confirm generated config validation runs before `nixos-install`
- confirm install failure screens show `/tmp/abora-install.log`
- confirm install failure screens can relaunch the installer without rebooting
- remove the ISO or boot with `make qemu-disk`
- confirm the installed system boots without relaunching the live installer
- confirm login and networking work
- confirm `abora network` works on the installed system
- on GNOME, confirm Abora wallpapers appear in `Settings -> Appearance`
- confirm the default wallpaper is applied on first login for the chosen desktop
- confirm `abora setup` opens the installed reconfiguration launcher
- confirm `abora config` shows the installed GPU driver and `abora config set gpu <value>` updates it
- confirm the installer can enable Desktop Gaming + Big Picture, then the installed config contains `abora.gaming.enable = true`, `abora.gaming.steam = true`, `abora.gaming.controllerSupport = true`, `abora.gaming.mangohud = true`, `abora.gaming.gamemode = true`, `abora.gaming.vulkanTools = true`, and `abora.gaming.launchers = true`
- confirm `abora gaming status`, `abora gaming doctor`, and `abora gaming big-picture on` run on the installed system
- capture the required docs/release screenshots from `docs/screenshots.md`

## ANIX Language Gate

- confirm `anix language list` shows ANIX Native, MAKO, and ModuCPP
- confirm `.mko` examples still use `using ANIX;`
- confirm `.moducpp` examples still use `add ANIX;`
- confirm `tools/moducpp-anix` is executable and included in the ANIX package
- confirm the standalone ANIX package includes `docs/wiki/Abora-Gaming.md`

## Release Gate

- if tagging from GitHub, review the draft release created by the workflow
- if install test passes, publish all edition ISOs, checksums, manifest, release notes, TinyPM package, and ANIX package
- if install test fails, do not publish; fix the blocker first

## Last-Minute Failure Triage

When a tester hits an installer, network, or update failure, collect the
basics before rebooting:

```sh
abora bug-report
abora bug-report --github --web
abora logs --lines 200
abora network
abora support-report
```

Add these if it happened during install, before first boot:

```sh
cat /tmp/abora-install.log
cat /tmp/abora-config.log
```

Add these if it happened after first boot:

```sh
abora check-full
sudo journalctl -b --no-pager
```
