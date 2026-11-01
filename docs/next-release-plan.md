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
| Install failed with hash mismatches, repeatedly | **Exact mismatch not reproduced.** A fresh install from the published v4.0.1 ISO was attempted on 2026-10-31. It failed during evaluation for a different, now-understood reason: current nixpkgs rejects the removed `boot.initrd.systemd.enable = false` and `boot.initrd.verbose` options. The 4.2 installer now says which of the three hash-failure kinds it sees and keeps the failing path and hashes. Do not blame the ISO checksum without that message. |
| Release and version information disagreed | Implemented (above). The website and GitHub releases also need checking at release time (row 1). |
| Manual partitioning | Fixed in 4.1.1; regression rows 2 and 4. |
| Desktop editions boot to a TUI installer | Documented in [Installation](wiki/Installation.md). **Decided:** no live desktop session; live sessions don't fit Abora. The live image should drop desktop components the installer doesn't use (needs a Nix build to verify the ISO still installs every edition). |
| Timezone entry | Implemented. |

## Unfinished (as of 2026-11-01)

Everything below is open. Boxes are ticked when done.

**Verification is in progress; use the recorded results below rather than assuming evaluation equals a boot test.**
- [ ] Release gate rows 1 to 19 above (none recorded in [Validation results](#validation-results) yet)
- [ ] A real `edge` update on an installed system with the current nixos-unstable, then reboot into the new kernel
- [ ] Boot test of the removed initrd options: they are checked by evaluation only (nixos-26.05 defaults the
  systemd initrd on, so nothing should change)
- [ ] Decide whether the corruption check stays on by default (row 19)
- [x] Fix the release-candidate warning `Could not check the packages`: the target system was built in
  `/mnt`'s Nix store but the checker queried the live store. Queries, verification and repairs now use the
  target store, with a regression test. A rebuilt ISO completed the full clean-media scan and install; row 18
  still needs the deliberately damaged-path test.

**Testing tool**
- [x] `testing/abora-break` deliberately breaks a test VM over SSH (full ESP, stopped DNS, failed unit, wrong
  `abora.gpu`, missing `/etc/abora` file, read-only root), each with `restore`. It refuses to run outside a VM, and
  `make check` fails if the ISO, installer, Nix modules or tools mention it. See
  [abora-break](testing/abora-break.md). Unit-tested only; its first real use is gate row 9.

- [x] **Release ISOs installed onto the `edge` channel** (nothing set `ABORA_RELEASE_STAGE`; v4.1 did it too).
  Fixed: the tag release workflow writes `RELEASE_STAGE` = `stable`, `live.nix` bakes it into the installer, and a
  release ISO always installs onto `stable`; nightly and local ISOs install onto `edge`. Checked by evaluation
  both ways. Still to see: the tagged v4.2 ISO's install saves `stable` (`/etc/nixos/abora/channel`).
- [x] Rebuild the ISO with the theme/wallpaper copy fix and re-run row 2 once (KDE Plasma, BIOS)

**Release housekeeping**
- [x] The v4.1 entry's `<RELEASE DATE>` is filled (2026-10-03)
- [ ] Fill the v4.2 `<RELEASE DATE>` in `RELEASE_NOTES.md` and remove the **Draft** banner when the gate passes
- [x] v4.1.1 never shipped; its release-notes section now says the work is included in 4.2 and claims no tag
- [ ] Tag `v4.2` and watch the release workflow build the ISO, checksums and manifest
- [ ] Website and GitHub releases agree on the release (row 1); the website's `/security` page matches the
  security notice (Checked 2026-11-01: `Abora-OS-website` has no `/security` page yet; add one or drop this.)
- [x] `docs/development/edge-branch.md` tells testers to open a public issue for any regression; security bugs
  must go through `SECURITY.md` instead

**Known limits to keep documented**
- [ ] **v4.1 → 4.2 upgrade, fixed in 4.2 (no hotfix).** The v4.1 updater rejected 4.2 because the C# plan
  tool's paths were gone; they are back as placeholders and now listed in `legacy-required-paths.txt` (with
  the Vanta paths v4.1 also requires). The v4.1 resolver clash is local to installed 4.1 systems, so their
  first update is `sudo env ABORA_UPDATE_RESOLVER_BIN=abora-update-resolver abora update` (in the release
  notes). Still to do: run that on an installed v4.1 VM (row 6).
- [ ] The boot-menu description line still names the NixOS release (for example "Zokor"): nixpkgs builds it from
  a read-only option
- [x] A published v4.0.1 ISO install was attempted; it reproduced the removed-initrd-options failure, not the
  reported hash mismatch. The historical mismatch remains unproven; the 4.2 installer checks and repairs the
  damaged-store-path class instead.

The repeatable update, boot and hash-mismatch procedures are in
[v4.2 known-limits validation](testing/v4.2-known-limits.md). The injected hash mismatch reproduces the reported
failure class, not the undocumented root cause of the original 4.0 incident.

**Cleanup**
- [ ] Delete old local branches: `edge-notes`, `fix/keyboard-layout-mapping`, `fix/ssh-hash-and-partitioning`,
  `fix/update-manifest`, `fix/welcome-autostart`, `port-support-python`, `pr52`, `security/kernel-7.3`, `v4.2-work`.
  Checked 2026-11-01: every commit on them is already in `edge`. `hotfix/v4.1-nixpkgs` and its worktree are
  dropped too: v4.1 upgrades are handled in 4.2.
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
| BIOS live-ISO boot smoke test (not release-gate row 2) | `abora-2026.10.31-x86_64-v4.2.iso` / `50fe092f243f` | Pass | QEMU/KVM with SeaBIOS reached the v4.2 installer Welcome screen on a fresh 32 GiB disk. No installation was attempted. |
| UEFI live-ISO boot smoke test (not release-gate row 2) | `abora-2026.10.31-x86_64-v4.2.iso` / `50fe092f243f` | Pass | QEMU/KVM with OVMF 202608 selected the UEFI DVD entry and reached the v4.2 installer Welcome screen. No installation was attempted. |
| Row 2 — COSMIC, UEFI, whole-disk install | `abora-2026.10.31-x86_64-v4.2.iso` / `50fe092f243f` | Pass with follow-up | QEMU/KVM, OVMF 202608, VirtIO GPU, fresh 32 GiB disk: install completed, `Boot0007 Abora OS` booted from disk, tty login and COSMIC greeter appeared. The pre-install package check warned because it queried the live store instead of the target store; fixed and verified with the rebuilt ISO in the next row. |
| Clean-media integrity scan after target-store fix | `abora-2026.10.31-x86_64-v4.2.iso` (`09780534a60d…60df3`) / dirty tree at `50fe092f243f` | Pass | Fresh UEFI COSMIC install on a separate 32 GiB QCOW2: the scan read the target closure for several minutes, emitted no indeterminate-check warning, and the install completed through Limine and EFI registration. Deliberate corruption was not injected. |
| Row 2 — COSMIC, legacy BIOS, whole-disk install | `abora-2026.10.31-x86_64-v4.2.iso` (`43ced53b8102…ff26b`) / dirty tree at `50fe092f243f` | Pass | QEMU/KVM with SeaBIOS, VirtIO GPU, and a fresh 32 GiB disk: the corrected target-store media scan completed without a warning, the install completed through Limine's BIOS stages, and the disk booted by itself to the COSMIC greeter. |
| Historical v4.0 hash-mismatch reproduction attempt | `abora-2026.08.29-x86_64-v4.0.iso` (`f486e0e93707…72da3`), published tag `v4.0.1` | Different failure reproduced | QEMU/KVM with SeaBIOS and a fresh 32 GiB disk: preflight passed, then target evaluation failed because current nixpkgs removed scripted initrd support and rejected `boot.initrd.systemd.enable = false` plus `boot.initrd.verbose`. No hash mismatch appeared. |
| Published v4.1 install and updater compatibility | `abora-cosmic-2026.10.03-x86_64-v4.1.iso` (`3efc22189325…0352c7`), published tag `v4.1` | Install/boot pass; two-step hotfix required | Official checksum passed. QEMU/KVM with SeaBIOS and a fresh 32 GiB disk completed the COSMIC install, installed Limine's BIOS stages, booted from disk, and accepted a tty login. The normal updater selected its public wrapper as the resolver and failed safely. `ABORA_UPDATE_RESOLVER_BIN=abora-update-resolver` cleared that collision and resolved `edge`, but checkout validation correctly rejected current edge because legacy `abora-plan-tool` sources required by the old updater are gone. All attempts left `flake.nix` untouched. |
| v4.1 compatibility-hotfix backport | local `hotfix/v4.1-nixpkgs` worktree at `cb572df` plus dirty changes | Superseded | Dropped on 2026-11-01: v4.1 upgrades are fixed in 4.2 instead (plan-tool placeholders). Backported the distinct `abora-update-core` resolver name and regression test on top of the removed-initrd-options fix. The updater suite and Nix package build pass. Full `make check` reaches an unrelated pre-existing hardware-test failure in this container. The hotfix ref must be published before the installed v4.1 VM can test the two-stage handoff. |
| Updater resolver packaging fix | `abora-2026.10.31-x86_64-v4.2.iso` (`d3ca7a9e6f11…5b186a`) / dirty tree at `50fe092f243f` | Build and checks pass; installed update pending | The public `abora-update` wrapper and internal Vanta resolver no longer share an executable name; the resolver is `abora-update-core`. Its Nix package built, resolved `edge`, and contains no colliding `abora-update` binary. The ISO was rebuilt with the fix; a full installed-system update remains required. |
| Latest rebuilt ISO BIOS smoke test | `abora-2026.10.31-x86_64-v4.2.iso` (`d3ca7a9e6f11…5b186a`) / dirty tree at `50fe092f243f` | Pass | QEMU/KVM with SeaBIOS loaded the Linux 7.3 kernel and initrd from the rebuilt ISO and reached the v4.2 Solstice installer Welcome screen. |
| v4.1 updater checkout validation against 4.2 | `v4.1` tag's `validate_upstream_checkout`, run on `origin/edge` and on `docs/v4.2-unfinished` | Pass after fix | Before: rejected for refs `edge` and `v4.2`, missing the plan tool's `AboraPlanTool.csproj`, `Program.cs` and `abora-plan-tool-deps.json` (the failure the v4.1 VM hit). After the placeholders: accepted for both refs. The build, switch and reboot on an installed v4.1 system are still row 6. |
| Row 2 — GNOME, legacy BIOS, whole-disk install | `abora-2026.10.31-x86_64-v4.2.iso` (`d3ca7a9e6f11…5b186a`) / dirty tree at `50fe092f243f` | Pass | Unattended `abora-install --batch` in QEMU/KVM with SeaBIOS, fresh 32 GiB disk: installed in 11 min, booted from disk through the Abora boot splash (row 17's splash part) to the GDM greeter. GDM shows the NixOS snowflake logo, not Abora's. |
| Row 9 — `anix doctor` with `abora-break` | same GNOME/BIOS install | Pass after fixes | Detected: `network-dns`, `services`, `abora-file-theme-sync.sh`, `disk-readonly`. Repairs `reset-failed` and `rebuild` fixed theirs; `restart-networkmanager` did **not** fix DNS (stale resolv.conf survives the restart), fixed by running `resolvconf -u` after it and re-verified. `full-esp` needs UEFI and `wrong-gpu` a GPU the doctor can see: still to run. |
| Row 10 — `anix package` | same | Pass | `install hello` ran without a rebuild, `uninstall` removed it, `keep` + `anix apply` committed generation 2 → 3 with hello in the system. |
| Row 8 — `anix undo` and `--keep-edits` | same | Pass after fix | First `anix undo` ended `rollback-failed`: the installer had copied themes and wallpapers as symlinks into /etc/static, the build turned them into store-path loops (unreadable from generation 1 on), and ABT's restore hit ELOOP. Fixed in the installer and in ABT; with the fixed ABT, undo restored the config and generation. A bad `anix set keyboard` failed the switch, ABT rolled back to the previous generation, and `anix undo --keep-edits` brought the edit back. A fresh install from a rebuilt ISO must confirm the theme fix. |
| Row 14 — invalid `anix.nix` | same | Pass | A syntax error stopped `anix apply` before switching; the system stayed on its generation. Also found: `anix set timezone Mars/Olympus_Mons` was accepted and built; now checked against zoneinfo. |
| Row 7 — a failing change rolls back | GNOME/BIOS install (`d3ca7a9e6f11…`) | Pass | A module adding a unit that exits 1 made the switch fail (exit 4); ABT rolled back to generation 6, `anix history` shows `rolled-back`, the unit is not left failed. Same ABT path as the updater's final switch; a real `anix update` against a failing edge commit is not run. |
| Row 13 — no network | same | Pass after fix | Cable unplugged through QEMU: `anix doctor` says "No network connection (no default route)" and points at `anix network`. `anix network` printed raw nmcli/ping/curl output with no conclusion and a guaranteed `resolvectl` failure; it now ends with "No network cable is plugged in, so this computer is offline. Plug in a cable." (re-verified on the VM). |
| Row 17 — Zen and `grab` | same | Pass after fix | First boot installed Zen system-wide (`app.zen_browser.zen`), once. `grab zen-browser` failed ("No remote refs found for 'flathub'": no Flathub in the user installation) and didn't see the installed Zen; both fixed in `grab`, the remote fix verified on the VM. The splash logo passed in row 2. |
| Row 2 — KDE Plasma, legacy BIOS, whole-disk install | `abora-2026.11.01-x86_64-v4.2.iso` / `docs/v4.2-unfinished` at the theme fix | Pass | Unattended install in 17 min; booted to the Plasma desktop with the Abora wallpaper and Welcome app after about 3 minutes (a long black screen first). The theme/wallpaper fix holds: no symlinks in `/etc/nixos/abora`, theme files readable. Channel saved: `edge` (a nightly ISO, as intended). |
| Row 12 — `anix desktop set` and back | GNOME/BIOS install | Pass after fix | `anix desktop set plasma` + `anix config apply` said "Done" and stayed on GNOME: anix.nix's `anix.desktop` overrides `abora.desktop`. Fixed; with the fix the VM rebooted into SDDM and Plasma, then `anix desktop set gnome` brought GDM and GNOME Shell back. The GDM greeter now shows the Abora logo (was the NixOS snowflake). |
| Row 15 — Minimal install (IceWM) | `abora-2026.11.01-x86_64-v4.2.iso` | Pass after fix | Unattended Minimal + IceWM install in 7 min; boots to IceWM. It had no Abora wallpaper (share/backgrounds not linked, the session service didn't know it was IceWM, icewmbg paints over feh); fixed and verified on the VM. Other minimal desktops not run. |
| Row 16 — NixOS release choice | same, plus the GNOME/KDE installs | Pass (both branches) | The Minimal install chose `unstable` and follows `nixos-unstable`; the GNOME and KDE installs chose `stable`. Own-flake installs not run. |
| Row 11 — failed install, logs to USB | `abora-2026.11.01-x86_64-v4.2.iso`, QEMU with a FAT32 USB stick | Pass after fixes | Network pulled during a batch install: it stopped before partitioning, but only said "Preflight failed ... See the log". Now it names the failed check. The failed-install screen hid "Likely cause" and "What failed" (cleared before shown) and its USB list errored (`bad array subscript`, garbled label, boot stick not excluded); all fixed. Saving wrote the install log and a support report to the stick, checked by mounting it. A failure later in the install (after partitioning) is not run. |
| Row 6 — update from v4.1 | published `abora-cosmic-2026.10.03-x86_64-v4.1.iso`, fresh unattended COSMIC install / `docs/v4.2-unfinished` | Pass after fix | Plain `abora update` fails safely (resolver clash, `flake.nix` untouched). The documented one-time command (run as `abora install pre-alpha --ref docs/v4.2-unfinished`, since `edge` lacks the fix until #54 merges) passed checkout validation and handed over to the 4.2 updater, which then failed: v4.1's cancelled pre-update snapshot left an empty Git repo and `flake.nix` was not staged before `nix flake update`. Fixed; the rerun built and switched (generation 2 → 3), and after a reboot the system runs v4.2 Solstice on Linux 7.3.0 (was 7.2.0) with no failed units, reaching the COSMIC greeter. Also fixed: the secret-scan false positive on Abora's own files, and the `unstable` channel name is now saved as `edge`. Update from 4.0 not run. |
| Row 2 — XFCE, legacy BIOS | `abora-2026.11.01-x86_64-v4.2.iso` | Pass (wallpaper fixed after this ISO) | Reached the XFCE desktop and Welcome app; it showed XFCE's own wallpaper because share/backgrounds wasn't linked (fixed since, with the minimal IceWM fix). |
| Row 2 — Cinnamon, legacy BIOS | same | Pass | Reached the Cinnamon desktop with the Abora wallpaper and Welcome app. |
| Row 4 — two installs sharing one ESP (UEFI) | `abora-2026.11.01-x86_64-v4.2.iso`, OVMF | **Fail** | GPT disk with a shared ESP; OS A installed into partition 2, then OS B into partition 3 (existing-partition mode, ESP reused). Only OS B boots: its Limine install rewrote the shared `limine.conf`, deleted OS A's kernel and initrd from `/boot/limine/kernels` as "unused boot files", and replaced `\EFI\BOOT\BOOTX64.EFI`. Every Abora install uses the same `/boot/limine`, so a second one strands the first. Another OS with its own loader (Windows, Ubuntu) is not run; it probably still boots from the firmware menu but is not in Limine's. `efibootmgr` is not installed. Needs a design fix (a boot directory per install, or refusing an ESP that already holds Abora's Limine). |
| Row 18 — damaged install media | same, NixOS unstable, one tzdata file corrupted in the live store | Pass | `nix-store --verify-path` failed on the corrupted path before the install. During the install Nix reported `hash mismatch importing path '.../tzdata-2026e'`, fetched a clean copy, the media check then said "Install media is intact", and the install completed. The raw Nix error is shown without an Abora explanation. With NixOS stable chosen, only 42 of 1468 target paths come from the ISO (everything else downloads), so media damage mostly matters for unstable installs. |
| Row 2 — Hyprland, legacy BIOS | same | Installed | Unattended install completed in 18 min; boot check below. |
| Repository script checks | dirty tree at `50fe092f243f` | Pass | `make check` completed with all script checks passing after the target-store integrity fix, read-only `anix status` Git probe fix, and updater command-collision regression test. Vanta-dependent tests were skipped by the host-side script runner because Vanta is unavailable there; the actual Nix-packaged Vanta updater built and passed its install check separately. |

## Carried over from 4.1 Horizon

From the 4.1 release candidate (`abora-cosmic-2026.09.23-x86_64-v4.1.iso`, QEMU/KVM, UEFI): whole-disk and
existing-partition installs passed; VirtualBox was **not run**. Still open:

- Limine prints `device_cache_block(): set_pos(): Invalid argument` while installing its BIOS stages on a UEFI
  install. The step succeeds.
- Limine installs to the removable path `\EFI\BOOT\BOOTX64.EFI`, which replaces another OS's fallback loader
  on a shared ESP. Row 4 covers it.
- The KDE user-switching, browser and VM rendering reports from #32/#33 don't yet point at a code defect. Don't
  add driver overrides or disable acceleration globally without reproducing them.
