<p align="center">
  <img src="assets/TinyLogo.png" alt="TinyPM v4 Logo" width="500"/>
</p>

<h1 align="center">TinyPM v4</h1>

<p align="center">
  Powered by <strong>Parcel</strong>.<br>
  A beginner-friendly Linux package wrapper and system bridge for Abora, ANIX, and NixOS-family systems.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-4.0.0-blue.svg" alt="v4.0.0"/>
  <img src="https://img.shields.io/badge/engine-Parcel-1f6feb.svg" alt="Parcel"/>
  <img src="https://img.shields.io/badge/license-GPLv3-blue.svg" alt="GPLv3"/>
  <img src="https://img.shields.io/badge/platform-Linux-success.svg" alt="Linux"/>
</p>

---

## TinyPM v4

TinyPM v4 keeps the simple `grab` flow from v3 and adds a system layer that understands Abora, ANIX, and normal NixOS installs.

The system name is `TinyPM v4`.
The core engine name is `Parcel`.

Parcel gives TinyPM one simple install flow across:

- native package managers
- Flatpak
- Snap

For Abora and NixOS-family systems, the native path is Nix and TinyPM exposes helper bridges for the system tools that already belong there.

The main command is:

```bash
grab firefox
```

Useful system checks:

```bash
tinypm system
tinypm anix doctor
tinypm abora doctor
Parcel --version
```

If your system has more than one valid source available and you do not pass a flag, Parcel asks which backend you want to use.

Examples:

```bash
grab firefox
grab -f org.mozilla.firefox
grab -flat org.mozilla.firefox
grab -flatpak org.mozilla.firefox
grab -s firefox
grab -n firefox
```

---

## Why v4

TinyPM v4 is about cooperation.

- `grab` stays the primary app install command
- `tinypm system` explains what OS layer TinyPM sees
- `tinypm anix <command>` forwards into ANIX when present
- `tinypm abora <command>` forwards into Abora tools when present
- Abora and NixOS-family detection now prefers the Nix backend
- the installer and package output use v4 names consistently

TinyPM still does not try to replace declarative NixOS configuration. It gives users a friendly app layer while leaving system rebuilds, rollback, and profiles to Abora, ANIX, and Nix.

---

## Features

- Primary install command: `grab`
- Engine command: `Parcel --version`
- Main CLI: `tinypm`
- Native-only wrapper: `syspm`
- Abora/NixOS status report: `tinypm system`
- Package source report: `tinypm sources`
- Repair shortcut: `tinypm repair`
- ANIX bridge: `tinypm anix <command>`
- Abora bridge: `tinypm abora <command>`
- Flatpak, Snap, and native package support
- Automatic backend detection
- Interactive backend choice when multiple sources are available
- Managed package tracking
- Curated discover catalog
- `tinypm doctor --fix`
- `tinypm export-state` and `tinypm import-state`

---

## Installation

Clone the repository:

```bash
git clone https://github.com/AnimatedGTVR/TinyPM.git
cd TinyPM
```

Install TinyPM v4:

```bash
chmod +x install.sh
./install.sh
```

Use the Abora flavor:

```bash
TINYPM_FLAVOR=abora ./install.sh
```

The installer will:

- install TinyPM into `~/.tinypm`
- link commands into `~/.local/bin`
- expose `tinypm`, `tiny`, `grab`, `syspm`, and `version`
- expose `Parcel --version` for engine/runtime inspection
- detect your native package manager automatically if one exists
- prefer `nix` automatically on Abora and NixOS-family systems

Then test it:

```bash
export PATH="$HOME/.local/bin:$PATH"
hash -r
grab firefox
tinypm system
tinypm doctor
tiny --version
Parcel --version
syspm update
```

---

## Commands

### Main

```bash
grab [-f|-flat|-flatpak|-s|-n] <package>
Parcel --version
tinypm install [-f|-flat|-flatpak|-s|-n|--brew|--nix] <package>
tinypm search [-f|-flat|-flatpak|-s|-n|--brew|--nix] <query>
tinypm remove [-f|-flat|-flatpak|-s|-n|--brew|--nix] <package>
tinypm list [-f|-flat|-flatpak|-s|-n|--brew|--nix]
tinypm update [-f|-flat|-flatpak|-s|-n|--brew|--nix]
tinypm info <package>
tinypm managed
tinypm discover [query]
tinypm doctor [--fix]
tinypm sources
tinypm repair
tinypm system
tinypm anix <command>
tinypm abora <command>
tinypm export-state [file]
tinypm import-state <file>
tinypm version
```

Quick forms:

```bash
tinypm i firefox
tinypm s blender
tinypm r htop
tinypm u
tinypm ls
tinypm v
tinypm src
tinypm fix
tinypm sys
tinypm ax doctor
```

### Native only

```bash
syspm install <package>
syspm search <query>
syspm remove <package>
syspm list
syspm update
syspm version
```

---

## Backend Rules

Parcel supports these native package managers:

- `apt`
- `dnf`
- `pacman`
- `xbps`
- `zypper`
- `apk`
- `emerge`
- `brew`
- `nix`

Abora and NixOS notes:

- Abora is NixOS-based, so Parcel prefers `nix` as the native backend on Abora installs
- systems with `ID_LIKE=nixos` are treated as NixOS-family systems
- `syspm` on Abora routes through the native Nix path
- system-level changes still belong in Abora, ANIX, or NixOS config workflows

Flags:

- `-n`, `--native` forces the native package manager
- `-f`, `-flat`, `-flatpak` forces Flatpak
- `-s`, `--snap` forces Snap

If you run `grab firefox` and more than one backend is available, TinyPM v4 asks which one to use.

---

## Project Shape

TinyPM v4 is intentionally small and system-aware.

- `tinypm`: main CLI
- `grab`: install-first entrypoint
- `Parcel`: core engine identity/version entrypoint
- `syspm`: native-only wrapper
- `version`: version and system report
- `lib/core/`: config, args, actions, state, doctor, UI, system bridge
- `lib/core/system.sh`: Abora, ANIX, and NixOS-family integration
- `lib/providers/`: native, Flatpak, Snap
- `share/`: logo and curated catalog

---

## License

TinyPM v4 is licensed under the GNU General Public License v3.0.

See [LICENSE](LICENSE) for the full text.
