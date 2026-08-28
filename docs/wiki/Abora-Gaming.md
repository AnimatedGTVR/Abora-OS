# Abora Gaming

Abora Gaming is an optional gaming layer for Abora OS, not a separate desktop lock-in.

The user should still choose any normal Abora desktop first: GNOME, KDE Plasma, COSMIC, Hyprland, Sway, MangoWM, or another supported profile. Gaming features are then enabled on top of that choice.

## Goals

- Keep desktop choice separate from gaming setup.
- Make Steam, Proton, game launchers, overlays, and controller support easy to enable.
- Support Steam Big Picture without forcing a console-style session.
- Offer Gamescope as an advanced console mode for users who want a SteamOS-like experience.
- Keep defaults safe for laptops and normal desktop users.

## Modes

### Desktop Gaming

The default mode. Abora boots into the selected desktop and installs the gaming tools selected by the user.

This mode should work across the normal Abora desktop matrix.

### Steam Big Picture Shortcut

Adds a launcher that runs Abora's Steam helper:

```sh
abora-steam-big-picture
```

The helper tries Steam's Gamepad UI mode first and falls back to the older Big Picture flag, so the launcher keeps working across Steam client changes.

### Steam Big Picture Autostart

Starts Steam Big Picture after desktop login. This is useful for living-room systems, but should remain opt-in because it can be annoying on laptops and shared desktops.

### Gamescope Console Session

Adds a separate fullscreen Gamescope/Steam session for a more console-like workflow:

```sh
abora-steam-gamescope-session
```

This should be marked advanced because Gamescope behavior depends more heavily on GPU drivers, display manager behavior, and controller/display setup. The wrapper falls back to Steam Big Picture directly if Gamescope is missing, and the Steam launcher falls back to legacy Big Picture mode if Gamepad UI fails.

## Options

The module starts small and keeps the gaming layer optional:

```nix
abora.gaming = {
  enable = false;
  steam = true;
  bigPictureShortcut = true;
  bigPictureAutostart = false;
  gamescopeSession = true;
  vulkanTools = true;
  controllerSupport = true;
  mangohud = true;
  gamemode = true;
  launchers = true;
};
```

`launchers = true` installs supported desktop launchers when they are present in the selected nixpkgs set.

## Packages

Core:

- Steam
- Heroic Games Launcher
- Lutris
- Bottles
- ProtonUp-Qt
- Wine and Winetricks
- MangoHud
- GameMode
- Gamescope
- Vulkan tools

Nice-to-have:

- Prism Launcher
- Vesktop or Discord
- GOverlay
- vkBasalt
- OBS Studio

## Installer Flow

After desktop selection, the installer asks:

```text
Gaming Setup

Enable Abora Gaming?

1. No gaming profile
2. Desktop gaming
3. Desktop gaming + Steam Big Picture shortcut
4. Big Picture console mode
```

Release default:

```text
No gaming profile
```

This keeps the normal install small and fast. Autostart remains a config-only option for now.

## Command

`abora gaming` reports the current gaming layer and launches Steam Big Picture:

```sh
abora gaming status
abora gaming welcome
abora gaming doctor
abora gaming enable
abora gaming steam on
abora gaming disable
abora gaming install steam
abora gaming install wine winetricks
abora gaming remove steam
abora gaming big-picture
abora gaming big-picture on
abora gaming session
abora gaming gamescope on
abora gaming controllers on
abora gaming mangohud on
abora gaming gamemode on
abora gaming vulkan on
abora gaming launchers on
abora gaming autostart off
abora gaming logs
abora gaming repair-cache
```

`abora gaming logs` is a shortcut to recent Abora installer/config logs when
you are debugging a failed Gaming install.

`abora gaming repair-cache` removes stale `~/.cache/nix/fetcher-cache-v*.sqlite*`
files. Use it when a Steam or launcher install fails with a local Nix
fetch-cache SQLite disk I/O error, then retry the install.

## Abora Gaming Welcome

A separate GTK app (`abora-gaming-welcome-gui`, or `abora gaming welcome`)
from Abora Welcome — Abora Welcome covers the system in general, this one
is dedicated to games: turning the gaming layer on, signing into Steam,
and installing a platform (Steam, Lutris, Heroic, Bottles, Wine,
Winetricks, GameMode, MangoHud) to get a game running through. Abora Welcome links to it once
gaming is enabled.

Enable the layer in `/etc/nixos/abora-local.nix`, then run `sudo abora update`:

```nix
abora.gaming.enable = true;
```

Or use the config helper:

```sh
abora config set gaming true
abora config set gaming.steam true
abora config set gaming.big-picture true
abora config set gaming.gamescope true
abora config set gaming.controllers true
abora config set gaming.mangohud true
abora config set gaming.gamemode true
abora config set gaming.vulkan true
abora config set gaming.launchers true
abora config apply
```

Or use the gaming helper:

```sh
abora gaming enable
abora gaming steam on
abora gaming install steam
abora gaming gamescope on
abora gaming controllers on
abora gaming mangohud on
abora gaming gamemode on
abora gaming launchers on
sudo abora update
```

To remove a gaming app later:

```sh
abora gaming remove steam
```

For Steam, removal also writes `abora.gaming.steam = false`, so the Gaming
module does not reinstall Steam on the next rebuild. It also clears Steam-only
session helpers such as Big Picture autostart, the Gamescope session, and
controller rules.

Or use ANIX:

```sh
anix enable gaming
anix enable gaming.steam
anix enable gaming.big-picture
anix enable gaming.gamescope
anix enable gaming.controllers
anix enable gaming.mangohud
anix enable gaming.gamemode
anix enable gaming.vulkan
anix enable gaming.launchers
anix apply
```

Gaming toggles are dependency-aware. For example, `anix enable gaming.big-picture`
also enables the gaming layer and Steam, while `anix disable gaming.steam`
turns off Steam-only helpers so the next rebuild does not bring Steam back
through a shortcut or session option.

Example status:

```text
Steam                 installed
GameMode              enabled
MangoHud              ready
Vulkan                ready
Wine                  installed
Winetricks            installed
32-bit graphics       ready
Controller rules      ready
Big Picture shortcut  enabled
Gamescope session     disabled
```

Future releases can add overlay controls and per-game profile helpers.
