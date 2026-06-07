# Abora OS Roadmap

This roadmap tracks the current Abora direction after the v2.5 installer work and the start of v3 Denali.

## v2 Era Summary

The v2 line moved Abora from a branded NixOS ISO toward a real OS experience:

- NixOS-based live ISO with branded boot, Plymouth, wallpapers, Fastfetch, and Limine assets
- terminal-first live boot flow with a guided installer
- selectable desktop profiles instead of one default desktop path
- installer-generated `/etc/nixos` layout with copied Abora assets under `/etc/nixos/abora`
- Abora commands for welcome, config, desktop selection, doctor, recovery, support reports, updates, and hardware checks
- ANIX as a beginner-friendly management layer for snapshots, rollback, profile switching, and config edits
- TinyPM vendored into the repo and exposed as Abora-flavored `grab`, `search`, `term`, `start`, and `supdate`
- release output split into ISO, TinyPM package, checksums, manifest, and release notes

## v2.5 Delivered

v2.5 was mainly a reliability and polish release.

- forced NetworkManager on in the live ISO so Wi-Fi setup works in stage one
- added `nmtui`/`nmcli` network setup paths to the installer
- remade the installer into a keyboard-first TUI flow
- added install progress output and clearer failure logs
- fixed flake-based `nixos-install` crashes by using the generated non-flake config for install
- validated bootloader output after install before reporting success
- fixed wallpaper packaging so empty or changed wallpaper directories do not break builds
- fixed GNOME package/config duplication in generated `abora-local.nix`
- fixed GNOME and LightDM option paths for the current nixpkgs
- verified all supported desktop profiles with `scripts/check-desktops.sh`, including Openbox
- added `make qemu-disk`, `make qemu-fresh`, and serial QEMU helpers
- made `make iso` build only the ISO
- made `make release` build the ISO, TinyPM package, and release metadata
- removed restricted Nix build options that caused warning spam for untrusted users
- added setup launcher assets to the live ISO and installed config tree so installed-system eval does not look for `/mnt/etc/scripts`

## v3 Denali Direction

v3 Denali is the current design and stabilization track.

- keep the Omarchy-inspired installer style: large Abora wordmark, compact boxed fields, and minimal prompts
- keep install validation strict enough to fail early before expensive `nixos-install` work
- make the installed desktop setup app useful for post-install reconfiguration
- keep the desktop matrix green across GNOME, Plasma, Hyprland, Sway, XFCE, Cinnamon, MATE, Budgie, LXQt, Pantheon, i3, AwesomeWM, Openbox, Niri, River, Qtile, BSPWM, Fluxbox, IceWM, and Herbstluftwm
- make Abora stand apart from SnowflakeOS, Guix System, and GNOME-over-Nix by focusing on a distro-like NixOS onboarding path, strong branding, and friendly system management commands
- add more automated VM install smoke tests after ISO build
- keep QEMU install tests focused on clean disks with `make qemu-fresh`
- improve hardware test coverage for Wi-Fi laptops, NVIDIA systems, BIOS boot, and UEFI boot
- document known install blockers immediately instead of letting users discover them late

## Release Direction

- keep GitHub releases as the primary public ISO distribution path
- attach ISO, checksums, manifest, release notes, and TinyPM package to release bundles
- require `check-scripts`, `check-desktops`, one full VM install, and one installed-system boot before publishing
- use `make iso` for fast ISO-only iteration
- use `make release` only for full release bundles
