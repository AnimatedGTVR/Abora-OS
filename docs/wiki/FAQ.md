# FAQ

## What is Abora?

Abora OS is a distro project built on top of NixOS with a focus on a simpler first-run and management experience.

## Is Abora just NixOS?

Abora is still NixOS-based, but it adds its own live image flow, installer experience, branding, update path, desktop profiles, support tools, ANIX workflows, and TinyPM-flavored app commands.

## What is DENALI 3.14?

DENALI 3.14 is the current stable release. It shipped the Omarchy-inspired TUI installer, stronger install validation, Abora branding across boot and desktop, ANIX v1, and TinyPM v4.

Key additions over v2.5:

- Omarchy-inspired TUI installer with a compact boxed UI and live progress output
- config validation runs before `nixos-install`
- Abora branding in bootloader, Plymouth, wallpapers, Fastfetch, and desktop defaults
- ANIX v1 profile manager with snapshots, diff/test/boot/switch/rollback workflows
- TinyPM v4 with Abora/ANIX/NixOS system bridges
- 21 desktop environments selectable at install time
- COSMIC desktop support added

## What changed in v2.5?

v2.5 focused on reliability:

- NetworkManager in the live installer
- stronger installer failure handling
- desktop profile evaluation checks
- QEMU fresh/disk boot helpers
- `make iso` vs `make release` split

## How do I update Abora?

Use:

```sh
sudo nixos update
```

Short aliases like `update` and `upgrade` are also available on installed systems.

## How do I build the ISO?

Use:

```sh
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

## Is Modularity available in Abora?

Yes. Modularity is a game engine editor by Tareno Labs and is included in the Developer app bundle.

Install it after setup:

```sh
grab modularity
```

Or select it from the Developer bundle during installation.

Modularity is backed by a custom Nix derivation with PhysX, Vulkan, and Mono support built in.

## Where are the project docs?

Start here:

- [Project README](../../README.md)
- [Release Notes](../../RELEASE_NOTES.md)
- [Roadmap](../roadmap.md)
- [Project Layout](../project-layout.md)
