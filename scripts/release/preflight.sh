#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$script_dir"
while [[ "$repo_dir" != "/" && ! -f "$repo_dir/flake.nix" ]]; do
    repo_dir="$(dirname "$repo_dir")"
done
[[ -f "$repo_dir/flake.nix" ]] || { echo "Could not find Abora repo root." >&2; exit 1; }
cd "$repo_dir"

printf '[preflight] script and runtime checks\n'
./scripts/check-scripts.sh

printf '\n[preflight] full repository file sweep\n'
./scripts/check-all-files.sh

printf '\n[preflight] desktop profile evaluation\n'
./scripts/check-desktops.sh

printf '\n[preflight] done\n'
