#!/usr/bin/env python3
"""abora check-full: collect full ANIX, TinyPM, desktop, driver, and Nix logs.

Writes one redacted log under $ABORA_CHECK_FULL_DIR (default
~/abora-check-full) and prints its path. Every section runs with a timeout
($ABORA_CHECK_FULL_TIMEOUT seconds, default 90), and a failing section is
recorded in the log rather than stopping the check.
"""

from __future__ import annotations

import os
import pwd
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

home = os.environ.get("HOME") or "/tmp"
out_dir = Path(os.environ.get("ABORA_CHECK_FULL_DIR") or f"{home}/abora-check-full")
section_timeout = int(os.environ.get("ABORA_CHECK_FULL_TIMEOUT") or 90)
state_home = os.environ.get("XDG_STATE_HOME") or f"{home}/.local/state"

# `sudo -n true` succeeds only if sudo can authenticate with zero interaction
# (cached credential, NOPASSWD) -- this is a diagnostic tool a user might run
# unattended, so it must never sit there prompting for a password; skip the
# dry-build cleanly instead.
NIX_DRY_BUILD = """\
if [ ! -d /etc/nixos ]; then
    printf 'missing /etc/nixos\\n'
    exit 0
fi
cd /etc/nixos
if [ "$(id -u)" -eq 0 ]; then
    nixos-rebuild dry-build --flake .#abora
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo nixos-rebuild dry-build --flake .#abora
else
    printf 'Skipped: dry-build needs root to write /etc/nixos/flake.lock.\\n'
    printf 'Run manually when needed: sudo nixos-rebuild dry-build --flake /etc/nixos#abora\\n'
fi
"""

NETWORK_AND_BLUETOOTH = (
    "systemctl --no-pager status NetworkManager bluetooth 2>/dev/null || true; "
    "nmcli networking connectivity check 2>/dev/null || true; "
    "nmcli device status 2>/dev/null || true; "
    "nmcli radio 2>/dev/null || true; "
    "nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || true; "
    "resolvectl status 2>/dev/null || true; "
    "curl -fsI --connect-timeout 5 --max-time 8 https://cache.nixos.org 2>/dev/null || true; "
    "rfkill list 2>/dev/null || true"
)

# ── redaction ─────────────────────────────────────────────────────────────────
# Obvious secrets: `key = value` / `key: value` credential pairs, and
# user:password@ URLs. Ported from the sed script these tools used, keeping
# its POSIX longest-match semantics where Python's first-match would differ.
# abora-support-report.py and abora-check-full.py carry this same block, and
# tests/support.test.py keeps the copies identical.

SECRET_KEY = re.compile(r"(^|[^A-Za-z0-9_])(hashedPassword|password|passwd|secret|token|api[_-]?key)(\s*[:=]\s*)", re.IGNORECASE)
SECRET_VALUES = (re.compile(r'"[^"]*"'), re.compile(r"'[^']*'"), re.compile(r"[^\s;]+"))
# The trailing "@" is what makes this a credential URL: without it any bare
# "word:word" (timestamps, host:port) would be redacted too.
CREDENTIAL_URL = re.compile(r"(github\.com/\S+://)?([^\s@/]+):([^\s@]+)@")


def redact_line(line: str) -> str:
    out, pos = [], 0
    search_from = 0
    while (key := SECRET_KEY.search(line, search_from)) is not None:
        # sed takes the longest of the value alternatives, not the first.
        value_end = max((m.end() for p in SECRET_VALUES if (m := p.match(line, key.end()))), default=None)
        if value_end is None:
            search_from = key.start() + 1
            continue
        out.append(line[pos:key.end()] + '"[redacted]"')
        pos = search_from = value_end
    out.append(line[pos:])
    return CREDENTIAL_URL.sub("[redacted-user]:[redacted]@", "".join(out))


def redact(text: str) -> str:
    return "\n".join(redact_line(line) for line in text.split("\n"))

# ── end redaction ─────────────────────────────────────────────────────────────


def run_with_timeout(argv: list[str]) -> tuple[str, int]:
    """Output (stdout and stderr) and exit status, like timeout(1): 124 on a
    timeout, 127 when the command is missing. The command gets its own
    process group so a timeout also stops anything it started."""
    try:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, process_group=0)
    except OSError as exc:
        return f"timeout: failed to run command '{argv[0]}': {exc.strerror}\n", 127
    try:
        output, _ = process.communicate(timeout=section_timeout)
        status = process.returncode
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        status = 124
    return output.decode("utf-8", errors="replace"), status


