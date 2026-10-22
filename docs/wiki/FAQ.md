# FAQ

## What is Abora?

Abora OS is a distro project built on top of NixOS with a focus on a simpler first-run and management experience.

## Is Abora just NixOS?

Abora is still NixOS-based, but it adds its own live image flow, installer experience, branding, update path, desktop profiles, support tools, and ANIX workflows, including `anix package` for installing nixpkgs packages without a rebuild.

## What is Abora OS v4.2 Solstice?

Abora OS v4.2 Solstice is the current alpha release line: a safer, simpler Abora. `anix` becomes the one
command (`abora` is its old name), system changes run as transactions that roll themselves back when they
fail ([ASA](ASA.md)), `anix doctor` explains and repairs problems, `anix package install` replaces TinyPM,
and the installer explains failures precisely. See [RELEASE_NOTES.md](../../RELEASE_NOTES.md).

## What was Abora OS v4.1 Horizon?

Abora OS v4.1 Horizon built on Everest with installer and update reliability work, community tools, a simplified ANIX language set, and first-class GPU support.

Key additions over DENALI 3.14:

- five edition ISOs (Cosmic, Hyprland, GNOME, KDE, Other) via `make iso-all`, instead of one general-purpose ISO
- ANIX v2: configuration can be written in a `.anix` file (ANIX Native; ModuCPP was available in 4.0 and 4.1) that resolves to a Plan JSON — see `anix language list`
- `abora.gpu` option and an installer GPU step: choose nouveau, nvidia, nvidia-open, amdgpu, intel, or none, with NVIDIA hardware auto-detected and defaulted to the license-free `nouveau` driver
- `abora hardware-test` now points at the GPU step and `abora config set gpu` when it detects NVIDIA hardware

## What is DENALI 3.14?

DENALI 3.14 shipped the Omarchy-inspired TUI installer, stronger install validation, Abora branding across boot and desktop, ANIX v1, and TinyPM v0.8.

Key additions over v2.5:

- Omarchy-inspired TUI installer with a compact boxed UI and live progress output
- config validation runs before `nixos-install`
- Abora branding in bootloader, Plymouth, wallpapers, Fastfetch, and desktop defaults
- ANIX v1 profile manager with snapshots, diff/test/boot/switch/rollback workflows
- TinyPM v0.8 with Abora/ANIX/NixOS system bridges
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

## The desktop's Software Center says updates failed, or an update I applied through it needs a reboot to take effect — is that an Abora bug?

No — this is a known upstream limitation, not something Abora ships or can patch. Abora has no first-party auto-update timer or app-store component; the "Software"/"Discover"-style app bundled with your desktop environment talks to NixOS through PackageKit, and PackageKit's NixOS backend is incomplete. It commonly fails silent background update checks (e.g. at login) and generally can't apply changes live, since NixOS updates work by building a new system generation and switching to it, not by patching packages in place.

Use `sudo abora update` (see above) for real updates — it goes through Abora's own updater, not the desktop's software center.

## Why does Abora not install every helper tool by default?

Abora is meant to feel easy, not stuffed. The base install keeps core desktop,
networking, updates, Flatpak, ANIX, and Abora tools available, while heavier
support tools are opt-in:

```sh
abora config set diagnostics true
abora config set vm-guests true
abora config set mobile-broadband true
abora config apply
```

You can also install individual apps and tools from `abora apps catalog`.

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

From the installer, open **Network tools** and try **Turn Wi-Fi on and rescan**
or **Quick Wi-Fi connect**. On an installed system, run:

```sh
abora network
```

`abora recovery network` is the same diagnostic path with the longer name.

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

## What happened to TinyPM?

TinyPM was removed in Abora OS 4.2 Solstice. `anix package install <pkg>` installs any nixpkgs package
right away, from the same nixpkgs revision as your system and without editing `flake.nix`;
`anix package add <pkg>` makes it part of the system config instead. Flatpak apps are `abora apps`. See
[Packages](Packages.md) for the full TinyPM-to-ANIX mapping.

## Is Modularity available in Abora?

Not as part of the OS since 4.2. Modularity (a game engine editor by Tareno Labs) used to be bundled and
updated through a special zip helper. It installs like any other program now: from its GitHub flake,

```sh
anix package install github:<owner>/<repo>
```

and `anix package keep <name>` makes it part of the system. See [Packages](Packages.md).

## Where are the project docs?

Start here:

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Roadmap](../roadmap.md)
- [Project Layout](../project-layout.md)
