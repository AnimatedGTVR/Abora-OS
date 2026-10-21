# Packages

Abora OS 4.2 Solstice installs software three ways. TinyPM, which wrapped all of them behind `grab`, was
removed in 4.2.

| You want | Command | Rebuild? |
| --- | --- | --- |
| A Nix package right now, just for you | `anix package install <pkg>` | No |
| A Nix package as part of the system | `anix package add <pkg>`, then `anix apply` | Yes |
| A desktop app from Flathub | `abora apps` | No |

## Install a package now

```sh
anix package search ripgrep      # find it in nixpkgs
anix package install ripgrep     # install it; it's on PATH straight away
anix package list                # what's declared and what's installed
anix package upgrade             # upgrade everything installed this way
anix package uninstall ripgrep   # remove it again
```

This doesn't edit `flake.nix`, `anix.nix` or anything else in `/etc/nixos`, and it doesn't need `sudo`.
The package goes into your own Nix profile (`~/.nix-profile`).

It always uses **the same nixpkgs revision your system is built from**. ANIX passes
`--inputs-from /etc/nixos`, so `nixpkgs` means the version pinned in `/etc/nixos/flake.lock`, not
whatever nixpkgs-unstable is today. That keeps the package consistent with the rest of the system and
reuses what's already in the Nix store. `abora update` moves that pin, and `anix package upgrade`
brings installed packages up to it.

If `anix.allowUnfree` is on (the default), unfree packages such as `discord` install the same way.

## Try a package without installing it

```sh
anix package try cowsay                 # a shell with cowsay in it; exit and it's gone
anix package try python3 -- python3 -V  # run one command with it
```

## Make it part of the system

A package installed with `anix package install` belongs to your user and isn't part of a system
generation, so `anix rollback` doesn't touch it and a reinstall won't bring it back. To keep it:

```sh
anix package keep ripgrep        # adds it to anix.packages in /etc/nixos/anix.nix
anix apply                       # builds it into the system
anix package uninstall ripgrep   # drop the now-duplicate personal copy
```

`anix package add` / `anix package remove` edit `anix.packages` directly.

## Coming from TinyPM

| TinyPM | Now |
| --- | --- |
| `grab <app>` (Nix) | `anix package install <app>` |
| `grab <app>` (Flatpak) | `abora apps` |
| `search <app>` | `anix package search <app>` |
| `term <app>` | `anix package uninstall <app>` |
| `supdate` | `anix package upgrade` and `abora update` |

Snap is no longer a source. `anix tinypm` now points to `anix package`. The old `anix.tinypm.enable` option
is still accepted so existing configs keep evaluating, but it does nothing.
