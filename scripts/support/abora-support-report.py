#!/usr/bin/env python3
"""abora support-report: collect a redacted support archive for bug reports.

Prints the archive path on stdout (callers such as `abora bug-report
--with-support-report` and abora-hardware-test capture it); messages go to
stderr. Exit status 2 for a usage error.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tarfile
import time
from datetime import datetime
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

def installed_version() -> str:
    """The version this system was built from (/etc/abora/VERSION), so a report never claims another one."""
    try:
        return "".join(Path("/etc/abora/VERSION").read_text(encoding="utf-8").split())
    except OSError:
        return ""


version = os.environ.get("ABORA_VERSION") or installed_version() or "4.2"
release_name = os.environ.get("ABORA_RELEASE_NAME") or "Abora OS v4.2 Solstice"
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

# Abora's shared core (abora_core.py): beside this tool in a checkout, on the live ISO and in the
# hardware-test package; in /etc/abora on an installed system, where each tool is its own Nix store file.
sys.path[:0] = [str(Path(__file__).resolve().parent), "/etc/abora"]
from abora_core import redact


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

    # The doctor's findings as JSON, a file of its own so support can read it without parsing the report.
    # It exits 1 whenever a check fails, which is still a complete report, so only stdout is kept.
    argv = ["abora-doctor", "--json"] if shutil.which("abora-doctor") else ["anix", "doctor", "--json"] if shutil.which("anix") else None
    if argv:
        try:
            done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=120)
            (report_dir / "doctor.json").write_text(redact(done.stdout.decode("utf-8", errors="replace")), encoding="utf-8")
        except (OSError, subprocess.TimeoutExpired):
            pass

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
