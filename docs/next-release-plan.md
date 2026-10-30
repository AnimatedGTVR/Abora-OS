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
| 2 | Fresh whole-disk install of the one ISO, reboot, reach the login screen | each desktop (COSMIC, GNOME, KDE Plasma, XFCE, Cinnamon, Hyprland, none); UEFI and BIOS |
| 3 | Same as 2 in **VirtualBox** | default graphics, and with 3D acceleration off |
| 4 | Install alongside an existing partition; the other OS still boots | UEFI with a shared ESP |
| 5 | Each GPU choice the installer offers on matching hardware or VM | nouveau, nvidia-open, amdgpu, intel |
| 6 | `anix update` from 4.1.1 and from 4.0, reboot. Must work against the **current** nixos-unstable: new nixpkgs removed `boot.initrd.systemd.enable`/`verbose` and older Abora fails to evaluate (fixed in 4.2) | one desktop is enough |
| 7 | A failing update rolls back (see [ASA](wiki/ASA.md)) | inject a failing unit; `anix history` shows `rolled-back` and the old generation runs |
| 8 | `anix undo <id>` after a committed `anix apply`; `anix set` typo, failed `anix apply`, then `anix undo --keep-edits <id>` | any |
| 9 | `anix doctor` reports and repairs each injected failure: full ESP, stopped DNS, failed unit, wrong `abora.gpu`, missing `/etc/abora` file | VM |
| 10 | `anix package install hello`, then `uninstall`, then `keep` + `anix apply` | any |
| 11 | An install that fails (pull the network mid-install) shows **What failed**, and **Save logs to a USB drive** writes the logs | VM with a USB stick passed through |
| 12 | `anix desktop set` to another desktop and back | GNOME and KDE |
| 13 | Broken network at first boot: `anix doctor` and `anix network` explain it | VM with the network off |
| 14 | Recovery from an invalid config: a typo in `anix.nix`, then `anix apply` | any; the switch must be refused or rolled back |
| 15 | **Minimal** install, with one of its small desktops (IceWM, LXQt, Lumina, Niri, Sway, Fluxbox, Openbox) | UEFI |
| 16 | **Own flake** install, and `anix nixos` / the installer's NixOS release choice with **stable** (`nixos-26.05`) and unstable | any |
| 17 | `grab zen-browser` and the first-boot Zen install; the Abora logo shows in the boot splash | any |
| 18 | Install onto a damaged ISO (flip bytes in the squashfs): the installer names the package and blames the media, or repairs it and goes on | VM |
| 19 | The corruption check's cost: time `Checking the install media` on a USB stick and on a VM disk, and decide whether it stays on by default | VM + real stick |

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
- One universal ISO (no editions); **Minimal** installs and their small desktops; **own-flake** installs and
  `abora adopt-nixos` through `nixosModules.default`; the NixOS **release choice** (stable or unstable) at
  install time and with `anix nixos`.
- `grab` (Nix/Lix, Flatpak, Snap), Zen as the default browser, a boot splash that shows, password hashes kept out
  of `/etc/nixos` and the Nix store.
- The installer's **Rust engine** (`tools/abora-installer`): disk, flake and config steps, with every value
  escaped for Nix in one place and checked against the old Bash output on 19 inputs.
- Corruption check before `nixos-install` (re-fetch damaged packages once, one retry only after a corrupt-path
  failure), downloads pinned to commits, channels named `stable` and `edge` everywhere.
- Evaluation fix for the Linux 7.3 nixpkgs (two removed initrd options); `os-release` and `lsb-release` say
  Solstice.

## DistroWatch 4.0 follow-up

| Report | State |
| --- | --- |
| Install failed with hash mismatches, repeatedly | **Not reproduced.** Needs a 4.0 ISO install attempt to capture the exact message. The 4.2 installer now says which of the three kinds it is and keeps the failing path and hashes. Do not blame the ISO checksum without that message. |
| Release and version information disagreed | Implemented (above). The website and GitHub releases also need checking at release time (row 1). |
| Manual partitioning | Fixed in 4.1.1; regression rows 2 and 4. |
| Desktop editions boot to a TUI installer | Documented in [Installation](wiki/Installation.md). **Decided:** no live desktop session; live sessions don't fit Abora. The live image should drop desktop components the installer doesn't use (needs a Nix build to verify the ISO still installs every edition). |
| Timezone entry | Implemented. |

## Unfinished (as of 2026-10-30)

Everything below is open. Boxes are ticked when done.

**Verification: nothing here has run on a real install since the installer and config changes**
- [ ] Release gate rows 1 to 19 above (none recorded in [Validation results](#validation-results) yet)
- [ ] A real `edge` update on an installed system with the current nixos-unstable, then reboot into the new kernel
- [ ] Boot test of the removed initrd options: they are checked by evaluation only (nixos-26.05 defaults the
  systemd initrd on, so nothing should change)
- [ ] Decide whether the corruption check stays on by default (row 19)

**Testing tool**
- [ ] A way to deliberately **break an installed system**, only to test `anix doctor` and the repairs (full ESP,
  stopped DNS, failed unit, wrong `abora.gpu`, missing `/etc/abora` file, read-only root). It must run from the
  test harness against the installed disk from outside, and must never be in the ISO, the installer, the Nix
  modules or anything that is copied to a user's machine. Add a check that fails the build if it is.

**Release housekeeping**
- [ ] `<RELEASE DATE>` in `RELEASE_NOTES.md` (the v4.2 entry and the v4.1.1 entry), and remove the **Draft** banner
- [ ] v4.1.1 never shipped; its changes are in 4.2. Fix or drop its `Tag: v4.1.1` entry in the release notes
- [ ] Tag `v4.2` and watch the release workflow build the ISO, checksums and manifest
- [ ] Website and GitHub releases agree on the release (row 1); the website's `/security` page matches the
  security notice
- [ ] `docs/development/edge-branch.md` tells testers to open a public issue for any regression; security bugs
  must go through `SECURITY.md` instead

**Known limits to keep documented**
- [ ] v4.1 and older cannot `abora update` until 4.2 (new nixpkgs rejects two options they set). They fail before
  anything changes. Decide whether to publish a `v4.1.2` hotfix tag (the fix is ready in `hotfix/v4.1-nixpkgs`)
- [ ] The boot-menu description line still names the NixOS release (for example "Zokor"): nixpkgs builds it from
  a read-only option
- [ ] The 4.0 hash-mismatch install failure was never reproduced; the 4.2 installer checks and repairs instead

**Cleanup**
- [ ] Old local branches (`edge-notes`, `fix/keyboard-layout-mapping`, `fix/ssh-hash-and-partitioning`,
  `fix/welcome-autostart`, `port-support-python`, `pr52`, `v4.2-work`) and `hotfix/v4.1-nixpkgs`
- [ ] Website: Atlas removal (on hold until you say so)

## Not in Solstice

- Atlas removal: Atlas exists only on the website (`Abora-OS-website`), not in this repo.
- One shared command list for `live.nix` and `installed-base.nix`: the duplication is mapped in
  [v4.2-prep.md](v4.2-prep.md) and is next. (The two C# tools are already replaced by Rust ones.)
- The rest of the installer in Rust (the build and `nixos-install`, boot checks, branding, the apps file, the flake
  lock) and the screens: planned for v5.0 in the [roadmap](roadmap.md).

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
