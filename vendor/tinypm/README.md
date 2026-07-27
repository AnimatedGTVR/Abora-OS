
<p align="center">
  <img
    src="src/share/tinypm/assets/TinyLogo.png"
    alt="TinyPM V4"
    width="500"
  />
</p>

<h1 align="center">TinyPM V4</h1>

<p align="center">
  One friendly package command across the major Linux package-manager families.
</p>

<p align="center">
  <strong>Pure Bash. One CLI. No background service. No legacy V3 runtime.</strong>
</p>

---

TinyPM is a package-manager wrapper that provides one consistent command across Linux distributions.

Instead of remembering a different syntax for APT, Pacman, DNF, APK, Nix, Zypper, XBPS, and others, TinyPM gives you a shared interface:

```bash
grab firefox
grab search neovim
grab update
grab remove vlc
````

V4 is a complete redesign. It uses one Bash runtime, one command parser, and one provider system. There is no separate engine process and no V3 compatibility layer.

## Quick start

Clone the repository, build TinyPM, and install it:

```bash
./build.sh
./install.sh

export PATH="$HOME/.local/bin:$PATH"
grab --dry-run curl
```

The root-level `build.sh` and `install.sh` files are lightweight links to the maintained implementations inside `scripts/`.

Install multiple packages at once:

```bash
grab firefox vlc gimp
```

Search, update, and remove packages:

```bash
grab search firefox
grab update
grab remove firefox
```

## Building TinyPM

TinyPM does not require compilation. A build validates the source tree and creates a self-contained runnable distribution:

```bash
./build.sh
```

Test the generated build directly:

```bash
./build/tinypm-v4/bin/tinypm help
./build/tinypm-v4/bin/grab --dry-run curl
```

The build output looks like this:

```text
build/
├── tinypm-v4/
│   ├── bin/             User-facing commands
│   ├── lib/tinypm/      TinyPM runtime
│   ├── share/tinypm/    Catalogs, flavors, aliases, and assets
│   └── scripts/         Installation and removal tools
├── tinypm-v4.tar.gz     Release archive
└── SHA256SUMS           Archive checksum
```

The runnable distribution only requires Bash and standard Unix utilities.

When available, `tar` and `sha256sum` are used to create the release archive and checksum.

Additional build options:

```bash
./build.sh --clean
./build.sh --output ./custom-build
```

## Installation

Install TinyPM for the current user:

```bash
./install.sh
```

The installer places:

```text
~/.tinypm/bin/    TinyPM runtime
~/.local/bin/     Command launchers
```

Add the launcher directory to your shell path when necessary:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

TinyPM automatically detects the system package manager:

```bash
grab firefox
```

You can override the detected backend:

```bash
./install.sh --native apk -y
./install.sh --native pacman -y
./install.sh --native nix -y
```

Install with a TinyPM flavor:

```bash
TINYPM_FLAVOR=abora ./install.sh --native nix -y
```

Shell completion is installed automatically for Bash, Zsh, and Fish. Open a new terminal after installation and try:

```text
grab ex<Tab>
grab --pa<Tab>
```

## The `grab` command

`grab` treats package installation as the default action:

```bash
grab <package...>
```

Its full command syntax includes:

```bash
grab <package...>                 # Install packages
grab -- <package...>              # Treat every argument as a package name
grab install <package...>         # Explicit installation
grab --dry-run <package...>       # Preview an installation
grab search <query>               # Search for packages
grab remove <package...>          # Remove packages
grab update                       # Refresh and update packages
grab list                         # List installed packages
grab info <package>               # Show package information
grab check <package>              # Check package availability
grab explain <package>            # Explain package resolution
grab undo                         # Preview the last reversible action
grab undo --yes                   # Perform the reversal
grab doctor                       # Diagnose TinyPM and provider issues
```

## Friendly package names

TinyPM can translate common package names into the correct native package.

For example:

```bash
grab gcc++
```

Depending on the provider, TinyPM resolves that name to:

```text
Arch Linux         gcc
Debian / Ubuntu    g++
Alpine Linux       g++
Fedora              gcc-c++
openSUSE            gcc-c++
```

If multiple requested names resolve to the same native package, TinyPM installs it once and reports the duplicate separately.

TinyPM also checks whether packages are already installed before starting a transaction, avoiding unnecessary reinstall requests.

Package aliases are stored in:

```text
src/share/tinypm/aliases.tsv
```

Mappings can therefore be reviewed or extended without modifying provider execution code.

## Typo protection

TinyPM detects likely command typos before passing anything to a package manager.

For example:

```bash
grab udpate
```

TinyPM suggests:

```bash
grab update
```

instead of attempting to install a package named `udpate`.

To intentionally install a package whose name resembles a TinyPM command, use:

```bash
grab -- udpate
```

## Package resolution

Use `grab explain` to inspect how a package will be handled without changing the system:

```text
$ grab explain --pacman gcc++

