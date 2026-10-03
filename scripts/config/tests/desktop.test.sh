#!/usr/bin/env bash
# Behaviour tests for desktop profiles, desktop preview and the dotfiles importer (scripts/config/abora-desktop-profiles.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-desktop-profiles.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

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

# abora-desktop-preview.sh is the standalone-user path onto the exact same
# abora_desktop_config_block/abora_desktop_package_block functions just
# exercised above, so verify its own arg handling/output plumbing works
# end to end rather than only unit-testing the library functions directly.
preview_out="$("$repo_dir/scripts/abora-desktop-preview.sh" hyprland de previewuser)"

if ! printf '%s\n' "$preview_out" | grep -q 'xkb.layout = "de"'; then
  fail "runtime: abora-desktop-preview.sh did not interpolate xkb layout"
elif ! printf '%s\n' "$preview_out" | grep -q 'previewuser'; then
  fail "runtime: abora-desktop-preview.sh did not interpolate username"
else
  pass "runtime: abora-desktop-preview.sh renders a real desktop config"
fi

if "$repo_dir/scripts/abora-desktop-preview.sh" not-a-real-desktop-profile \
    >/dev/null 2>&1; then
  fail "runtime: abora-desktop-preview.sh accepted an unknown desktop profile"
else
  pass "runtime: abora-desktop-preview.sh rejects an unknown desktop profile"
fi

tmp_dotfiles_src="$(mktemp -d)"

tmp_dotfiles_home="$(mktemp -d)"

tmp_dotfiles_cache="$(mktemp -d)"

mkdir -p "$tmp_dotfiles_src/.config/hypr" "$tmp_dotfiles_src/.config/waybar" "$tmp_dotfiles_home"

printf 'source-dotfile\n' > "$tmp_dotfiles_src/.zshrc"

printf 'hyprland config\n' > "$tmp_dotfiles_src/.config/hypr/hyprland.conf"

printf 'existing\n' > "$tmp_dotfiles_home/.zshrc"

git -C "$tmp_dotfiles_src" init >/dev/null 2>&1

git -C "$tmp_dotfiles_src" config user.email test@example.invalid

git -C "$tmp_dotfiles_src" config user.name "Abora Test"

git -C "$tmp_dotfiles_src" add . >/dev/null

git -C "$tmp_dotfiles_src" commit -m dotfiles >/dev/null 2>&1

dotfiles_dry_run_out="$(HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh --dry-run "$tmp_dotfiles_src" 2>&1)"

if grep -q 'would copy' <<<"$dotfiles_dry_run_out" \
  && HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh "$tmp_dotfiles_src" >/dev/null \
  && grep -q 'existing' "$tmp_dotfiles_home/.zshrc" \
  && grep -q 'hyprland config' "$tmp_dotfiles_home/.config/hypr/hyprland.conf" \
  && HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh --replace "$tmp_dotfiles_src" >/dev/null \
  && grep -q 'source-dotfile' "$tmp_dotfiles_home/.zshrc" \
  && HOME="$tmp_dotfiles_home" bash scripts/abora-dotfiles-import.sh \
      --git-url "file://$tmp_dotfiles_src" "$tmp_dotfiles_cache/checkout" >/dev/null 2>&1 \
  && [[ -d "$tmp_dotfiles_cache/checkout/.git" ]] \
  && grep -q 'source-dotfile' "$tmp_dotfiles_cache/checkout/.zshrc" \
  && mkdir -p "$tmp_dotfiles_cache/abora-dotfiles" \
  && printf 'stale\n' > "$tmp_dotfiles_cache/abora-dotfiles/partial" \
  && HOME="$tmp_dotfiles_home" XDG_CACHE_HOME="$tmp_dotfiles_cache" \
    bash scripts/abora-dotfiles-import.sh \
      --git-url "file://$tmp_dotfiles_src" "$tmp_dotfiles_cache/abora-dotfiles" >/dev/null 2>&1 \
  && [[ ! -e "$tmp_dotfiles_cache/abora-dotfiles/partial" ]] \
  && [[ -d "$tmp_dotfiles_cache/abora-dotfiles/.git" ]] \
  && mkdir -p "$tmp_dotfiles_cache/manual-nonempty" \
  && printf 'keep\n' > "$tmp_dotfiles_cache/manual-nonempty/file" \
  && ! HOME="$tmp_dotfiles_home" XDG_CACHE_HOME="$tmp_dotfiles_cache" \
    bash scripts/abora-dotfiles-import.sh \
      --git-url "file://$tmp_dotfiles_src" "$tmp_dotfiles_cache/manual-nonempty" >/dev/null 2>&1 \
  && grep -q 'keep' "$tmp_dotfiles_cache/manual-nonempty/file"; then
  pass "runtime: dotfiles importer preserves by default and replaces on request"
else
  fail "runtime: dotfiles importer preserves by default and replaces on request"
fi

rm -rf "$tmp_dotfiles_src" "$tmp_dotfiles_home" "$tmp_dotfiles_cache"

testlib_finish
