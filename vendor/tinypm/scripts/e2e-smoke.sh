#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '[e2e] syntax checks...\n'
bash -n \
  "$repo_root/Parcel" \
  "$repo_root/grab" \
  "$repo_root/tinypm" \
  "$repo_root/syspm.sh" \
  "$repo_root/version" \
  "$repo_root/install.sh" \
  "$repo_root/uninstall.sh" \
  "$repo_root/scripts/install.sh" \
  "$repo_root/scripts/uninstall.sh" \
  "$repo_root/lib/core/"*.sh \
  "$repo_root/lib/providers/"*.sh

printf '[e2e] local command smoke...\n'
"$repo_root/Parcel" --version >/dev/null
"$repo_root/tinypm" help >/dev/null
"$repo_root/tinypm" doctor >/dev/null
"$repo_root/grab" --version >/dev/null
"$repo_root/tinypm" search yq >/dev/null
"$repo_root/version" >/dev/null
version_output="$(mktemp)"
TINYPM_FLAVOR=abora "$repo_root/version" >"$version_output"
grep -q 'Abora TinyPM V3 / Parcel v3.0.0' "$version_output"
rm -f "$version_output"
"$repo_root/syspm.sh" help >/dev/null

printf '[e2e] fresh install smoke...\n'
tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

export HOME="$tmp_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export TINYPM_PREFIX="$HOME/.tinypm"

mkdir -p "$HOME"

"$repo_root/install.sh" >/dev/null

"$HOME/.local/bin/Parcel" --version >/dev/null
"$HOME/.local/bin/tinypm" help >/dev/null
"$HOME/.local/bin/tiny" --version >/dev/null
"$HOME/.local/bin/grab" help >/dev/null
"$HOME/.local/bin/syspm" help >/dev/null
"$HOME/.local/bin/tinypm" doctor --fix >/dev/null

printf '[e2e] flavored install smoke...\n'
rm -rf "$HOME/.tinypm" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config/tinypm"
mkdir -p "$HOME/.local/bin"
TINYPM_FLAVOR=abora "$repo_root/install.sh" >/dev/null
installed_version_output="$(mktemp)"
"$HOME/.local/bin/Parcel" --version >/dev/null
"$HOME/.local/bin/tiny" --version >"$installed_version_output"
grep -q 'Abora TinyPM V3 / Parcel v3.0.0' "$installed_version_output"
rm -f "$installed_version_output"
"$HOME/.local/bin/grab" --version >/dev/null

printf '[e2e] PASS\n'
