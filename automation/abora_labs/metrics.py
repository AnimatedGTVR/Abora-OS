"""Objective metrics that can be measured without running anything risky.

Only what is actually measurable is reported. Anything approximate carries
`heuristic` in its key so reports can label it.
"""

from __future__ import annotations

import os
import re
import statistics
from pathlib import Path

from .config import Language

WARNING_LINE = re.compile(r"\bwarning\b", re.IGNORECASE)
# Tally lines ("    0 Warning(s)" from MSBuild, "3 warnings generated." from clang)
# restate warnings already counted on their own lines, or report none at all.
WARNING_SUMMARY = re.compile(r"^\s*(\d+|no) warnings?(\(s\))?( generated)?\.?\s*$", re.IGNORECASE)


def source_lines(directory: Path, language: Language, exclude_dirs: tuple[str, ...]) -> dict[str, int]:
    """Non-blank lines in files that belong to the experiment's language."""
    files = 0
    lines = 0
    for current, dirnames, filenames in os.walk(directory):
        dirnames[:] = sorted(d for d in dirnames if d not in exclude_dirs and not d.startswith("."))
        for filename in filenames:
            path = Path(current) / filename
            if not language.owns(path):
                continue
            files += 1
            try:
                with path.open(encoding="utf-8", errors="replace") as handle:
                    lines += sum(1 for line in handle if line.strip())
            except OSError:
                continue
    return {"files": files, "lines": lines}


def artifact_sizes(directory: Path, artifacts: tuple[str, ...]) -> dict[str, object] | None:
    if not artifacts:
        return None
    sizes: dict[str, int] = {}
    missing: list[str] = []
    for relative in artifacts:
        path = directory / relative
        if path.is_file():
            sizes[relative] = path.stat().st_size
        elif path.is_dir():
            sizes[relative] = sum(p.stat().st_size for p in path.rglob("*") if p.is_file())
        else:
            missing.append(relative)
    return {"bytes": sum(sizes.values()), "files": sizes, "missing": missing}


def warning_lines_heuristic(lines: list[str]) -> int:
    """Count output lines mentioning "warning". Compilers differ; treat as a rough signal."""
    return sum(1 for line in lines if WARNING_LINE.search(line) and not WARNING_SUMMARY.match(line))


def summarize_timings(samples: list[float]) -> dict[str, float]:
    return {
        "median_s": round(statistics.median(samples), 6),
        "min_s": round(min(samples), 6),
        "max_s": round(max(samples), 6),
    }
