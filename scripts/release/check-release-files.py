#!/usr/bin/env python3
"""Fail if any file an installed Abora system's updater needs is missing.

The list lives in release-required-paths.txt (one repo-relative path per line)
and mirrors abora-update.sh's required_upstream_paths() for a release-tagged
checkout (the newest layout, so every conditional release_has_*/release_uses_*
path there applies). Run this before tagging a release: if a listed file is
missing from the checkout, any installed Abora system that later runs
`sudo abora update` against this tag will fail validate_upstream_checkout()
and refuse to update -- catching that here, at tag time, is much cheaper than
a user hitting it. make check verifies the two lists stay in sync.
"""

from __future__ import annotations

import sys
from pathlib import Path

from abora_release import repo_root

REQUIRED_PATHS = Path(__file__).resolve().parent / "release-required-paths.txt"


def main() -> int:
    repo = repo_root(__file__)
    paths = [line.strip() for line in REQUIRED_PATHS.read_text(encoding="utf-8").splitlines() if line.strip()]

    missing = [path for path in paths if not (repo / path).exists()]
    for path in missing:
        print(f"missing required release file: {path}", file=sys.stderr)
    if missing:
        print("Release file check failed. Do not tag or ship this checkout.", file=sys.stderr)
        return 1

    print("All updater-required release files are present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
