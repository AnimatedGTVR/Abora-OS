#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: abora-dotfiles-import [--dry-run] [--replace] [--git-url URL] DOTFILES_DIR

Copy common desktop dotfiles from DOTFILES_DIR into your home folder.
With --git-url, clone the repo first, then import from it.

By default existing files are kept. Use --replace to overwrite them.
EOF
}

dry_run=0
replace=0
source_dir=""
git_url=""

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

# If a git URL was given, clone it into a temp dir and use that as source_dir
if [[ -n "$git_url" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    printf 'git is required for --git-url but was not found\n' >&2
    exit 1
  fi
  clone_dir="$(mktemp -d /tmp/abora-dotfiles.XXXXXX)"
  printf 'Cloning %s ...\n' "$git_url"
  # The `--` stops git from treating a URL starting with `-` as an option
  # (argument injection); $git_url is user-supplied (installer Dotfiles page
  # or --git-url), so this isn't just style here.
  if ! git clone --depth=1 -- "$git_url" "$clone_dir"; then
    rm -rf "$clone_dir"
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

# Clean up temp clone dir if we created one
if [[ -n "$git_url" && -d "$source_dir" && "$source_dir" == /tmp/abora-dotfiles.* ]]; then
  rm -rf "$source_dir"
fi
