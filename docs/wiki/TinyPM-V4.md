# TinyPM v4

TinyPM v4 is the Abora app layer and system bridge.

It keeps the easy app commands from v3 while adding first-class awareness for Abora, ANIX, and NixOS-family systems.

## Mental Model

TinyPM is for apps and package sources.
ANIX is for system profiles, rebuilds, and rollback.
Abora commands are for distro-specific setup, recovery, and health checks.

That split keeps TinyPM simple while still letting it cooperate with the rest of the OS.

## Main Commands

| Command | Purpose |
|---|---|
| `grab <package>` | Install an app/package through the best available source |
| `tinypm search <query>` | Search native, Flatpak, and Snap sources |
| `tinypm list` | List packages from available sources |
| `tinypm remove <package>` | Remove a package |
| `tinypm update` | Update package sources |
| `tinypm info <package>` | Show package tracking and install status |
| `tinypm managed` | Show TinyPM-tracked packages |
| `tinypm sources` | Show native/Flatpak/Snap availability |
| `tinypm repair` | Run repair-focused doctor checks |
| `tinypm system` | Show Abora/NixOS/ANIX system bridge status |
| `tinypm anix <command>` | Forward a command to ANIX |
| `tinypm abora <command>` | Forward a command to Abora |
| `Parcel --version` | Show engine, runtime, and system report |

## Quick Aliases

```sh
tinypm i firefox
tinypm s blender
tinypm r htop
tinypm u
tinypm ls
tinypm src
tinypm fix
tinypm sys
tinypm ax doctor
```

## Package Sources

TinyPM supports:

- native package managers: APT, DNF, Pacman, XBPS, Zypper, APK, Portage, Homebrew, Nix
- Flatpak
- Snap

On Abora and NixOS-family systems, TinyPM prefers Nix for native packages.

Force a source:

```sh
grab -n git
grab -f org.mozilla.firefox
grab -s code
tinypm install --nix ripgrep
```

## Abora And ANIX Bridge

TinyPM does not rebuild the OS itself. Instead:

```sh
tinypm system
tinypm anix status
tinypm anix switch nix gaming
tinypm abora doctor
tinypm abora recovery
```

This makes TinyPM useful from one command surface without blurring responsibility.

## Install

From the vendored source:

```sh
cd vendor/tinypm
TINYPM_FLAVOR=abora ./install.sh
```

The installer links:

- `tinypm`
- `tiny`
- `grab`
- `Parcel`
- `syspm`
- `version`

## Local Checks

```sh
vendor/tinypm/tinypm --version
vendor/tinypm/tinypm sources
vendor/tinypm/tinypm system
vendor/tinypm/scripts/e2e-smoke.sh
```

Release packaging:

```sh
make tinypm-package
```

The package lands in:

```text
out/packages/
```
