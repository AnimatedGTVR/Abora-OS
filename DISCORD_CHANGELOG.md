# Security update: patched Linux kernels

several serious Linux kernel vulnerabilities were fixed upstream, including one in IPv4 networking and a local privilege escalation. details: https://www.aboraos.org/security

**what is patched right now:**
- **edge channel:** yes. the update carries kernel 7.3 and the other fixed kernels
- **v4.1 and older (stable channel):** not yet. `abora update` currently stops with an error on these (new NixOS removed two boot options old Abora still sets). it fails *before* changing anything, so your system is safe, but you can't get the new kernel by updating. **v4.2 Solstice ships in a few days and fixes this**

**what to do:**
- **on edge:** `sudo abora update`, then `sudo reboot`. an update alone doesn't protect you, you have to boot the new kernel (`uname -r` to check)
- **on v4.1 or older:** wait for v4.2. please don't downgrade, older releases have the same problem and the downgrade guard will stop you anyway

**if you really need the security fix before v4.2** (advanced, not tested on every setup):

```sh
# 1. back up, then remove the two options new NixOS no longer accepts
sudo cp /etc/nixos/abora/installed-base.nix /etc/nixos/abora/installed-base.nix.bak
sudo sed -E -i \
  '/^[[:space:]]*boot\.initrd\.(systemd\.enable|verbose)[[:space:]]*=/d' \
  /etc/nixos/abora/installed-base.nix

# 2. pull the newest packages (this includes the fixed kernel) and switch
cd /etc/nixos
sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#abora

# 3. boot into the new kernel
sudo reboot
```

do **not** run `abora update` or `anix update` after this until v4.2 is out, they put the original file back and fail again. if something goes wrong, pick the previous entry in the boot menu or run `sudo nixos-rebuild switch --rollback`. this downloads a lot, since it moves you to the newest packages and not just the kernel

---

# Abora OS v4.1.1

small one, but it matters for 4.2. `abora update` was copying a fixed list of files from your *old* version, so new files never showed up and removed ones never went away. that's fixed now.

**Changelog:**
- updates now install every file the new release needs, not just the ones your old version knew about
- files a release drops or renames get cleaned up on the next update
- only files the updater put there are ever removed. your own files, `apps.nix` and `apps.list` are never touched
- your first update just records what's installed, nothing gets removed

**How to update:** `sudo abora update`. on 4.0, run it twice (the first run brings in the new updater, the second uses it)

---

# Abora OS v4.1 Horizon

## Screenshots

<table>
<tr>
<td><img src="https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/Images/v4/screenshot-2026-07-27_03-54-02.png" width="340" alt="Abora Welcome on GNOME"></td>
<td><img src="https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/Images/v4/screenshot-2026-07-27_03-56-03.png" width="340" alt="Abora System Settings"></td>
</tr>
<tr>
<td><img src="https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/Images/v4/screenshot-2026-07-27_03-58-15.png" width="340" alt="fastfetch on GNOME"></td>
<td><img src="https://raw.githubusercontent.com/Abora-OS/Abora-OS/edge/assets/Images/v4/screenshot-2026-07-27_05-32-15.png" width="340" alt="fastfetch on COSMIC"></td>
</tr>
</table>

## What's New?

Horizon is the "make it actually work" release. Most of 4.1 is fixes from your install reports (#32 and #33): the installer now tells you *why* it failed instead of dumping a wall of Nix, there's a partition editor built right in, and a bunch of things that broke on real machines got fixed. Plus a few new bits: opt-in Labs, a community app, and a GUI for sending feedback.

## Changelog:

**Installer**
- partition editor built in: `cfdisk` in the TUI, a GParted button in the GUI
- install onto an existing partition without wiping the whole disk
- if an install fails it reads its own log and tells you the likely cause in plain English (bad signature, build failure, network drop, disk full)
- checks your clock before starting, since a wrong clock quietly breaks downloads
- Japanese/non-US keyboards: `jp106` no longer leaks into the desktop, you get `jp`
- password hashing can't silently fail anymore, and empty passwords are refused
- fixed the `target-flake.lock` nixpkgs mismatch
- fixed installs sitting at the .NET build step for ages
- login screen shows your name instead of "Abora User"

**New stuff**
- Abora Labs: opt-in at install, a workspace manager for experimental stuff. nothing experimental runs during install
- Abora Community: optional survey, Learn Nix, optional reminders
- feedback + bug report GUI, with the same redacted diagnostics as `abora support-report`
- adopt Abora on an existing NixOS install without reinstalling

**Fixes**
- Abora Welcome now actually opens on first login on KDE Plasma
- Flathub setup keeps retrying after first boot instead of giving up
- `abora update` with no args actually updates now (it was a no-op lol)
- `abora rollback` actually rolls back now
- Ventoy USBs boot again
- thermald is opt-in, it was breaking rebuilds on some desktops
- security: better redaction of Wi-Fi passwords and auth headers in support reports

**ANIX**
- ANIX v2 configs: ANIX Native or ModuCPP. MKO got dropped
- `anix diff-plan` still shows ADD/CHANGE/SAME before you touch anything

**Under the hood**
- support + release tooling moved from Bash to Python, same commands
- big audit pass across scripts, nix modules and the installer

**Still from Everest**
- 5 editions (Cosmic, Hyprland, GNOME, KDE, Other), GPU driver picking, Abora Gaming, TinyPM v0.8, all 23 desktops

**Known stuff**
- VirtualBox installs aren't fully validated yet. if one fails, try turning off 3D acceleration and send `/tmp/abora-install.log`
- Limine might print a scary `set_pos(): Invalid argument` line on UEFI. it's harmless

Update with `sudo abora update`. If anything goes sideways, `abora rollback`.

## 3.14

Abora DENALI 3.14 was the installer/identity/tooling release. Still the foundation everything above builds on:

- the Omarchy-style TUI installer with the boxed UI
- config gets validated before nixos-install runs
- Abora branding everywhere (bootloader, Plymouth, wallpapers, fastfetch)
- ANIX v1 (snapshots, diff/test/boot/switch/rollback)
- TinyPM v0.8
- 23 desktops selectable at install, COSMIC and MangoWM both added this release
- desktop matrix gets checked in CI so we don't ship a broken profile

## Other

- MINT (the Go/Bubble Tea installer front-end) is built but not wired up as the default yet, that's on hold for now
- if you hit an install issue, `abora support-report` or `abora hardware-test --with-report` before asking, saves everyone time
- as always, `stable` channel tracks tagged releases, `unstable` tracks edge if you like living dangerously
