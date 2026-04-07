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

if ! nix-instantiate --find-file nixpkgs >/dev/null 2>&1; then
  printf 'The nixpkgs NIX_PATH entry is not available for desktop checks.\n' >&2
  exit 1
fi

while IFS= read -r desktop_profile; do
  desktop_label=""
  desktop_variant_id=""
  abora_sync_desktop_label "$desktop_profile"
  desktop_block="$(abora_desktop_config_block "$desktop_profile" "us" "abora" "$(abora_default_wallpaper_uri)")"
  desktop_packages="$(abora_desktop_package_block "$desktop_profile")"

  cat > "$tmpdir/${desktop_profile}.nix" <<EOF
let
  pkgsPath = <nixpkgs>;
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
  config.system.nixos.variantName
EOF
done < <(abora_supported_desktop_profiles)

while IFS= read -r desktop_profile; do
  printf '[..]  evaluating: %s\n' "$desktop_profile"
  if nix-instantiate --eval --strict "$tmpdir/${desktop_profile}.nix" >/dev/null 2>&1; then
    pass "desktop eval: ${desktop_profile}"
  else
    fail "desktop eval: ${desktop_profile}"
    nix-instantiate --eval --strict "$tmpdir/${desktop_profile}.nix" || true
  fi
done < <(abora_supported_desktop_profiles)

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more desktop checks failed.\n' >&2
  exit 1
fi

printf '\nAll desktop checks passed.\n'
