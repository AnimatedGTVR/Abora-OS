#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

version_value="$(tr -d '\n' < VERSION | tr -cd '[:alnum:]._-')"
case "$version_value" in
  [Vv]*) release_tag="$version_value" ;;
  *) release_tag="v$version_value" ;;
esac

bash_scripts=(
  "scripts/abora-boot.sh"
  "scripts/abora-center.sh"
  "scripts/abora-installer.sh"
  "scripts/abora-launch-gui.sh"
  "scripts/abora-update.sh"
  "scripts/abora-welcome.sh"
  "scripts/build-iso.sh"
  "scripts/build-tinypm-image.sh"
  "scripts/package-tinypm.sh"
  "scripts/rebuild-vm.sh"
  "scripts/release-metadata.sh"
  "scripts/run-qemu.sh"
  "scripts/check-scripts.sh"
)

nix_files=(
  "flake.nix"
  "nix/modules/installed-base.nix"
  "nix/profiles/live.nix"
)

failed=0

pass() {
  printf '[ok]   %s\n' "$1"
}

fail() {
  printf '[fail] %s\n' "$1"
  failed=1
}

for file in "${bash_scripts[@]}"; do
  if [[ ! -f "$file" ]]; then
    fail "Missing file: $file"
    continue
  fi

  if bash -n "$file"; then
    pass "syntax (bash): $file"
  else
    fail "syntax (bash): $file"
  fi

  if [[ -x "$file" ]]; then
    pass "executable: $file"
  else
    fail "not executable: $file"
  fi
done

for file in "${nix_files[@]}"; do
  if [[ -f "$file" ]]; then
    pass "exists: $file"
  else
    fail "Missing file: $file"
  fi
done

if command -v nix >/dev/null 2>&1; then
  if nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file "$repo_dir" >/dev/null 2>&1; then
    pass "nix flake evaluation"
  else
    fail "nix flake evaluation"
  fi
else
  pass "nix command unavailable (flake eval skipped)"
fi

tmp_ok="$(mktemp -d)"
tmp_empty="$(mktemp -d)"
trap 'rm -rf "$tmp_ok" "$tmp_empty"' EXIT

touch "$tmp_ok/abora-test-x86_64-${release_tag}.iso"
touch "$tmp_ok/tinypm-v0.0.0-abora-${release_tag}.tar.gz"
if ABORA_OUT_DIR="$tmp_ok" scripts/release-metadata.sh >/dev/null; then
  if [[ -f "$tmp_ok/SHA256SUMS-${release_tag}.txt" ]] \
    && [[ -f "$tmp_ok/RELEASE_MANIFEST-${release_tag}.txt" ]] \
    && [[ -f "$tmp_ok/RELEASE_NOTES-${release_tag}.md" ]] \
    && grep -q "tinypm-v0.0.0-abora-${release_tag}.tar.gz" "$tmp_ok/SHA256SUMS-${release_tag}.txt"; then
    pass "runtime: release-metadata checksum generation"
  else
    fail "runtime: release-metadata checksum generation"
  fi
else
  fail "runtime: release-metadata checksum generation"
fi

empty_output="$(ABORA_OUT_DIR="$tmp_empty" scripts/release-metadata.sh 2>&1 || true)"
if printf '%s' "$empty_output" | grep -q "No ISO files found"; then
  pass "runtime: release-metadata empty-dir guard"
else
  fail "runtime: release-metadata empty-dir guard"
fi

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

printf '\nAll script checks passed.\n'
