# Abora OS DENALI 3.14

**DENALI 3.14 is the release where Abora becomes a real operating system.**

DENALI 3.14 ships a rebuilt installer, a full OS identity, 21 desktop environments, ANIX v1, TinyPM v4, and Modularity — all on top of the NixOS foundation that v2 laid down. If you have been waiting for the right time to try Abora, this is it.

---

## What's New

### Installer — rebuilt from the ground up

The installer is now an Omarchy-inspired terminal UI with a large Abora wordmark header, compact boxed fields, and numbered menus. It is calmer, faster to read, and safer when things go wrong.

- Config is validated before `nixos-install` — bad configs fail early with a clear message
- Live install progress with a log panel and elapsed timer
- Failed installs drop to a live shell with `/tmp/abora-install.log` and the full error context
- Bootloader files are verified on disk before the installer declares success
- QEMU installs auto-power off and tell you to run `make qemu-disk` to boot the installed system

### 22 Desktop Environments

Choose your desktop at install time from the full supported matrix:

| Desktop | Type |
|---|---|
| GNOME | Full DE |
| KDE Plasma | Full DE |
| COSMIC | Full DE |
| MangoWM | Wayland compositor |
| XFCE | Full DE |
| Cinnamon | Full DE |
| MATE | Full DE |
| Budgie | Full DE |
| LXQt | Lightweight DE |
| Pantheon | Full DE |
| Hyprland | Wayland compositor |
| Sway | Wayland compositor |
| Niri | Wayland compositor |
| River | Wayland compositor |
| i3 | Tiling WM |
| AwesomeWM | Tiling WM |
| Qtile | Tiling WM |
| BSPWM | Tiling WM |
| Herbstluftwm | Tiling WM |
| Openbox | Floating WM |
| Fluxbox | Floating WM |
| IceWM | Floating WM |
| No desktop | Console-only |

COSMIC Desktop is new in DENALI 3.14, using its own COSMIC Greeter display manager. All 21 profiles are evaluated in CI before every release via `make check-desktops`.

### Abora Branding

The installed system now identifies itself as **Abora OS DENALI 3.14** everywhere — OS release metadata, issue reporter URLs, installer copy, and first-run surfaces.

The Abora visual identity is applied across the full session:

- Limine bootloader with Abora branding on installed systems
- Plymouth splash theme
- Abora wallpaper pack: Mountain Day, Mountain Night, Ocean Dusk, Blue Horizon, Astronaut, Glacier Reflection
- Dark-first defaults across all supported desktop sessions
- Papirus Dark icon defaults
- Fastfetch with the Abora logo on first shell open
- zsh with Spaceship prompt
- GNOME wallpaper and accent color auto-sync

### ANIX v1

ANIX is the human layer for NixOS. It gives you profile switching, rollback, snapshots, and health checks without requiring you to know the rebuild and flake syntax.

```sh
anix quickstart          # first-run setup
anix status              # profile, generation, and snapshot state
anix profiles            # list available profiles
anix diff nix gaming     # preview changes before applying
anix test nix gaming     # temp-activate a profile
anix switch nix gaming   # apply now
anix rollback nix        # roll back a generation
anix save                # local Git snapshot of /etc/nixos
anix doctor --fix        # health checks and auto-repair
anix set desktop gnome   # change settings without editing Nix
anix --gui               # graphical helper via zenity
```

Named flake profiles available out of the box: `stable`, `minimal`, `gaming`, `creator`, `developer`.

### TinyPM v4

TinyPM is the app layer. v4 is the first version with first-class Abora, ANIX, and NixOS awareness.

```sh
grab firefox             # install through the best available source
tinypm sources           # show native/Flatpak/Snap availability
tinypm system            # Abora/NixOS/ANIX bridge status
tinypm repair            # repair-focused doctor checks
tinypm anix status       # forward to ANIX
tinypm abora doctor      # forward to Abora
```

### App Catalog — 53 apps across 6 bundles

Select a starter bundle at install time: **Fan Favorites**, **Essentials**, **Social**, **Creator**, **Developer**, or **Gaming**. Every bundle is opt-in — you can also skip all of them.

New in DENALI 3.14: **Modularity** is included in the Developer bundle — a game engine editor by Tareno Labs with PhysX, Vulkan, and Mono support baked in.

### Hardware and Live Image

The live image now comes up with the hardware services you expect before install:

- NetworkManager with radio unblock at boot
- Bluetooth, Blueman, and ModemManager
- Redistributable firmware, Intel and AMD microcode
- Common Wi-Fi, Ethernet, Bluetooth, storage, and VM driver modules
- Flathub added automatically on first boot of the installed system

---

## Getting Started

**Build and test the ISO:**

```sh
make iso
make qemu-fresh
```

**After installing in QEMU, boot the installed system:**

```sh
make qemu-disk
```

**On an installed system, update or roll back:**

```sh
sudo nixos update
sudo nixos rollback
```

---

## Release Assets

| File | Description |
|---|---|
| `abora-2026.05.30-x86_64-3.14.iso` | Bootable live ISO |
| `tinypm-v4.0.0-abora-3.14.tar.gz` | TinyPM v4 package |
| `SHA256SUMS-3.14.txt` | Checksums |
| `RELEASE_MANIFEST-3.14.txt` | Full release manifest |

---

## Upgrade Notes

From an existing Abora install:

```sh
sudo nixos update
```

For the cleanest Denali experience — especially from older v2 or pre-release builds — a fresh install is recommended.

---

## Known Limits

- The ISO is larger than earlier v2 builds due to broader firmware and hardware coverage.
- Flatpak and app bundle installs require network after first boot.
- Modularity requires the Developer bundle to be selected at install, or `grab modularity` post-install.
- COSMIC Greeter manages its own session; GNOME auto-login settings do not apply to COSMIC.
- Hardware support depends on Linux kernel support for your exact device.

---

## Validation

Completed before this release:

- `make check` — 79 script checks: syntax, executability, runtime ANIX behaviors
- `make check-desktops` — all 21 desktop profiles evaluated against nixpkgs
- `make preflight` — full release preflight
- QEMU fresh install and disk boot
- TinyPM v4 package generation and smoke test
- Release manifest, checksums, and release notes generated
