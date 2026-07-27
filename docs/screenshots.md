# Abora Screenshot Checklist

Use this when preparing docs, Discord updates, or release images. Capture from a
fresh ISO whenever possible so the screenshots match what users see.

## Installer

- live boot on `tty1` showing the Abora logo in color
- MINT welcome screen with `Install Abora OS to System`
- edition picker
- network step with the `nmtui` option visible
- timezone region picker and timezone search result
- disk selection
- final install review
- install progress or failure screen with log path visible

## Installed System

- first boot desktop with the Abora wallpaper
- `abora welcome` or welcome GUI
- `abora config` or config GUI
- `anix language list` showing ANIX Native, MAKO, and ModuCPP
- `anix diff-plan examples/anix-v2/workstation.mko`
- `anix diff-plan examples/anix-v2/workstation.moducpp`

## Naming

Store final docs screenshots under `docs/screenshots/` when they are committed.
Use short lowercase names, for example:

```text
installer-welcome-tty.png
installer-timezone-search.png
installer-review.png
anix-language-list.png
anix-mako-diff.png
anix-moducpp-diff.png
```

Avoid screenshots that include private usernames, Wi-Fi names, machine serials,
or real disks unless they are intentionally part of a bug report.
