# Abora Scripts

Root-level script paths are compatibility symlinks. New work should use the
foldered source files:

- `core/`: shared command entry points and UI helpers
- `install/`: installer, setup launcher, boot/adopt/build helpers
- `config/`: desktop, theme, session, local config, and repair tools
- `apps/`: app catalog, package management, and gaming helpers
- `support/`: update, recovery, diagnostics, welcome, and reports
- `release/`: ISO builds, QEMU, packaging, and repository checks

Keep the root symlinks until the ISO profile, standalone packages, and older
docs have all moved to the foldered paths.

The support tools (doctor, recovery, welcome, support-report, check-full,
hardware-test) are Python, `support/abora-*.py`, but their root links keep
the old `.sh` names: `abora update` on an installed 4.0 system requires
`scripts/abora-doctor.sh` and the rest to exist in the release it fetches,
and copies them to `/etc/nixos/abora/doctor.sh` and so on, so those six links
stay for as long as 4.0 systems can update.

On Windows, clone with `git config core.symlinks true` (and Developer Mode
on); otherwise each link checks out as a one-line text file holding its
target path.