Package resolution

  Requested     gcc++
  Resolved      gcc
  Provider      Pacman
  Description   The GNU Compiler Collection - C and C++ frontends
  Reason        Arch provides GCC and G++ together in the gcc package
  Command       pacman -S --noconfirm gcc
```

## TinyPM workflows

The full `tinypm` command exposes package tracking, bundles, history, synchronization, and maintenance tools:

```bash
tinypm managed
tinypm pin firefox
tinypm unpin firefox
tinypm history 100
tinypm undo

tinypm bundle list
tinypm bundle Gaming

tinypm sync packages.txt
tinypm sync --generate packages.txt

tinypm discover editor
tinypm apps

tinypm doctor --fix
tinypm selftest
```

## Selecting a package provider

Provider flags may appear before or after package names where appropriate.

| Flag              | Provider                                      |
| ----------------- | --------------------------------------------- |
| `-n`, `--native`  | Automatically detected native package manager |
| `-f`, `--flatpak` | Flatpak                                       |
| `-s`, `--snap`    | Snap                                          |
| `--apk`           | Alpine APK                                    |
| `--apt`           | APT                                           |
| `--dnf`           | DNF                                           |
| `--pacman`        | Pacman                                        |
| `--xbps`          | XBPS                                          |
| `--zypper`        | Zypper                                        |
| `--emerge`        | Gentoo Portage                                |
| `--eopkg`         | Solus eopkg                                   |
| `--swupd`         | Clear Linux swupd                             |
| `--slackpkg`      | Slackware slackpkg                            |
| `--opkg`          | OpenWrt opkg                                  |
| `--urpmi`         | Mageia URPMI                                  |
| `--guix`          | GNU Guix                                      |
| `--brew`          | Homebrew                                      |
| `--nix`           | Nix                                           |

Examples:

```bash
grab --pacman firefox
grab neovim --apt
grab --flatpak org.gimp.GIMP
grab --nix ripgrep
```

## Alpine Linux

Alpine Linux is a first-class TinyPM V4 backend.

Install TinyPM with APK selected explicitly:

```bash
./install.sh --native apk -y
```

Use the Alpine backend:

```bash
grab --apk curl bash git
grab search --apk neovim
grab update --apk
grab remove --apk curl
```

### APK repository tags

Repository URLs may optionally receive an APK tag:

```bash
grab-add-repo --apk \
  https://dl-cdn.alpinelinux.org/alpine/edge/community edge
