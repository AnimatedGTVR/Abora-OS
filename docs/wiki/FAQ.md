# FAQ

## What is Abora?

Abora OS is a distro project built on top of NixOS with a focus on a simpler first-run experience.

## Is Abora just NixOS?

Abora is still NixOS-based, but it adds its own live image flow, installer experience, branding, and update path.

## How do I update Abora?

Use:

```sh
sudo nixos update
```

## How do I build the ISO?

Use:

```sh
cd /home/animated/abora-os
make iso
```

Then boot it with:

```sh
make qemc
```

## Does TinyPM V3 install permanent NixOS system packages?

Not in the full declarative NixOS sense. TinyPM is still better treated as a separate Abora ecosystem tool, not the main Abora system package path.

## Where are the project docs?

Start here:

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Roadmap](../roadmap.md)
- [Project Layout](../project-layout.md)
