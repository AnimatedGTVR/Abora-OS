# Abora Bug Report Template

Use this for Discord, GitHub issues, or release-candidate testing notes.

To open a GitHub issue with this template from an Abora terminal:

```sh
abora bug-report --github --web
```

Use `--with-support-report` if you want Abora to create the support archive
first and mention its local path in the issue body.

## Summary

What broke?

## Where It Happened

- Live ISO installer / installed system / update / first boot:
- Edition: Cosmic / Hyprland / GNOME / KDE / Other:
- Real hardware or VM:
- Wired, Wi-Fi, or offline:

## What You Tried

```sh
abora logs --lines 200
abora network
abora support-report
```

If you need to save the archive somewhere specific:

```sh
abora support-report --output-dir ~/Desktop
```

For installed-system update or rebuild failures:

```sh
abora check-full
sudo journalctl -b --no-pager
```

## Paste The Important Part

Paste the exact error message and attach the generated
`abora-support-*.tar.gz` archive when possible.

Before posting publicly, quickly review the archive. Abora redacts obvious
password, token, secret, and API key lines, but you should still check it.

## Screenshots

Attach screenshots only if they help show the broken screen. Avoid screenshots
with private Wi-Fi names, real disks, serial numbers, or personal paths unless
they are needed for the bug.
