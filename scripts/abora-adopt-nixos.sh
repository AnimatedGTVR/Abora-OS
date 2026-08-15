#!/usr/bin/env bash
set -euo pipefail

repo_url="${ABORA_REPO_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"
config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  abora adopt-nixos [--apply] [--desktop PROFILE] [--config-dir DIR]

Add Abora OS to an existing NixOS install without erasing /home or replacing
the user's current desktop/app configuration.

By default this is a dry run. Pass --apply to copy Abora modules into the
existing NixOS config and add a tiny import file.

Examples:
  git clone https://github.com/AnimatedGTVR/Abora-OS.git
  cd Abora-OS
  ./abora adopt-nixos
  sudo ./abora adopt-nixos --apply
  sudo ./abora adopt-nixos --apply --desktop gnome
EOF
}

apply=0
desktop="none"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    --desktop)
      [[ -n "${2:-}" ]] || { printf 'abora adopt-nixos: --desktop needs a profile\n' >&2; exit 2; }
      desktop="$2"
      shift 2
      ;;
    --config-dir)
      [[ -n "${2:-}" ]] || { printf 'abora adopt-nixos: --config-dir needs a directory\n' >&2; exit 2; }
      config_dir="$2"
      shift 2
      ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'abora adopt-nixos: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

valid_desktop() {
  case "$1" in
    none|gnome|plasma|hyprland|sway|xfce|cinnamon|mate|budgie|lxqt|pantheon|i3|awesome|openbox|niri|river|qtile|bspwm|fluxbox|icewm|herbstluftwm|cosmic|mangowm)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

valid_desktop "$desktop" || {
  printf 'abora adopt-nixos: unknown desktop profile: %s\n' "$desktop" >&2
  exit 2
}

if [[ ! -f /etc/os-release ]] || ! grep -qi '^ID=.*nixos' /etc/os-release; then
  printf 'abora adopt-nixos: this command is for existing NixOS systems.\n' >&2
  exit 1
fi

if [[ ! -d "$config_dir" ]]; then
  printf 'abora adopt-nixos: config directory not found: %s\n' "$config_dir" >&2
  exit 1
fi

if [[ "$apply" == 1 && "${EUID:-$(id -u)}" != 0 ]]; then
  printf 'abora adopt-nixos: run with sudo when using --apply.\n' >&2
  exit 1
fi

if [[ ! -f "$repo_dir/nix/modules/installed-base.nix" ]]; then
  printf 'abora adopt-nixos: run this from an Abora OS source checkout.\n' >&2
  printf 'Clone with: git clone %s\n' "$repo_url" >&2
  exit 1
fi

target_import="$config_dir/abora-adopt.nix"
configuration_nix="$config_dir/configuration.nix"
flake_nix="$config_dir/flake.nix"

print_plan() {
  printf 'Abora NixOS adoption plan\n'
  printf '  Source checkout : %s\n' "$repo_dir"
  printf '  NixOS config    : %s\n' "$config_dir"
  printf '  Desktop profile : %s\n' "$desktop"
  printf '\n'
  printf 'This will keep your existing /home, users, packages, and desktop config.\n'
  printf 'It copies Abora modules to %s/abora and writes %s.\n' "$config_dir" "$target_import"
  printf 'Default desktop "none" means Abora will not replace your current desktop.\n'
}

copy_if_exists() {
  local source="$1"
  local dest="$2"
  [[ -e "$source" ]] || return 0
  rm -rf "$dest"
  cp -R "$source" "$dest"
}

ensure_import_in_configuration() {
  local import_line='    ./abora-adopt.nix'

  [[ -f "$configuration_nix" ]] || return 0
  grep -q './abora-adopt.nix' "$configuration_nix" && return 0

  if grep -q '^[[:space:]]*imports[[:space:]]*=' "$configuration_nix"; then
    sed -i "/^[[:space:]]*imports[[:space:]]*=/a\\$import_line" "$configuration_nix"
  else
    sed -i '0,/{/s//{\
  imports = [\
    .\/abora-adopt.nix\
  ];/' "$configuration_nix"
  fi
}

print_plan

if [[ "$apply" != 1 ]]; then
  printf '\nDry run only. Re-run with --apply to make these changes.\n'
  exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$config_dir/abora-backups/$timestamp"
