# TinyPM v0.8

TinyPM v0.8 remix is the Abora app layer.

It keeps the easy app commands from v3 while adding better native package routing, desktop helpers, bundles, manifests, history, rollback previews, and Abora/ANIX-aware Nix support.

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
| `tinypm check <package>` | Check package availability across sources |
| `tinypm managed` | Show TinyPM-tracked packages |
| `tinypm apps` | Show curated app suggestions |
| `tinypm bundle <category>` | Install a category bundle |
| `tinypm sync <manifest>` | Install from a package manifest |
| `tinypm doctor [--fix]` | Run TinyPM health checks |
| `tinypm history` | Show recent TinyPM transactions |
| `tinypm undo` | Preview the last reversible transaction |
| `tinypm check-update` | Check whether TinyPM itself has an update |
| `tinypm self-update` | Update the user TinyPM runtime |
| `tinypm add-repo <repo> [name]` | Add a package source through the native backend |
| `tinypm de <desktop>` | Show/install desktop environment support |
| `abora apps custom update <id>` | Update standalone custom packages such as Modularity Stable |
| `Parcel --version` | Show engine, runtime, and system report |
| `syspm <command>` | Route TinyPM through the native system package manager only |

## Quick Aliases

```sh
tinypm i firefox
tinypm s blender
tinypm r htop
tinypm u
tinypm ls
tinypm c firefox
tinypm b Gaming
tinypm h
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

## Abora And ANIX

TinyPM does not rebuild the OS itself. Use TinyPM for apps, then use Abora or ANIX for system changes:

```sh
tinypm doctor
tinypm check firefox
tinypm check-update
tinypm self-update
sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity-7.0.0-Linux.zip
anix status
anix switch nix gaming
abora doctor
abora recovery
grab-de gnome
grab-add-repo https://nixos.org/channels/nixos-unstable unstable
```

This makes TinyPM useful from one command surface without blurring responsibility.

## Standalone Custom Packages

Some apps ship as standalone vendor zips instead of normal Nixpkgs, Flatpak, or
Snap packages. Abora handles those through custom package helpers:

```sh
abora apps custom list
abora apps custom info modularity-stable
sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity-7.0.0-Linux.zip
```

Use `--url <url>` instead of `--zip <file>` if you want Abora to download the
archive first. Add `--no-rebuild` to update the files now and rebuild later with
`abora apps rebuild`.

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
vendor/tinypm/tinypm doctor
vendor/tinypm/tinypm check-update
vendor/tinypm/grab --dry-run curl
vendor/tinypm/syspm version
```

Installed Abora systems also run a user timer named `tinypm-update-check.timer`.
It checks quietly every few hours and uses desktop notifications when a TinyPM update is available.

Release packaging:

```sh
make tinypm-package
```

The package lands in:

```text
out/packages/
```
