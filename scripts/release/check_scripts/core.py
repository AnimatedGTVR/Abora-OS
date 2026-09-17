"""Reporting, command helpers and the condition DSL the check groups share."""

from __future__ import annotations

import os
import subprocess
import tempfile
from collections.abc import Callable
from pathlib import Path

DETAIL_INDENT = " " * 14

Condition = Callable[["Context"], bool]


class Context:
    def __init__(self, repo: Path):
        self.repo = repo
        self.failed = False
        self.resolver_bin: Path | None = None
        self.plan_tool_bin: Path | None = None
        self._temp = tempfile.TemporaryDirectory(prefix="abora-check-")
        self.tmp = Path(self._temp.name)

    def close(self) -> None:
        self._temp.cleanup()

    # ── reporting ──
    def ok(self, name: str) -> None:
        print(f"[ok]   {name}", flush=True)

    def fail(self, name: str) -> None:
        print(f"[fail] {name}", flush=True)
        self.failed = True

    def result(self, passed: bool, name: str, fail_name: str | None = None) -> bool:
        if passed:
            self.ok(name)
        else:
            self.fail(fail_name or name)
        return passed

    def detail(self, text: str) -> None:
        for line in text.splitlines():
            print(f"{DETAIL_INDENT}{line}", flush=True)

    # ── commands ──
    def run(self, argv: list[str], *, env: dict[str, str] | None = None, quiet: bool = False,
            capture: bool = False, cwd: Path | None = None, input: str | None = None) -> subprocess.CompletedProcess:
        """Run from the repo root. quiet: discard stdout and stderr; capture: return them (stderr merged)."""
        kwargs: dict = {"cwd": cwd or self.repo, "text": True, "input": input}
        if env is not None:
            kwargs["env"] = {**os.environ, **env}
        if capture:
            kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        elif quiet:
            kwargs.update(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            return subprocess.run(argv, **kwargs)
        except OSError as exc:
            return subprocess.CompletedProcess(argv, 127, stdout=f"{argv[0]}: {exc.strerror}\n" if capture else None)

    def grep(self, *args: str, stdin: str | None = None, quiet_errors: bool = False) -> bool:
        """True when `grep args...` exits 0. Runs the real grep so patterns keep POSIX semantics."""
        result = subprocess.run(
            ["grep", *args],
            cwd=self.repo,
            input=stdin,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL if quiet_errors else None,
        )
        return result.returncode == 0

    def grep_output(self, *args: str, stdin: str | None = None) -> str:
        result = subprocess.run(["grep", *args], cwd=self.repo, input=stdin, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return result.stdout

    def path(self, relative: str) -> Path:
        return self.repo / relative


# ── condition DSL for declarative checks ──
def grep(*args: str, quiet_errors: bool = False) -> Condition:
    return lambda ctx: ctx.grep(*args, quiet_errors=quiet_errors)


def not_(condition: Condition) -> Condition:
    return lambda ctx: not condition(ctx)


def test(flag: str, path: str) -> Condition:
    """Bash `[[ flag path ]]` for -f, -d, -e, -x, -s (all follow symlinks)."""

    def check(ctx: Context) -> bool:
        target = ctx.repo / path
        return {
            "-f": target.is_file,
            "-d": target.is_dir,
            "-e": target.exists,
            "-x": lambda: target.exists() and os.access(target, os.X_OK),
            "-s": lambda: target.is_file() and target.stat().st_size > 0,
        }[flag]()

    return check


class Check:
    """A named chain of conditions that must all hold; evaluation stops at the first that doesn't."""

    def __init__(self, name: str, *conditions: Condition, fail_name: str | None = None):
        self.name = name
        self.conditions = conditions
        self.fail_name = fail_name

    def conditions_hold(self, ctx: Context) -> bool:
        return all(condition(ctx) for condition in self.conditions)

    def run(self, ctx: Context) -> bool:
        return ctx.result(self.conditions_hold(ctx), self.name, self.fail_name)
