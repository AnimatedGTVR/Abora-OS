# Abora OS v2.5.0

Abora OS v2.5.0 is about making the system feel easier to live with after install.

The big theme for this release is management: clearer commands, safer updates, better rollback paths, a real first-run welcome, and less need to remember raw Nix commands just to take care of the machine.

---

## Highlights

### A Real Abora Command Layer

Abora now has a friendlier command front door:

```sh
abora welcome
abora doctor
abora recovery
abora desktop list
abora desktop set gnome
```

`abora welcome` gives users a first-step status screen with the current desktop, wallpaper, update channel, Flathub state, and ANIX state.

`abora doctor` checks the installed Abora tooling, Flatpak/Flathub, update channel, desktop config, boot assets, theme sync files, and ANIX health.

`abora recovery` gathers the scary stuff in one place: rollback, rebuild, Flathub repair, support reports, and doctor checks.

### ANIX Is Becoming The Human Layer

ANIX now wraps common NixOS workflows in commands that read more like normal OS management:

```sh
anix switch nix gaming
anix rollback nix
anix rollback nix minimal
anix save
anix doctor
```

Named profiles now point to real flake outputs:

- `stable`
- `minimal`
- `gaming`
- `creator`
- `developer`

Snapshots stay local by default. ANIX also warns if it sees possible secrets before saving, and recommends moving real secrets to `sops-nix` or `agenix`.

### Safer Updates

Installed systems can track either `stable` or `unstable`:

```sh
nixos channel
nixos channel list
nixos channel set stable
nixos channel set unstable
```

Before an update rebuilds the system, Abora now offers to save a local ANIX snapshot first. That gives users a cleaner recovery point before changing the system.

### Easier System Configuration

`abora-local.nix` now uses simple `abora.*` options:

```nix
abora.hostname = "my-pc";
abora.timezone = "America/New_York";
abora.desktop  = "gnome";
```

And `abora config` can edit the safe settings without opening the Nix file by hand:

```sh
abora config
abora config set hostname my-pc
abora config set timezone America/New_York
abora config set desktop hyprland
abora config apply
```

`user` and `disk` stay read-only through the command for safety.

### Shared Terminal UI

The Abora terminal tools now share the same ocean-themed UI library. Headers, cards, progress bars, warnings, and success messages should feel like they belong to the same OS instead of a pile of unrelated scripts.

### Flatpak + Flathub

Flatpak is enabled on installed systems, and Flathub is added automatically on first boot when networking is available.

### App Catalog

The app catalog is now **52 apps across 6 categories**.

New categories:

- **Gaming:** Steam, Lutris, Heroic Games Launcher, Bottles, MangoHud, GameMode
- **System:** GParted, Disks, Timeshift, Flameshot, btop, Mission Center

Other new picks include Chromium, Bitwarden, Discord, Slack, Zoom, RawTherapee, Zed, tmux, Alacritty, Ghostty, Lazygit, and Docker.

Bundles:

- `favorites`
- `essentials`
- `social`
- `creator`
- `developer`
- `gaming`
- `system`

---

## Changed Files

| Area | What Changed |
|---|---|
| `scripts/abora.sh` | New top-level command router |
| `scripts/abora-welcome.sh` | First-step status and quick actions |
| `scripts/abora-doctor.sh` | Abora health checker |
| `scripts/abora-recovery.sh` | Rollback, repair, rebuild, and diagnostics menu |
| `scripts/abora-desktop.sh` | Desktop profile helper |
| `scripts/anix.sh` | Profile switching, rollback, snapshots, config, and doctor |
| `scripts/abora-config.sh` | Installed-system settings editor |
| `scripts/abora-update.sh` | Update channels, snapshots before rebuilds, profile-aware flakes |
| `scripts/abora-apps.sh` | Styled catalog and installed-app views |
| `scripts/abora-app-catalog.sh` | 52 apps across 6 categories |
| `scripts/abora-hardware-test.sh` | Shared UI styling |
| `scripts/abora-installer.sh` | New config format and named profile outputs |
| `scripts/abora-ui.sh` | Shared terminal UI library |
| `nix/modules/abora-options.nix` | `abora.*` NixOS option namespace |
| `nix/modules/installed-base.nix` | Management commands, Flatpak, MOTD, first-shell welcome |
| `nix/profiles/live.nix` | New commands included in the ISO |
| `Makefile` | New `make preflight` target |

---

## Upgrade Notes

Existing v2.5 installs can update with:

```sh
sudo nixos update
```

The updater syncs the new Abora files into `/etc/nixos/abora/`, updates the flake, and rebuilds.

Older installs that still use the pre-v2.5 config format will not automatically become full `abora.*` systems. For those, reinstalling from the v2.5 ISO is the cleanest path. Manual migration is possible by rewriting `abora-local.nix` to use the new options format.

---

## Release Assets

- `abora-v2.5.0-x86_64.iso`
- `SHA256SUMS-v2.5.0.txt`
- `RELEASE_MANIFEST-v2.5.0.txt`

---

## Known Limits

- `abora config` does not edit `user` or `disk`.
- Flathub setup needs network after first boot.
- ANIX snapshots are local unless `anix config set snapshots.push true` is enabled.
- Named ANIX profiles are flake configs, not raw `/nix/var/nix/profiles` symlinks.

---

## Validation Focus

Before tagging, run:

```sh
make preflight
```

For hardware testing, focus on:

1. Live ISO boots and the installer completes cleanly.
2. Fresh install writes the new `abora.*` config format.
3. `abora welcome`, `abora doctor`, `abora recovery`, and `abora desktop list` work.
4. `abora config` can read and change safe settings.
5. `nixos channel set unstable` followed by `nixos update` tracks main.
6. `abora-apps add <id>` works for Gaming and System catalog entries.
7. Flatpak and Flathub are available after first boot.
8. `anix switch nix gaming --now` targets `/etc/nixos#gaming`.
9. `anix rollback nix` uses `nixos-rebuild switch --rollback`.
