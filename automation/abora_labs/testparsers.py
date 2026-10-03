"""Turning test output into pass/fail/skip counts.

Each experiment names its output format in `[test] format`. Parsers only count
what they can recognise; if a format finds nothing, the stage result says so
rather than inventing a number.

The `labs` format is the fallback for any language without a test framework
(Vanta 0.1, SQL scripts, shell): print one line per test,

    LABS-TEST: PASS <name>
    LABS-TEST: FAIL <name>
    LABS-TEST: SKIP <name>
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass


@dataclass
class TestCounts:
    passed: int = 0
    failed: int = 0
    skipped: int = 0

    @property
    def total(self) -> int:
        return self.passed + self.failed + self.skipped

    def to_dict(self) -> dict[str, int]:
        return {**asdict(self), "total": self.total}


GO_LINE = re.compile(r"^\s*--- (PASS|FAIL|SKIP): (\S+)")
CARGO_SUMMARY = re.compile(r"^test result: \w+\. (\d+) passed; (\d+) failed; (\d+) ignored")
LABS_LINE = re.compile(r"^LABS-TEST: (PASS|FAIL|SKIP)\b")
TAP_LINE = re.compile(r"^(not ok|ok)\b(.*)$")


def _tally(counts: TestCounts, word: str) -> None:
    if word == "PASS":
        counts.passed += 1
    elif word == "FAIL":
        counts.failed += 1
    else:
        counts.skipped += 1


def parse_go(lines: Iterable[str]) -> TestCounts:
    """Counts leaf tests only: a parent like TestAllows whose subtests
    (TestAllows/...) are also reported is a group, not an extra test."""
    results: dict[str, str] = {}
    for line in lines:
        if match := GO_LINE.match(line):
            results[match.group(2)] = match.group(1)
    counts = TestCounts()
    for name, word in results.items():
        if not any(other.startswith(name + "/") for other in results):
            _tally(counts, word)
    return counts


def parse_cargo(lines: Iterable[str]) -> TestCounts:
    counts = TestCounts()
    for line in lines:
        if match := CARGO_SUMMARY.match(line.strip()):
            counts.passed += int(match.group(1))
            counts.failed += int(match.group(2))
            counts.skipped += int(match.group(3))
    return counts


def parse_labs(lines: Iterable[str]) -> TestCounts:
    counts = TestCounts()
    for line in lines:
        if match := LABS_LINE.match(line.strip()):
            _tally(counts, match.group(1))
    return counts


def parse_tap(lines: Iterable[str]) -> TestCounts:
    counts = TestCounts()
    for line in lines:
        match = TAP_LINE.match(line.strip())
        if not match:
            continue
        if "# skip" in match.group(2).lower():
            counts.skipped += 1
        elif match.group(1) == "ok":
            counts.passed += 1
        else:
            counts.failed += 1
    return counts


PARSERS: dict[str, Callable[[Iterable[str]], TestCounts]] = {
    "go": parse_go,
    "cargo": parse_cargo,
    "labs": parse_labs,
    "tap": parse_tap,
}
