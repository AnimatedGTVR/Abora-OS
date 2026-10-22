# Abora OS v4.2 Solstice

**Draft.** Solstice is not released yet: the install, update and rollback matrix in
[docs/next-release-plan.md](docs/next-release-plan.md) has to pass first.

A safer, simpler Abora: one command instead of two, system changes that undo themselves when they fail, a
doctor that explains and repairs, and an installer that says exactly what went wrong.

Released: **<RELEASE DATE>** · Tag: `v4.2` · Channel: `stable`

## Highlights

- **`anix` is the one command.** Everything `abora` did is now `anix <command>`: `anix update`,
  `anix doctor`, `anix apps`, `anix gaming`, `anix recovery`. `abora` still works as its old name, so
  `abora update` and `anix update` are the same thing.
- **Safe system changes (ASA).** `anix apply`, `anix config apply`, `anix apps` and `anix update` run as
  transactions: checked, snapshotted, applied, verified, and rolled back to the previous generation and
  config if anything fails, including a service that newly fails. `anix history` lists them; `anix undo <id>`
  reverses one, and `anix undo --keep-edits <id>` brings back the edits a failed change rolled back. See [ASA](docs/wiki/ASA.md).
- **`anix doctor`** checks the bootloader, Nix, the ANIX config, the update channel, the desktop and login
  screen, the GPU driver, network and DNS, disk space and a read-only root, failed services and Flatpak,
  explains each problem in plain language, and fixes what it safely can (`anix doctor repair`).
  `anix doctor --json` is for bug reports, and support reports include it.
- **Packages without a rebuild.** `anix package install <pkg>` installs any nixpkgs package right away,
  from the exact nixpkgs your system is pinned to, without touching `flake.nix`. `anix package keep` makes
  it part of the system. **TinyPM is removed**; see [Packages](docs/wiki/Packages.md) for the mapping.
- **Installer failures you can act on.** Three kinds of "hash mismatch" are told apart (a damaged USB
  stick or RAM, a changed download, an installer bug), a **What failed** block names the failed build, the
  path and both hashes, and **Save logs to a USB drive** keeps the log through a reboot.
- **A clearer timezone question**: UTC or Region/City in any case, and a city on its own lists matches.
- **ModuCPP, MAKO and the bundled Modularity are removed.** ANIX Native (`.anix` files) is the language ANIX
  ships. Software outside nixpkgs, Modularity included, installs from its GitHub flake with
  `anix package install github:owner/repo`; `abora apps custom` is gone.
- **Two update channels.** `demo` and `dev` are gone; there is `stable` and `unstable`. A system still
  saved on one of the old names follows `unstable` and says so. `anix channel set stable` for tagged releases.
- **Less to keep.** The zenity dialogs, `anix ringtone` and the login sound, and unused images are removed.
- **One installer.** The terminal installer, drawn with gum, is the only one. MINT and the GTK installer are
  removed, and the live ISO is an installer only, with no live desktop session.

## Fixed from DistroWatch's 4.0 review

Thanks to **Jesse Smith of DistroWatch** for testing Abora OS 4.0 across several attempts and publishing
direct, constructive criticism.

| Issue | Status |
| --- | --- |
| Confusing release and version information | 4.1 aligned the names; 4.2 makes every shipped file derive its release name from one place and fails the build when one doesn't |
| Manual partitioning | fixed in 4.1.1 |
| Install failures with hash mismatches | diagnosis and logs improved (above); the 4.0 failure itself is **not yet reproduced** |
| Timezone entry unclear | fixed (above) |
| Live ISO layout (desktop editions boot to a TUI installer) | by design: Abora's live image is an installer, not a live desktop. Documented in [Installation](docs/wiki/Installation.md) |

## Upgrading

```
sudo anix update
```

- **On 4.1 or 4.1.1:** one update is enough. The updater hands over to 4.2's own updater, which installs the
  new files (ABT, the shared core) along with everything else.
- **On 4.0:** run `sudo abora update` twice. The 4.0 updater can't hand over mid-update, so the first run
  installs the newer updater and the second uses it.

Release files, once published: `abora-<edition>-<stamp>-x86_64-v4.2.iso` for each edition, with
`SHA256SUMS-v4.2.txt`. Check the ISO against it before writing the USB stick.

## Known limitations

- The install matrix (every edition, UEFI and BIOS, GPU choices) has not been run on 4.2 yet.
- ABT can't protect a first install: there's no earlier generation to go back to.

---

# Abora OS v4.1.1

A small update to Horizon that fixes how `abora update` handles files.

Released: **<RELEASE DATE>** · Tag: `v4.1.1` · Channel: `stable`

