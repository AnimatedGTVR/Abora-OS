#!/usr/bin/env bash
# abora apps custom: removed in Abora OS 4.2.
#
# It only ever managed one package, Modularity (a zip dropped into the Abora vendor tree). Packages now install
# with `anix package install`, which also accepts a GitHub flake (`anix package install github:owner/repo`).
#
# The script stays, as this stub, because the updater already installed on Abora 4.0 and 4.1 refuses to update
# to a release that doesn't contain it (scripts/release/legacy-required-paths.txt), and `abora apps custom`
# still has to answer. Delete both in a later release.
set -euo pipefail

cat >&2 <<'MSG'
Custom packages were removed in Abora OS 4.2.

Install software with ANIX instead:
  anix package install <package>            a nixpkgs package, right away, no rebuild
  anix package install github:owner/repo    a program from a GitHub flake
  abora apps                                Flatpak apps from Flathub

Modularity is no longer bundled; install it from its GitHub repository the same way.
MSG
exit 1
