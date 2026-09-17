#!/usr/bin/env python3
"""A friendly pre-flight check for anyone about to work on Abora OS itself.

First-time contributors most of all. abora-doctor.sh diagnoses an *installed
Abora system*; this diagnoses *your dev machine*, before you've built
anything, so a missing tool or disabled Nix feature shows up as one clear,
actionable line instead of a cryptic failure five minutes into `make iso`.

Environment:
  ABORA_NIXPKGS_PATH               nixpkgs source to use for the import check
  ABORA_NIXPKGS_RESOLVE_TIMEOUT    seconds to wait for the flake's nixpkgs (default 30)
  ABORA_UI_LIB                     point at a missing file for plain [ok]/[warn]/[fail] output
"""

from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

from abora_release import repo_root
from abora_ui import UI

MIN_FREE_GIB = 20


def first_line(argv: list[str]) -> str:
    result = subprocess.run(argv, capture_output=True, text=True)
    return (result.stdout.splitlines() or [""])[0]


def quiet(argv: list[str], timeout: float | None = None) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


class Doctor:
    def __init__(self, repo: Path):
        self.repo = repo
        self.ui = UI(repo / "scripts/core/abora-ui.sh")
        self.warnings = 0
        self.failures = 0

    def ok(self, message: str) -> None:
        self.ui.success(message)

    def warn(self, message: str) -> None:
        self.warnings += 1
        self.ui.warn(message)

    def fail(self, message: str) -> None:
        self.failures += 1
        self.ui.error(message)

    def resolve_nixpkgs_source(self) -> str | None:
        explicit = os.environ.get("ABORA_NIXPKGS_PATH")
        if explicit and Path(explicit).is_dir():
            return explicit

        if shutil.which("nix-instantiate"):
            result = quiet(["nix-instantiate", "--find-file", "nixpkgs"])
            candidate = result.stdout.strip() if result and result.returncode == 0 else ""
            if candidate and Path(candidate).is_dir():
                return candidate

        if shutil.which("nix"):
            timeout = float(os.environ.get("ABORA_NIXPKGS_RESOLVE_TIMEOUT") or 30)
            result = quiet(
                [
                    "nix", "--extra-experimental-features", "nix-command flakes",
                    "eval", "--raw", "--impure",
                    "--expr", f'(builtins.getFlake "path:{self.repo}").inputs.nixpkgs.outPath',
                ],
                timeout=timeout,
            )
            candidate = result.stdout if result else ""
            if candidate and Path(candidate).is_dir():
                return candidate

        for candidate in sorted(Path("/nix/store").glob("*-source")):
            if (candidate / "nixos/lib/eval-config.nix").is_file() and (candidate / "lib/modules.nix").is_file():
                return str(candidate)
        return None

    def check_nix(self) -> None:
        if not shutil.which("nix"):
            self.fail("nix not found — install it from https://nixos.org/download (Determinate Nix or the official installer both work)")
            return
        self.ok(f"nix found ({first_line(['nix', '--version'])})")

        # Flakes + nix-command are opt-in experimental features on most Nix
        # installs; this repo needs both for every `make iso`/`make qemu`
        # target, and the error you get without them ("experimental Nix
        # feature ... is disabled") doesn't say what to do about it.
        flakes = re.compile(r"experimental-features.*(flakes|nix-command)")
        confs = (Path("/etc/nix/nix.conf"), Path.home() / ".config/nix/nix.conf")
        if any(conf.is_file() and flakes.search(_read(conf)) for conf in confs):
            self.ok("flakes + nix-command look enabled in your nix.conf")
        else:
            self.warn("flakes/nix-command not found in nix.conf — add this line to /etc/nix/nix.conf (or ~/.config/nix/nix.conf):")
            self.ui.info("    experimental-features = nix-command flakes")
            self.ui.info("  or pass --extra-experimental-features 'nix-command flakes' to every nix/make command")

        store = quiet(["nix", "--extra-experimental-features", "nix-command flakes", "store", "info"])
        if store and store.returncode == 0:
            self.ok("nix daemon is reachable")
        else:
            self.fail("nix daemon is not reachable — 'make iso'/'make qemu' will not work until it is.")
            self.ui.info("  On NixOS: check 'systemctl status nix-daemon'.")
            self.ui.info("  On other distros: (re)run the official installer — https://nixos.org/download")
            self.ui.info("  In a container/sandbox without a daemon, single-user Nix (nix-user-chroot or")
            self.ui.info("  a VM with real Nix) is the usual fix — a daemon-less Nix cannot build flakes.")

        if not shutil.which("nix-instantiate"):
            self.fail("nix-instantiate not found — check-desktops/preflight need it to evaluate desktop profiles.")
            return
        source = self.resolve_nixpkgs_source()
        if source is None:
            self.fail("no nixpkgs source found — check-desktops/preflight need one.")
            self.ui.info("  Set ABORA_NIXPKGS_PATH to a nixpkgs checkout/store path, or configure NIX_PATH.")
            self.ui.info("  Example: ABORA_NIXPKGS_PATH=/nix/store/...-source ./scripts/check-desktops.py")
            return
        expr = f'let pkgs = import {source} {{ system = "x86_64-linux"; }}; in pkgs.lib.version'
        imported = quiet(["nix-instantiate", "--eval", "--strict", "--expr", expr])
        if imported and imported.returncode == 0:
            self.ok("nixpkgs import works for desktop profile checks")
        else:
            self.fail("nixpkgs source was found but cannot be imported — check-desktops/preflight will fail.")
            self.ui.info(f"  Source: {source}")
            self.ui.info("  This usually means the Nix daemon/store is unavailable or not writable by this user.")
            self.ui.info(f"  After fixing Nix, retry: ABORA_NIXPKGS_PATH={source} ./scripts/check-desktops.py")

    def run(self) -> int:
        print()
        print("Abora OS dev environment check")
        print("This looks at YOUR machine, not the repo — run it before your first build.\n", flush=True)

        # ── Required tools ──
        if shutil.which("git"):
            self.ok(f"git found ({first_line(['git', '--version'])})")
        else:
            self.fail("git not found — install it with your distro's package manager (e.g. 'sudo apt install git', 'sudo pacman -S git')")

        self.check_nix()

        if shutil.which("qemu-system-x86_64") and shutil.which("qemu-img"):
            self.ok(f"qemu found ({first_line(['qemu-system-x86_64', '--version'])})")
        else:
            self.warn("qemu-system-x86_64/qemu-img not found — you can still 'make iso', but 'make qemu' (boot-testing) needs them.")
            self.ui.info("  Debian/Ubuntu: sudo apt install qemu-system-x86 qemu-utils")
            self.ui.info("  Fedora:        sudo dnf install qemu-kvm qemu-img")
            self.ui.info("  Arch:          sudo pacman -S qemu-full")
            self.ui.info("  NixOS:         nix profile install nixpkgs#qemu")

        # ── Disk space ──
        # nixpkgs plus a handful of edition ISOs adds up fast; a build failing two
        # hours in because the disk filled up is a much worse first impression than
        # a warning up front.
        try:
            stats = os.statvfs(self.repo)
        except OSError:
            stats = None
        if stats is not None:
            free_gib = stats.f_bavail * stats.f_frsize // 1024 // 1024 // 1024
            if free_gib < MIN_FREE_GIB:
                self.warn(f"only ~{free_gib} GiB free at {self.repo} — a full ISO build (with the Nix store) wants 20+ GiB free")
            else:
                self.ok(f"~{free_gib} GiB free at {self.repo}")

        # ── System ──
        # The flake only ever targets x86_64-linux (see flake.nix's `system =`); on
        # anything else, being told that clearly beats a confusing eval error.
        kernel, arch = platform.system() or "unknown", platform.machine() or "unknown"
        if kernel == "Linux" and arch == "x86_64":
            self.ok("running on Linux/x86_64 (matches the flake's target system)")
        else:
            self.warn(f"running on {kernel}/{arch} — this flake only targets x86_64-linux; building elsewhere (incl. under emulation) is unsupported")

        print(flush=True)
        if self.failures:
            self.ui.error(f"{self.failures} thing(s) need fixing before you can build Abora OS. See above.")
            return 1
        if self.warnings:
            self.ui.warn(f"{self.warnings} thing(s) worth a look, but you can likely proceed. Try: make check")
            return 0
        self.ui.success("You're set. Try: make check, then make iso")
        return 0


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


if __name__ == "__main__":
    sys.exit(Doctor(repo_root(__file__)).run())
