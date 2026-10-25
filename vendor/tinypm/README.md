<p align="center">
  <img src="src/share/tinypm/assets/TinyLogo.png" alt="TinyPM" width="500">
</p>

# TinyPM 0.8.1-alpha

TinyPM provides one friendly package workflow across Linux distributions.
This release begins a ground-up Rust implementation; the previous Bash runtime
is being retired and is not part of the new architecture.

The two binaries have separate roles:

- `grab` installs, removes, updates, and reverses package transactions.
- `tinypm` inspects packages, checks availability, diagnoses providers, and
  reads TinyPM state. It does not change installed packages.

> The Rust edition is alpha software. Use `--dry-run` before allowing TinyPM to
> change packages on a real system.

## Install a release archive

Download the archive and matching `.sha256` file for your architecture and
libc, then verify the download before extracting it:

```console
sha256sum --check tinypm-linux-x86_64-gnu.sha256
tar -xzf tinypm-linux-x86_64-gnu.tar.gz
```

Install both Rust binaries in a directory on your `PATH`:

```console
mkdir -p ~/.local/bin
install -m 0755 tinypm-linux-x86_64-gnu/grab ~/.local/bin/grab
install -m 0755 tinypm-linux-x86_64-gnu/tinypm ~/.local/bin/tinypm
```

Use `grab` for package changes and `tinypm` for inspection and diagnostics.
The release does not use the retired Bash installer. To install directly from
a source checkout instead, run `cargo install --path . --locked`.

## Build

Rust 1.85 or newer is required.

```console
cargo build
cargo test
cargo run -- --help
```

Contributors can run the local release gates with `make release-check`; see
`CONTRIBUTING.md` for its audit-tool prerequisite and CI-only target checks.

For a release build:

```console
cargo build --release
```

The release output contains both executables:

```text
target/release/grab
target/release/tinypm
```

Tag builds package both binaries, the license, changelog, and README in four
archives:

- `tinypm-linux-x86_64-gnu.tar.gz` for glibc distributions
- `tinypm-linux-x86_64-musl.tar.gz` for Alpine, musl, and broadly portable
  Linux installations
- `tinypm-linux-aarch64-gnu.tar.gz` for ARM64 glibc distributions
- `tinypm-linux-aarch64-musl.tar.gz` for ARM64 Alpine, OpenWrt, and portable
  musl installations

Each archive has a matching `.sha256` checksum. CI compiles the musl target and
also checks the crate with Rust 1.85 to enforce the declared minimum supported
Rust version. A version-matching `v*` tag publishes all four archives and their
checksums to GitHub Releases after the packaged binaries pass smoke tests.
Provider auto-detection is additionally exercised inside Ubuntu, Fedora, Arch
Linux, Alpine, and openSUSE userspaces.

## Commands available in the first Rust milestone

```console
grab <PACKAGE>...
grab add <PACKAGE>...
tinypm search <QUERY>
tinypm info <PACKAGE>
tinypm check <PACKAGE> [--json]
grab remove <PACKAGE>...
grab update
tinypm list
tinypm explain <PACKAGE>
tinypm doctor
tinypm providers
tinypm history [LIMIT]
tinypm managed
tinypm undo [--json]
grab undo --yes
tinypm completions <SHELL>
```

Choose a provider with `--provider` and preview an operation with `--dry-run`:

```console
grab --provider pacman --dry-run add gcc++
tinypm --provider apk explain gcc++
```

`info` prints detailed provider metadata. `check` performs a quiet availability
probe, prints a concise result, and returns a nonzero status when unavailable.
`explain` shows the resolved provider name, whether a catalog alias was used,
the reason for that mapping, and the exact install command. Use
`tinypm explain <PACKAGE> --json` for structured resolution data.

When the binary is invoked as `grab`, installing remains the default action:

```console
grab firefox
grab search neovim
```

## Shell completions

Completion definitions are generated from the Rust CLI, so they always match
the installed version. For example:

