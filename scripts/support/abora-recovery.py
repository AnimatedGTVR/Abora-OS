#!/usr/bin/env python3
"""abora recovery: rollback, repair, and diagnostics.

`abora recovery <action>` runs one action and exits with its status; plain
`abora recovery` opens the interactive menu.
"""

from __future__ import annotations

import contextlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Abora's shared core (abora_core.py): beside this tool in a checkout, on the live ISO and in the
# hardware-test package; in /etc/abora on an installed system, where each tool is its own Nix store file.
sys.path[:0] = [str(Path(__file__).resolve().parent), "/etc/abora"]
from abora_core import CYAN, DIM, NC, banner, dim_line, error, step, ui_setup, warning


def run(argv: list[str]) -> int:
    try:
        return subprocess.run(argv).returncode
    except OSError:
        print(f"{argv[0]}: command not found", file=sys.stderr)
        return 127


def run_cmd(*argv: str) -> int:
    print()
    step(" ".join(argv))
    return run(list(argv))


def run_diag(*argv: str) -> int:
    """Like run_cmd, but a failure is reported and diagnostics carry on."""
    status = run_cmd(*argv)
    if status != 0:
        warning(f"Command exited with status {status}; continuing diagnostics.")
    return 0


def menu() -> None:
    banner("Recovery", "Rollback, repair, and collect diagnostics.")
    print(f"  {CYAN}1{NC}  Roll back previous generation")
    print(f"  {CYAN}2{NC}  Run support report")
    print(f"  {CYAN}3{NC}  Repair Flathub remote")
    print(f"  {CYAN}4{NC}  Rebuild current config")
    print(f"  {CYAN}5{NC}  Run ANIX doctor")
    print(f"  {CYAN}6{NC}  Run Abora doctor")
    print(f"  {CYAN}7{NC}  Network diagnostics")
    print(f"  {DIM}q{NC}  Quit\n")


def usage() -> None:
    banner("Recovery", "Rollback, repair, and collect diagnostics.")
    for command, description in (
        (f"{CYAN}abora recovery{NC}", "Open the interactive recovery menu."),
        (f"{CYAN}abora recovery rollback{NC}", "Roll back to the previous NixOS generation with ANIX."),
        (f"{CYAN}abora recovery report{NC}", "Create a redacted support archive."),
        (f"{CYAN}abora recovery flathub{NC}", "Re-add the Flathub system remote."),
        (f"{CYAN}abora recovery rebuild{NC}", "Rebuild the current /etc/nixos#abora config."),
        (f"{CYAN}abora recovery anix{NC}  /  {CYAN}abora recovery doctor{NC}", "Run ANIX or Abora health checks."),
        (f"{CYAN}abora recovery network{NC}", "Show NetworkManager, Wi-Fi, DNS, and cache connectivity status."),
    ):
        print(f"  {command}")
        dim_line(f"  {description}")
        print()


def rollback() -> int:
    return run_cmd("anix", "rollback", "nix", "--now")


def support_report() -> int:
    return run_cmd("abora", "support-report")


def repair_flathub() -> int:
    if not shutil.which("flatpak"):
        error("flatpak is not installed.")
        return 1
    return run_cmd("flatpak", "remote-add", "--system", "--if-not-exists", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo")


def rebuild_current() -> int:
    return run_cmd("sudo", "nixos-rebuild", "switch", "--flake", "/etc/nixos#abora")


def anix_doctor() -> int:
    return run_cmd("anix", "doctor")


def abora_doctor() -> int:
    return run_cmd("abora", "doctor")


def network_diagnostics() -> int:
    banner("Network Diagnostics", "Connectivity, Wi-Fi, DNS, and Abora cache checks.")

    if shutil.which("systemctl"):
        run_diag("systemctl", "--no-pager", "--full", "status", "NetworkManager")
    else:
        warning("systemctl is not available.")

    if shutil.which("nmcli"):
        run_diag("nmcli", "networking", "connectivity", "check")
        run_diag("nmcli", "device", "status")
        run_diag("nmcli", "radio")
        run_diag("nmcli", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list")
    else:
        warning("nmcli is not available.")

    if shutil.which("resolvectl"):
        run_diag("resolvectl", "status")
    else:
        warning("resolvectl is not available.")

    if shutil.which("ping"):
        run_diag("ping", "-c", "2", "-W", "3", "1.1.1.1")

    if shutil.which("curl"):
        run_diag("curl", "-fsI", "--connect-timeout", "5", "--max-time", "8", "https://cache.nixos.org")
    else:
        warning("curl is not available.")
    return 0


ACTIONS = {
    "rollback": rollback,
    "report": support_report,
    "flathub": repair_flathub,
    "rebuild": rebuild_current,
    "anix": anix_doctor,
    "doctor": abora_doctor,
    "network": network_diagnostics,
}

MENU_CHOICES = {
    "1": rollback,
    "2": support_report,
    "3": repair_flathub,
    "4": rebuild_current,
    "5": anix_doctor,
    "6": abora_doctor,
    "7": network_diagnostics,
}


def interactive_menu() -> int:
    while True:
        menu()
        try:
            choice = input("  Choose: ")
        except EOFError:
            return 1
        # A failing action's status is deliberately ignored: this menu is
        # reached specifically when something on the system is already broken,
        # and a failing rollback/doctor/rebuild/report/repair (exactly the
        # commands most likely to fail there) must return to the menu so the
        # user can try a different recovery option, not end the session. The
        # failure is still visible (run_cmd/run_diag print it). The direct
        # `abora recovery <action>` form keeps propagating real exit codes,
        # since scripted callers need that.
        if choice in ("q", "Q"):
            return 0
        if choice in MENU_CHOICES:
            MENU_CHOICES[choice]()
        else:
            warning(f"Unknown choice: {choice}")
        print()
        try:
            input("  Press Enter to continue...")
        except EOFError:
            return 1


def main(args: list[str]) -> int:
    command = args[0] if args else "menu"
    if command in ACTIONS:
        return ACTIONS[command]()
    if command in ("menu", ""):
        return interactive_menu()
    if command in ("help", "--help", "-h"):
        usage()
        return 0
    error(f"Unknown recovery command: {command}")
    with contextlib.redirect_stdout(sys.stderr):
        usage()
    return 1


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    ui_setup()
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
