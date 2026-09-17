"""Runs the Bash behaviour-test suites (scripts/*/tests/*.test.sh).

Each suite is its own process with its own scratch directories, so one suite's
failure never stops the others. A suite that exits non-zero without printing a
[fail] line crashed (e.g. a syntax error or an unguarded command under set -e),
which is reported as a failure of its own.
"""

from __future__ import annotations

import os
import subprocess

from .core import Context


def run(ctx: Context) -> None:
    env = {
        **os.environ,
        "ABORA_TEST_RESOLVER_BIN": str(ctx.resolver_bin or ""),
        "ABORA_TEST_PLAN_TOOL_BIN": str(ctx.plan_tool_bin or ""),
    }
    for suite in sorted(ctx.repo.glob("scripts/*/tests/*.test.sh")):
        relative = suite.relative_to(ctx.repo).as_posix()
        process = subprocess.Popen([str(suite)], cwd=ctx.repo, env=env, stdout=subprocess.PIPE, text=True)
        reported_failure = False
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            reported_failure = reported_failure or line.startswith("[fail] ")
        status = process.wait()
        if status != 0:
            ctx.failed = True
            if not reported_failure:
                ctx.fail(f"suite crashed: {relative} (exit {status})")
