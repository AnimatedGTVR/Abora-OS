# Recovery

This page is the fast path when an Abora install boots but something is wrong.

## First Checks

```sh
anix doctor              # check the whole system and explain what's wrong
anix doctor repair       # list the fixes for what it found
anix logs --lines 200
anix network
anix status
```

## Doctor

`anix doctor` (or `abora doctor`, the same thing) checks:

| Area | What it looks at |
| --- | --- |
| Abora files | `flake.nix`, `abora-local.nix`, and the tools in `/etc/abora` |
| Bootloader | UEFI or BIOS, the EFI partition mounted at `/boot`, free space on it |
| Nix | `nix` and `nixos-rebuild`, `flake.lock`, the Nix daemon |
| ANIX config | `anix.nix`, flake evaluation, the snapshot Git repo |
| Updates | the update channel |
| Desktop | the desktop profile, and whether the login screen started |
| GPU | which GPU is installed, `abora.gpu`, and whether that driver is loaded |
| Network | a network connection and working DNS |
| Disk | a read-only root filesystem, free space for the next update |
| Services | failed systemd units |
| Apps | Flatpak and Flathub |

Every problem comes with an explanation, and most come with a fix:

```sh
anix doctor repair                 # what can be fixed, and the exact command each fix runs
anix doctor repair gc-generations  # run one (it asks first)
anix doctor repair rebuild --yes   # without asking
```

A fix only ever runs an ordinary Abora, ANIX or NixOS command, shown before it runs. For a bug report,
`anix doctor --json` prints the same findings as JSON, and `anix support-report` includes it as
`doctor.json`. `anix doctor --fix` still creates missing ANIX config basics (`anix.nix`, the snapshot
repo).

## Roll Back

Use the normal Abora rollback alias:

```sh
rollback
```

Or use ANIX directly:

```sh
anix generations
anix rollback nix
```

## Rebuild Current Profile

```sh
sudo nixos-rebuild switch --flake /etc/nixos#abora
```

Or through ANIX:

```sh
anix switch nix abora
```

## Repair Flake Purity

If rebuilds fail with `/nix/store/assets/mango/config.conf` in pure evaluation mode, repair the installed config first:

```sh
sudo abora repair --mango
sudo nix --extra-experimental-features "nix-command flakes" flake update --flake /etc/nixos
sudo nixos-rebuild switch --flake /etc/nixos#abora
```

Do not use `--impure` as the normal fix. The repair ensures `/etc/nixos/abora/mango/config.conf` exists, rewrites copied Abora modules away from repo-relative Mango asset paths, and runs `git add` when `/etc/nixos` is a Git flake tree.

## Test Before Switching

```sh
anix diff nix abora
anix test nix abora
```

## Boot Next Profile Without Switching Now

```sh
anix boot nix stable
```

Reboot when ready.

## Repair App Sources

```sh
abora apps          # Flatpak / Flathub setup
anix package list   # Nix packages installed without a rebuild
```

If Flatpak is the issue:

```sh
abora recovery
```

## Network Diagnostics

If Wi-Fi, DNS, or updates are failing:

```sh
abora network
```

This prints NetworkManager status, Wi-Fi radio/device state, visible SSIDs,
DNS status, ping reachability, and `cache.nixos.org` reachability.
Failed checks do not stop the report; they stay visible so support can see the
whole network picture.
The longer `abora recovery network` command still works too.

## Save A Snapshot

Before making larger changes:

```sh
anix save "before recovery changes"
```

## Support Report

If the failure happened in the live installer, start with:

```sh
abora bug-report
abora logs --lines 200
```

```sh
abora support-report
```

Attach the generated archive when asking for help.
Obvious password, token, secret, and API key lines are redacted automatically,
but still review the archive before posting it publicly.

## Live ISO Recovery

If the installed system does not boot:

1. Boot the Abora ISO.
2. Choose the live shell.
3. Mount the installed root partition.
4. Inspect `/mnt/etc/nixos`.
5. Rebuild or copy out support logs.

The installer also detects an installed Abora disk and warns when the ISO is still attached.
