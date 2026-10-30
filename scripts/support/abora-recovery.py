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

# ── UI ────────────────────────────────────────────────────────────────────────
# Python port of the abora-ui.sh primitives. Inlined, not imported: `abora
# update` on a 4.0 system copies each support tool into /etc/nixos/abora on
# its own (sync_abora_files in abora-update.sh), so a shared module would never
# reach it. Every scripts/support/*.py tool carries this same block, and
# tests/support.test.py keeps the copies identical.

BLUE = "\033[38;5;33m"
ACCENT = "\033[38;5;87m"
CYAN = "\033[38;5;44m"
YELLOW = "\033[38;5;222m"
WHITE = "\033[1;97m"
DIM = "\033[38;5;242m"
FAINT = "\033[38;5;237m"
GREEN = "\033[38;5;77m"
RED = "\033[38;5;203m"
NC = "\033[0m"


def ui_setup() -> None:
    # Line buffering keeps our output ordered with the child processes we run.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)


def ui_version() -> str:
    if os.environ.get("ABORA_VERSION"):
        return os.environ["ABORA_VERSION"]
    try:
        return "".join(Path("/etc/abora/VERSION").read_text(encoding="utf-8").split())
    except OSError:
        return "v4 Everest"


def ui_cols() -> int:
    return shutil.get_terminal_size((80, 24)).columns


def rule() -> None:
    print(f"  {FAINT}{'─' * (ui_cols() - 4)}{NC}")


def brand_header() -> None:
    inner = max(ui_cols() - 6, 18)
    left, right = "  ▸ ABORA OS", f"{ui_version()}  "
    max_left = max(inner - len(right) - 1, 6)
    if len(left) > max_left:
        left = left[: max_left - 3] + "..."
    pad = max(inner - len(left) - len(right), 1)
    print(f"{BLUE}╭{'─' * inner}╮{NC}")
    print(f"{BLUE}│{NC}{WHITE}{left}{NC}{' ' * pad}{DIM}{right}{NC}{BLUE}│{NC}")
    print(f"{BLUE}╰{'─' * inner}╯{NC}")


def banner(title: str = "", subtitle: str = "") -> None:
    print()
    brand_header()
    if title:
        print(f"\n  {WHITE}{title}{NC}")
    if subtitle:
        print(f"  {DIM}{subtitle}{NC}")
    print()
    rule()
    print()


def info(message: str) -> None:
    print(f"  {BLUE}·{NC}  {message}")


def success(message: str) -> None:
    print(f"  {GREEN}✓{NC}  {GREEN}{message}{NC}")


def warning(message: str) -> None:
    print(f"  {YELLOW}!{NC}  {YELLOW}{message}{NC}")


def error(message: str) -> None:
    print(f"  {RED}✗{NC}  {RED}{message}{NC}", file=sys.stderr)


def step(message: str) -> None:
    print(f"  {CYAN}▸{NC}  {message}")


def dim_line(message: str) -> None:
    print(f"  {DIM}{message}{NC}")


def kv(key: str, value: str, width: int = 18) -> None:
    print(f"  {BLUE}│{NC}  {DIM}{key:<{width}}{NC}  {CYAN}{value}{NC}")


def _card_inner() -> int:
    return min(max(ui_cols() - 6, 20), 70)


def card_start(title: str = "") -> None:
    inner = _card_inner()
    if title:
        body = f"{ACCENT} {title} " + "─" * max(inner - len(title) - 3, 0)
    else:
        body = "─" * inner
    print(f"  {BLUE}╭─{body}╮{NC}")


def card_end() -> None:
    print(f"  {BLUE}╰{'─' * (_card_inner() + 1)}╯{NC}")

# ── end UI ────────────────────────────────────────────────────────────────────


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
