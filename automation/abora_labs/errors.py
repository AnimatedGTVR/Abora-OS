"""User-facing error types.

Every error the CLI prints should say what went wrong and, where possible,
what to do about it. Nothing in the controller should swallow an exception
to keep going quietly.
"""

from __future__ import annotations

from pathlib import Path

# CLI exit codes (also documented in docs/labs/cli.md).
EXIT_OK = 0
EXIT_FAILED = 1  # a stage failed, crashed, timed out, or hit a harness error
EXIT_USAGE = 2  # bad arguments, invalid manifest or config
EXIT_NOT_RUN = 3  # nothing failed, but something was blocked or unavailable


class LabsError(Exception):
    def __init__(self, message: str, hint: str | None = None, exit_code: int = EXIT_USAGE):
        super().__init__(message)
        self.message = message
        self.hint = hint
        self.exit_code = exit_code


class ManifestError(LabsError):
    """A TOML file (experiment manifest, evaluation, config) failed validation."""

    def __init__(self, path: Path, problems: list[str]):
        self.path = path
        self.problems = problems
        lines = "\n".join(f"  - {p}" for p in problems)
        super().__init__(f"{path}: invalid\n{lines}")
