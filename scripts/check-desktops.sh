#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

# shellcheck source=/dev/null
source "$repo_dir/scripts/abora-desktop-profiles.sh"

version="$(tr -d '\n' < "$repo_dir/VERSION")"
bootloader_background="$repo_dir/assets/bootloader/limine-background.png"
tmpdir="$(mktemp -d)"
staged_abora="$tmpdir/abora"
failed=0
pkgs_path=""
nix_cmd=(nix-instantiate)

if [[ -n "${ABORA_NIX_STORE:-}" ]]; then
  nix_cmd+=(--store "$ABORA_NIX_STORE")
fi

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

  if "${nix_cmd[@]}" --find-file nixpkgs 2>/dev/null; then
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

stage_installed_abora() {
  mkdir -p \
    "$staged_abora/bootloader" \
    "$staged_abora/desktops" \
    "$staged_abora/effects" \
    "$staged_abora/mango" \
    "$staged_abora/pkgs" \
    "$staged_abora/plymouth" \
    "$staged_abora/themes" \
    "$staged_abora/wallpapers"

  cp "$repo_dir/VERSION" "$staged_abora/VERSION"
  cp "$repo_dir/assets/abora-title.txt" "$staged_abora/title.txt"
  cp "$repo_dir/assets/fastfetch-logo.txt" "$staged_abora/fastfetch-logo.txt"
  cp "$repo_dir/assets/fastfetch-config.jsonc" "$staged_abora/fastfetch-config.jsonc"
  cp "$repo_dir/assets/Abora-LOGO.png" "$staged_abora/Abora-LOGO.png"
  cp "$repo_dir/assets/wallpapers/collection/Daytime-MNT.jpg" "$staged_abora/default-wallpaper.png"
  cp "$repo_dir/assets/mango/config.conf" "$staged_abora/mango/config.conf"
  cp "$repo_dir/assets/plymouth/abora.plymouth" "$staged_abora/plymouth/abora.plymouth"
  cp "$repo_dir/assets/plymouth/abora.script" "$staged_abora/plymouth/abora.script"
  cp "$repo_dir/assets/Effects/v3StartingAbora.mp3" "$staged_abora/effects/v3StartingAbora.mp3"
  cp "$repo_dir"/assets/bootloader/* "$staged_abora/bootloader/"
  cp "$repo_dir"/assets/wallpapers/collection/* "$staged_abora/wallpapers/"
  cp "$repo_dir"/assets/wallpaper-themes/* "$staged_abora/themes/"

  cp "$repo_dir/nix/modules/installed-base.nix" "$staged_abora/installed-base.nix"
  cp "$repo_dir/nix/modules/abora-options.nix" "$staged_abora/abora-options.nix"
  cp "$repo_dir/nix/modules/anix.nix" "$staged_abora/anix-module.nix"
  cp -R "$repo_dir/nix/modules/desktops/." "$staged_abora/desktops/"
  cp "$repo_dir/nix/pkgs/mango.nix" "$staged_abora/pkgs/mango.nix"
  cp "$repo_dir/nix/pkgs/modularity.nix" "$staged_abora/pkgs/modularity.nix"

  cp "$repo_dir/scripts/abora-ui.sh" "$staged_abora/ui.sh"
  cp "$repo_dir/scripts/abora-config.sh" "$staged_abora/config.sh"
  cp "$repo_dir/scripts/abora.sh" "$staged_abora/abora.sh"
  cp "$repo_dir/scripts/abora-desktop.sh" "$staged_abora/desktop.sh"
  cp "$repo_dir/scripts/abora-doctor.sh" "$staged_abora/doctor.sh"
  cp "$repo_dir/scripts/abora-check-full.sh" "$staged_abora/check-full.sh"
  cp "$repo_dir/scripts/abora-recovery.sh" "$staged_abora/recovery.sh"
  cp "$repo_dir/scripts/abora-welcome.sh" "$staged_abora/welcome.sh"
  cp "$repo_dir/scripts/anix.sh" "$staged_abora/anix.sh"
  cp "$repo_dir/scripts/abora-app-catalog.sh" "$staged_abora/app-catalog.sh"
  cp "$repo_dir/scripts/abora-apps.sh" "$staged_abora/apps.sh"
  cp "$repo_dir/scripts/abora-support-report.sh" "$staged_abora/support-report.sh"
  cp "$repo_dir/scripts/abora-hardware-test.sh" "$staged_abora/hardware-test.sh"
  cp "$repo_dir/scripts/abora-desktop-profiles.sh" "$staged_abora/desktop-profiles.sh"
  cp "$repo_dir/scripts/abora-installer.sh" "$staged_abora/installer.sh"
  cp "$repo_dir/scripts/abora-setup-launcher.sh" "$staged_abora/setup-launcher.sh"
  cp "$repo_dir/scripts/abora-setup.desktop" "$staged_abora/setup.desktop"
  cp "$repo_dir/scripts/abora-session-setup.sh" "$staged_abora/session-setup.sh"
  cp "$repo_dir/scripts/abora-theme-sync.sh" "$staged_abora/theme-sync.sh"
  cp "$repo_dir/scripts/abora-update.sh" "$staged_abora/update.sh"
  cp -R "$repo_dir/vendor/tinypm" "$staged_abora/tinypm"
}

stage_installed_abora

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
  installedBase = import ${staged_abora}/installed-base.nix;
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
  if "${nix_cmd[@]}" --eval --strict "$tmpdir/${desktop_profile}.nix" >/dev/null 2>&1; then
    pass "desktop toplevel: ${desktop_profile}"
  else
    fail "desktop toplevel: ${desktop_profile}"
    "${nix_cmd[@]}" --eval --strict "$tmpdir/${desktop_profile}.nix" || true
  fi
done < <(abora_supported_desktop_profiles)

if [[ "$failed" -ne 0 ]]; then
  printf '\nOne or more desktop checks failed.\n' >&2
  exit 1
fi

printf '\nAll desktop checks passed.\n'
