# Frequently Asked Questions

## Is Abora its own distribution?

Abora is a Linux distribution based on NixOS. It uses NixOS and nixpkgs while adding its own installer, defaults, editions, tools, release process, and project direction.

## Is it stable?

Use Stable for normal installations. Edge is for development and may break. Abora is still young, so keep backups and test major releases first.

## Which edition should I use?

COSMIC is the main modern desktop choice. GNOME and KDE provide familiar full desktops. Hyprland targets tiling users. Other Desktops exposes additional supported profiles.

## Can I add Abora to an existing NixOS installation?

Yes. Use the adoption path in the [installation guide](Installation.md) and review its plan before applying it.

## How do I update or roll back?

Use `sudo abora update` and `sudo abora rollback`. See [Updating](Updating-Abora.md) and [Recovery](Recovery.md).

## Wi-Fi shows as unavailable in nmtui/nmcli during install. What do I do?

Run `rfkill list`, `nmcli radio wifi on`, and `systemctl restart NetworkManager`. If it remains unavailable, collect `journalctl -u NetworkManager -b` and the relevant Wi-Fi driver messages from `dmesg`.

## Does ANIX replace Nix?

No. ANIX provides simpler workflows over NixOS generations and configuration.

## Where should I report problems?

Use GitHub Issues and include the version, edition, hardware or VM, reproduction steps, exact error, and relevant logs. Report vulnerabilities privately through [SECURITY.md](../../SECURITY.md).

## Who maintains Abora?

Abora was created and is led by AnimatedGTVR, with contributions and testing from the community.
