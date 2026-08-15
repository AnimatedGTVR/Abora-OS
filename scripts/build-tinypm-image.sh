#!/usr/bin/env bash
set -euo pipefail

# Builds a Docker/container image of TinyPM (packaging/tinypm/Dockerfile) --
# a third distribution channel alongside the Nix package (nix/pkgs/anix.nix
# has its own TinyPM wiring) and the standalone tarball (package-tinypm.sh),
# for running TinyPM outside any NixOS/Abora system entirely.
repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

abora_version="$(tr -d '\n' < VERSION | tr -cd '[:alnum:]._-')"
[[ -n "$abora_version" ]] || abora_version="unknown"

tinypm_version=""
for common_sh in vendor/tinypm/lib/tinypm/core/common.sh vendor/tinypm/lib/core/common.sh; do
  [[ -f "$common_sh" ]] || continue
  tinypm_version="$(awk -F'"' '/^tinypm_version=/{print $2; exit}' "$common_sh")"
  [[ -n "$tinypm_version" ]] && break
done
tinypm_version="$(printf '%s' "${tinypm_version:-unknown}" | tr -cd '[:alnum:]._-')"
[[ -n "$tinypm_version" ]] || tinypm_version="unknown"

image_name="${1:-${IMAGE_NAME:-abora-tinypm:${tinypm_version}-abora-${abora_version}}}"

docker build \
  --file packaging/tinypm/Dockerfile \
  --build-arg TINYPM_VERSION="$tinypm_version" \
  --build-arg ABORA_VERSION="$abora_version" \
  --build-arg IMAGE_SOURCE="https://github.com/AnimatedGTVR/Abora-OS" \
  --tag "$image_name" \
  vendor/tinypm

printf 'Built TinyPM image: %s\n' "$image_name"
printf 'Try it with: docker run --rm %s Parcel --version\n' "$image_name"
printf 'The full TinyPM project lives at: /opt/tinypm/project\n'
