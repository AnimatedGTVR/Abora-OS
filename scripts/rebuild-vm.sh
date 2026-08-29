#!/usr/bin/env bash
set -euo pipefail

# Clean-checkout build for a dedicated build VM/box: clones (or fast-forward
# pulls) the repo into its own workspace directory rather than building from
# whatever local working tree happens to be checked out, then runs the same
# build-iso.sh a local `make iso` would. Meant for a persistent build
# machine, not a one-off developer build.
workspace="${ABORA_VM_WORKSPACE:-/var/tmp/abora-vm-build}"
repo_dir="${ABORA_REPO_DIR:-$workspace/abora-os}"
out_dir="${ABORA_OUT_DIR:-$workspace/out}"
repo_url="${ABORA_REPO_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"
repo_branch="${ABORA_REPO_BRANCH:-edge}"

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
    # Without --branch, a plain clone checks out the repo's default HEAD
    # branch (stable), not $repo_branch (edge by default here) -- silently
    # wrong on exactly the case this script exists for, a fresh/reset
    # persistent build workspace, since there's no error or warning, just
    # a build from the wrong branch. Reproduced directly: a fresh clone
    # with ABORA_REPO_BRANCH=edge against a repo whose default branch is
    # stable landed on stable every time.
    git clone --branch "$repo_branch" "$repo_url" "$repo_dir"
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
