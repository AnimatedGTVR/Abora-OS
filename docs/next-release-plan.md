# Abora OS v4.2 Solstice release plan

Solstice's goal, from the v4.2 checklist (PR #39): **a cleaner codebase, a more reliable system.** Reduce
duplication, unify core systems, improve recovery, and make system changes safer by default. It also answers
Jesse Smith's DistroWatch review of 4.0, which hit repeated install failures and confusing release
information.

A change counts as fixed only once it has worked on a release-candidate ISO in the affected environment.
Code that passes `make check` is **implemented**, not **verified**.

## Release gate

Solstice ships only when every row below has passed on a release-candidate ISO built from the commit being
tagged. Record the ISO name, the commit, and the result in [Validation results](#validation-results).

| # | Test | Environments |
| --- | --- | --- |
| 1 | ISO matches `SHA256SUMS-v4.2.txt` after download from the published location | the published release files |
| 2 | Fresh whole-disk install, reboot, reach the login screen | COSMIC, GNOME, KDE, Hyprland, Other editions; UEFI and BIOS |
| 3 | Same as 2 in **VirtualBox** | default graphics, and with 3D acceleration off |
| 4 | Install alongside an existing partition; the other OS still boots | UEFI with a shared ESP |
| 5 | Each GPU choice the installer offers on matching hardware or VM | nouveau, nvidia-open, amdgpu, intel |
| 6 | `anix update` from 4.1.1 and from 4.0, reboot | one edition is enough |
| 7 | A failing update rolls back (see [ASA](wiki/ASA.md)) | inject a failing unit; `anix history` shows `rolled-back` and the old generation runs |
| 8 | `anix undo <id>` after a committed `anix apply` | any |
| 9 | `anix doctor` reports and repairs each injected failure: full ESP, stopped DNS, failed unit, wrong `abora.gpu`, missing `/etc/abora` file | VM |
| 10 | `anix package install hello`, then `uninstall`, then `keep` + `anix apply` | any |
| 11 | An install that fails (pull the network mid-install) shows **What failed**, and **Save logs to a USB drive** writes the logs | VM with a USB stick passed through |
| 12 | `anix desktop set` to another desktop and back | GNOME and KDE |
| 13 | Broken network at first boot: `anix doctor` and `anix network` explain it | VM with the network off |
| 14 | Recovery from an invalid config: a typo in `anix.nix`, then `anix apply` | any; the switch must be refused or rolled back |

## Implemented in source (not yet verified)

- `anix` is the one command; `abora` forwards to it.
- TinyPM removed; `anix package install/uninstall/search/upgrade/try/keep` replaces it.
- `anix doctor`: bootloader, Nix, ANIX config, channel, desktop/session, GPU, network/DNS, disk, services,
  Flatpak; `--json`; `repair`.
- ASA/ABT transactions for `anix apply`, `anix switch`, `anix config apply`, `anix apps` and the updater's
  final switch; `anix history`, `anix undo`.
- Installer: three-way hash-mismatch diagnosis, **What failed** block, `nix log` of the failed build in the
  log, a log copy on the target, **Save logs to a USB drive**, clearer timezone question.
- Release consistency: every shipped release name comes from `VERSION` + `RELEASE_CODENAME`
  (`scripts/release/abora_release.py`), and `make check` fails when one doesn't.
- A coreutils 9.2+ bug that broke `abora dotfiles` re-runs.

## DistroWatch 4.0 follow-up

| Report | State |
| --- | --- |
| Install failed with hash mismatches, repeatedly | **Not reproduced.** Needs a 4.0 ISO install attempt to capture the exact message. The 4.2 installer now says which of the three kinds it is and keeps the failing path and hashes. Do not blame the ISO checksum without that message. |
| Release and version information disagreed | Implemented (above). The website and GitHub releases also need checking at release time (row 1). |
| Manual partitioning | Fixed in 4.1.1; regression rows 2 and 4. |
| Desktop editions boot to a TUI installer | Documented in [Installation](wiki/Installation.md). **Open decision:** offer the edition's desktop as a live session, or drop the unused desktop from the live image. |
| Timezone entry | Implemented. |

## Not in Solstice

- Atlas removal: Atlas exists only on the website (`Abora-OS-website`), not in this repo.
- `anix desktop set`, `anix gaming` and `anix config set gpu` don't use `abt begin`/`commit` yet, so on
  failure they roll back the generation but not their config edit.
- One shared command list for `live.nix` and `installed-base.nix`, and folding the two small C# tools into
  Python: the duplication is mapped in [v4.2-prep.md](v4.2-prep.md) and is next.

## Validation results

| Test | ISO / commit | Result | Notes |
| --- | --- | --- | --- |
| | | | |

## Carried over from 4.1 Horizon

From the 4.1 release candidate (`abora-cosmic-2026.09.23-x86_64-v4.1.iso`, QEMU/KVM, UEFI): whole-disk and
existing-partition installs passed; VirtualBox was **not run**. Still open:

- Limine prints `device_cache_block(): set_pos(): Invalid argument` while installing its BIOS stages on a UEFI
  install. The step succeeds.
- Limine installs to the removable path `\EFI\BOOT\BOOTX64.EFI`, which replaces another OS's fallback loader
  on a shared ESP. Row 4 covers it.
- The KDE user-switching, browser and VM rendering reports from #32/#33 don't yet point at a code defect. Don't
  add driver overrides or disable acceleration globally without reproducing them.
