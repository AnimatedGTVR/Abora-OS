# Abora OS v4 Everest

Abora OS v4 Everest is the multi-edition release: five ready-made ISOs, ANIX v2 with pluggable configuration languages, real GPU driver selection, an optional Abora Gaming layer, and a major audit-driven stability pass.

Everest builds on the DENALI 3.14 foundation while expanding how Abora can be installed, configured, updated, and used.

Since the last tagged Everest alpha, another **83 commits** have landed across new features, hardware support, installer work, tooling, and bug fixes.

---
# Highlights

![Highlights](https://raw.githubusercontent.com/AnimatedGTVR/Abora-OS/edge/assets/highlights_converted.gif)

Everest also introduces:

- Non-destructive installation onto an existing partition
- Abora adoption for existing NixOS systems
- ANIX v2 with pluggable configuration languages
- GPU driver selection for NVIDIA, AMD, and Intel
- Abora Gaming as an optional system layer
- Abora Gaming Welcome as its own GTK application
- TinyPM rewritten in Rust
- Linux kernel 7.2
- MediaTek MT7902 Wi-Fi 6E and Bluetooth support
- C# implementations of ANIX and the updater version/channel resolver
- Expanded MINT installer support
- A large audit across scripts, Nix modules, installer flows, and release tooling

All 23 desktop profiles remain available:

GNOME, KDE Plasma, COSMIC, MangoWM, XFCE, Cinnamon, MATE, Budgie, LXQt, Pantheon, Hyprland, Sway, Niri, River, i3, AwesomeWM, Qtile, BSPWM, Herbstluftwm, Openbox, Fluxbox, IceWM, and console-only.

The App Catalog continues to provide seven optional starter bundles:

- Fan Favorites
- Essentials
- Social
- Creator
- Developer
- Gaming
- System Tools

Every bundle is optional.

---

# What's New

![What's New](https://raw.githubusercontent.com/AnimatedGTVR/Abora-OS/edge/assets/whatsnew_converted.gif)

## Non-Destructive Installation

The installer now offers **Use an existing partition**, installing Abora onto a partition you choose without wiping the entire disk. Fixes two failure modes found in testing: the EFI System Partition could be offered as the root target, and existing-partition installs could produce an unbootable system on Legacy BIOS.

## Adopt Abora on Existing NixOS

Existing NixOS users can now adopt Abora without reinstalling, via a new interactive adoption wizard and one-command downloader that install Abora tooling — ANIX, `abora`, Abora configuration tooling, and Abora system integrations — onto a NixOS system you already have.

## GPU Driver Support

Everest adds the `abora.gpu` option with support for:

```text
nouveau
nvidia
nvidia-open
amdgpu
intel
none
```

The installer detects the GPU vendor using `lspci` and offers appropriate choices. NVIDIA systems default to `nouveau`, while `nvidia` and `nvidia-open` remain explicit opt-in choices.

GPU configuration can also be changed later:

```sh
abora config set gpu nvidia
abora config apply
```

`abora hardware-test` can now direct NVIDIA users toward GPU configuration when required.

## ANIX v2

ANIX v2 introduces pluggable configuration languages. Supported adapters:

- ANIX Native (`.anix`)
- MKO (`.mko`)
- ModuCPP (`.moducpp`)

Example:

```sh
anix language list
anix language use anix
anix run workstation.mko
anix validate-plan plan.json
anix apply-plan plan.json
anix diff-plan workstation.mko
```

Each adapter resolves into the same underlying Plan JSON format. `anix diff-plan` labels settings as `ADD`, `CHANGE`, or `SAME`.

Examples are available in `examples/anix-v2/`, and the adapter documentation is available in `docs/wiki/ANIX-V2-Languages.md`.

## Abora Gaming

Abora Gaming is optional and independent of desktop choice. It can provide:

- Steam with 32-bit graphics support
- GameMode
- MangoHud
- Steam hardware and controller support
- Vulkan diagnostic tools
- Common game launchers when available
- Wine and Winetricks
- Steam Big Picture launcher
- Optional fullscreen Gamescope Big Picture session

Commands include:

```sh
abora gaming status
abora gaming enable
abora gaming steam on
abora gaming install steam
abora gaming install wine winetricks
abora gaming big-picture
abora gaming gamescope on
abora gaming controllers on
abora gaming mangohud on
abora gaming gamemode on
abora gaming launchers on
abora gaming logs
abora gaming repair-cache
sudo abora update
```

`abora gaming repair-cache` clears stale local Nix fetch-cache files after
SQLite disk I/O failures during Gaming app installs.

The same functionality is available through Abora Config and ANIX:

```sh
abora config set gaming true
anix enable gaming
anix enable gaming.steam
anix enable gaming.big-picture
anix enable gaming.controllers
anix enable gaming.mangohud
anix enable gaming.gamemode
anix enable gaming.launchers
```

## Abora Gaming Welcome

Abora Gaming Welcome is now a separate GTK application dedicated to gaming setup. Launch it with:

```sh
abora gaming welcome
```

It handles enabling the gaming layer, signing into Steam, and installing Steam, Lutris, Heroic, Bottles, Wine, Winetricks, GameMode, and MangoHud.

## TinyPM v0.8

TinyPM has been rewritten from Bash into a Rust crate.

```sh
grab firefox
tinypm providers
tinypm doctor
```

## MediaTek MT7902 Support

Everest moves to Linux kernel 7.2, bringing upstream support for the MediaTek MT7902 Wi-Fi 6E and Bluetooth chipset via the in-tree `mt7921e` driver.

## Installer Improvements

The GTK installer now includes:

- `Esc` as another way to go back
- Full IANA timezone data with fuzzy search
- Improved disk filtering
- Consistent desktop ordering between the GUI and TUI
- GPU selection alongside identity, desktop, and disk configuration

Everest also continues to include Limine, Plymouth, Abora wallpapers, dark-first defaults, Papirus Dark, Fastfetch on first shell launch, zsh with Spaceship prompt, and Flathub setup after first boot.

---

# Changes

![Changes](https://raw.githubusercontent.com/AnimatedGTVR/Abora-OS/edge/assets/Changes_converted.gif)

## `abora update`

Fix `abora update` with no arguments — the primary documented way to update Abora — being a complete no-op that only printed the usage banner instead of updating.

## `abora rollback`

Fix `abora rollback` never being wired up to its own already-working rollback logic, so the command did nothing at all.

## Update Synchronization

Close a nine-file gap between what the release gate checks and what `abora-update.sh` actually keeps synchronized, including `check-full.sh`, `installer.sh`, `setup-launcher.sh`, and `setup.desktop`.

## Ventoy Booting

Fix Ventoy-flashed USB drives failing to boot: the live initrd was missing `busybox`, which Ventoy's own udev hook depends on (`grep`, `sed`, `awk`, `cut`, `blkid`) to bridge the ISO into a kernel-visible block device.

## thermald

Fix `anix.power.thermald` defaulting to enabled — on unsupported desktop hardware it exits nonzero, which `nixos-rebuild switch` treats as a failed activation, breaking every rebuild including `abora update`. Now opt-in.

## VirtualBox Guest Additions

VirtualBox Guest Additions are no longer force-built into the live ISO — the out-of-tree kernel module's incompatibility with new kernels was blocking unrelated Abora kernel updates. Still available as an opt-in on installed systems through `abora config`.

## Installer Fixes

Fixed:

- `/dev/zram0` appearing as an install target
- Hotplug-disk filtering not actually filtering
- Pantheon missing from the GUI desktop list
- Different desktop ordering between GUI and TUI
- Hardware-readiness checks counting zram as real storage

## Start Abora

Fix the `.desktop` launcher showing **Install Abora OS** on systems that were already installed — the launcher itself already detected live vs. installed correctly, only the static label was wrong. Relabeled to **Start Abora**.

## ANIX Fixes

Fixed:

- `anix run --language` with no value silently crashing
- Broken `anix switch nix <fam>` README examples
- Native `.anix` plan values being truncated at spaces
- CRLF endings leaking into plan values
- Gaming warnings firing when gaming was already enabled
- Plan-tool fields accepting control characters

## MINT

The Go TUI installer now includes Root Account setup, ANIX toggle, Gaming Layer configuration, dotfiles importing (including for the Other edition), and starter application bundles. Two real MINT bugs were fixed, and automated build, vet, and test coverage was added.

## Diagnostics and Support

Fixed:

- `redact_stream` mangling timestamps
- `abora-support-report` leaving its staging directory behind
- `abora-custom-packages` leaking temporary files and directories
- `abora bug-report --github` crashing before `gh` ran

## Audit Pass

A dedicated audit across Abora uncovered:

- **12 real bugs** in a full `scripts/` sweep
- **6 more** in the `nix/` modules
- **3 more** during an end-to-end live installation test
- **2 release blockers** found when `check-desktops` ran against a working Nix daemon

Additional fixes included:

- Missing word boundary in `check-desktops`
- .NET build artifacts leaking into `check-all`
- Two ineffective duplicate tests in `check-scripts.sh`
- Incorrect UI library variable in the standalone ANIX wrapper
- `rebuild-vm.sh` ignoring the requested branch
- `abora build --from-source --ref` ignoring the requested ref on existing checkouts
- A `flake.nix` issue breaking flake evaluation

Validation for Everest includes:

```sh
make check
make check-desktops
make preflight
make iso-all
```

Along with:

- QEMU fresh installation
- Installed-disk boot testing
- ANIX v1 and v2 runtime tests
- GPU option evaluation
- Abora Gaming configuration testing
- TinyPM v0.8 package smoke testing
- Release manifest generation
- Checksum generation

---

# Known Issues

![Known Issues](https://raw.githubusercontent.com/AnimatedGTVR/Abora-OS/edge/assets/KnownIssues_converted.gif)

## xone-dongle-firmware

A `nixos-rebuild` / `abora update` failure involving `xone-dongle-firmware` has been reported, but has not yet been reproduced. Current builds complete successfully on our end.

If you encounter this issue, include the complete:

```text
builder for '...' failed
```

line when reporting it.

## VirtualBox Guest Additions

VirtualBox Guest Additions are now opt-in rather than default-on for the live ISO. If your live-ISO testing workflow relies on Guest Additions, enable them manually.

## Current Limits

- Everest ISOs are larger than older releases because of broader firmware and hardware support.
- Flatpak and app bundle installation requires network access after first boot.
- Steam and gaming launchers require network access.
- Some gaming packages may require unfree package permission through normal NixOS/nixpkgs configuration.
- Modularity requires the Developer bundle or can be installed later with:

```sh
grab modularity
```

- COSMIC Greeter manages its own session, so GNOME auto-login settings do not apply to COSMIC.
- `nvidia` and `nvidia-open` require accepting NVIDIA's license through normal NixOS unfree-package configuration.
- Hardware support ultimately depends on Linux kernel support for the specific device.

For networking problems:

```sh
abora network
```

For support reports:

```sh
abora support-report
```

For installer logs:

```sh
abora logs --lines 200
```

If installation fails before reboot, preserve:

```text
/tmp/abora-install.log
/tmp/abora-config.log
```

before powering off.

---

# Download

![Download](https://raw.githubusercontent.com/AnimatedGTVR/Abora-OS/edge/assets/download_converted.gif)

Everest is available in five editions:

| Release Asset | Edition |
|---|---|
| `abora-cosmic-<date>-x86_64-v4.0.iso` | COSMIC |
| `abora-hyprland-<date>-x86_64-v4.0.iso` | Hyprland |
| `abora-gnome-<date>-x86_64-v4.0.iso` | GNOME |
| `abora-kde-<date>-x86_64-v4.0.iso` | KDE Plasma |
| `abora-other-<date>-x86_64-v4.0.iso` | Other |

Additional release assets:

| File | Description |
|---|---|
| `tinypm-v0.8-abora-v4.0.tar.gz` | TinyPM v0.8 |
| `anix-*-abora-v4.0.tar.gz` | ANIX standalone package |
| `SHA256SUMS-v4.0.txt` | Checksums |
| `RELEASE_MANIFEST-v4.0.txt` | Release manifest |

Existing Abora installations can update with:

```sh
sudo abora update
```

For the cleanest Everest experience, especially when upgrading from DENALI or older pre-release builds, a fresh installation is recommended.

**Five editions. 23 desktop profiles. ANIX v2. Abora Gaming. New hardware support. A safer installer. A repaired update path. 83 commits since the last Everest Alpha.**

# Welcome to Everest.
