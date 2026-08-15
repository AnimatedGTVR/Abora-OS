# Abora Tools

Abora includes a small command layer for distro-specific tasks.

Use these commands for Abora health, setup, recovery, desktop selection, updates, support reports, and system configuration.

## Main Commands

| Command | Purpose |
|---|---|
| `abora learn` | Show the short beginner cheat sheet |
| `abora welcome` | Show first-step status and useful actions |
| `abora welcome-gui` | Graphical version of the above — status card, update check, and quick actions in a window. Opens once automatically on first desktop login |
| `abora doctor` | Check install health, Flatpak, themes, boot assets, updates, and ANIX |
| `abora network` | Diagnose Wi-Fi, DNS, NetworkManager, and Abora cache/update reachability |
| `abora logs` | Show recent live installer/config logs if present |
| `abora bug-report` | Print a copy-pasteable Discord/GitHub bug report template |
| `abora recovery` | Rollback, rebuild, repair, and support actions |
| `abora setup` | Installed reconfiguration launcher |
| `abora config` | View or change installed Abora settings |
| `abora config-gui` | Graphical settings editor — same settings as `abora config`, no terminal required |
| `abora desktop list` | List supported desktop profiles |
| `abora desktop set <profile>` | Change desktop profile |
| `abora dotfiles` | Import shell, app, and tiling-window-manager dotfiles |
| `abora gaming` | Check gaming tools and launch Steam Big Picture |
| `abora gaming enable` | Enable desktop gaming and the Big Picture launcher |
| `abora config set gaming true` | Enable the optional gaming layer |
| `abora apps` | App bundle and catalog helpers |
| `abora apps custom` | Update standalone custom packages such as Modularity Stable |
| `abora support-report` | Collect support diagnostics |
| `abora update` | Update Abora |
| `abora update --check` | Check whether an update is available without installing it |
| `abora channel` | View or change the update channel |
| `abora rollback` | Roll back to the previous system generation |
| `abora install pre-alpha` | One-shot install of unfinished pre-alpha development builds |

## Normal Installed Workflow

```sh
abora learn
abora doctor
anix status
anix learn
anix --gui
tinypm sources
abora apps custom list
sudo abora update
```

## Easy Command Map

Start here when you forget what to type:

```sh
abora learn
anix learn
```

Use `abora` for distro tasks: updates, recovery, desktop switching, apps, gaming,
support reports, and NixOS adoption. Use `anix` for the Nix config layer:
hostname, timezone, wallpaper, packages, feature toggles, snapshots, rebuilds,
and rollback.

## Pre-Alpha Builds

Pre-alpha builds are unfinished development versions for testing and feedback only. They may fail to boot, break applications, lose data, or require manual recovery.

Preview the selected development ref without changing the system:

```sh
sudo abora install pre-alpha --dry-run
```

Install the default pre-alpha ref:

```sh
sudo abora install pre-alpha
```

Install a specific branch or tag:

```sh
sudo abora install pre-alpha --ref my-test-branch
```

The command is one-shot: it does not switch your saved update channel. You must type `I ACCEPT THE RISK` exactly before it continues.

## Configuration

Show current config:

```sh
abora config
```

Change common values:

```sh
abora config set hostname my-pc
abora config set timezone America/New_York
abora config set desktop gnome
abora config set gpu nvidia   # or nouveau, nvidia-open, amdgpu, intel, none, auto
abora config set diagnostics true
abora config set vm-guests true
abora config set mobile-broadband true
abora config apply
```

Abora keeps the default install light. Hardware diagnostics, VM guest agents,
and cellular modem support are opt-in so normal laptop/desktop installs do not
carry tools and services they may never use.

For ANIX-managed values:

```sh
anix set hostname my-pc
anix set desktop hyprland
anix apply
```

## Custom Packages

Standalone packages that do not come from normal Nixpkgs can be updated with
the custom package helper. Modularity Stable is the first supported package:

```sh
abora apps custom info modularity-stable
sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity-7.0.0-Linux.zip
```

Bundled wallpapers: `titlis-alps.jpg`, `aurora-lofoten.jpg`, `alpine-glacier.jpg`,
`tannheimer-mountains.jpg`, plus the `abora-dark.svg`/`abora-light.svg`
originals. Source and license for each photo are in
[assets/wallpapers/CREDITS.md](../../assets/wallpapers/CREDITS.md).

```sh
abora config set wallpaper titlis-alps.jpg
```

## Graphical Tools

Prefer a window over the terminal for everyday tasks? Two GTK4/libadwaita apps cover the two most common ones, and both are thin front-ends over the same CLI commands above — nothing they do is exclusive to the GUI:

```sh
abora welcome-gui   # status card, "Check for Updates" / "Update Now", quick actions
abora config-gui    # hostname, timezone, keyboard, desktop, wallpaper, GPU driver
```

`abora welcome-gui` opens automatically the first time you log into your desktop after installing (it won't reappear on later logins), and both are always reachable afterward from your application menu or by running the commands above directly.

## Desktop Profiles

List profiles:

```sh
abora desktop list
```

Switch profile:

```sh
abora desktop set plasma
```

Then rebuild or apply through the relevant Abora/ANIX flow.

## Dotfiles

Hyprland and Other Environment installs can save a dotfiles Git URL during
install. Abora imports it automatically on the first successful desktop login
and writes a log to `~/.local/state/abora/dotfiles-import.log`.
`abora support-report` and `abora check-full` include the log when it exists.

Run the importer manually at any time:

```sh
abora dotfiles --dry-run ~/dotfiles
abora dotfiles ~/dotfiles
abora dotfiles --git-url https://github.com/you/dotfiles
```

By default existing files are kept. Add `--replace` only when you want the
incoming dotfiles to overwrite files already in your home folder.

## App Layer

Use TinyPM for apps:

```sh
grab firefox
tinypm search krita
tinypm sources
```

Use ANIX or Abora config for system-level changes.

## Network

When Wi-Fi, DNS, or updates fail, start with:

```sh
abora network
```

It prints NetworkManager status, Wi-Fi radio state, visible networks, DNS
status, ping reachability, and Abora/Nix cache reachability. The longer
`abora recovery network` command opens the same diagnostic path.

When an install failed in the live ISO, start with:

```sh
abora logs --lines 200
```

It tails `/tmp/abora-install.log` and `/tmp/abora-config.log` when they exist.

## Support

Collect a report:

```sh
abora support-report
```

Save it somewhere specific:

```sh
abora support-report --output-dir ~/Desktop
```

Support archives redact obvious password, token, secret, and API key lines
from copied logs/config snippets. Review the archive before posting it publicly.
For full reports, use the [bug report template](../bug-report-template.md).
You can print it from a terminal with:

```sh
abora bug-report
```

Or open a GitHub issue draft with the GitHub CLI:

```sh
abora bug-report --github --web
```

To create a support archive first and mention its local path in the issue body:

```sh
abora bug-report --github --web --with-support-report
```

GitHub CLI cannot attach the archive file directly from this command. Drag the
generated `abora-support-*.tar.gz` file into the issue before submitting, or
attach it in a follow-up comment.

Run health checks:

```sh
abora doctor
anix doctor
tinypm doctor
```
