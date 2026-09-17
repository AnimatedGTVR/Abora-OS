#!/usr/bin/env python3
"""Evaluate a real minimal NixOS system for every supported desktop profile.

For each profile in scripts/abora-desktop-profiles.sh, generate a throwaway
Nix file that builds a minimal NixOS configuration (through nixpkgs' own
eval-config.nix) with that desktop's config and package blocks wired into
Abora's installed base, then evaluate its toplevel derivation. This catches a
broken desktop block (typo, missing option, bad package name) that no
script-level test would exercise, without a nixos-rebuild or VM boot per
desktop. It also checks every profile is listed in the CLI and Nix option enums.

The desktop list and blocks come from the Bash desktop-profiles library, which
is what this checks; it moves to Nix modules separately.

Environment:
  ABORA_NIXPKGS_PATH             nixpkgs source to evaluate against
  ABORA_NIXPKGS_RESOLVE_TIMEOUT  seconds to wait for the flake's nixpkgs (default 30)
  ABORA_NIX_STORE                pass --store to nix-instantiate
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from abora_release import repo_root

RELEASE_SHORT = "v4 Everest"

# Every profile must be representable by the CLI and the Nix option types.
PROFILE_LISTS = ("scripts/anix.sh", "scripts/abora-config.sh", "nix/modules/abora-options.nix", "nix/modules/anix.nix")

# (repo source, path under the staged /etc/abora) — the tree the installer and
# updater copy onto a real system, which installed-base.nix expects beside it.
STAGED_FILES = (
    ("VERSION", "VERSION"),
    ("assets/abora-title.txt", "title.txt"),
    ("assets/fastfetch-logo.txt", "fastfetch-logo.txt"),
    ("assets/fastfetch-config.jsonc", "fastfetch-config.jsonc"),
    ("assets/Abora-LOGO.png", "Abora-LOGO.png"),
    ("assets/wallpapers/collection/titlis-alps.jpg", "default-wallpaper.png"),
    ("assets/mango/config.conf", "mango/config.conf"),
    ("assets/plymouth/abora.plymouth", "plymouth/abora.plymouth"),
    ("assets/plymouth/abora.script", "plymouth/abora.script"),
    ("assets/Effects/v3StartingAbora.mp3", "effects/v3StartingAbora.mp3"),
    ("nix/modules/installed-base.nix", "installed-base.nix"),
    ("nix/modules/abora-options.nix", "abora-options.nix"),
    ("nix/modules/anix.nix", "anix-module.nix"),
    ("nix/pkgs/mango.nix", "pkgs/mango.nix"),
    ("nix/pkgs/scenefx-0_5.nix", "pkgs/scenefx-0_5.nix"),
    ("nix/pkgs/modularity.nix", "pkgs/modularity.nix"),
    ("nix/pkgs/moducpp-anix.nix", "pkgs/moducpp-anix.nix"),
    ("nix/pkgs/vanta.nix", "pkgs/vanta.nix"),
    ("nix/pkgs/abora-update.nix", "pkgs/abora-update.nix"),
    ("tools/moducpp-anix", "tools/moducpp-anix"),
    ("scripts/abora-ui.sh", "ui.sh"),
    ("scripts/abora-config.sh", "config.sh"),
    ("scripts/abora.sh", "abora.sh"),
    ("scripts/abora-build.sh", "build.sh"),
    ("scripts/abora-adopt-nixos.sh", "adopt-nixos.sh"),
    ("scripts/abora-desktop.sh", "desktop.sh"),
    ("scripts/abora-gaming.sh", "gaming.sh"),
    ("scripts/abora-dotfiles-import.sh", "dotfiles-import.sh"),
    ("scripts/abora-doctor.sh", "doctor.sh"),
    ("scripts/abora-check-full.sh", "check-full.sh"),
    ("scripts/abora-recovery.sh", "recovery.sh"),
    ("scripts/abora-repair-flake-purity.sh", "repair-flake-purity.sh"),
    ("scripts/abora-welcome.sh", "welcome.sh"),
    ("scripts/anix.sh", "anix.sh"),
    ("scripts/abora-app-catalog.sh", "app-catalog.sh"),
    ("scripts/abora-apps.sh", "apps.sh"),
    ("scripts/abora-custom-packages.sh", "custom-packages.sh"),
    ("scripts/abora-support-report.sh", "support-report.sh"),
    ("scripts/abora-hardware-test.sh", "hardware-test.sh"),
    ("scripts/abora-desktop-profiles.sh", "desktop-profiles.sh"),
    ("scripts/abora-installer.sh", "installer.sh"),
    ("scripts/abora-setup-launcher.sh", "setup-launcher.sh"),
    ("scripts/abora-setup.desktop", "setup.desktop"),
    ("scripts/abora-session-setup.sh", "session-setup.sh"),
    ("scripts/abora-theme-sync.sh", "theme-sync.sh"),
    ("scripts/abora-update.sh", "update.sh"),
)
# (repo directory, staged directory): contents copied, the directory itself kept.
STAGED_FLAT_DIRS = (
    ("assets/bootloader", "bootloader"),
    ("assets/wallpapers/collection", "wallpapers"),
    ("assets/wallpaper-themes", "themes"),
)
# (repo directory, staged directory): whole trees, symlinks kept.
STAGED_TREES = (
    ("nix/modules/desktops", "desktops"),
    ("vendor/modularity", "vendor/modularity"),
    ("vendor/tinypm", "tinypm"),
    ("tools/abora-update", "abora-update"),
)

# Prints, NUL-separated, for each profile: name, label, variant id, config block, package block.
# Command substitutions drop trailing newlines exactly as the Bash check did.
LIBRARY_QUERY = r"""
set -euo pipefail
source "$1"
while IFS= read -r desktop_profile; do
  desktop_label=""
  desktop_variant_id=""
  abora_sync_desktop_label "$desktop_profile"
  desktop_block="$(abora_desktop_config_block "$desktop_profile" "us" "abora" "$(abora_default_wallpaper_uri)")"
  desktop_packages="$(abora_desktop_package_block "$desktop_profile")"
  printf '%s\0' "$desktop_profile" "$desktop_label" "$desktop_variant_id" "$desktop_block" "$desktop_packages"
