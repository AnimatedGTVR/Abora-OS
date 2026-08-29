# TinyPM v0.8

TinyPM is the Abora app layer. It began as a Bash multicall tool and has been
rewritten from the ground up as a real Rust crate — the old Bash runtime,
flavor branding, and multicall alias set (`tiny`, `Parcel`, `search`, `term`,
`start`, `supdate`, `grab-add-repo`, `grab-de`, `syspm`) are gone and have no
Rust equivalent. Two binaries exist now:

- `grab` installs, removes, updates, and reverses package transactions.
- `tinypm` inspects packages, checks availability, diagnoses providers, and
  reads TinyPM state. It never changes installed packages.

On Abora, both binaries ship system-wide as ordinary Nix packages (see
`nix/profiles/live.nix`'s `tinypmPackage`) — there is no per-user install
step. They are on `PATH` for every user as soon as the system is built.

## Mental Model

TinyPM is for apps and package sources.
ANIX is for system profiles, rebuilds, and rollback.
Abora commands are for distro-specific setup, recovery, and health checks.

## Main Commands

```console
grab <PACKAGE>...
grab add <PACKAGE>...
grab remove <PACKAGE>...
grab update
grab undo --yes

tinypm search <QUERY>
tinypm info <PACKAGE>
tinypm check <PACKAGE> [--json]
tinypm list
tinypm explain <PACKAGE> [--json]
tinypm doctor
tinypm providers
tinypm history [LIMIT]
tinypm managed
tinypm undo [--json]
tinypm completions <SHELL>
```

Choose a provider with `--provider` and preview an operation with
`--dry-run`:

```console
grab --provider pacman --dry-run add gcc++
tinypm --provider apk explain gcc++
```

`info` prints detailed provider metadata. `check` performs a quiet
availability probe and returns a nonzero status when unavailable. `explain`
shows the resolved provider, whether a catalog alias was used, the reason for
that mapping, and the exact install command that would run.

## Package Sources

TinyPM auto-detects the host's native package manager (APT, DNF, Pacman,
XBPS, Zypper, APK, Portage, Homebrew, Nix, and more) via `tinypm providers`.
On Abora and NixOS-family systems, TinyPM prefers Nix for native packages.

## Abora And ANIX

TinyPM does not rebuild the OS itself. Use TinyPM for apps, then use Abora or
ANIX for system changes:

```console
tinypm doctor
tinypm check firefox
sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity-7.0.0-Linux.zip
anix status
anix switch nix gaming
abora doctor
abora recovery
```

## Standalone Custom Packages

Some apps ship as standalone vendor zips instead of normal Nixpkgs, Flatpak,
or Snap packages. Abora handles those through custom package helpers:

```console
abora apps custom list
abora apps custom info modularity-stable
sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity-7.0.0-Linux.zip
```

Use `--url <url>` instead of `--zip <file>` if you want Abora to download the
archive first. Add `--no-rebuild` to update the files now and rebuild later
with `abora apps rebuild`.

## Install (outside Abora)

Download a release archive and matching `.sha256` file for your architecture
and libc from TinyPM's GitHub Releases, verify it, then extract both
binaries onto your `PATH`:

```console
sha256sum --check tinypm-linux-x86_64-gnu.sha256
tar -xzf tinypm-linux-x86_64-gnu.tar.gz
mkdir -p ~/.local/bin
install -m 0755 tinypm-linux-x86_64-gnu/grab ~/.local/bin/grab
install -m 0755 tinypm-linux-x86_64-gnu/tinypm ~/.local/bin/tinypm
```

From a source checkout: `cargo install --path . --locked`.

## Local Checks

```console
vendor/tinypm/target/release/tinypm --version
vendor/tinypm/target/release/tinypm doctor
vendor/tinypm/target/release/grab --dry-run curl
```

Release packaging:

```console
make tinypm-package
```

The package lands in:

```text
out/packages/
```
