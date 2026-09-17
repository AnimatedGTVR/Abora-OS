"""Terminal output: colors (off when piped or NO_COLOR is set) and plain tables."""

from __future__ import annotations

import os
import re
import sys
from typing import TextIO

from . import results as r

ANSI = re.compile(r"\x1b\[[0-9;]*m")

STATUS_STYLE = {
    r.PASSED: "32",
    r.FAILED: "31",
    r.CRASHED: "1;31",
    r.TIMEOUT: "31",
    r.ERROR: "1;31",
    r.BLOCKED: "33",
    r.UNAVAILABLE: "33",
    r.SKIPPED: "2",
}


class UI:
    def __init__(self, out: TextIO | None = None, err: TextIO | None = None, color: bool | None = None, verbose: bool = False):
        self.out = out or sys.stdout
        self.err = err or sys.stderr
        if color is None:
            color = self.out.isatty() and "NO_COLOR" not in os.environ and os.environ.get("TERM") != "dumb"
        self.color = color
        self.verbose = verbose

    def style(self, text: str, code: str) -> str:
        return f"\x1b[{code}m{text}\x1b[0m" if self.color else text

    def status(self, status: str) -> str:
        return self.style(status, STATUS_STYLE.get(status, "0"))

    def bold(self, text: str) -> str:
        return self.style(text, "1")

    def dim(self, text: str) -> str:
        return self.style(text, "2")

    def print(self, text: str = "") -> None:
        print(text, file=self.out)

    def heading(self, text: str) -> None:
        self.print(self.bold(text))

    def warn(self, text: str) -> None:
        print(f"{self.style('warning:', '33')} {text}", file=self.err)

    def error(self, text: str, hint: str | None = None) -> None:
        print(f"{self.style('error:', '1;31')} {text}", file=self.err)
        if hint:
            print(f"{self.style('hint:', '36')} {hint}", file=self.err)

    def table(self, headers: list[str], rows: list[list[str]]) -> None:
        widths = [len(h) for h in headers]
        for row in rows:
            for i, cell in enumerate(row):
                widths[i] = max(widths[i], visible_len(cell))
        self.print("  ".join(self.bold(pad(h, widths[i])) for i, h in enumerate(headers)).rstrip())
        for row in rows:
            self.print("  ".join(pad(cell, widths[i]) for i, cell in enumerate(row)).rstrip())


def visible_len(text: str) -> int:
    return len(ANSI.sub("", text))


def pad(text: str, width: int) -> str:
    return text + " " * (width - visible_len(text))


def human_bytes(value: int | None) -> str:
    if value is None:
        return "-"
    size = float(value)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if size < 1024 or unit == "GiB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{value} B"


def human_seconds(value: float | None) -> str:
    if value is None:
        return "-"
    if value < 1:
        return f"{value * 1000:.1f} ms"
    return f"{value:.2f} s"
