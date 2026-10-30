# Packages

Abora OS 4.2 Solstice installs software these ways. `grab` is the quick one: name an app and it finds a
source for it.

| You want | Command | Rebuild? |
| --- | --- | --- |
| An app, from wherever it's available | `grab <app>` | No |
| A Nix package right now, just for you | `anix package install <pkg>` | No |
| A Nix package as part of the system | `anix package add <pkg>`, then `anix apply` | Yes |
| A desktop app from Flathub | `abora apps` | No |

## grab

```sh
grab zen-browser          # finds it and installs it
grab htop ripgrep         # several at once
grab info firefox         # where grab would get it, and the exact command
grab search spotify       # matches from every source
grab remove zen-browser   # uninstalls it from wherever it came from
grab providers            # which sources this system has
```

`grab` asks the sources in this order and installs the first **exact** match:

1. **Nix** (or **Lix**, which `grab` detects and names): `nix profile add nixpkgs#<app>`, using the
   nixpkgs pinned in `/etc/nixos`, like `anix package install`.
2. **Flatpak**, from Flathub: installed for your user (`--system` installs for everyone, with `sudo`).
3. **Snap**, when `snapd` is installed (Abora doesn't ship it; Snap installs need `sudo`).

A few names are pinned to a source because the obvious search would miss them: `zen-browser` comes from
Flathub, since it isn't in nixpkgs. When nothing is called exactly what you typed, `grab` lists the close
matches instead of guessing; install one by its id (`grab com.spotify.Client`). `--provider
nix|lix|flatpak|snap` uses only that source, and `--dry-run` prints the commands without running them.

Nothing `grab` installs touches `/etc/nixos`. To make a package part of the system, use
`anix package add <pkg>` and `anix apply`.

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

## Programs that aren't in nixpkgs

Software that lives in its own GitHub repository installs from that repository's flake:

```sh
anix package install github:owner/repo              # the flake's default package
anix package install 'github:owner/repo#attribute'  # a specific one
```

It is fetched and built by Nix like anything else, and installs into your profile, so it's ready at once and
`anix package uninstall <repo>` removes it. GitLab, SourceHut and `git+https` flakes work the same way. The
flake's code runs in the build, so install only flakes you trust. This is how Modularity installs now; the
`abora apps custom` helper and the bundled copy were removed in 4.2.

## Coming from TinyPM

| TinyPM | Now |
| --- | --- |
| `grab <app>` (Nix) | `anix package install <app>` |
| `grab <app>` (Flatpak) | `abora apps` |
| `search <app>` | `anix package search <app>` |
| `term <app>` | `anix package uninstall <app>` |
| `supdate` | `anix package upgrade` and `abora update` |

`anix package` installs from nixpkgs only, so Snap is not one of its sources; `grab` still offers Snap. `anix tinypm` now points to `anix package`. The old `anix.tinypm.enable` option
is still accepted so existing configs keep evaluating, but it does nothing.
