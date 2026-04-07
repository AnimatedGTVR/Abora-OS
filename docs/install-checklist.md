# Abora Install Checklist

Use this after building a release candidate ISO and after running one real install.

## Live Session

- ISO reaches the boot menu without dropping to an emergency shell
- boot menu opens on `tty1`
- installer opens from the boot menu without dropping into a shell first
- installer welcome screen appears before disk/account questions
- installer pre-install setup screen shows keyboard, desktop, and starter app choices
- networking works in the live session
- `/etc/abora/default-wallpaper.png` exists
- `/etc/abora/themes/current.conf` exists
- `/etc/abora/wallpapers/` contains the curated wallpaper set
- Fastfetch shows the Abora ASCII logo

## VM Coverage

- QEMU install works end to end
- at least one Windows-host VM run is checked in VMware or Hyper-V
- if testing Hyper-V Generation 2, secure boot is disabled
- if testing VirtualBox, boot is checked with the default graphics controller first

## Installer

- installer opens from the boot menu
- hardware summary screen renders useful info
- `abora-support-report` works from the live environment
- disk selection and user creation remain interactive
- GitHub device login can be skipped cleanly
- install completes without fatal errors
- failed installs show a support report path when available

## Installed System

- installed system boots without the ISO attached
- bootloader starts without manual repair
- login prompt starts
- networking is enabled and functional
- on GNOME installs, Abora wallpapers appear in `Settings -> Appearance`
- on every supported desktop, the first login starts on the Abora default wallpaper
- on GNOME installs, picking an Abora wallpaper updates accent/style automatically

## Bug Report

Collect:

```sh
journalctl -b --no-pager
```

and attach installer logs if available.
