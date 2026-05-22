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
  "scripts/abora-app-catalog.sh"
  "scripts/abora-apps.sh"
  "scripts/abora.sh"
  "scripts/abora-boot.sh"
  "scripts/abora-config.sh"
  "scripts/abora-desktop.sh"
  "scripts/abora-desktop-profiles.sh"
  "scripts/abora-doctor.sh"
  "scripts/abora-hardware-test.sh"
  "scripts/abora-installer.sh"
  "scripts/abora-recovery.sh"
  "scripts/abora-session-setup.sh"
  "scripts/abora-setup-launcher.sh"
  "scripts/abora-support-report.sh"
  "scripts/abora-ui.sh"
  "scripts/abora-welcome.sh"
  "scripts/anix.sh"
  "scripts/check-desktops.sh"
  "scripts/abora-theme-sync.sh"
  "scripts/abora-update.sh"
  "scripts/build-iso.sh"
  "scripts/build-tinypm-image.sh"
  "scripts/package-tinypm.sh"
  "scripts/preflight.sh"
  "scripts/rebuild-vm.sh"
  "scripts/release-metadata.sh"
  "scripts/run-qemu.sh"
  "scripts/check-scripts.sh"
)

nix_files=(
  "flake.nix"
  "nix/modules/abora-options.nix"
  "nix/modules/anix.nix"
  "nix/modules/installed-base.nix"
  "nix/profiles/live.nix"
)

required_files=(
  "scripts/abora-setup.desktop"
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

for file in "${required_files[@]}"; do
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

tmp_anix="$tmp_ok/anix.nix"
printf '%s\n' \
  '{ ... }:' \
  '{' \
  '  anix.enable = true;' \
  '  anix.hostname = "testbox";' \
  '  anix.timezone = "UTC";' \
  '  anix.keyboard.console = "us";' \
  '  anix.keyboard.xkb = "us";' \
  '  anix.desktop = "gnome";' \
  '  anix.wallpaper = "oceandusk.png";' \
  '}' > "$tmp_anix"
anix_output="$(
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  ANIX_CONFIG_FILE="$tmp_anix" \
  ANIX_SYSTEM_CONFIG="$tmp_ok" \
  scripts/anix.sh show 2>&1
)"
if printf '%s' "$anix_output" | grep -q "testbox" \
  && printf '%s' "$anix_output" | grep -q "oceandusk.png"; then
  pass "runtime: anix fallback UI show"
else
  fail "runtime: anix fallback UI show"
fi

tmp_anix_config_dir="$tmp_ok/anix-config"
mkdir -p "$tmp_anix_config_dir"
if ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_config_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh config set snapshots.push true >/dev/null \
  && grep -q "snapshots.push=true" "$tmp_anix_config_dir/.anix/config"; then
  pass "runtime: anix tool config set"
else
  fail "runtime: anix tool config set"
fi

tmp_anix_save_dir="$tmp_ok/anix-save"
mkdir -p "$tmp_anix_save_dir"
printf '%s\n' '{ ... }: { networking.hostName = "testbox"; }' > "$tmp_anix_save_dir/configuration.nix"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_save_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh save "anix: test snapshot" >/dev/null \
  && git -C "$tmp_anix_save_dir" log --oneline -1 | grep -q "anix: test snapshot"; then
  pass "runtime: anix local snapshot"
else
  fail "runtime: anix local snapshot"
fi

tmp_anix_switch_dir="$tmp_ok/anix-switch"
tmp_anix_bin="$tmp_ok/anix-bin"
tmp_anix_log="$tmp_ok/anix-rebuild.log"
mkdir -p "$tmp_anix_switch_dir" "$tmp_anix_bin"
printf '%s\n' '{ ... }: { }' > "$tmp_anix_switch_dir/flake.nix"
git -C "$tmp_anix_switch_dir" init >/dev/null
git -C "$tmp_anix_switch_dir" -c user.name=ANIX -c user.email=anix@localhost add -A
git -C "$tmp_anix_switch_dir" -c user.name=ANIX -c user.email=anix@localhost commit -m "initial" >/dev/null
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$ANIX_REBUILD_LOG"' > "$tmp_anix_bin/nixos-rebuild"
chmod +x "$tmp_anix_bin/nixos-rebuild"
if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh switch nix gaming --now >/dev/null \
  && grep -q "switch --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix switch maps flake profile"
else
  fail "runtime: anix switch maps flake profile"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh rollback nix --now >/dev/null \
  && grep -q "switch --rollback" "$tmp_anix_log"; then
  pass "runtime: anix generation rollback"
else
  fail "runtime: anix generation rollback"
fi

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$repo_dir/scripts/abora-desktop-profiles.sh"
gnome_config_block="$(abora_desktop_config_block gnome us abora)"
gnome_package_block="$(abora_desktop_package_block gnome)"
if printf '%s\n' "$gnome_config_block" | grep -q "environment.systemPackages"; then
  fail "runtime: desktop config block contains environment.systemPackages"
elif ! printf '%s\n' "$gnome_package_block" | grep -q "gnomeExtensions.dash-to-dock"; then
  fail "runtime: GNOME package block missing extension packages"
else
  pass "runtime: desktop package/config split"
fi

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more checks failed.\n' >&2
  exit 1
fi

printf '\nAll script checks passed.\n'
