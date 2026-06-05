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
| `abora update` | Abora update helper used by `sudo nixos update` |

## Normal Installed Workflow

```sh
abora doctor
anix status
anix --gui
tinypm sources
sudo nixos update
```

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
abora config apply
```

For ANIX-managed values:

```sh
anix set hostname my-pc
anix set desktop hyprland
anix apply
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
