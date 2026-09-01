#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$script_dir"
while [[ "$repo_dir" != "/" && ! -f "$repo_dir/flake.nix" ]]; do
    repo_dir="$(dirname "$repo_dir")"
done
[[ -f "$repo_dir/flake.nix" ]] || { echo "Could not find Abora repo root." >&2; exit 1; }
version="$(tr -d '\n' < "$repo_dir/VERSION")"
release_name="${ABORA_RELEASE_NAME:-Abora OS v4 Everest}"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
iso_dir="${ABORA_ISO_DIR:-$out_dir/iso}"
package_dir="${ABORA_PACKAGE_DIR:-$out_dir/packages}"
release_dir="${ABORA_RELEASE_DIR:-$out_dir/release}"
release_notes_src="$repo_dir/RELEASE_NOTES.md"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
release_date="$(date -u +%Y-%m-%d)"
release_stamp="${ABORA_RELEASE_STAMP:-$(date -u +%Y.%m.%d)}"
release_stamp_explicit="${ABORA_RELEASE_STAMP:+yes}"

version="$(printf '%s' "$version" | tr -cd '[:alnum:]._-')"
[[ -n "$version" ]] || version="dev"
case "$version" in
    [Vv]*) version_tag="$version" ;;
    *) version_tag="v$version" ;;
esac

mkdir -p "$release_dir"

(
    cd "$release_dir"
    shopt -s nullglob
    iso_files=("$iso_dir"/*"$release_stamp"*-x86_64-"$version_tag".iso)
    if [ "${#iso_files[@]}" -eq 0 ] && [ -z "$release_stamp_explicit" ]; then
        all_version_isos=("$iso_dir"/*-x86_64-"$version_tag".iso)
        if [ "${#all_version_isos[@]}" -gt 0 ]; then
            newest_stamp="$(
                for iso_file in "${all_version_isos[@]}"; do
                    basename "$iso_file" | sed -nE "s/.*-([0-9]{4}\.[0-9]{2}\.[0-9]{2})-x86_64-${version_tag}\.iso$/\1/p"
                done | sort -V | tail -n 1
            )"
            if [ -n "$newest_stamp" ]; then
                release_stamp="$newest_stamp"
                iso_files=("$iso_dir"/*"$release_stamp"*-x86_64-"$version_tag".iso)
            fi
        fi
    fi
    package_files=(
        "$package_dir"/tinypm-*-abora-"$version_tag".tar.gz
        "$package_dir"/anix-*-abora-"$version_tag".tar.gz
    )
    asset_files=("${iso_files[@]}")

    if [ "${#iso_files[@]}" -eq 0 ]; then
        echo "No ISO files found for ${release_stamp} ${version_tag} in: $iso_dir" >&2
        exit 1
    fi

    if [ "${#package_files[@]}" -gt 0 ]; then
        asset_files+=("${package_files[@]}")
    fi

    checksum_file="SHA256SUMS-${version_tag}.txt"
    manifest_file="RELEASE_MANIFEST-${version_tag}.txt"
    notes_file="RELEASE_NOTES-${version_tag}.md"

    sha256sum "${asset_files[@]}" \
        | sed "s#  $iso_dir/#  #; s#  $package_dir/#  #" \
        > "$checksum_file"

    {
        printf '%s (%s) release manifest\n' "$release_name" "$version_tag"
        printf 'Generated: %s\n' "$generated_at"
        printf '\nAssets\n'

        for asset_file in "${asset_files[@]}"; do
            asset_name="$(basename "$asset_file")"
            size_bytes="$(stat -c '%s' "$asset_file")"
            size_human="$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || printf '%s bytes' "$size_bytes")"
            checksum="$(sha256sum "$asset_file" | awk '{print $1}')"

            printf -- '- %s\n' "$asset_name"
            printf '  size: %s (%s bytes)\n' "$size_human" "$size_bytes"
            printf '  sha256: %s\n' "$checksum"
        done

        printf '\nSupporting files\n'
        printf -- '- %s\n' "$checksum_file"
    } > "$manifest_file"

    {
        printf '# %s\n\n' "$release_name"
        printf '_Version tag: %s_\n\n' "$version_tag"
        printf '_Release date: %s UTC_\n\n' "$release_date"
        printf '## Downloads\n\n'

        for asset_file in "${asset_files[@]}"; do
            printf -- '- `%s`\n' "$(basename "$asset_file")"
        done

        printf -- '- `%s`\n' "$checksum_file"
        printf -- '- `%s`\n\n' "$manifest_file"

        if [ -f "$release_notes_src" ]; then
            tail -n +2 "$release_notes_src"
            printf '\n'
        fi

        printf '## Checksums\n\n```text\n'
        cat "$checksum_file"
        printf '```\n'
    } > "$notes_file"
)

printf '%s\n' "$version_tag"
