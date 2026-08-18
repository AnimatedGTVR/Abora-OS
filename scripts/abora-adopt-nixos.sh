#!/usr/bin/env bash
set -euo pipefail

repo_url="${ABORA_REPO_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"
config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  abora adopt-nixos [--apply] [--desktop PROFILE] [--gaming] [--config-dir DIR]

Add Abora OS to an existing NixOS install without erasing /home or replacing
the user's current desktop/app configuration.

Run with no arguments at all for an interactive wizard that asks a couple of
questions (desktop profile, gaming layer) and confirms before applying
anything. Pass any flag to skip straight to the scripted, non-interactive
path instead -- by default that's a dry run; pass --apply to copy Abora
modules into the existing NixOS config and add a tiny import file.

Examples:
  git clone https://github.com/AnimatedGTVR/Abora-OS.git
  cd Abora-OS
  ./abora adopt-nixos
  sudo ./abora adopt-nixos --apply
  sudo ./abora adopt-nixos --apply --desktop gnome --gaming
EOF
}

apply=0
desktop="none"
gaming_enable=0
had_args=$#

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
    --gaming)
      gaming_enable=1
      shift
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

# Non-interactive path (any flag given at all) validates desktop up front,
# same as before. Interactive mode (no flags) asks for it later, inside
# run_interactive_wizard, once print_plan exists to show the result.
if [[ "$had_args" -gt 0 ]]; then
  valid_desktop "$desktop" || {
    printf 'abora adopt-nixos: unknown desktop profile: %s\n' "$desktop" >&2
    exit 2
  }
fi

if [[ "${ABORA_ASSUME_NIXOS:-0}" != 1 ]] && { [[ ! -f /etc/os-release ]] || ! grep -qi '^ID=.*nixos' /etc/os-release; }; then
  printf 'abora adopt-nixos: this command is for existing NixOS systems.\n' >&2
  exit 1
fi

if [[ ! -d "$config_dir" ]]; then
  printf 'abora adopt-nixos: config directory not found: %s\n' "$config_dir" >&2
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
  printf '  Gaming layer    : %s\n' "$([[ "$gaming_enable" == 1 ]] && printf 'enabled' || printf 'off')"
  printf '\n'
  printf 'This will keep your existing /home, users, packages, and desktop config.\n'
  printf 'It copies Abora modules to %s/abora and writes %s.\n' "$config_dir" "$target_import"
  printf 'Default desktop "none" means Abora will not replace your current desktop.\n'
}

# Interactive wizard: only when the command is run bare (no flags at all),
# so every scripted/automated use of this command keeps working exactly as
# before. Asks the two questions that actually change the generated config
# (desktop, gaming), shows the same plan the scripted path would via
# print_plan, and requires an explicit "yes" before touching anything.
run_interactive_wizard() {
  printf 'Abora NixOS Adoption Wizard\n'
  printf '%s\n\n' "----------------------------------------"
  printf 'This adds ANIX and Abora tools to your existing NixOS system.\n'
  printf 'Your users, home directories, and current desktop config are kept as-is\n'
  printf 'unless you choose a desktop profile below.\n\n'

  printf 'Desktop profile to let Abora manage (leave blank to keep your current one):\n'
  printf '  none gnome plasma hyprland sway xfce cinnamon mate budgie lxqt pantheon\n'
  printf '  i3 awesome openbox niri river qtile bspwm fluxbox icewm herbstluftwm\n'
  printf '  cosmic mangowm\n'
  printf 'Desktop [none]: '
  read -r answer_desktop || answer_desktop=""
  desktop="${answer_desktop:-none}"
  valid_desktop "$desktop" || {
    printf 'abora adopt-nixos: unknown desktop profile: %s\n' "$desktop" >&2
    exit 2
  }

  printf '\nEnable the Abora Gaming layer (Steam, GameMode, MangoHud, Vulkan tools)? [y/N]: '
  read -r answer_gaming || answer_gaming=""
  case "$answer_gaming" in
    y|Y|yes|Yes|YES) gaming_enable=1 ;;
    *) gaming_enable=0 ;;
  esac

  printf '\n'
  print_plan
  printf '\n'

  printf 'Apply these changes now? [y/N]: '
  read -r answer_apply || answer_apply=""
  case "$answer_apply" in
    y|Y|yes|Yes|YES) apply=1 ;;
    *)
      printf '\nNo changes made. Re-run this wizard anytime, or use flags directly:\n'
      printf '  sudo ./abora adopt-nixos --apply --desktop %s%s\n' \
        "$desktop" "$([[ "$gaming_enable" == 1 ]] && printf ' --gaming')"
      exit 0
      ;;
  esac
}

