#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
iso_dir="${ABORA_ISO_DIR:-$out_dir/iso}"
nix_out_dir="${ABORA_NIX_OUT_DIR:-$out_dir/nix}"
version_id="${ABORA_VERSION_ID:-}"
build_date="$(date +%Y.%m.%d)"
edition="${ABORA_EDITION:-cosmic}"
editions=(cosmic hyprland gnome kde other)

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

mkdir -p "$iso_dir" "$nix_out_dir"

export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

is_supported_edition() {
    local candidate="$1"
    local item
    for item in "${editions[@]}"; do
        [[ "$candidate" == "$item" ]] && return 0
    done
    return 1
}

build_one() {
    local edition_name="$1"
    local package="iso-${edition_name}"
    local nix_target="$repo_dir#packages.x86_64-linux.${package}"
    local artifact_prefix="abora-${edition_name}"
    local build_link="$nix_out_dir/${package}-result"
    local iso_src=""
    local resolved_link=""
    local target_iso=""

    echo "Building target: $nix_target"

    rm -f "$build_link"

    nix build "$nix_target" \
        --print-build-logs \
        --show-trace \
        --out-link "$build_link" \
        --option substituters "https://cache.nixos.org" \
        --option max-jobs auto \
        --cores 0

    if [[ ! -e "$build_link" ]]; then
        echo "Nix build completed but output link was not created: $build_link" >&2
        exit 1
    fi

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

    target_iso="$iso_dir/${artifact_prefix}-${build_date}-x86_64-${version_tag}.iso"
    rm -f "$iso_dir/${artifact_prefix}-"*"-${version_tag}.iso"
    cp -f "$iso_src" "$target_iso"

    echo "ISO output: $target_iso"
}

case "$edition" in
    all)
        for edition_name in "${editions[@]}"; do
            build_one "$edition_name"
        done
        ;;
    *)
        if ! is_supported_edition "$edition"; then
            echo "Unsupported ABORA_EDITION: $edition" >&2
            echo "Supported editions: ${editions[*]} all" >&2
            exit 1
        fi
        build_one "$edition"
        ;;
esac

# COSMIC is the single-ISO default `make iso` builds; also drop a copy under
# the old pre-multi-edition filename (no "-cosmic-" segment) so tooling or
# docs still expecting that name (from before editions existed) keep working.
if [[ "$edition" == "cosmic" ]]; then
    latest_cosmic="$iso_dir/abora-cosmic-${build_date}-x86_64-${version_tag}.iso"
    legacy_iso="$iso_dir/abora-${build_date}-x86_64-${version_tag}.iso"
    if [[ -f "$latest_cosmic" ]]; then
        cp -f "$latest_cosmic" "$legacy_iso"
        echo "Legacy ISO output: $legacy_iso"
    fi
fi
