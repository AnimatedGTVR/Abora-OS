# How the Installer Works

This page is for people who test, debug or change the installer. To install Abora, read
[Installation](Installation.md).

The installer is the only thing on the ISO. There is no live desktop: it boots to a terminal screen,
draws its menus with [gum](https://github.com/charmbracelet/gum), asks its questions, and installs.

## Two parts

| Part | Where | What it does |
| --- | --- | --- |
| The screens | `scripts/install/abora-installer.sh` (Bash) | asks the questions, shows progress and errors, decides the values |
| The engine | `tools/abora-installer/` (Rust) | does the work that must be exact and testable: disks, flakes and the Nix files it writes |

The screens call the engine as `$ABORA_INSTALLER_BIN` (`abora-installer` on the ISO). The aim, set for 4.2, is to
move one piece at a time from Bash into Rust, keeping Bash as glue. Each piece moves only when the old and new
code can be shown to produce the same result.

### What the engine does

```text
abora-installer disk erase <disk>                       wipe a disk: BIOS-boot + 512 MiB ESP + ext4 root
abora-installer disk existing <disk> --root P --esp P   reuse an existing ESP, format only the root partition
abora-installer disk mount --root P --efi P             mount the target at /mnt

abora-installer flake check <flake>[#<config>]          validate a flake reference you typed
abora-installer flake judge ...                         decide if a flake can be installed on this machine
abora-installer flake write ...                         write the wrapper for your own flake
abora-installer flake write-installed --branch B        write flake.nix for a normal install on nixpkgs branch B
abora-installer flake audit FILE...                     refuse files that point at a path on the installer

abora-installer config write < settings                 write configuration.nix, abora-local.nix and anix.nix
```

Run any of them with `--help`. The disk commands also take `--dry-run`, which prints the commands and changes
nothing.

Two properties matter:

- **Everything that ends up inside a Nix string is escaped in one place** (`nixcfg.rs`). A hostname, username or
  disk name can never close the string or start a `${...}`. `config write` also refuses a missing or misspelled
  setting, so a typo cannot silently fall back to a default.
- **The engine never builds or installs by itself.** It writes files and prepares disks; `nixos-install` is
  still run by the screens.

### What is still in Bash

The screens and their decisions, plus the steps that are mostly calling other programs: `nixos-generate-config`,
the branding assets, the starter-apps file, locking the flake, `nixos-install` and the boot checks. These are
the next candidates to move.

## The flow

1. **Source**: install Abora, or your own NixOS flake instead (it is checked, and the installer says what it
   changed and why it was accepted or refused).
2. **Disk**: use the whole disk, partition by hand, or install onto an existing partition (dual boot).
3. **You**: your name, computer name, passwords, language, timezone and keyboard, and the look of the system.
4. **NixOS release**: stable or unstable.
5. **Desktop**: COSMIC, GNOME, KDE Plasma, XFCE, Hyprland, Cinnamon or none. **Minimal** adds a lean set
   (IceWM, LXQt, Lumina, Niri, Sway, Fluxbox, Openbox, or your own).
6. **GPU driver**, **gaming**, **Abora Labs**, and **starter apps**.
7. **Preflight** (network, disk space and the machine), then a **review** screen.
8. **Install.** Failures name what failed and can save the log to a USB drive.

## What gets written

On the installed system, `/etc/nixos` holds:

| File | Written by |
| --- | --- |
| `flake.nix`, `flake.lock` | `flake write-installed` and the lock step |
| `configuration.nix` | `config write`: imports the files below |
| `abora-local.nix` | `config write`: your choices (hostname, desktop, gaming, minimal, ...) |
| `anix.nix` | `config write`, only when ANIX is on |
| `abora/` | Abora's modules, `apps.nix`, and small markers such as `nixos-release` and `channel` |

Password hashes are **not** in `/etc/nixos`, because everything there is copied into the world-readable Nix
store. They are written to `/var/lib/abora/secrets/` (mode 0700) and NixOS reads them when it creates the
accounts.

## Logs and knobs

| Path | Contents |
| --- | --- |
| `/tmp/abora-install.log` | the whole install, including Nix output |
| `/tmp/abora-config.log` | configuration generation |

Environment variables for weak or slow connections (set before starting the installer):

| Variable | Default | Meaning |
| --- | --- | --- |
| `ABORA_INSTALL_SUBSTITUTION_JOBS` | 32 | parallel downloads from the binary cache |
| `ABORA_INSTALL_HTTP_CONNECTIONS` | 32 | simultaneous HTTP connections; lower it if downloads fail in a VM |
| `ABORA_INSTALL_NIX_MAX_SILENT_TIME` | 900 | seconds a build may print nothing before it is stopped |
| `ABORA_INSTALL_WARN_AFTER` | 480 | seconds before the status line starts warning that this is taking long |
| `ABORA_INSTALL_IDLE_TIMEOUT` | 1800 | a step that prints nothing for this many seconds is stopped |
| `ABORA_INSTALL_HARD_TIMEOUT` | 5400 | the longest any one step may run |
| `ABORA_INSTALL_GAMING_DURING_SETUP` | no | install the gaming layer during setup |
| `ABORA_INSTALL_APPS_DURING_SETUP` | no | bake the chosen starter apps into the install |

## Testing

```sh
cd tools/abora-installer && cargo test      # the engine
make check                                  # every script suite, including scripts/install/tests/
make qemu-fresh                             # a clean install in a VM
make qemu-disk                              # boot the disk it produced
```

When a piece moves from Bash to Rust, compare the files the old code wrote with the files the new code writes
on the same inputs, including hostile ones (quotes, `${...}`, backslashes). The 4.2 config writer was checked
that way against the old templates before the Bash was removed.