```console
tinypm completions bash > ~/.local/share/bash-completion/completions/tinypm
tinypm completions zsh > ~/.local/share/zsh/site-functions/_tinypm
tinypm completions fish > ~/.config/fish/completions/tinypm.fish
grab completions bash > ~/.local/share/bash-completion/completions/grab
```

Generated `tinypm` completions contain only inspection and diagnostic
commands. Generated `grab` completions include the package-changing workflow.

## Providers

The Rust provider layer currently supports APT, DNF, Pacman, APK, Zypper,
XBPS, Portage, eopkg, swupd, slackpkg, opkg, URPMI, Guix, Moss, TazPkg,
prt-get, Nix, Homebrew, Flatpak, and Snap. Moss support targets AerynOS's atomic
package and system state workflow; TazPkg supports SliTaz repository packages;
and prt-get uses CRUX's dependency-aware ports workflow. Native provider
detection follows the distribution family in `/etc/os-release` (or
the standard `/usr/lib/os-release` vendor fallback), then uses the first
supported package manager found in `PATH`. Override detection with `--provider`
or the `TINYPM_PROVIDER` environment variable.

Derivative detection also recognizes common APT, DNF, Pacman, APK, and Zypper
families including Kali, elementary OS, Devuan, Oracle Linux, Nobara, Artix,
Garuda, CachyOS, postmarketOS, Chimera Linux, and SUSE Linux Enterprise.
See [`docs/PROVIDERS.md`](docs/PROVIDERS.md) for the validation level of every
backend and the acceptance criteria for additional managers.

Before installing, TinyPM deduplicates names that resolve to the same package
and asks providers with reliable query support whether each package is already
installed. Skipped packages are not written to transaction history. Dry runs
remain side-effect free and show the complete requested plan.

Removal uses the same preflight in reverse: packages confirmed absent are
skipped, while unknown provider state is never treated as proof of absence.

Package identifiers are validated before provider execution. Option-like names
beginning with `-`, whitespace, control characters, and shell syntax are
rejected before any package-manager process starts.

Root-required providers use `sudo` when available and fall back to `doas`.
When neither helper exists, `grab` stops before provider execution with a clear
message; running as root needs no helper.

Package-changing batches execute one package at a time. TinyPM continues after
an individual failure, records only successful operations, prints a final
summary, and returns a failing exit status if any package failed.

Interactive installs and removals show an animated spinner with the provider
and batch position; updates show the selected provider and completion state.
Animation disables itself when output is redirected or the
terminal is noninteractive. Use `--no-progress` or set `TINYPM_NO_PROGRESS=1`
for stable line-oriented output explicitly; provider output and authentication
prompts remain visible in every mode.

## State

After a successful install or removal, TinyPM appends a transaction to
`$XDG_STATE_HOME/tinypm/history.jsonl` (or
`~/.local/state/tinypm/history.jsonl`). `tinypm managed` derives its result
from this durable log, so the history remains the single source of truth.
`tinypm undo` previews the latest available reversal; `grab undo --yes`
executes it.

Undo previews use the provider recorded in history but do not require that
provider to exist on the current host. Confirmed reversals through
`grab undo --yes` require the recorded executable and only append history after
it succeeds.

History readers and writers use cross-process file locks. Each JSONL record is
fully encoded before it is appended, preventing concurrent TinyPM processes
from interleaving or exposing partial transaction data.
New transactions use UUID string identifiers, while numeric and ID-less records
from earlier Rust alpha builds remain readable.

Both state views support stable structured output for scripts:

```console
tinypm history 10 --json
tinypm managed --json
```

`tinypm doctor` checks the selected provider's complete executable set and
TinyPM transaction state. It reports the resolved primary executable, missing
companion tools, history location, record count, and overall health. Use
`tinypm doctor --json` for structured support data.

`tinypm providers` lists every supported backend, whether its full command set
is ready, its validation level, and any missing companion executables.
`tinypm providers --json` exposes the same registry to tools while retaining
primary-executable availability separately from complete readiness.

## Version direction

- `0.8.1-alpha`: active Rust rewrite
- `0.10.0`: planned first stable Rust release

TinyPM is licensed under the GNU General Public License v3.0.