## Why this update

Until now, `abora update` copied a fixed list of files, and that list came from the version you already had
installed. If a new release added a file, it never reached your system. If a release removed or renamed a
file, the old copy stayed behind. That blocks the cleanup planned for v4.2, which adds, moves and removes
files. 4.1.1 fixes the updater first so v4.2 can arrive safely.

## What changed

- **New files arrive.** After `abora update` downloads a release, it switches to that release's updater, which
  now installs everything the release needs, including files your old updater didn't know about. Nothing is
  downloaded twice.
- **Old files are cleaned up.** Each update keeps a list of the files it installed in
  `/etc/nixos/abora/.abora-installed-files`. The next update removes anything on that list that the new release
  no longer ships.
- **Your files are safe.** Only files on that list are ever removed. Files you created, `apps.nix`, `apps.list`
  and anything outside `/etc/nixos/abora` are never touched. Your first update after 4.1.1 only writes the list
  and removes nothing.

## Updating

```
sudo abora update
```

- **On 4.1:** one update is enough.
- **On 4.0:** run `sudo abora update` twice. The 4.0 updater can't switch to the newer updater mid-update, so
  the first run installs 4.1.1's updater and the second run uses it.

No reinstall is needed, and the ISOs are only refreshed with the new version number.

---

# Abora OS v4.1 Horizon

![Abora OS v4.1 Horizon](https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/Images/v4.1-horizon-banner.png)


Abora OS v4.1 Horizon is the reliability-focused follow-up to Everest: a safer installer, corrected update and configuration paths, improved diagnostics, built-in community and learning tools, and a smaller ANIX language surface.

Horizon builds on Everest 4.0 and the DENALI 3.14 foundation while expanding how Abora can be installed, configured, updated, and used.

Released: **<RELEASE DATE>** · Tag: `v4.1` · Channel: `stable`

---
# Highlights

![Highlights](https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/highlights_converted.gif)

Horizon includes the Everest feature set and adds:

- An opt-in Abora Labs installer choice that adds a guarded workspace manager
  without fetching or executing experimental code during system installation.

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
- A partition editor (GParted) right inside the installer
- Plain-language explanations when an install fails
- Abora Community: an optional survey, Learn Nix, and reminders
- GTK feedback and bug-report apps
- The installed login screen shows your own name
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

