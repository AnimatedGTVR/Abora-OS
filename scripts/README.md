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
