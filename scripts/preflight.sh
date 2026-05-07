#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

printf '[preflight] script and runtime checks\n'
./scripts/check-scripts.sh

printf '\n[preflight] desktop profile evaluation\n'
./scripts/check-desktops.sh

printf '\n[preflight] done\n'
