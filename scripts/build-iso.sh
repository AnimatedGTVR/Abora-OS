#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
version_id="${ABORA_VERSION_ID:-}"
build_date="$(date +%Y.%m.%d)"

if ! command -v nix >/dev/null 2>&1; then
    echo "nix command not found. Install Nix with flakes support first." >&2
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

mkdir -p "$out_dir"

export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

nix build "$repo_dir#packages.x86_64-linux.iso" --print-build-logs

result_link="$repo_dir/result"
if [[ ! -e "$result_link" ]]; then
    echo "Nix build completed but no result link was found." >&2
    exit 1
fi

iso_src="$(find -L "$result_link" -type f -name '*.iso' | head -n 1)"
if [[ -z "$iso_src" || ! -f "$iso_src" ]]; then
    echo "Unable to locate ISO file in Nix build output." >&2
    exit 1
fi

target_iso="$out_dir/abora-${build_date}-x86_64-${version_tag}.iso"
cp -f "$iso_src" "$target_iso"

echo "ISO output: $target_iso"
ABORA_OUT_DIR="$out_dir" "$repo_dir/scripts/release-metadata.sh" >/dev/null
