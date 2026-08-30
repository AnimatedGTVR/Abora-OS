#!/usr/bin/env bash
# abora-adopt-bootstrap.sh — the one-command entry point for existing NixOS
# users: `curl -sSL <raw-url-of-this-file> | bash`. Its only job is getting
# a real Abora OS checkout onto disk, then handing off to the real
# adoption wizard (scripts/abora-adopt-nixos.sh via ./abora adopt-nixos) --
# it does not touch any system state itself and never needs sudo. Keeping
# this script small and single-purpose matters because it's the one part
# of the whole flow a user runs without a chance to read it first; every
# actual system change happens later, from a real local checkout, and
# still requires an explicit "yes" in the wizard before anything is
# written or `sudo` is invoked.
set -euo pipefail

repo_url="${ABORA_REPO_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"
repo_ref="${ABORA_REPO_REF:-edge}"
clone_dir="${ABORA_CLONE_DIR:-$HOME/Abora-OS}"

if [[ ! -f /etc/os-release ]] || ! grep -qi '^ID=.*nixos' /etc/os-release; then
    printf 'This installer is for existing NixOS systems only.\n' >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    printf 'git is required. Install it first (e.g. nix-shell -p git) and re-run.\n' >&2
    exit 1
fi

if [[ -d "$clone_dir/.git" ]]; then
    printf 'Using existing Abora OS checkout at %s\n' "$clone_dir"
    git -C "$clone_dir" fetch --depth=1 origin "$repo_ref"
    git -C "$clone_dir" checkout "$repo_ref"
    git -C "$clone_dir" reset --hard "origin/$repo_ref"
else
    printf 'Cloning Abora OS (%s) into %s...\n' "$repo_ref" "$clone_dir"
    git clone --depth=1 --branch "$repo_ref" "$repo_url" "$clone_dir"
fi

printf '\n'
exec "$clone_dir/abora" adopt-nixos "$@"
