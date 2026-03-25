<p align="center">
  <img src="assets/TinyLogo.png" alt="TinyPM V3 Logo" width="500"/>
</p>

<h1 align="center">TinyPM V3</h1>

<p align="center">
  Powered by <strong>Parcel</strong>.<br>
  A beginner-friendly Linux package wrapper for the Abora ecosystem, built on a NixOS base.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0.0-blue.svg" alt="v3.0.0"/>
  <img src="https://img.shields.io/badge/engine-Parcel-1f6feb.svg" alt="Parcel"/>
  <img src="https://img.shields.io/badge/license-GPLv3-blue.svg" alt="GPLv3"/>
  <img src="https://img.shields.io/badge/platform-Linux-success.svg" alt="Linux"/>
</p>

---

## TinyPM V3

TinyPM V3 is the remastered release of TinyPM.

The system name is `TinyPM V3`.
The core engine name is `Parcel`.

Parcel gives TinyPM one simple install flow across:

- native package managers
- Flatpak
- Snap

For Abora, the native path is Nix because Abora uses NixOS as its base.

The main command is now:

```bash
grab firefox
```

You can also inspect the engine directly:

```bash
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

## Why V3

TinyPM V3 is simpler on purpose.

- `grab` is now the primary install command
- Seed has been removed
- desktop and intro launchers have been removed
- the installer no longer asks you to pick a default install command flow
- provider choice happens at install time when it is actually needed

---

## Features

- Primary install command: `grab`
- Engine command: `Parcel --version`
- Main CLI: `tinypm`
- Native-only wrapper: `syspm`
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

Install TinyPM V3:

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
- prefer `nix` automatically on NixOS-based systems like Abora

Then test it:

```bash
export PATH="$HOME/.local/bin:$PATH"
hash -r
grab firefox
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

Abora note:

- Abora is NixOS-based, so Parcel prefers `nix` as the native backend on Abora installs
- `syspm` on Abora routes through the native Nix path

Flags:

- `-n`, `--native` forces the native package manager
- `-f`, `-flat`, `-flatpak` forces Flatpak
- `-s`, `--snap` forces Snap

If you run `grab firefox` and more than one backend is available, TinyPM V3 asks which one to use.

---

## Project Shape

TinyPM V3 is intentionally smaller than the previous release.

- `tinypm`: main CLI
- `grab`: install-first entrypoint
- `Parcel`: core engine identity/version entrypoint
- `syspm`: native-only wrapper
- `version`: version and system report
- `lib/core/`: config, args, actions, state, doctor, UI
- `lib/providers/`: native, Flatpak, Snap
- `share/`: logo and curated catalog

---

## License

TinyPM V3 is licensed under the GNU General Public License v3.0.

See [LICENSE](LICENSE) for the full text.
