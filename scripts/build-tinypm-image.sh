#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

abora_version="$(tr -d '\n' < VERSION | tr -cd '[:alnum:]._-')"
[[ -n "$abora_version" ]] || abora_version="unknown"

tinypm_version="$(
  awk -F'"' '/^tinypm_version=/{print $2; exit}' vendor/tinypm/lib/core/common.sh
)"
tinypm_version="$(printf '%s' "${tinypm_version:-unknown}" | tr -cd '[:alnum:]._-')"
[[ -n "$tinypm_version" ]] || tinypm_version="unknown"

image_name="${1:-${IMAGE_NAME:-abora-tinypm:${tinypm_version}-abora-${abora_version}}}"

docker build \
  --file packaging/tinypm/Dockerfile \
  --build-arg TINYPM_VERSION="$tinypm_version" \
  --build-arg ABORA_VERSION="$abora_version" \
  --build-arg IMAGE_SOURCE="https://github.com/AnimatedGTVR/abora-os" \
  --tag "$image_name" \
  vendor/tinypm

printf 'Built TinyPM image: %s\n' "$image_name"
printf 'Try it with: docker run --rm %s Parcel --version\n' "$image_name"
printf 'The full TinyPM project lives at: /opt/tinypm/project\n'
