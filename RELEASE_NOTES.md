# Abora OS v4 Everest

**Abora OS v4 Everest is the multi-edition release: five ready-made ISOs, a second-generation ANIX with pluggable configuration languages, real GPU driver support, and an optional Abora Gaming layer.**

Abora OS v4 Everest builds on the DENALI 3.14 foundation — the rebuilt installer, 23 desktop environments, and app catalog are all still here — and adds edition-based ISOs, ANIX v2, first-class NVIDIA/AMD/Intel driver selection, and optional Steam/Big Picture gaming setup.

---

## What's New

### Multi-edition ISOs

Instead of one general-purpose ISO, Abora OS v4 Everest ships five editions, each defaulting to a different desktop so the download matches what you actually want to boot into:

| Edition | Default desktop |
|---|---|
| Cosmic | COSMIC |
| Hyprland | Hyprland |
| GNOME | GNOME |
| KDE | Plasma |
| Other | Console-first, pick any of the 23 profiles at install |

Every edition still installs the full desktop matrix — the edition just decides the ISO's live-session default. Build every edition for release validation:

```sh
make iso-all
```

### GPU driver support

Abora now configures your graphics driver instead of leaving NVIDIA on whatever NixOS defaults to:

- New `abora.gpu` option: `nouveau`, `nvidia`, `nvidia-open`, `amdgpu`, `intel`, or `none`
- The installer detects your GPU vendor via `lspci` and offers the right choices — NVIDIA hardware defaults to the safe, no-license-required `nouveau` driver, with proprietary `nvidia` and NVIDIA's open kernel modules (`nvidia-open`, Turing and newer) available as explicit opt-ins
- AMD and Intel already work out of the box through the kernel's own open-source drivers; the option mainly makes that choice visible to `abora config`
- Change it any time post-install:

```sh
abora config set gpu nvidia   # or nouveau, nvidia-open, amdgpu, intel, none, auto
abora config apply
```

- `abora hardware-test` now points at the GPU step and `abora config set gpu` when it detects NVIDIA hardware

### ANIX v2 — pluggable configuration languages

ANIX no longer speaks only its own command language. A system's configuration can now be written in whichever adapter is installed:

- **ANIX Native** (`.anix`) — the same short command language ANIX has always used
- **MKO** (`.mko`) — the MAKO project's systems language
- **ModuCPP** (`.moducpp`) — via the new `moducpp-anix` adapter, with a dedicated `add ANIX;` plan module

```sh
anix language list
anix language use anix        # or mako, moducpp
anix run workstation.mko
anix validate-plan plan.json
anix apply-plan plan.json
anix diff-plan workstation.mko
```

Every adapter resolves to the same underlying Plan JSON, applied as one transaction — `anix diff-plan` works against any source language and labels each setting `ADD`, `CHANGE`, or `SAME` before you apply anything. See `examples/anix-v2/` for minimal and multi-operation examples in all three languages, and `docs/wiki/ANIX-V2-Languages.md` for the full adapter contract.

### 23 Desktop Environments

The full desktop matrix is unchanged from DENALI 3.14 and remains available on every edition:

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

All 23 profiles are evaluated in CI before every release via `make check-desktops`.

### App Catalog — 7 starter bundles

Select a starter bundle at install time: **Fan Favorites**, **Essentials**, **Social**, **Creator**, **Developer**, **Gaming**, or **System Tools**. Every bundle is opt-in — you can also skip all of them. Modularity (a game engine editor by Tareno Labs with PhysX, Vulkan, and Mono support) is included in the Developer bundle.

### Abora Gaming

Abora Gaming is optional and separate from desktop choice. You can install GNOME, KDE Plasma, COSMIC, Hyprland, or another desktop, then add gaming support on top:

- Steam with 32-bit graphics support
- GameMode and MangoHud
- controller/Steam hardware support
- Vulkan diagnostic tools
- common game launchers when available in nixpkgs
- Steam Big Picture launcher
- optional Gamescope Big Picture login session

Enable it during install or after first boot:

```sh
abora gaming status
abora gaming enable
abora gaming big-picture
abora gaming gamescope on
sudo abora update
```

The same controls are available through `abora config`, the graphical settings app, Welcome, and ANIX:

