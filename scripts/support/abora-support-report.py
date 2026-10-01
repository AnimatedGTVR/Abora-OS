#!/usr/bin/env python3
"""abora support-report: collect a redacted support archive for bug reports.

Prints the archive path on stdout (callers such as `abora bug-report
--with-support-report` and abora-hardware-test capture it); messages go to
stderr. Exit status 2 for a usage error.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
from datetime import datetime
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

version = os.environ.get("ABORA_VERSION") or "4.0"
release_name = os.environ.get("ABORA_RELEASE_NAME") or "Abora OS v4 Everest"
state_home = Path(os.environ.get("XDG_STATE_HOME") or f"{os.environ.get('HOME') or '/tmp'}/.local/state")

SECTIONS = (
    ("System", ["uname", "-a"]),
    ("OS release", ["sh", "-lc", "cat /etc/os-release"]),
    ("Hostnamectl", ["hostnamectl"]),
    ("Uptime", ["uptime"]),
    ("Kernel command line", ["sh", "-lc", "cat /proc/cmdline"]),
    ("Memory", ["free", "-h"]),
    ("CPU", ["lscpu"]),
    ("Block devices", ["lsblk", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN,RM,ROTA"]),
    ("Filesystems", ["df", "-h"]),
    ("PCI", ["lspci", "-nnk"]),
    ("USB", ["lsusb"]),
    ("IP links", ["ip", "-br", "link"]),
    ("IP addresses", ["ip", "-br", "addr"]),
    ("Routes", ["ip", "route"]),
    ("Wireless", ["iw", "dev"]),
)

LATE_SECTIONS = (
    ("Bluetooth", ["sh", "-lc", "rfkill list || true"]),
    ("Dmesg (tail)", ["sh", "-lc", "dmesg | tail -n 200"]),
    ("Current boot journal (tail)", ["journalctl", "-b", "-n", "300", "--no-pager"]),
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


def usage(output_root: str, file=sys.stdout) -> None:
    print(f"""Usage:
  abora support-report [--output-dir DIR]

Collect a redacted support archive for Abora OS bug reports.

Default output:
  {output_root}/abora-support-<timestamp>.tar.gz

Environment:
  ABORA_SUPPORT_OUTPUT_DIR=/path  choose the output directory""", file=file)


def command_output(argv: list[str]) -> str:
    """stdout and stderr together, with a marker line when the command failed."""
    try:
        done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError:
        return f"{argv[0]}: command not found\n[command failed]\n"
    output = done.stdout.decode("utf-8", errors="replace")
    return output + "[command failed]\n" if done.returncode != 0 else output


def main(args: list[str]) -> int:
    output_root = os.environ.get("ABORA_SUPPORT_OUTPUT_DIR") or "/tmp"
    while args:
        if args[0] in ("--output-dir", "--out"):
            if len(args) < 2 or not args[1]:
                print("abora support-report: --output-dir needs a directory", file=sys.stderr)
                return 2
            output_root = args[1]
            args = args[2:]
        elif args[0] in ("--help", "-h"):
            usage(output_root)
            return 0
        else:
            print(f"abora support-report: unknown argument: {args[0]}", file=sys.stderr)
            usage(output_root, file=sys.stderr)
            return 2

    report_dir = Path(output_root) / f"abora-support-{time.strftime('%Y%m%d-%H%M%S')}"
    archive_path = Path(f"{report_dir}.tar.gz")
    report_dir.mkdir(parents=True, exist_ok=True)

    with (report_dir / "report.txt").open("w", encoding="utf-8") as report:
        timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
        report.write(redact(f"Abora OS support report\nRelease: {release_name}\nVersion ID: {version}\nTimestamp: {timestamp}\n\n"))

        def capture_section(title: str, argv: list[str]) -> None:
            report.write(f"## {title}\n\n{redact(command_output(argv))}\n")

        for title, argv in SECTIONS:
            capture_section(title, argv)
        if shutil.which("abora"):
            capture_section("Abora network diagnostics", ["abora", "network"])
        elif shutil.which("abora-recovery"):
            capture_section("Abora network diagnostics", ["abora-recovery", "network"])
        for title, argv in LATE_SECTIONS:
            capture_section(title, argv)

    for source, target in (
        ("/tmp/abora-generate-config.log", "abora-generate-config.log"),
        ("/tmp/abora-install.log", "abora-install.log"),
        (state_home / "abora" / "dotfiles-import.log", "dotfiles-import.log"),
    ):
        if Path(source).is_file():
            text = Path(source).read_text(encoding="utf-8", errors="replace")
            (report_dir / target).write_text(redact(text), encoding="utf-8")

    with tarfile.open(archive_path, "w:gz") as archive:
        archive.add(report_dir, arcname=report_dir.name)
    shutil.rmtree(report_dir)

    print("Abora support archive created:", file=sys.stderr)
    print(f"  {archive_path}", file=sys.stderr)
    print("Review it before posting publicly. Obvious secrets are redacted, but you should still check it.", file=sys.stderr)
    print(archive_path)
    return 0


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
