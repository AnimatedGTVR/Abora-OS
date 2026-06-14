#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

# shellcheck source=/dev/null
source "$repo_dir/scripts/abora-desktop-profiles.sh"

version="$(tr -d '\n' < "$repo_dir/VERSION")"
bootloader_background="$repo_dir/assets/bootloader/limine-background.png"
tmpdir="$(mktemp -d)"
failed=0
pkgs_path=""

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

pass() {
  printf '[ok]   %s\n' "$1"
}

fail() {
  printf '[fail] %s\n' "$1"
  failed=1
}

resolve_nixpkgs_path() {
  if [[ -n "${ABORA_NIXPKGS_PATH:-}" && -d "${ABORA_NIXPKGS_PATH:-}" ]]; then
    printf '%s\n' "$ABORA_NIXPKGS_PATH"
    return 0
  fi

  if nix-instantiate --find-file nixpkgs 2>/dev/null; then
    return 0
  fi

  if command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features "nix-command flakes" \
      eval --raw --impure \
      --expr "(builtins.getFlake \"path:${repo_dir}\").inputs.nixpkgs.outPath" 2>/dev/null
  fi
}

assert_supported_everywhere() {
  local profile="$1"
  local file
  for file in \
    "$repo_dir/scripts/anix.sh" \
    "$repo_dir/scripts/abora-config.sh" \
    "$repo_dir/nix/modules/abora-options.nix" \
    "$repo_dir/nix/modules/anix.nix"; do
    if ! grep -Eq "\"?${profile}\"?([[:space:]]|$)" "$file"; then
      fail "desktop list missing ${profile}: ${file#$repo_dir/}"
    fi
  done
}

if ! pkgs_path="$(resolve_nixpkgs_path)"; then
  printf 'No nixpkgs source is available. Set ABORA_NIXPKGS_PATH or NIX_PATH.\n' >&2
  exit 1
fi

while IFS= read -r desktop_profile; do
  desktop_label=""
  desktop_variant_id=""
  abora_sync_desktop_label "$desktop_profile"
  desktop_block="$(abora_desktop_config_block "$desktop_profile" "us" "abora" "$(abora_default_wallpaper_uri)")"
  desktop_packages="$(abora_desktop_package_block "$desktop_profile")"

  assert_supported_everywhere "$desktop_profile"

  cat > "$tmpdir/${desktop_profile}.nix" <<EOF
let
  pkgsPath = ${pkgs_path};
  evalConfig = import (pkgsPath + "/nixos/lib/eval-config.nix");
  installedBase = import ${repo_dir}/nix/modules/installed-base.nix;
  desktopModule = { pkgs, lib, ... }: {
    system.nixos.variantName = "Abora ${version} ${desktop_label} Edition";
    system.nixos.variant_id = "${desktop_variant_id}";

    networking.hostName = "abora-${desktop_profile}";
    time.timeZone = "UTC";
    console.keyMap = "us";

    fileSystems."/" = {
      device = "/dev/disk/by-label/ABORA_ROOT";
      fsType = "ext4";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/ABORA_EFI";
      fsType = "vfat";
    };

    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.limine = {
      enable = true;
      biosSupport = true;
      biosDevice = "/dev/vda";
      efiSupport = true;
      efiInstallAsRemovable = true;
      style.wallpapers = [ ${bootloader_background} ];
    };

${desktop_block}
    users.users.abora = {
      isNormalUser = true;
      description = "Abora User";
      createHome = true;
      extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
      hashedPassword = "!";
    };

    security.sudo.wheelNeedsPassword = true;

    environment.systemPackages = with pkgs; [
${desktop_packages}
    ];

    system.stateVersion = "26.05";
  };
  config = (evalConfig {
    system = "x86_64-linux";
    modules = [ installedBase desktopModule ];
  }).config;
in
  {
    inherit (config.system.nixos) variantName variant_id;
    defaultSession = config.services.displayManager.defaultSession or null;
    toplevel = config.system.build.toplevel.drvPath;
  }
EOF
done < <(abora_supported_desktop_profiles)

while IFS= read -r desktop_profile; do
  printf '[..]  instantiating: %s\n' "$desktop_profile"
  if nix-instantiate --eval --strict "$tmpdir/${desktop_profile}.nix" >/dev/null 2>&1; then
    pass "desktop toplevel: ${desktop_profile}"
  else
    fail "desktop toplevel: ${desktop_profile}"
    nix-instantiate --eval --strict "$tmpdir/${desktop_profile}.nix" || true
  fi
done < <(abora_supported_desktop_profiles)

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more desktop checks failed.\n' >&2
  exit 1
fi

printf '\nAll desktop checks passed.\n'
