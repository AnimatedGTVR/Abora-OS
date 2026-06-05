# FAQ

## What is Abora?

Abora OS is a distro project built on top of NixOS with a focus on a simpler first-run and management experience.

## Is Abora just NixOS?

Abora is still NixOS-based, but it adds its own live image flow, installer experience, branding, update path, desktop profiles, support tools, ANIX workflows, and TinyPM-flavored app commands.

## What changed in v2.5?

v2.5 focused on reliability:

- NetworkManager in the live installer
- stronger installer failure handling
- desktop profile evaluation checks
- QEMU fresh/disk boot helpers
- `make iso` vs `make release` split
- fixed generated config issues around `environment.systemPackages`, LightDM, GNOME setup, wallpapers, and setup launcher assets

## What is v3 Denali?

v3 Denali is the current direction for Abora's installer and identity.

It focuses on:

- Omarchy-inspired TUI setup
- early generated-config validation
- a more distinctive Abora look and feel
- post-install `abora setup` reconfiguration
- keeping the desktop matrix reliable

## How do I update Abora?

Use:

```sh
sudo nixos update
```

Short aliases like `update` and `upgrade` are also available on installed systems.

## How do I build the ISO?

Use:

```sh
cd /home/animated/abora-os
make iso
```

Then boot it with:

```sh
make qemu-fresh
```

After install, boot the virtual disk with:

```sh
make qemu-disk
```

## Does TinyPM v4 install permanent NixOS system packages?

TinyPM is part of the Abora ecosystem, but it is not a full replacement for declarative NixOS configuration.

In Abora it provides friendly app commands such as `grab`, `search`, `term`, `start`, and `supdate`, plus helpers such as `tinypm sources`, `tinypm system`, `tinypm anix <command>`, and `tinypm abora <command>`.

## Where are the project docs?

Start here:

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Roadmap](../roadmap.md)
- [Project Layout](../project-layout.md)
