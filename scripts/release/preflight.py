#!/usr/bin/env python3
"""Full release preflight: script checks, repository file sweep, desktop evaluation.

Stops at the first failing stage and exits with its status.
"""

from __future__ import annotations

import subprocess
import sys

from abora_release import repo_root

STAGES = (
    ("script and runtime checks", "./scripts/check-scripts.py"),
    ("full repository file sweep", "./scripts/check-all-files.py"),
    ("desktop profile evaluation", "./scripts/check-desktops.py"),
)


def main() -> int:
    repo = repo_root(__file__)
    for index, (title, command) in enumerate(STAGES):
        print(f"{'' if index == 0 else chr(10)}[preflight] {title}", flush=True)
        status = subprocess.run([command], cwd=repo).returncode
        if status != 0:
            return status
    print("\n[preflight] done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