mkdir -p "$backup_dir"
cp -a "$config_dir"/. "$backup_dir"/

abora_dir="$config_dir/abora"
mkdir -p "$abora_dir"

copy_if_exists "$repo_dir/VERSION" "$abora_dir/VERSION"
copy_if_exists "$repo_dir/nix/modules/abora-options.nix" "$abora_dir/abora-options.nix"
copy_if_exists "$repo_dir/nix/modules/installed-base.nix" "$abora_dir/installed-base.nix"
copy_if_exists "$repo_dir/nix/modules/anix.nix" "$abora_dir/anix-module.nix"
copy_if_exists "$repo_dir/nix/modules/desktops" "$abora_dir/desktops"
copy_if_exists "$repo_dir/nix/pkgs" "$abora_dir/pkgs"
copy_if_exists "$repo_dir/assets/wallpapers" "$abora_dir/wallpapers"
copy_if_exists "$repo_dir/assets/wallpaper-themes" "$abora_dir/wallpaper-themes"
copy_if_exists "$repo_dir/assets/bootloader" "$abora_dir/bootloader"
copy_if_exists "$repo_dir/assets/plymouth" "$abora_dir/plymouth"
copy_if_exists "$repo_dir/assets/Effects" "$abora_dir/effects"
copy_if_exists "$repo_dir/assets/mango" "$abora_dir/mango"
copy_if_exists "$repo_dir/assets/anix-languages" "$abora_dir/anix-languages"
copy_if_exists "$repo_dir/docs" "$abora_dir/docs"
copy_if_exists "$repo_dir/vendor/modularity" "$abora_dir/vendor/modularity"

for pair in \
  "scripts/abora-ui.sh:ui.sh" \
  "scripts/abora.sh:abora.sh" \
  "scripts/abora-build.sh:build.sh" \
  "scripts/abora-config.sh:config.sh" \
  "scripts/abora-desktop.sh:desktop.sh" \
  "scripts/abora-dotfiles-import.sh:dotfiles-import.sh" \
  "scripts/abora-doctor.sh:doctor.sh" \
  "scripts/abora-recovery.sh:recovery.sh" \
  "scripts/abora-welcome.sh:welcome.sh" \
  "scripts/abora-app-catalog.sh:app-catalog.sh" \
  "scripts/abora-apps.sh:apps.sh" \
  "scripts/abora-support-report.sh:support-report.sh" \
  "scripts/abora-hardware-test.sh:hardware-test.sh" \
  "scripts/abora-gaming.sh:gaming.sh" \
  "scripts/anix.sh:anix.sh" \
  "scripts/abora-update.sh:update.sh" \
  "scripts/abora-theme-sync.sh:theme-sync.sh"; do
  src="${pair%%:*}"
  dest="${pair#*:}"
  copy_if_exists "$repo_dir/$src" "$abora_dir/$dest"
  [[ ! -f "$abora_dir/$dest" ]] || chmod 0755 "$abora_dir/$dest"
done

cat > "$target_import" <<EOF
{ ... }:
{
  imports = [
    ./abora/abora-options.nix
    ./abora/installed-base.nix
    ./abora/anix-module.nix
  ];

  # NixOS adoption mode:
  # - keeps existing users, homes, packages, and desktop settings
  # - installs Abora tools/branding with mkDefault-safe system defaults
  # - set abora.user.name later only if you want Abora to manage that user
  abora.user.name = null;
  abora.desktop = "$desktop";
}
EOF

if [[ -f "$configuration_nix" ]]; then
  ensure_import_in_configuration
elif [[ -f "$flake_nix" ]]; then
  printf '\nFlake config detected. Add ./abora-adopt.nix to your NixOS module list.\n'
  printf 'Example:\n'
  printf '  modules = [ ./configuration.nix ./abora-adopt.nix ];\n'
else
  printf '\nNo configuration.nix or flake.nix found in %s.\n' "$config_dir"
  printf 'Import %s from your real NixOS configuration.\n' "$target_import"
fi

printf '\nBackup saved: %s\n' "$backup_dir"
printf 'Next step:\n'
printf '  sudo nixos-rebuild test\n'
printf 'Then, if it looks good:\n'
printf '  sudo nixos-rebuild switch\n'
