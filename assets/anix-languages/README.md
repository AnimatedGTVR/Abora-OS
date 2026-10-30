# ANIX language adapters

Abora OS ships no language adapters. ModuCPP and MAKO were removed in 4.2; ANIX Native (`.anix` files) is
built in and needs none.

A system adapter is a JSON manifest in `/etc/anix/languages/` (see `docs/wiki/ANIX-V2-Languages.md`). This
directory stays because the updater already installed on Abora 4.0 and 4.1 requires it to exist.