def header_value(read) -> str:
    try:
        return read()
    except (OSError, KeyError):
        return "unknown"


class Report:
    def __init__(self, path: Path):
        self.path = path
        self.file = path.open("w", encoding="utf-8")

    def write(self, text: str) -> None:
        self.file.write(text)
        self.file.flush()

    def section(self, title: str, argv: list[str]) -> None:
        self.write(f"\n## {title}\n$ {shlex.join(argv)}\n\n")
        output, status = run_with_timeout(argv)
        if status != 0:
            output += f"\n[exit {status}]\n"
        self.write(redact(output))

    def optional_command(self, title: str, argv: list[str]) -> None:
        if shutil.which(argv[0]):
            self.section(title, argv)
        else:
            self.write(f"\n## {title}\n\n{argv[0]} command not found\n")

    def append_file(self, title: str, path: str) -> None:
        self.write(f"\n## {title}\nfile: {path}\n\n")
        try:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            self.write("missing or unreadable\n")
            return
        self.write("".join(redact(text).splitlines(keepends=True)[:260]))


def main() -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    report = Report(out_dir / f"abora-full-check-{time.strftime('%Y%m%d-%H%M%S')}.log")

    kernel = subprocess.run(["uname", "-a"], stdout=subprocess.PIPE, text=True).stdout.strip() if shutil.which("uname") else "unknown"
    report.write(redact(
        "Abora full check\n"
        f"Generated: {datetime.now().astimezone().isoformat(timespec='seconds')}\n"
        f"Host: {header_value(socket.gethostname)}\n"
        f"User: {header_value(lambda: pwd.getpwuid(os.geteuid()).pw_name)}\n"
        f"Kernel: {kernel}\n"
    ))

    report.section("OS release", ["sh", "-lc", "cat /etc/os-release 2>/dev/null || true"])
    report.section("Current system", ["sh", "-lc", "readlink /run/current-system 2>/dev/null || true; nixos-version 2>/dev/null || true"])
    report.section("Abora doctor", ["abora", "doctor"])
    report.section("ANIX status", ["anix", "status"])
    report.section("ANIX doctor", ["anix", "doctor"])
    report.section("ANIX profiles", ["anix", "profiles"])
    report.section("ANIX generations", ["anix", "generations"])
    report.optional_command("TinyPM version", ["tinypm", "--version"])
    report.optional_command("TinyPM package check", ["tinypm", "check", "firefox"])
    report.optional_command("TinyPM doctor", ["tinypm", "doctor"])
    report.section("Abora desktop", ["abora", "desktop", "list"])
    report.section("Display services", ["sh", "-lc", "systemctl --no-pager --failed; systemctl --no-pager status display-manager 2>/dev/null || true"])
    report.section("Network and Bluetooth", ["sh", "-lc", NETWORK_AND_BLUETOOTH])
    report.section("Audio", ["sh", "-lc", "systemctl --user --no-pager status pipewire wireplumber pulseaudio 2>/dev/null || true; pactl info 2>/dev/null || true"])
    report.section("Graphics", ["sh", "-lc", 'lspci -nnk 2>/dev/null | sed -n "/VGA\\|3D\\|Display/,+4p"; glxinfo -B 2>/dev/null || true'])
    report.section("Nix flake check", ["sh", "-lc", 'cd /etc/nixos && nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file 2>&1'])
    report.section("Nix dry build", ["sh", "-c", NIX_DRY_BUILD])

    report.append_file("ANIX config", "/etc/nixos/anix.nix")
    report.append_file("Abora local config", "/etc/nixos/abora-local.nix")
    report.append_file("NixOS config", "/etc/nixos/configuration.nix")
    report.append_file("Dotfiles import log", f"{state_home}/abora/dotfiles-import.log")

    if Path("/etc/abora/docs/wiki").is_dir():
        report.section("Abora docs present", ["sh", "-lc", 'find /etc/abora/docs/wiki -maxdepth 1 -type f -printf "%f\\n" | sort'])

    print(f"\nFull check log: {report.path}")
    print("Send this file when asking for help.")
    return 0


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