done < <(abora_supported_desktop_profiles)
"""

TEMPLATE = """\
let
  pkgsPath = {pkgs_path};
  evalConfig = import (pkgsPath + "/nixos/lib/eval-config.nix");
  installedBase = import {staged}/installed-base.nix;
  aboraOptions = import {staged}/abora-options.nix;
  desktopModule = {{ pkgs, lib, ... }}: {{
    system.nixos.variantName = "Abora {release_short} {label} Edition";
    system.nixos.variant_id = "{variant_id}";

    networking.hostName = "abora-{profile}";
    time.timeZone = "UTC";
    console.keyMap = "us";

    fileSystems."/" = {{
      device = "/dev/disk/by-label/ABORA_ROOT";
      fsType = "ext4";
    }};
    fileSystems."/boot" = {{
      device = "/dev/disk/by-label/ABORA_EFI";
      fsType = "vfat";
    }};

    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.limine = {{
      enable = true;
      biosSupport = true;
      biosDevice = "/dev/vda";
      efiSupport = true;
      efiInstallAsRemovable = true;
      style.wallpapers = [ {bootloader_background} ];
    }};

{config_block}
    users.users.abora = {{
      isNormalUser = true;
      description = "Abora User";
      createHome = true;
      extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
      hashedPassword = "!";
    }};

    security.sudo.wheelNeedsPassword = true;

    environment.systemPackages = with pkgs; [
{packages}
    ];

    system.stateVersion = "26.05";
  }};
  config = (evalConfig {{
    system = "x86_64-linux";
    modules = [ installedBase aboraOptions desktopModule ];
  }}).config;
in
  {{
    inherit (config.system.nixos) variantName variant_id;
    defaultSession = config.services.displayManager.defaultSession or null;
    toplevel = config.system.build.toplevel.drvPath;
  }}
