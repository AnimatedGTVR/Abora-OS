# Abora Install Checklist

Use this after building a release candidate ISO and after running one real install.

## Live Session

- ISO reaches the boot menu without dropping to an emergency shell
- `Install Abora OS` appears on the desktop
- Plasma session loads
- wallpaper is the Abora default wallpaper
- `abora-doctor` exists in the live session
- networking works in the live session

## Installer

- `Install Abora OS` opens Calamares
- Abora branding appears inside the installer
- disk selection and user creation remain interactive
- install completes without fatal errors

## Installed System

- installed system boots without the ISO attached
- SDDM starts
- Plasma session launches successfully
- NetworkManager is enabled and functional
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
