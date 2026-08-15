#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: abora dotfiles [--dry-run] [--replace] DOTFILES_DIR
       abora dotfiles [--dry-run] [--replace] --git-url URL [CHECKOUT_DIR]

Direct helper:
       abora-dotfiles-import [--dry-run] [--replace] DOTFILES_DIR

Copy common desktop dotfiles from DOTFILES_DIR into your home folder.
With --git-url, clone the repo first, then import from it. If CHECKOUT_DIR is
provided, clone there; otherwise a temporary checkout is used and cleaned up.

By default existing files are kept. Use --replace to overwrite them.
EOF
}

dry_run=0
replace=0
source_dir=""
git_url=""
clone_dir=""
cleanup_clone=0
default_cache_checkout="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/abora-dotfiles"

cleanup() {
  if [[ "$cleanup_clone" == 1 && -n "${clone_dir:-}" && -d "$clone_dir" ]]; then
    rm -rf "$clone_dir"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --replace)
      replace=1
      shift
      ;;
    --git-url)
      if [[ -z "${2:-}" ]]; then
        printf '--git-url requires a URL argument\n' >&2
        exit 2
      fi
      git_url="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$source_dir" ]]; then
        printf 'Only one DOTFILES_DIR may be provided.\n' >&2
        usage >&2
        exit 2
      fi
      source_dir="$1"
      shift
      ;;
  esac
done

# If a git URL was given, clone it first and use that checkout as source_dir.
if [[ -n "$git_url" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    printf 'git is required for --git-url but was not found\n' >&2
    exit 1
  fi
  if [[ -n "$source_dir" ]]; then
    clone_dir="$source_dir"
    mkdir -p "$(dirname -- "$clone_dir")"
  else
    clone_dir="$(mktemp -d /tmp/abora-dotfiles.XXXXXX)"
    cleanup_clone=1
  fi

  if [[ -e "$clone_dir" && -n "$(find "$clone_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]]; then
    case "$clone_dir" in
      "$default_cache_checkout"|"$default_cache_checkout"/*|/tmp/abora-dotfiles.*)
        rm -rf -- "$clone_dir"
        ;;
      *)
        printf 'Checkout directory already exists and is not empty: %s\n' "$clone_dir" >&2
        printf 'Choose an empty CHECKOUT_DIR or remove it yourself before retrying.\n' >&2
        exit 1
        ;;
    esac
  fi

  printf 'Cloning %s -> %s ...\n' "$git_url" "$clone_dir"
  # The `--` stops git from treating a URL starting with `-` as an option
  # (argument injection); $git_url is user-supplied (installer Dotfiles page
  # or --git-url), so this isn't just style here.
  if ! git clone --depth=1 -- "$git_url" "$clone_dir"; then
    printf 'Failed to clone dotfiles repository.\n' >&2
    exit 1
  fi
  source_dir="$clone_dir"
fi

if [[ -z "$source_dir" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "$source_dir" ]]; then
  printf 'Dotfiles directory not found: %s\n' "$source_dir" >&2
  exit 1
fi

copy_path() {
  local rel="$1"
  local src="$source_dir/$rel"
  local dst="$HOME/$rel"
  local dst_parent

  [[ -e "$src" ]] || return 0
  if [[ -n "${copied_paths[$rel]:-}" ]]; then
    return 0
  fi
  copied_paths[$rel]=1
  dst_parent="$(dirname -- "$dst")"

  if [[ "$dry_run" == 1 ]]; then
    printf 'would copy %s -> %s\n' "$src" "$dst"
    return 0
  fi

  mkdir -p "$dst_parent"
  if [[ "$replace" == 1 ]]; then
    rm -rf -- "$dst"
    cp -a -- "$src" "$dst"
  else
    cp -an -- "$src" "$dst_parent/"
  fi
  printf 'copied %s\n' "$rel"
}

common_paths=(
  ".bashrc"
  ".zshrc"
  ".profile"
  ".xprofile"
  ".gitconfig"
  ".config/hypr"
  ".config/waybar"
  ".config/sway"
  ".config/i3"
  ".config/mango"
  ".config/foot"
  ".config/kitty"
  ".config/ghostty"
  ".config/alacritty"
)

declare -A copied_paths=()
for rel in "${common_paths[@]}"; do
  copy_path "$rel"
done

if [[ -d "$source_dir/.config" ]]; then
  while IFS= read -r -d '' entry; do
    rel=".config/$(basename -- "$entry")"
    copy_path "$rel"
  done < <(find "$source_dir/.config" -mindepth 1 -maxdepth 1 -print0)
fi

printf 'Dotfiles import complete.\n'
