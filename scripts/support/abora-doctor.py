#!/usr/bin/env python3
"""abora doctor: check installed-system health.

Exit status: 1 if any check failed, else 0 (warnings alone still exit 0).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Abora's shared core (abora_core.py): beside this tool in a checkout, on the live ISO and in the
# hardware-test package; in /etc/abora on an installed system, where each tool is its own Nix store file.
sys.path[:0] = [str(Path(__file__).resolve().parent), "/etc/abora"]
from abora_core import banner, error, success, ui_setup, warning

config_dir = Path(os.environ.get("ABORA_SYSTEM_CONFIG") or "/etc/nixos")
abora_dir = Path(os.environ.get("ABORA_DIR") or "/etc/abora")
local_config = config_dir / "abora-local.nix"
anix_log = "/tmp/abora-anix-doctor.log"

# First match wins, so more specific markers come first.
DESKTOP_MARKERS = (
    ("services.desktopManager.gnome.enable = true;", "gnome"),
    ("services.desktopManager.plasma6.enable = true;", "plasma"),
    ("programs.hyprland", "hyprland"),
    ("programs.sway.enable = true;", "sway"),
    ("desktopManager.xfce.enable = true;", "xfce"),
    ("desktopManager.cinnamon.enable = true;", "cinnamon"),
    ("desktopManager.mate.enable = true;", "mate"),
    ("desktopManager.budgie.enable = true;", "budgie"),
    ("desktopManager.lxqt.enable = true;", "lxqt"),
    ("desktopManager.pantheon.enable = true;", "pantheon"),
    ("desktopManager.cosmic.enable = true;", "cosmic"),
    ("desktopManager.enlightenment.enable = true;", "enlightenment"),
    ("windowManager.i3.enable = true;", "i3"),
    ("windowManager.awesome.enable = true;", "awesome"),
    ("windowManager.openbox.enable = true;", "openbox"),
    ("programs.niri.enable = true;", "niri"),
    ("programs.river.enable = true;", "river"),
    ("windowManager.qtile.enable = true;", "qtile"),
    ("windowManager.bspwm.enable = true;", "bspwm"),
    ("windowManager.fluxbox.enable = true;", "fluxbox"),
    ("windowManager.icewm.enable = true;", "icewm"),
    ("windowManager.herbstluftwm.enable = true;", "herbstluftwm"),
)


class Tally:
    warnings = 0
    failures = 0


def ok(message: str) -> None:
    success(message)


def warn(message: str) -> None:
    Tally.warnings += 1
    warning(message)


def fail(message: str) -> None:
    Tally.failures += 1
    error(message)


def check_file(path: Path, label: str) -> None:
    if path.exists():
        ok(label)
    else:
        fail(f"{label} missing: {path}")


def local_config_text() -> str:
    try:
        return local_config.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def read_local_string(key: str) -> str:
    """The first `key = "value";` line of abora-local.nix, or ""."""
    pattern = re.compile(r'\s*' + re.escape(key) + r'\s*=\s*"([^"]+)";')
    for line in local_config_text().splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1)
    return ""


def detect_desktop_from_local_config() -> str:
    text = local_config_text()
    return next((name for marker, name in DESKTOP_MARKERS if marker in text), "")


def check_flatpak() -> None:
    if not shutil.which("flatpak"):
        warn("flatpak command is not installed")
        return
    remotes = subprocess.run(["flatpak", "remotes", "--system"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
    if "flathub" in (line.split()[0] for line in remotes.splitlines() if line.split()):
        ok("Flathub system remote is configured")
    else:
        warn("Flathub system remote is not configured yet")


def check_channel() -> None:
    channel = os.environ.get("ABORA_DEFAULT_CHANNEL") or "unstable"
    channel_file = config_dir / "abora" / "channel"
    if channel_file.is_file():
        channel = "".join(channel_file.read_text(encoding="utf-8").split())
    if channel in ("stable", "demo", "dev", "unstable"):
        ok(f"update channel: {channel}")
    else:
        warn(f"unknown update channel: {channel}")


def supported_desktops() -> list[str]:
    profiles = abora_dir / "desktop-profiles.sh"
    if not profiles.is_file():
        return []
    listed = subprocess.run(
        ["bash", "-c", 'source "$1"; abora_supported_desktop_profiles', "bash", str(profiles)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    return listed.stdout.splitlines()


def check_desktop() -> None:
    desktop = (
        read_local_string("abora.desktop")
        or read_local_string("system.nixos.variant_id")
        or detect_desktop_from_local_config()
    )
    if not desktop:
        warn("desktop setting was not found in abora-local.nix")
        return
    if desktop in supported_desktops():
        ok(f"desktop profile is valid: {desktop}")
    else:
        warn(f"desktop profile may be invalid: {desktop}")


def check_anix() -> None:
    if not shutil.which("anix"):
        warn("ANIX command is not installed")
        return
    ok("ANIX command is installed")
    # Fixed, predictable /tmp path by design (so "see ..." below is
    # actionable) -- a plain open() there is a classic symlink race, so remove
    # the name (never follows a symlink), then create it exclusively: a
    # symlink racing back into place makes the open fail closed.
    try:
        os.unlink(anix_log)
    except OSError:
        pass
    try:
        log = os.fdopen(os.open(anix_log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666), "w")
    except OSError:
        warn(f"ANIX doctor reported issues; see {anix_log}")
        return
    with log:
        passed = subprocess.run(["anix", "doctor"], stdout=log, stderr=subprocess.STDOUT).returncode == 0
    if passed:
        ok("ANIX doctor completed")
    else:
        warn(f"ANIX doctor reported issues; see {anix_log}")


def main() -> int:
    banner("Abora Doctor", "Checking installed-system health.")

    check_file(config_dir / "flake.nix", "flake.nix exists")
    check_file(local_config, "abora-local.nix exists")
    check_file(abora_dir / "update.sh", "Abora update tool exists")
    check_file(abora_dir / "theme-sync.sh", "Abora theme sync exists")
    check_file(abora_dir / "support-report.sh", "Abora support report exists")
    check_file(abora_dir / "anix.sh", "ANIX script exists")
    check_file(abora_dir / "bootloader/theme.txt", "bootloader theme exists")
    check_file(abora_dir / "plymouth/abora.plymouth", "Plymouth theme exists")

    check_flatpak()
    check_channel()
    check_desktop()
    check_anix()

    print()
    if Tally.failures:
        error(f"Abora doctor found {Tally.failures} problem(s) and {Tally.warnings} warning(s).")
        return 1
    if Tally.warnings:
        warning(f"Abora doctor found {Tally.warnings} warning(s).")
    else:
        success("Abora doctor found no problems.")
    print()
    return 0


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    ui_setup()
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
