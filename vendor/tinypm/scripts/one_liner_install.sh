#!/usr/bin/env bash
set -euo pipefail

PREFIX="${TINYPM_PREFIX:-$HOME/.tinypm}"
REPO_DIR="$PREFIX/repo"

if ! command -v git >/dev/null 2>&1; then
    echo 'TinyPM installer requires git.' >&2
    exit 1
fi

mkdir -p "$PREFIX"

if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" pull --rebase origin main || true
else
    git clone https://github.com/AnimatedGTVR/TinyPM.git "$REPO_DIR"
fi

exec "$REPO_DIR/install.sh"