```sh
abora config set gaming true
anix enable gaming
anix enable gaming.big-picture
```

### TinyPM v0.8

TinyPM is the app layer, unchanged from DENALI 3.14:

```sh
grab firefox             # install through the best available source
tinypm sources            # show native/Flatpak/Snap availability
tinypm system              # Abora/NixOS/ANIX bridge status
tinypm repair              # repair-focused doctor checks
```

### Installer and Abora Branding

Carried forward from DENALI 3.14 and updated for Abora OS v4 Everest throughout - installer copy, OS release metadata, issue reporter URLs, and first-run surfaces all identify as **Abora OS v4 Everest**.

- Omarchy-inspired TUI installer with a GPU step alongside identity, desktop, and disk selection
- Limine bootloader, Plymouth splash, and the Abora wallpaper pack
- Dark-first defaults, Papirus Dark icons, Fastfetch on first shell open, zsh with Spaceship prompt

### Hardware and Live Image

- NetworkManager with radio unblock at boot
- Bluetooth, Blueman, and ModemManager
- Redistributable firmware, Intel and AMD microcode
- GPU driver selection (see above) in addition to the existing Wi-Fi, Ethernet, Bluetooth, storage, and VM driver modules
- Flathub added automatically on first boot of the installed system

---

## Getting Started

**Build and test the ISO:**

```sh
make iso
make qemu-fresh
```

For release validation, build every edition:

```sh
make iso-all
```

**After installing in QEMU, boot the installed system:**

```sh
make qemu-disk
```

**On an installed system, update or roll back:**

```sh
sudo abora update
sudo abora rollback
```

---

## Release Assets

| File | Description |
|---|---|
| `abora-cosmic-<date>-x86_64-v4.0.iso` | Cosmic edition live ISO |
| `abora-hyprland-<date>-x86_64-v4.0.iso` | Hyprland edition live ISO |
| `abora-gnome-<date>-x86_64-v4.0.iso` | GNOME edition live ISO |
| `abora-kde-<date>-x86_64-v4.0.iso` | KDE Plasma edition live ISO |
| `abora-other-<date>-x86_64-v4.0.iso` | Other Desktops edition live ISO |
| `tinypm-v0.8-abora-v4.0.tar.gz` | TinyPM v0.8 package |
| `anix-*-abora-v4.0.tar.gz` | ANIX standalone package (with v2 language adapters) |
| `SHA256SUMS-v4.0.txt` | Checksums |
| `RELEASE_MANIFEST-v4.0.txt` | Full release manifest |

---

## Upgrade Notes

From an existing Abora install:

```sh
sudo abora update
```

For the cleanest EVEREST experience — especially from DENALI or earlier v2/pre-release builds — a fresh install is recommended.

---

## Known Limits

- The ISO is larger than earlier v2 builds due to broader firmware and hardware coverage.
- Flatpak and app bundle installs require network after first boot.
- If Wi-Fi, DNS, updates, or install networking fail, run `abora network` and attach `abora support-report` when asking for help.
- If a live install fails, run `abora logs --lines 200` first to show recent installer/config output.
- If an install fails before reboot, capture `/tmp/abora-install.log` and `/tmp/abora-config.log` before powering off.
- Steam and gaming launchers require network and may require unfree package permission through the normal NixOS/nixpkgs path.
- Modularity requires the Developer bundle to be selected at install, or `grab modularity` post-install.
- COSMIC Greeter manages its own session; GNOME auto-login settings do not apply to COSMIC.
- The proprietary `nvidia` and `nvidia-open` GPU drivers require accepting NVIDIA's license via the normal NixOS `nixpkgs.config.allowUnfree` prompt; `nouveau` needs no license.
- Hardware support depends on Linux kernel support for your exact device.

---

## Validation

Completed before this release:

- `make check` — full script check suite: syntax, executability, runtime ANIX v1/v2 behaviors, GPU option evaluation, and Abora Gaming config coverage
- `make check-desktops` — all 23 desktop profiles evaluated against nixpkgs
- `make preflight` — full release preflight
- QEMU fresh install and disk boot
- TinyPM v0.8 package generation and smoke test
- Release manifest, checksums, and release notes generated
