# Abora Install Checklist

Use this after building a release candidate ISO and after running one real install.

## Live Session

- ISO reaches the boot menu without dropping to an emergency shell
- live desktop starts successfully
- networking works in the live session
- `/etc/abora/default-wallpaper.png` exists
- pre-desktop extension prompt appears before display manager starts

## Installer

- installer opens from the live desktop
- installer shows Abora logo branding
- disk selection and user creation remain interactive
- install completes without fatal errors

## Installed System

- installed system boots without the ISO attached
- login manager starts
- desktop session launches successfully
- networking is enabled and functional

## Bug Report

Collect:

```sh
journalctl -b --no-pager
```

and attach installer logs if available.
