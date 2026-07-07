#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: abora-dotfiles-import [--dry-run] [--replace] DOTFILES_DIR

Copy common desktop dotfiles from DOTFILES_DIR into your home folder.

By default existing files are kept. Use --replace to overwrite them.
EOF
}

dry_run=0
replace=0
source_dir=""

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
