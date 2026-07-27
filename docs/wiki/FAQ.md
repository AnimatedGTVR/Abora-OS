# FAQ

## What is Abora?

Abora OS is a distro project built on top of NixOS with a focus on a simpler first-run and management experience.

## Is Abora just NixOS?

Abora is still NixOS-based, but it adds its own live image flow, installer experience, branding, update path, desktop profiles, support tools, ANIX workflows, and TinyPM-flavored app commands.

## What is Abora OS 2026.7.27?

Abora OS 2026.7.27 is the current stable release. It shipped multi-edition ISOs, ANIX v2 with pluggable configuration languages, and first-class GPU driver support, on top of everything DENALI 3.14 introduced.

Key additions over DENALI 3.14:

- five edition ISOs (Cosmic, Hyprland, GNOME, KDE, Other) via `make iso-all`, instead of one general-purpose ISO
- ANIX v2: configuration can be written in ANIX Native, MKO, or ModuCPP, all resolving to the same Plan JSON — see `anix language list`
- `abora.gpu` option and an installer GPU step: choose nouveau, nvidia, nvidia-open, amdgpu, intel, or none, with NVIDIA hardware auto-detected and defaulted to the license-free `nouveau` driver
- `abora-hardware-test` now points at the GPU step and `abora config set gpu` when it detects NVIDIA hardware

## What is DENALI 3.14?

DENALI 3.14 shipped the Omarchy-inspired TUI installer, stronger install validation, Abora branding across boot and desktop, ANIX v1, and TinyPM v4.

Key additions over v2.5:

- Omarchy-inspired TUI installer with a compact boxed UI and live progress output
- config validation runs before `nixos-install`
- Abora branding in bootloader, Plymouth, wallpapers, Fastfetch, and desktop defaults
- ANIX v1 profile manager with snapshots, diff/test/boot/switch/rollback workflows
- TinyPM v4 with Abora/ANIX/NixOS system bridges
- 21 desktop environments selectable at install time
- COSMIC desktop support added

## What changed in v2.5?

v2.5 focused on reliability:

- NetworkManager in the live installer
- stronger installer failure handling
- desktop profile evaluation checks
- QEMU fresh/disk boot helpers
- `make iso` vs `make release` split

## How do I update Abora?

Use:

```sh
sudo abora update
```

Compatibility aliases may still exist on installed systems, but `sudo abora
update` is the intended Abora command.

## How do I test a pre-alpha build?

Pre-alpha builds are unfinished and may make the system unbootable or require a reinstall. Do not use them on a primary computer.

Preview what would be selected:

```sh
sudo abora install pre-alpha --dry-run
```

Install after the risk prompt:

```sh
sudo abora install pre-alpha
```

You must type `I ACCEPT THE RISK` exactly. This is a one-shot install path and does not save the system update channel as pre-alpha.

## How do I get a shell on the live ISO for troubleshooting?

Pick **Live shell** from the installer's first screen (instead of **Install
Abora OS**) — it drops to a root prompt on `tty1` with no login needed, and
`abora-install` relaunches the installer from there. If you switch to another
console (`tty2`–`tty6`) instead, log in as `aboraos` with a blank password, or
`root` with password `linux` as a fallback. See [Installation](Installation.md#getting-a-shell-for-diagnostics).

## Wi-Fi shows as "unavailable" in nmtui/nmcli during install — what do I do?

If `nmcli device status` shows your Wi-Fi device (e.g. `wlp1s0`) stuck at
`unavailable` — not `disconnected` — even though the card and driver loaded
fine (check `dmesg | grep -i iwlwifi` for firmware load messages), check
`journalctl -u NetworkManager -b --no-pager` for:

```text
Couldn't initialize supplicant interface: Failed to D-Bus activate wpa_supplicant service
```

This means NetworkManager can see and initialize the card but can't hand it
off to `wpa_supplicant` at all — it's a networking-config bug in older live
ISOs (fixed in `nix/profiles/live.nix` going forward), not a hardware or
driver problem, and it isn't rfkill (check `rfkill list all` to rule that out
too, but this specific error means rfkill isn't the cause).

From a [live shell](#how-do-i-get-a-shell-on-the-live-iso-for-troubleshooting),
start `wpa_supplicant` manually in the same D-Bus-controlled mode NixOS
would otherwise configure automatically:

```sh
sudo mkdir -p /run/wpa_supplicant
sudo wpa_supplicant -u -s -O /run/wpa_supplicant -B
nmcli device status
```

The device should flip to `disconnected`. Run `abora-install` to relaunch
the installer and continue normally from there — `nmtui` and the network
step will work as expected.

## How do I build the ISO?

For quick Cosmic-edition testing:

```sh
make iso
```

For the full release set:

```sh
make iso-all
```

That builds Cosmic, Hyprland, GNOME, KDE Plasma, and Other Desktops editions.

Then boot it with:

```sh
make qemu-fresh
```

After install, boot the virtual disk with:

```sh
make qemu-disk
```

## Does TinyPM v4 install permanent NixOS system packages?

TinyPM is part of the Abora ecosystem, but it is not a full replacement for declarative NixOS configuration.

In Abora it provides friendly app commands such as `grab`, `search`, `term`, `start`, and `supdate`, plus helpers such as `tinypm sources`, `tinypm system`, `tinypm anix <command>`, and `tinypm abora <command>`.

## Is Modularity available in Abora?

Yes. Modularity is a game engine editor by Tareno Labs and is included in the Developer app bundle.

Install it after setup:

```sh
grab modularity
```

Or select it from the Developer bundle during installation.

Modularity is backed by a custom Nix derivation with PhysX, Vulkan, and Mono support built in.

## Where are the project docs?

Start here:

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Roadmap](../roadmap.md)
- [Project Layout](../project-layout.md)