```

This creates an entry similar to:

```text
@edge https://dl-cdn.alpinelinux.org/alpine/edge/community
```

Packages can then be installed from that repository:

```bash
grab --apk package@edge
```

Repository additions are idempotent and refresh repository metadata without upgrading the entire system.

## Adding repositories

`grab-add-repo` translates repository sources into the correct native backend operation.

```bash
grab-add-repo ppa:owner/project
grab-add-repo --dnf copr:owner/project
grab-add-repo --pacman 'myrepo=https://example.com/$arch'
grab-add-repo --nix https://nixos.org/channels/nixos-unstable unstable
grab-add-repo --brew owner/tap
```

Supported repository systems include:

* APT repositories and PPAs
* DNF repositories and COPR
* Zypper repositories
* Alpine APK repositories
* Pacman repositories
* XBPS repositories
* Homebrew taps
* Solus eopkg repositories
* Mageia URPMI media
* OpenWrt opkg feeds
* Nix channels

Declarative or specialized source systems—including Guix channels, Portage overlays, swupd mixers, and slackpkg mirrors—receive instructions instead of potentially unsafe automatic edits.

## Distribution coverage

TinyPM detects the following package managers:

| Manager    | Distribution families                                |
| ---------- | ---------------------------------------------------- |
| `apt`      | Debian, Ubuntu, Mint, Pop!_OS, Kali, and derivatives |
| `dnf`      | Fedora, RHEL, CentOS Stream, Rocky Linux, AlmaLinux  |
| `pacman`   | Arch Linux, Manjaro, EndeavourOS, Garuda, CachyOS    |
| `zypper`   | openSUSE and SUSE                                    |
| `apk`      | Alpine Linux and newer APK-based OpenWrt systems     |
| `xbps`     | Void Linux                                           |
| `emerge`   | Gentoo                                               |
| `eopkg`    | Solus                                                |
| `swupd`    | Clear Linux                                          |
| `slackpkg` | Slackware                                            |
| `opkg`     | OpenWrt 24.10 and older, plus embedded Linux systems |
| `urpmi`    | Mageia                                               |
| `guix`     | GNU Guix System                                      |
| `nix`      | NixOS, Abora, and other Nix environments             |
| `brew`     | Linuxbrew and macOS                                  |

Flatpak and Snap are available as optional providers.

TinyPM cannot guarantee compatibility with every private, experimental, or future distribution. Unsupported environments fail clearly instead of guessing or invoking the wrong package manager.

### OpenWrt safety

TinyPM refreshes opkg metadata without performing a blanket package upgrade.

Mass-upgrading every opkg package can leave OpenWrt systems unstable or unbootable, so TinyPM avoids that behavior.

Newer OpenWrt releases using APK are detected through the APK backend automatically.

## Desktop environments

Use `grab-de` to install supported desktop environments on imperative distributions:

```bash
grab-de gnome
grab-de plasma
grab-de xfce
grab-de cosmic
```

### NixOS

Desktop environments on NixOS are declarative. TinyPM prints the appropriate `configuration.nix` settings instead of creating an incomplete `nix-env` profile.

### Abora

When ANIX is available, TinyPM uses it as Abora's native system-management path:

```bash
grab firefox
# anix package add firefox
# anix apply
```

```bash
grab remove firefox
# anix package remove firefox
# anix apply
```

```bash
grab-de gnome
# anix set desktop gnome
# anix apply
```

Disable ANIX integration:

```bash
TINYPM_NO_ANIX=1 grab firefox
```

Update the ANIX configuration without applying it immediately:

```bash
TINYPM_ANIX_APPLY=0 grab firefox
```

## Terminal output

Color is enabled automatically in interactive terminals.

Disable color using the conventional environment variable:

```bash
NO_COLOR=1 grab firefox
```

Force color when output is redirected:

```bash
FORCE_COLOR=1 grab firefox
```

Disable animated progress output:

```bash
TINYPM_NO_SPINNER=1 grab firefox
```

Interactive installations include a colored Pac-Man chase animation. Redirected output and CI logs remain plain and stable.

## Development

Build and run the smoke tests:

```bash
./build.sh
./scripts/e2e-smoke.sh
```

Run ShellCheck:

```bash
shellcheck -x -e SC1090 -e SC1091 \
  scripts/*.sh \
  src/bin/* \
  src/lib/tinypm/core/*.sh \
  src/lib/tinypm/providers/*.sh
```

The smoke suite validates:

* Source-tree commands
* Terminal color behavior
* Runnable release builds
* Clean local installation
* Flavor installation
* Package installation and search
* Package updates
* Repository operations
* A simulated Alpine APK backend

Continuous integration also runs TinyPM inside Ubuntu, Fedora, Arch Linux, Alpine Linux, and openSUSE containers.

## Project layout

```text
src/bin/                     Command entrypoints
src/lib/tinypm/core/         Parsing, actions, state, history, and UI
src/lib/tinypm/providers/    Package managers, repositories, DEs, and ANIX
src/share/tinypm/            Catalogs, aliases, flavors, and assets

scripts/build.sh             Release builder
scripts/install.sh           Local installer
scripts/e2e-smoke.sh         Cross-backend smoke suite

tests/resolver.sh            Alias and package-resolution tests

build/tinypm-v4/bin/         Generated runnable commands

build.sh                     Root build entrypoint
install.sh                   Root installation entrypoint
```

## License

TinyPM V4 is licensed under the GNU General Public License v3.0.

See [LICENSE](LICENSE) for the complete license text.

```

This version keeps all the technical detail, but makes the README much easier to scan. I also moved the strongest selling points near the top, reduced repeated wording, converted the long provider and distro sections into tables, and made the Abora/ANIX behavior clearer.
```
