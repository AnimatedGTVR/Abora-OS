#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
tinypm_dir="$repo_dir/vendor/tinypm"
version_id="${ABORA_VERSION_ID:-}"
tinypm_version=""

if [[ ! -d "$tinypm_dir" ]]; then
  echo "TinyPM source directory not found: $tinypm_dir" >&2
  exit 1
fi

if [[ -z "$version_id" && -f "$repo_dir/VERSION" ]]; then
  version_id="$(tr -d '\n' < "$repo_dir/VERSION")"
fi

version_id="$(printf '%s' "$version_id" | tr -cd '[:alnum:]._-')"
[[ -n "$version_id" ]] || version_id="dev"
case "$version_id" in
  [Vv]*) version_tag="$version_id" ;;
  *) version_tag="v$version_id" ;;
esac

tinypm_version="$(
  awk -F'"' '/^tinypm_version=/{print $2; exit}' "$tinypm_dir/lib/core/common.sh"
)"
tinypm_version="$(printf '%s' "${tinypm_version:-unknown}" | tr -cd '[:alnum:]._-')"
[[ -n "$tinypm_version" ]] || tinypm_version="unknown"
case "$tinypm_version" in
  [Vv]*) tinypm_tag="$tinypm_version" ;;
  *) tinypm_tag="v$tinypm_version" ;;
esac

mkdir -p "$out_dir"

package_name="tinypm-${tinypm_tag}-abora-${version_tag}.tar.gz"
package_path="$out_dir/$package_name"
rm -f "$package_path"

tar \
  --exclude='.git' \
  --exclude='*.swp' \
  --exclude='*.tmp' \
  -czf "$package_path" \
  -C "$repo_dir/vendor" \
  tinypm

printf '%s\n' "$package_path"
