# Abora OS v4.1 Horizon release plan

This plan tracks GitHub issues #32 and #33 as of 2026-09-13. The next release
should be a reliability release. A checked code path is not considered fixed
until it succeeds on a release candidate in the affected environment.

## Readiness snapshot

- Feature implementation is roughly 70% complete for the intended Horizon
  scope. Core installation, updating, desktop selection, Gaming, community
  tools, and Labs enrollment exist in source.
- Release confidence is much lower because the recurring installer failures
  have not passed the required VM and real-hardware matrix. Horizon is an alpha
  until those blockers below are reproduced, fixed, and rerun successfully.
- Avoid adding more default applications or large subsystems before the release
  blockers pass. The remaining work is mostly reliability and validation.

## Implemented in source

- The installer offers whole-disk erase and an existing-partition mode.
- Existing-partition mode reuses an EFI System Partition without formatting it,
  excludes mounted and active partitions, and summarizes what will be erased.
- The installer builds the target before `nixos-install`, pins its flake input,
  records network diagnostics, watches silent builds and reports stage failures.
- Installed configurations define only the selected user. The next release also
  rejects the live-media names `liveuser` and `aboraos` for installed accounts.
- Firefox is included in the installed base instead of relying on Flatpak or a
  starter-app choice.
- Japanese defaults use `jp106` for the Linux console and `jp` for XKB. Those
  are different namespaces; changing both to one value would be incorrect.
- Abora Labs is an explicit installer opt-in. It installs only a workspace
  manager; experimental code is not downloaded, executed, or used for normal
  system updates during installation.

## Release blockers requiring reproduction

- Complete an installation in VirtualBox with default graphics, then repeat
  with 3D acceleration disabled. Capture `/tmp/abora-install.log`, the selected
  GPU mode, VM RAM/CPU/disk settings and the first failed derivation.
- Complete one real-hardware install after an interrupted network transfer.
  Confirm retry does not repartition an already-prepared disk unexpectedly.
- Upgrade from the latest public Everest image, reboot, then perform rollback.
- Confirm the installed login manager selects the configured username and no
  live-media account appears.
- Reproduce KDE Plasma user switching with a second declared normal user. Record
  whether the failure is in SDDM, the lock screen, or account discovery.
- Reproduce browser instability with browser version, desktop, session type,
  VM graphics controller and acceleration settings.
- Test Japanese console input on a TTY and Japanese XKB input in each graphical
  session separately.
- Test the new Rust installer front controller and Bash backend together on
  every release edition. The Rust program still delegates installation to the
  Bash backend, so the installer rewrite is not complete.
- Run the full static suite and all Nix evaluations on a build machine, then
  install each release-candidate ISO in a VM. At least one whole-disk path and
  one existing-partition path must also pass on disposable real hardware.

## Validation results

Release candidate: `abora-cosmic-2026.09.23-x86_64-v4.1.iso`, built from
`edge` at `0e6d0be`. The installs used QEMU/KVM with q35 and UEFI (OVMF 4M),
8 GiB of RAM, 8 vCPUs, a 48 GiB virtio disk and virtio-vga. They ran the
installer's `--batch` mode over the serial console with the Cosmic desktop.

| Test | Result | Notes |
|---|---|---|
| Whole-disk install, then boot | Pass | Install took 284 s. The installed system reaches cosmic-greeter within 60 s and stays up. |
| Existing-partition install, then boot | Pass | Install took 338 s. The pre-existing ext4 partition and a foreign `EFI/Other` directory on the reused ESP are intact. The installed system boots to the greeter. |
| Installed login shows the chosen user, with no live account | Fixed after the RC | Only the chosen account exists, but every account was labelled "Abora User", which looked like a leftover live login (#33). `abora.user.fullName` now defaults the display name to the username. Needs recheck on the next RC. |
| VirtualBox, with default graphics and without 3D | Not run | KVM holds VT-x on this host (`kvm.enable_virt_at_load=Y`), so `kvm_intel` must be unloaded before VirtualBox can start. |

Observations to follow up:

- Limine prints `device_cache_block(): set_pos(): Invalid argument` while
  installing its BIOS stages on a UEFI install. The step still succeeds and
  the system boots.
- Limine is installed at the removable path `\EFI\BOOT\BOOTX64.EFI`. On a
  shared ESP that replaces another OS's fallback loader. The other OS keeps
  its own NVRAM entry, but dual-boot testing should cover this.

## Partitioning follow-up

The current preservation mode formats one existing root partition and reuses an
existing ESP. It does not yet assign a separate `/home`, swap, encryption or
arbitrary mount points, resize partitions, or create partitions in free space.
Those features should land behind an Advanced label only after destructive and
non-destructive cases have automated fixture tests plus manual Windows/Linux
dual-boot validation. The whole-disk path remains the simple default.

## Not yet established

- The VirtualBox failure has not been proven to be a guest-driver failure.
- The reported live-user login has not been reproduced from the current source.
- The KDE, browser and VM rendering reports do not yet identify a specific code
  defect. Do not add driver overrides or disable acceleration globally without
  reproducing the affected setup.
