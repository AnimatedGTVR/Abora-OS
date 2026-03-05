# Abora Install Checklist

Use this after building a release candidate ISO and after running one real install.

## Live Session

- ISO reaches the boot menu without dropping to an emergency shell
- `Install Abora OS` appears on the desktop
- Plasma session loads
- wallpaper is the Abora default wallpaper
- `tinypm`, `syspm`, and `abora-doctor` exist in the live session
- networking works in the live session

## Installer

- `Install Abora OS` opens the Abora installer wrapper
- `archinstall` launches with Abora defaults preloaded
- disk selection and user creation still remain interactive
- install completes without fatal errors

## Installed System

- installed system boots without the ISO attached
- SDDM starts
- Plasma session launches successfully
- NetworkManager is enabled and functional
- TinyPM is installed and runnable
- `abora-doctor` reports the expected services and wallpaper
- wallpaper and Plasma defaults match the live session

## Bug Report

If the install or first boot fails, capture:

```sh
abora-doctor --report
```

and collect anything relevant from:

```sh
journalctl -b --no-pager
```
