# Updating Abora

Update an installed system with:

```sh
abora update --check
sudo abora update
```

The updater resolves the selected channel, downloads Abora project files, updates flake inputs, and runs the system rebuild.

## Channels

```sh
abora channel
abora channel list
sudo abora channel set stable
sudo abora channel set unstable
```

Stable tracks tested releases. Unstable tracks `edge` and may contain unfinished work.

## Before a large update

```sh
anix save "before update"
anix status
sudo abora update
```

Rollback if needed:

```sh
sudo abora rollback
# or
anix generations
anix rollback nix
```

For network failures run `abora network`. For disk-full errors, free ordinary files first, then consider `sudo nix-collect-garbage -d`. Never delete files directly from `/nix/store`.