copy_if_exists() {
  local source="$1"
  local dest="$2"
  [[ -e "$source" ]] || return 0
  rm -rf "$dest"
  cp -R "$source" "$dest"
}

ensure_import_in_configuration() {
  [[ -f "$configuration_nix" ]] || return 0
  grep -q './abora-adopt.nix' "$configuration_nix" && return 0

  if grep -q '^[[:space:]]*imports[[:space:]]*=' "$configuration_nix"; then
    # Insert right after the list's opening "[", not right after "imports =".
    # nixos-generate-config's own standard output (what most real
    # configuration.nix files still look like) puts "imports =" and "["
    # on separate lines:
    #   imports =
    #     [ # Include the results of the hardware scan.
    #       ./hardware-configuration.nix
    #     ];
    # Inserting right after "imports =" used to land the new path *before*
    # that "[", producing `imports = ./abora-adopt.nix [ ... ];` --
    # Nix parses that as function application (call the path
    # ./abora-adopt.nix with the list as its argument), not list
    # concatenation, and fails at eval time with "attempt to call
    # something which is not a function but a path". The "[" can be on
    # the very same line as "imports =" instead (`imports = [ ./hw.nix ];`)
    # too, which this handles the same way either way.
    # Splices in right after the "[" character itself (not as a whole new
    # line following it) -- a single-line `imports = [ ./hw.nix ];` still
    # has its closing "];" on that same line, so inserting a *new line*
    # after it would land the addition after the closing bracket, outside
    # the list, the same class of bug this is fixing.
    awk '
      BEGIN { seeking = 0; done = 0 }
      {
        line = $0
        if (!seeking && !done && line ~ /^[[:space:]]*imports[[:space:]]*=/) { seeking = 1 }
        if (seeking && !done) {
          pos = index(line, "[")
          if (pos > 0) {
            print substr(line, 1, pos) " ./abora-adopt.nix"
            rest = substr(line, pos + 1)
            if (rest != "") print rest
            seeking = 0
            done = 1
            next
          }
        }
        print line
      }
    ' "$configuration_nix" > "$configuration_nix.abora-tmp"
    mv "$configuration_nix.abora-tmp" "$configuration_nix"
  else
    # No existing imports attribute: add a fresh one right inside the
    # config body's opening "{". The body's brace is *not* generally the
    # first "{" in the file -- nixos-generate-config's standard format
    # starts with a function header on its own line first:
    #   { config, pkgs, ... }:
    #
    #   { ... }
    # Naively replacing the first "{" in the whole file (the old
    # approach) mangled the function's own argument list instead --
    # `{ imports = [ ./abora-adopt.nix ]; config, pkgs, ... }:` -- a hard
    # Nix syntax error, not just a semantic mismatch. Skips past a
    # single-line function header (a line ending in ":") before looking
    # for the body's "{", same as ordinary hand-written configs that
    # start directly with "{ ... }" (no function header at all) still
    # work correctly since there's nothing to skip.
    awk '
      BEGIN { past_header = 0; done = 0 }
      {
        line = $0
        if (!past_header) {
          if (line ~ /^[[:space:]]*$/) { print; next }
          past_header = 1
          if (line ~ /:[[:space:]]*(#.*)?$/) { print; next }
        }
        if (!done) {
          pos = index(line, "{")
          if (pos > 0) {
            print substr(line, 1, pos)
            print "  imports = ["
            print "    ./abora-adopt.nix"
            print "  ];"
            rest = substr(line, pos + 1)
            if (rest != "") print rest
            done = 1
            next
          }
        }
        print
      }
    ' "$configuration_nix" > "$configuration_nix.abora-tmp"
    mv "$configuration_nix.abora-tmp" "$configuration_nix"
  fi
}

if [[ "$had_args" -eq 0 ]]; then
  run_interactive_wizard
else
  print_plan
  if [[ "$apply" != 1 ]]; then
    printf '\nDry run only. Re-run with --apply to make these changes.\n'
    exit 0
  fi
fi

if [[ "$apply" == 1 && "${EUID:-$(id -u)}" != 0 ]]; then
  if [[ "$had_args" -eq 0 ]]; then
    printf '\nRe-running with sudo to apply changes...\n'
    exec sudo "$0" --apply --desktop "$desktop" $([[ "$gaming_enable" == 1 ]] && printf -- '--gaming') --config-dir "$config_dir"
  fi
  printf 'abora adopt-nixos: run with sudo when using --apply.\n' >&2
  exit 1
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
  abora.gaming.enable = $([[ "$gaming_enable" == 1 ]] && printf 'true' || printf 'false');
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
