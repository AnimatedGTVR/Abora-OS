# Abora Installer Remake

The replacement installer must prioritize user control without making the safe path difficult. The current
shell installer remains a compatibility implementation while this replacement is built; new installation
logic belongs in the Rust installer.

## Required installation paths

- Guided whole-disk installation with an exact, reviewable partition plan.
- Manual partitioning that can create, delete, resize, format, mount, and reuse partitions.
- Existing-partition installation without formatting partitions the user marked for reuse.
- Explicit EFI System Partition selection and validation for UEFI installations.
- A final confirmation screen showing every destructive operation before anything is written.
- A recoverable execution journal so an interrupted install can explain what completed and what remains.

Partition discovery, validation, planning, formatting, mounting, and bootloader installation must be typed
Rust operations. Shell may launch the installer or a system tool, but it must not decide what disk operation
to perform.

## Pre-install software setup

Before the final review, users can configure software for the installed system:

- Enable or disable Flatpak and the Flathub remote.
- Search and select Flatpak applications.
- Select packages from nixpkgs.
- Choose curated bundles such as gaming, development, creator, and accessibility tools.
- Add optional third-party applications from a reviewed catalog.

Selections are written into the target system configuration or an installation manifest before installation.
The installer must not install selected applications into the live environment. Network downloads happen only
after the user reviews the plan, and a failed optional application must not corrupt the base OS installation.

**Modularity** should appear as the recommended optional application for game developers. It is not bundled
with Abora and is not part of ANIX. Its catalog entry must use an owned, verified upstream source and clearly
show that it is third-party software before the option becomes available.

## Separation of responsibilities

| Component | Responsibility |
| --- | --- |
| Rust installer | State machine, storage plan, validation, execution journal, target configuration |
| Nix | Installed-system configuration, packages, desktop choice, services, boot configuration |
| Package catalog | Reviewed metadata for Flatpak, nixpkgs, bundles, and third-party choices |
| Shell | Small launch and compatibility wrappers only |

The installer UI must consume a plan produced by the engine. It must never construct destructive commands by
concatenating user-entered strings.

## Release gate

The replacement is not the default until automated tests cover guided installation, custom partition layouts,
partition reuse, separate home, UEFI, failed downloads, interrupted installs, and configuration rollback. At
least one real-machine installation must verify NVIDIA hybrid graphics and one must verify AMD or Intel graphics.