![What's New](https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/whatsnew_converted.gif)

## Abora Labs

Labs is an explicit opt-in in the installer. It adds a guarded workspace manager for trying experimental Abora work. Nothing experimental is downloaded, run, or used for normal system updates during installation, and the updater only touches Labs on releases that ship it.

## Abora Community

A new community module brings together an optional survey, a Learn Nix guide, and optional reminders. The survey has its own small GTK app, and everything in it is opt-in.

## Feedback and Bug Reports

A new GTK4 app collects feedback and bug reports. Bug reports carry the same redacted diagnostics as `abora support-report`, so you no longer need the terminal to file a useful report.

## Installer: Partition Editor

The TUI installer has an **Edit partitions** step that opens `cfdisk`, and the GUI installer has an **Open partition editor (GParted)** button. GParted ships on every live ISO. Make room for Abora, or set up dual boot, without leaving the installer.

## Installer: Clearer Failures

When an install fails, the installer now reads the end of its own log and explains the likely cause in plain language: a signature or key problem, a package that failed to build, a network drop, or a disk that ran out of space. It also checks the system clock before starting, because a wrong clock is a common hidden cause of download and signature failures.

## Non-Destructive Installation

The installer now offers **Use an existing partition**, installing Abora onto a partition you choose without wiping the entire disk. Fixes two failure modes found in testing: the EFI System Partition could be offered as the root target, and existing-partition installs could produce an unbootable system on Legacy BIOS.

## Adopt Abora on Existing NixOS

Existing NixOS users can now adopt Abora without reinstalling, via a new interactive adoption wizard and one-command downloader that install Abora tooling — ANIX, `abora`, Abora configuration tooling, and Abora system integrations — onto a NixOS system you already have.

## GPU Driver Support

The Everest foundation added the `abora.gpu` option with support for:

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
- ModuCPP (`.moducpp`)

The previously bundled MAKO adapter has been removed. Existing third-party
adapter discovery remains available through ANIX language manifests.

Example:

```sh
anix language list
anix language use anix
anix run workstation.moducpp
anix validate-plan plan.json
anix apply-plan plan.json
anix diff-plan workstation.moducpp
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

The Everest foundation moved to Linux kernel 7.2, bringing upstream support for the MediaTek MT7902 Wi-Fi 6E and Bluetooth chipset via the in-tree `mt7921e` driver.

## Installer Improvements

The GTK installer now includes:

- `Esc` as another way to go back
- Full IANA timezone data with fuzzy search
- Improved disk filtering
- Consistent desktop ordering between the GUI and TUI
- GPU selection alongside identity, desktop, and disk configuration

Horizon continues to include Limine, Plymouth, Abora wallpapers, light desktop defaults, Papirus, Fastfetch on first shell launch, zsh with Spaceship prompt, and Flathub setup after first boot.

---

# Changes

![Changes](https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/Changes_converted.gif)

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

## Installer Reliability (issues #32 and #33)

Fixed:

- Japanese and other non-US keyboards: the console keymap (for example `jp106`) was passed straight to the graphical session, which needs `jp`. Console names are now mapped to the right desktop layout.
- User passwords: password hashing could fail silently on some live environments. It now uses a hardened `openssl` path with fallbacks, and refuses an empty password instead of hashing it.
- `target-flake.lock` failing with a nixpkgs mismatch: the bundled nixpkgs symlink is now resolved before it is checked against the lock.
- Installs stalling for a long time at the .NET build step: the Native AOT tools now have a fixed source name, so the install reuses the already-built tools instead of rebuilding them.
- Flathub setup now keeps retrying after first boot instead of giving up silently when the network is not ready yet.
- The login screen showed every account as "Abora User", which looked like a leftover live account. The display name now defaults to your username and can be changed with `abora.user.fullName`.

## Abora Welcome on KDE Plasma

Fix the Abora Welcome app not opening on first login under KDE Plasma (it worked when launched by hand). It now starts once the Plasma panel is ready.

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

## Security

Fixed:

- Support reports and full checks redact Wi-Fi PSKs written as multi-line Nix strings, plus `Authorization` headers of every kind (Bearer, Basic, Token, Digest).
- The Abora adoption downloader refuses a hard reset over untracked or modified local work unless you explicitly force it.
- `abora build` fails closed when it cannot verify the checkout ref.
- CI no longer keeps its GitHub token in the checkout.

## Less Shell in the Core

The support and release tooling has moved from Bash to Python, continuing the work to remove shell scripts from Abora's core. Commands and output stay the same.

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

Validation for Horizon includes:

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

![Known Issues](https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/KnownIssues_converted.gif)

## xone-dongle-firmware

A `nixos-rebuild` / `abora update` failure involving `xone-dongle-firmware` has been reported, but has not yet been reproduced. Current builds complete successfully on our end.

If you encounter this issue, include the complete:

```text
builder for '...' failed
```

line when reporting it.

## VirtualBox Guest Additions

VirtualBox Guest Additions are now opt-in rather than default-on for the live ISO. If your live-ISO testing workflow relies on Guest Additions, enable them manually.

## VirtualBox Installs

Installing inside VirtualBox (issue #33) has not been fully validated yet. If an install fails there, try disabling 3D acceleration and attach `/tmp/abora-install.log` to your report.

## Limine Message on UEFI

On UEFI installs Limine may print `device_cache_block(): set_pos(): Invalid argument` while installing its BIOS stages. It is harmless: the install completes and the system boots. On a shared EFI partition, Limine also installs to the fallback path `\EFI\BOOT\BOOTX64.EFI`; other operating systems keep their own boot entries.

## Current Limits

- Horizon ISOs are larger than older releases because of broader firmware and hardware support.
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

![Download](https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/download_converted.gif)

Horizon ships in five editions:

| Release Asset | Edition |
|---|---|
| `abora-cosmic-<date>-x86_64-v4.1.iso` | COSMIC |
| `abora-hyprland-<date>-x86_64-v4.1.iso` | Hyprland |
| `abora-gnome-<date>-x86_64-v4.1.iso` | GNOME |
| `abora-kde-<date>-x86_64-v4.1.iso` | KDE Plasma |
| `abora-other-<date>-x86_64-v4.1.iso` | Other |

Additional release assets:

| File | Description |
|---|---|
| `tinypm-v0.8-abora-v4.1.tar.gz` | TinyPM v0.8 |
| `anix-*-abora-v4.1.tar.gz` | ANIX standalone package |
| `SHA256SUMS-v4.1.txt` | Checksums |
| `RELEASE_MANIFEST-v4.1.txt` | Release manifest |

Existing Abora installations can update with:

```sh
sudo abora update
```

Everest 4.0 systems can update in place with the command above. As with any major update, keep a backup, and remember `abora rollback` returns you to the previous generation if something goes wrong.

**Five editions. 23 desktop profiles. ANIX v2. Abora Gaming. Community tools. A safer installer and update path.**

# Welcome to Horizon.
