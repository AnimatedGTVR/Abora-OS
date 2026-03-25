# Abora Install Checklist

Use this after building a release candidate ISO and after running one real install.

## Live Session

- ISO reaches the boot menu without dropping to an emergency shell
- boot menu opens on `tty1`
- `Abora Welcome` opens from the boot menu
- `Abora Center` opens from the boot menu
- networking works in the live session
- `/etc/abora/default-wallpaper.png` exists
- Fastfetch shows the Abora ASCII logo

## Installer

- installer opens from the boot menu
- disk selection and user creation remain interactive
- install completes without fatal errors

## Installed System

- installed system boots without the ISO attached
- bootloader starts without manual repair
- login prompt starts
- networking is enabled and functional

## Bug Report

Collect:

```sh
journalctl -b --no-pager
```

and attach installer logs if available.
