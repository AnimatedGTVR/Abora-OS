# Abora OS Release Notes

## v4.1.1

This bridge update fixes the installed updater so new files reach existing systems and files removed by a release are cleaned up safely. Only paths previously recorded as Abora-managed are removed; user files and local app configuration are preserved.

Update with:

```sh
sudo abora update
```

Systems on v4.0 may need to run the command twice because their older updater cannot re-execute the newly downloaded updater in one pass.

## v4.1 Horizon

Horizon focused on installation and daily-use reliability.

### Highlights

- manual and existing-partition installation
- adoption path for existing NixOS systems
- clearer installer failures and saved logs
- GPU selection for Intel, AMD, Nouveau, NVIDIA, and NVIDIA Open
- stable and Edge update channels with rollback support
- ANIX v2 system-management workflows
- optional Abora Gaming and Labs
- Rust-based TinyPM application layer
- diagnostics through `abora doctor`, `abora network`, and support reports

### Known limits

VirtualBox remains less reliable than QEMU, VMware, and Hyper-V. Edge builds can break. Hardware-specific firmware and proprietary drivers may require extra work. Review the current GitHub issues before installing on a main machine.

Download official images and checksums from [GitHub Releases](https://github.com/AnimatedGTVR/Abora-OS/releases).
