# Recovery

This page is the fast path when an Abora install boots but something is wrong.

## First Checks

```sh
abora doctor
abora logs --lines 200
abora network
anix status
anix doctor
anix --gui
tinypm system
```

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
tinypm repair
tinypm sources
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
