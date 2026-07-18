# Abora Tools

Abora includes a small command layer for distro-specific tasks.

Use these commands for Abora health, setup, recovery, desktop selection, updates, support reports, and system configuration.

## Main Commands

| Command | Purpose |
|---|---|
| `abora welcome` | Show first-step status and useful actions |
| `abora doctor` | Check install health, Flatpak, themes, boot assets, updates, and ANIX |
| `abora recovery` | Rollback, rebuild, repair, and support actions |
| `abora setup` | Installed reconfiguration launcher |
| `abora config` | View or change installed Abora settings |
| `abora desktop list` | List supported desktop profiles |
| `abora desktop set <profile>` | Change desktop profile |
| `abora apps` | App bundle and catalog helpers |
| `abora support-report` | Collect support diagnostics |
| `abora update` | Update Abora |
| `abora channel` | View or change the update channel |
| `abora rollback` | Roll back to the previous system generation |
| `abora install pre-alpha` | One-shot install of unfinished pre-alpha development builds |

## Normal Installed Workflow

```sh
abora doctor
anix status
anix --gui
tinypm sources
sudo abora update
```

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
abora config apply
```

For ANIX-managed values:

```sh
anix set hostname my-pc
anix set desktop hyprland
anix apply
```

Bundled wallpapers: `Daytime-MNT.jpg`, `NightTime-MNT.png`, `alpine-glacier.jpg`,
`tannheimer-mountains.jpg`, `titlis-alps.jpg`, `aurora-lofoten.jpg`, plus the
`abora-dark.svg`/`abora-light.svg` originals. Source and license for each photo
are in [assets/wallpapers/CREDITS.md](../../assets/wallpapers/CREDITS.md).

```sh
abora config set wallpaper titlis-alps.jpg
```

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

## App Layer

Use TinyPM for apps:

```sh
grab firefox
tinypm search krita
tinypm sources
```

Use ANIX or Abora config for system-level changes.

## Support

Collect a report:

```sh
abora support-report
```

Run health checks:

```sh
abora doctor
anix doctor
tinypm doctor
```
