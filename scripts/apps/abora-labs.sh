#!/usr/bin/env bash
set -euo pipefail

repo_url="${ABORA_LABS_REPO_URL:-https://github.com/AboraOS-Project/Abora-Labs.git}"
repo_ref="${ABORA_LABS_REPO_REF:-stable}"
workspace="${ABORA_LABS_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/abora/labs}"

usage() {
    cat <<'EOF'
Abora Labs is an experimental workspace. Labs code is not used by normal
Abora OS updates and is never run automatically.

Usage:
  abora labs status        show the Labs workspace state
  abora labs install       clone the Labs workspace
  abora labs update        fast-forward an existing workspace
  abora labs path          print the workspace path

Review experiments before running them. Do not use Labs as your system flake.
EOF
}

case "${1:-status}" in
    status)
        printf 'Repository: %s\nBranch: %s\nWorkspace: %s\n' "$repo_url" "$repo_ref" "$workspace"
        if [[ -d "$workspace/.git" ]]; then
            printf 'State: installed\nCommit: '
            git -C "$workspace" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
        else
            printf 'State: not downloaded\nRun: abora labs install\n'
        fi
        ;;
    install)
        [[ ! -e "$workspace" ]] || {
            printf 'abora labs: workspace already exists: %s\n' "$workspace" >&2
            printf 'Use `abora labs update`, or move the existing directory first.\n' >&2
            exit 1
        }
        printf 'Abora Labs contains experimental, unsupported code.\n'
        printf 'It will be downloaded but not executed or added to your system configuration.\n'
        printf 'Type LABS to continue: '
        read -r confirmation
        [[ "$confirmation" == "LABS" ]] || { printf 'Cancelled.\n'; exit 1; }
        mkdir -p "$(dirname "$workspace")"
        git clone --branch "$repo_ref" --single-branch -- "$repo_url" "$workspace"
        printf 'Labs workspace installed at %s\n' "$workspace"
        ;;
    update)
        [[ -d "$workspace/.git" ]] || {
            printf 'abora labs: no workspace at %s; run `abora labs install`.\n' "$workspace" >&2
            exit 1
        }
        [[ -z "$(git -C "$workspace" status --porcelain)" ]] || {
            printf 'abora labs: local changes found; refusing to overwrite them.\n' >&2
            exit 1
        }
        git -C "$workspace" fetch --prune origin "$repo_ref"
        git -C "$workspace" checkout "$repo_ref"
        git -C "$workspace" merge --ff-only "origin/$repo_ref"
        ;;
    path)
        printf '%s\n' "$workspace"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        printf 'abora labs: unknown command: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac
