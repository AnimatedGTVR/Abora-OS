#!/usr/bin/env bash
set -euo pipefail

workspace="${ABORA_VM_WORKSPACE:-/var/tmp/abora-vm-build}"
repo_dir="${ABORA_REPO_DIR:-$workspace/abora-os}"
out_dir="${ABORA_OUT_DIR:-$workspace/out}"
repo_url="${ABORA_REPO_URL:-https://github.com/AnimatedGTVR/abora-os.git}"
repo_branch="${ABORA_REPO_BRANCH:-main}"

if ! command -v git >/dev/null 2>&1; then
    echo "git command not found." >&2
    exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
    echo "nix command not found. Install Nix with flakes support first." >&2
    exit 1
fi

mkdir -p "$workspace"

if [[ ! -d "$repo_dir/.git" ]]; then
    git clone "$repo_url" "$repo_dir"
else
    git -C "$repo_dir" fetch origin "$repo_branch"
    git -C "$repo_dir" checkout "$repo_branch"
    git -C "$repo_dir" pull --ff-only origin "$repo_branch"
fi

cd "$repo_dir"
ABORA_OUT_DIR="$out_dir" ./scripts/build-iso.sh

echo
echo "Build complete."
echo "ISO output directory: $out_dir"
ls -lah "$out_dir"
