"""Abora terminal message style for Python tooling.

Mirrors the message helpers in scripts/core/abora-ui.sh (abora_info,
abora_success, abora_warn, abora_error) so Python tools look the same as the
Bash ones. Like the Bash scripts, pointing ABORA_UI_LIB at a file that does
not exist selects the plain fallback ("[ok]", "[warn]", "[fail]"), which
the test suites use to check output in isolation.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

BLUE = "\033[38;5;33m"
YELLOW = "\033[38;5;222m"
GREEN = "\033[38;5;77m"
RED = "\033[38;5;203m"
NC = "\033[0m"


class UI:
    def __init__(self, default_lib: Path):
        lib = os.environ.get("ABORA_UI_LIB") or str(default_lib)
        self.styled = Path(lib).is_file()

    def info(self, message: str) -> None:
        print(f"  {BLUE}·{NC}  {message}" if self.styled else f"  {message}", flush=True)

    def success(self, message: str) -> None:
        print(f"  {GREEN}✓{NC}  {GREEN}{message}{NC}" if self.styled else f"  [ok]   {message}", flush=True)

    def warn(self, message: str) -> None:
        print(f"  {YELLOW}!{NC}  {YELLOW}{message}{NC}" if self.styled else f"  [warn] {message}", flush=True)

    def error(self, message: str) -> None:
        # The styled helper writes errors to stderr; the plain fallback prints them with the rest.
        if self.styled:
            sys.stdout.flush()
            print(f"  {RED}✗{NC}  {RED}{message}{NC}", file=sys.stderr, flush=True)
        else:
            print(f"  [fail] {message}", flush=True)
