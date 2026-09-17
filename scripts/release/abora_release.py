"""Shared helpers for Abora's Python release tooling (scripts/release/*.py).

The release scripts import this as a sibling module. Python puts the script's
real directory on sys.path even when it is run through a scripts/<name>.py
symlink, so `import abora_release` works from either path.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def env(name: str) -> str | None:
    """An environment variable, with empty treated as unset (like Bash's ${VAR:-default})."""
    return os.environ.get(name) or None


def find_repo_root(start: Path) -> Path:
    for directory in (start, *start.parents):
        if (directory / "flake.nix").is_file():
            return directory
    sys.exit("Could not find Abora repo root.")


def repo_root(script: str) -> Path:
    return find_repo_root(Path(script).resolve().parent)


def sanitize(value: str) -> str:
    """Keeps only [A-Za-z0-9._-], matching `tr -cd '[:alnum:]._-'` in the C locale."""
    return re.sub(r"[^A-Za-z0-9._-]", "", value)


def as_tag(value: str) -> str:
    """"4.0" -> "v4.0"; values that already start with v/V are kept."""
    return value if value[:1] in ("v", "V") else f"v{value}"


def read_version(repo: Path) -> str:
    """VERSION with newlines removed, or "" if the file is missing."""
    path = repo / "VERSION"
    return path.read_text(encoding="utf-8").replace("\n", "") if path.is_file() else ""


def abora_version_tag(repo: Path, override: str | None = None) -> str:
    """The Abora release tag (e.g. "v4.0") from `override` or VERSION; "vdev" if both are empty."""
    return as_tag(sanitize(override if override else read_version(repo)) or "dev")


def first_quoted_value(path: Path, line_pattern: str) -> str:
    """The text between the first pair of double quotes on the first line matching
    `line_pattern`, like `awk -F'"' '/pattern/{print $2; exit}'`. "" if none."""
    pattern = re.compile(line_pattern)
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if pattern.search(line):
                fields = line.rstrip("\n").split('"')
                return fields[1] if len(fields) > 1 else ""
    return ""


def component_tag(path: Path, line_pattern: str) -> str:
    """A component's own version tag (TinyPM, ANIX), "vunknown" if it cannot be read."""
    return as_tag(sanitize(first_quoted_value(path, line_pattern) or "unknown") or "unknown")
