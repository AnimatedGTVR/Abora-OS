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

nix_target="$repo_dir#packages.x86_64-linux.iso"
echo "Building target: $nix_target"

build_link="$out_dir/nix-iso-result"
rm -f "$build_link"

nix build "$nix_target" \
    --print-build-logs \
    --show-trace \
    --out-link "$build_link"

if [[ ! -e "$build_link" ]]; then
    echo "Nix build completed but output link was not created: $build_link" >&2
    exit 1
fi

iso_src=""
if [[ -f "$build_link" ]]; then
    resolved_link="$(readlink -f "$build_link" || true)"
    if [[ -n "$resolved_link" && -f "$resolved_link" ]]; then
        iso_src="$resolved_link"
    elif [[ "$build_link" == *.iso ]]; then
        iso_src="$build_link"
    fi
fi

if [[ -z "${iso_src:-}" ]]; then
    iso_src="$(find -L "$build_link" -type f -name '*.iso' | head -n 1)"
fi

if [[ -z "${iso_src:-}" || ! -f "$iso_src" ]]; then
    echo "Unable to locate ISO file in Nix build output: $build_link" >&2
    exit 1
fi

target_iso="$out_dir/abora-${build_date}-x86_64-${version_tag}.iso"
rm -f "$out_dir"/*-"${version_tag}".iso
rm -f "$out_dir/SHA256SUMS-${version_tag}.txt"
rm -f "$out_dir/RELEASE_MANIFEST-${version_tag}.txt"
rm -f "$out_dir/RELEASE_NOTES-${version_tag}.md"
cp -f "$iso_src" "$target_iso"

echo "ISO output: $target_iso"
ABORA_OUT_DIR="$out_dir" "$repo_dir/scripts/release-metadata.sh" >/dev/null
