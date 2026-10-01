"""Runs the behaviour-test suites (scripts/*/tests/*.test.sh and *.test.py).

A suite tests its tool in the tool's own language: Bash suites for Bash tools,
Python suites for tools ported to Python. Each suite is its own process with
its own scratch directories, so one suite's failure never stops the others.
Every suite prints [ok]/[fail] lines; one that exits non-zero without printing
a [fail] line crashed (e.g. a syntax error or an unguarded command under
set -e), which is reported as a failure of its own.
"""

from __future__ import annotations

import os
import subprocess
import sys

from .core import Context


def run(ctx: Context) -> None:
    env = {
        **os.environ,
        "ABORA_TEST_RESOLVER_BIN": str(ctx.resolver_bin or ""),
        "ABORA_TEST_PLAN_TOOL_BIN": str(ctx.plan_tool_bin or ""),
    }
    suites = sorted([*ctx.repo.glob("scripts/*/tests/*.test.sh"), *ctx.repo.glob("scripts/*/tests/*.test.py")])
    for suite in suites:
        relative = suite.relative_to(ctx.repo).as_posix()
        argv = [sys.executable, str(suite)] if suite.suffix == ".py" else [str(suite)]
        process = subprocess.Popen(argv, cwd=ctx.repo, env=env, stdout=subprocess.PIPE, text=True)
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