"""


@dataclass(frozen=True)
class Profile:
    name: str
    label: str
    variant_id: str
    config_block: str
    packages: str


class DesktopCheck:
    def __init__(self, repo: Path, workdir: Path):
        self.repo = repo
        self.workdir = workdir
        self.staged = workdir / "abora"
        self.failed = False
        self.nix = ["nix-instantiate"]
        if os.environ.get("ABORA_NIX_STORE"):
            self.nix += ["--store", os.environ["ABORA_NIX_STORE"]]

    def ok(self, message: str) -> None:
        print(f"[ok]   {message}", flush=True)

    def fail(self, message: str) -> None:
        print(f"[fail] {message}", flush=True)
        self.failed = True

    # ── nixpkgs ──
    def resolve_nixpkgs(self) -> str | None:
        explicit = os.environ.get("ABORA_NIXPKGS_PATH")
        if explicit and Path(explicit).is_dir():
            return explicit

        found = subprocess.run([*self.nix, "--find-file", "nixpkgs"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()

        if shutil.which("nix"):
            timeout = float(os.environ.get("ABORA_NIXPKGS_RESOLVE_TIMEOUT") or 30)
            try:
                evaluated = subprocess.run(
                    [
                        "nix", "--extra-experimental-features", "nix-command flakes",
                        "eval", "--raw", "--impure",
                        "--expr", f'(builtins.getFlake "path:{self.repo}").inputs.nixpkgs.outPath',
                    ],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=timeout,
                )
                if evaluated.returncode == 0 and evaluated.stdout:
                    return evaluated.stdout
            except subprocess.TimeoutExpired:
                pass

        # Last-resort daemonless fallback for dev shells where a nixpkgs source is
        # already in /nix/store but nix-daemon/NIX_PATH are unavailable.
        for candidate in sorted(Path("/nix/store").glob("*-source")):
            if (candidate / "nixos/lib/eval-config.nix").is_file() and (candidate / "lib/modules.nix").is_file():
                return str(candidate)
        return None

    def nixpkgs_imports(self, pkgs_path: str) -> bool:
        expr = f'let pkgs = import {pkgs_path} {{ system = "x86_64-linux"; }}; in pkgs.lib.version'
        return subprocess.run([*self.nix, "--eval", "--strict", "--expr", expr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

    # ── staging ──
    def stage_installed_abora(self) -> None:
        for directory in ("bootloader", "desktops", "effects", "mango", "pkgs", "plymouth", "themes", "tools", "vendor", "wallpapers"):
            (self.staged / directory).mkdir(parents=True, exist_ok=True)
        for source, target in STAGED_FILES:
            shutil.copy(self.repo / source, self.staged / target)  # keeps the mode, like cp
        for source, target in STAGED_FLAT_DIRS:
            for path in sorted((self.repo / source).iterdir()):
                if not path.name.startswith("."):
                    shutil.copy(path, self.staged / target / path.name)
        for source, target in STAGED_TREES:
            shutil.copytree(self.repo / source, self.staged / target, symlinks=True, dirs_exist_ok=True)

    # ── profiles ──
    def profiles(self) -> list[Profile]:
        library = self.repo / "scripts/abora-desktop-profiles.sh"
        result = subprocess.run(["bash", "-c", LIBRARY_QUERY, "desktop-profiles", str(library)], cwd=self.repo, stdout=subprocess.PIPE, check=True)
        fields = result.stdout.decode().split("\0")[:-1]
        return [Profile(*fields[i:i + 5]) for i in range(0, len(fields), 5)]

    def check_listed_everywhere(self, profile: str) -> None:
        pattern = re.compile(rf'(^|[^A-Za-z0-9_-])"?{re.escape(profile)}"?(\s|$)', re.MULTILINE)
        for relative in PROFILE_LISTS:
            if not pattern.search((self.repo / relative).read_text(encoding="utf-8", errors="replace")):
                self.fail(f"desktop list missing {profile}: {relative}")

    def render(self, profile: Profile, pkgs_path: str) -> str:
        return TEMPLATE.format(
            pkgs_path=pkgs_path,
            staged=self.staged,
            release_short=RELEASE_SHORT,
            label=profile.label,
            variant_id=profile.variant_id,
            profile=profile.name,
            bootloader_background=self.repo / "assets/bootloader/limine-background.png",
            config_block=profile.config_block,
            packages=profile.packages,
        )

    def run(self) -> int:
        pkgs_path = self.resolve_nixpkgs()
        if pkgs_path is None:
            print("No nixpkgs source is available.", file=sys.stderr)
            print("Set ABORA_NIXPKGS_PATH to a nixpkgs checkout/store path, or configure NIX_PATH.", file=sys.stderr)
            print("Example: ABORA_NIXPKGS_PATH=/nix/store/...-source ./scripts/check-desktops.py", file=sys.stderr)
            return 1
        if not self.nixpkgs_imports(pkgs_path):
            print("nixpkgs source was found, but Nix cannot import it in this environment.", file=sys.stderr)
            print("This usually means the Nix daemon/store is unavailable or not writable by this user.", file=sys.stderr)
            print("Fix the daemon/store, or run with a working remote/local store, then retry:", file=sys.stderr)
            print(f"  ABORA_NIXPKGS_PATH={pkgs_path} ./scripts/check-desktops.py", file=sys.stderr)
            return 1

        self.stage_installed_abora()
        profiles = self.profiles()
        for profile in profiles:
            self.check_listed_everywhere(profile.name)
            (self.workdir / f"{profile.name}.nix").write_text(self.render(profile, pkgs_path), encoding="utf-8")

        for profile in profiles:
            print(f"[..]  instantiating: {profile.name}", flush=True)
            nix_file = str(self.workdir / f"{profile.name}.nix")
            if subprocess.run([*self.nix, "--eval", "--strict", nix_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                self.ok(f"desktop toplevel: {profile.name}")
            else:
                self.fail(f"desktop toplevel: {profile.name}")
                subprocess.run([*self.nix, "--eval", "--strict", nix_file])

        if self.failed:
            print("\nOne or more desktop checks failed.", file=sys.stderr)
            return 1
        print("\nAll desktop checks passed.")
        return 0


def main() -> int:
    repo = repo_root(__file__)
    keep = os.environ.get("ABORA_CHECK_DESKTOPS_KEEP_DIR")
    if keep:  # for inspecting the generated files
        workdir = Path(keep)
        workdir.mkdir(parents=True, exist_ok=True)
        return DesktopCheck(repo, workdir).run()
    with tempfile.TemporaryDirectory() as tmp:
        return DesktopCheck(repo, Path(tmp)).run()


if __name__ == "__main__":
    sys.exit(main())
