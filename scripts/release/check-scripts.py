#!/usr/bin/env python3
"""Abora's repository checks: what `make check` runs before every push.

Builds the C# tools the tests need, checks syntax and required files, runs the
static content checks and the GUI and release-tooling tests, then every Bash
behaviour-test suite in scripts/*/tests/. See scripts/release/check_scripts/.

Exit status: 1 if any check failed, else 0.
"""

from __future__ import annotations

import sys

from abora_release import repo_root
from check_scripts import gui, release, setup, static_manual, suites
from check_scripts.core import Context
from check_scripts.static_checks import CHECKS


def main() -> int:
    ctx = Context(repo_root(__file__))
    try:
        setup.run(ctx)
        for check in CHECKS:
            check.run(ctx)
        static_manual.run(ctx)
        gui.run(ctx)
        release.run(ctx)
        suites.run(ctx)
    finally:
        ctx.close()

    if ctx.failed:
        print("\nOne or more checks failed.", file=sys.stderr)
        return 1
    print("\nAll script checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
