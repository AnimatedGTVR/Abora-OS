#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(tr -d '\n' < "$repo_dir/VERSION")"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
release_notes_src="$repo_dir/RELEASE_NOTES.md"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
release_date="$(date -u +%Y-%m-%d)"

version="$(printf '%s' "$version" | tr -cd '[:alnum:]._-')"
[[ -n "$version" ]] || version="dev"
case "$version" in
    [Vv]*) version_tag="$version" ;;
    *) version_tag="v$version" ;;
esac

mkdir -p "$out_dir"

(
    cd "$out_dir"
    shopt -s nullglob
    iso_files=(./*-"$version_tag".iso)
    if [ "${#iso_files[@]}" -eq 0 ]; then
        echo "No ISO files found for version ${version_tag} in: $out_dir" >&2
        exit 1
    fi

    checksum_file="SHA256SUMS-${version_tag}.txt"
    manifest_file="RELEASE_MANIFEST-${version_tag}.txt"
    notes_file="RELEASE_NOTES-${version_tag}.md"

    sha256sum "${iso_files[@]}" | sed 's# \./# #' > "$checksum_file"

    {
        printf 'Abora OS %s release manifest\n' "$version_tag"
        printf 'Generated: %s\n' "$generated_at"
        printf '\nAssets\n'

        for iso_file in "${iso_files[@]}"; do
            iso_name="${iso_file#./}"
            size_bytes="$(stat -c '%s' "$iso_name")"
            size_human="$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || printf '%s bytes' "$size_bytes")"
            checksum="$(sha256sum "$iso_name" | awk '{print $1}')"

            printf -- '- %s\n' "$iso_name"
            printf '  size: %s (%s bytes)\n' "$size_human" "$size_bytes"
            printf '  sha256: %s\n' "$checksum"
        done

        printf '\nSupporting files\n'
        printf -- '- %s\n' "$checksum_file"
    } > "$manifest_file"

    {
        printf '# Abora OS %s\n\n' "$version_tag"
        printf '_Release date: %s UTC_\n\n' "$release_date"
        printf '## Downloads\n\n'

        for iso_file in "${iso_files[@]}"; do
            printf -- '- `%s`\n' "${iso_file#./}"
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
