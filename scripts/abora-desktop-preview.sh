#!/usr/bin/env bash
set -euo pipefail

# Prints the exact NixOS config/package blocks Abora would generate for a
# given desktop profile, standalone -- no installer, no ISO, nothing
# written to disk. Meant for a plain NixOS user who wants "give me Abora's
# take on configuring GNOME/Hyprland/whatever" to paste into their own
# configuration.nix, the same idea as the anix/branding standalone modules
# but for the desktop-profile layer (abora_desktop_config_block /
# abora_desktop_package_block in abora-desktop-profiles.sh), which is
# shell-generated text and so can't be a declarative nixosModule the same
# way anix/branding are.

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage: abora-desktop-preview.sh <profile> [xkb-layout] [username]

Prints the NixOS config block and package list Abora uses for <profile>,
so you can paste them into your own configuration.nix on a plain NixOS
system -- no Abora install required.

  profile      Desktop profile id (e.g. gnome, hyprland, plasma, xfce, niri).
               Run with no arguments to list every available profile.
  xkb-layout   Keyboard layout for the config block. Default: us
  username     Username referenced by autologin/session config. Default: user

Examples:
  abora-desktop-preview.sh gnome
  abora-desktop-preview.sh hyprland de myuser
EOF
}

profiles_lib="$script_dir/abora-desktop-profiles.sh"
if [[ ! -f "$profiles_lib" ]]; then
    printf 'ERROR: could not find abora-desktop-profiles.sh next to this script (%s)\n' "$script_dir" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$profiles_lib"

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    if [[ $# -eq 0 ]]; then
        printf '\nAvailable profiles:\n'
        abora_supported_desktop_profiles | sed 's/^/  /'
    fi
    exit 0
fi

profile="$1"
xkb_layout="${2:-us}"
username="${3:-user}"

if ! abora_supported_desktop_profiles | grep -qx "$profile"; then
    printf 'ERROR: unknown desktop profile: %s\n\n' "$profile" >&2
    printf 'Available profiles:\n' >&2
    abora_supported_desktop_profiles | sed 's/^/  /' >&2
    exit 1
fi

printf '# --- Abora desktop config for "%s" (xkb=%s, user=%s) ---\n' \
    "$profile" "$xkb_layout" "$username"
printf '# Paste the block below into your NixOS configuration:\n\n'
abora_desktop_config_block "$profile" "$xkb_layout" "$username"

printf '\n# Packages Abora installs alongside this desktop\n'
printf '# (add these to environment.systemPackages):\n'
abora_desktop_package_block "$profile" 2>/dev/null || \
    printf '  # (no extra packages for this profile)\n'
