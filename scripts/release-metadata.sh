#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(tr -d '\n' < "$repo_dir/VERSION")"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"

mkdir -p "$out_dir"

(
    cd "$out_dir"
    sha256sum ./*.iso > "SHA256SUMS-${version}.txt"
)

printf '%s\n' "$version"
