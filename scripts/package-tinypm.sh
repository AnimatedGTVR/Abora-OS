#!/usr/bin/env bash
set -euo pipefail

# Builds vendor/tinypm/ (a real Rust crate) and packages the two release
# binaries -- tinypm and grab -- plus license/docs into a release tarball.
repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
package_dir="${ABORA_PACKAGE_DIR:-$out_dir/packages}"
tinypm_dir="$repo_dir/vendor/tinypm"
version_id="${ABORA_VERSION_ID:-}"

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

tinypm_version="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$tinypm_dir/Cargo.toml")"
tinypm_version="$(printf '%s' "${tinypm_version:-unknown}" | tr -cd '[:alnum:]._-')"
[[ -n "$tinypm_version" ]] || tinypm_version="unknown"
case "$tinypm_version" in
  [Vv]*) tinypm_tag="$tinypm_version" ;;
  *) tinypm_tag="v$tinypm_version" ;;
esac

( cd "$tinypm_dir" && cargo build --release --locked )

release_dir="$tinypm_dir/target/release"
for bin in tinypm grab; do
  if [[ ! -x "$release_dir/$bin" ]]; then
    echo "TinyPM release build did not produce $release_dir/$bin" >&2
    exit 1
  fi
done

mkdir -p "$package_dir"

package_name="tinypm-${tinypm_tag}-abora-${version_tag}.tar.gz"
package_path="$package_dir/$package_name"
rm -f "$package_path"

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

mkdir -p "$stage_dir/tinypm"
install -m 0755 "$release_dir/tinypm" "$stage_dir/tinypm/tinypm"
install -m 0755 "$release_dir/grab" "$stage_dir/tinypm/grab"
for doc in README.md LICENSE CHANGELOG.md; do
  if [[ -f "$tinypm_dir/$doc" ]]; then
    install -m 0644 "$tinypm_dir/$doc" "$stage_dir/tinypm/$doc"
  fi
done

tar -czf "$package_path" -C "$stage_dir" tinypm

printf '%s\n' "$package_path"
