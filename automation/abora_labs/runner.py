"""Executing one command with logging, a timeout, and resource accounting.

- Each command runs in its own session/process group, so a timeout kills the
  whole tree it started, not just the shell.
- The child is reaped with os.wait4, which gives peak RSS (including waited-for
  descendants) without any external dependency.
- Captured output goes to a log file with a short header and footer; the last
  lines are kept in memory for error messages.
"""

from __future__ import annotations

import collections
import os
import signal
import subprocess
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import TextIO

LOG_PREFIX = "[abora-labs] "
CRASH_SIGNALS = {signal.SIGSEGV, signal.SIGABRT, signal.SIGBUS, signal.SIGILL, signal.SIGFPE}
KILL_GRACE_SECONDS = 5.0
DRAIN_SECONDS = 2.0


@dataclass
class CommandSpec:
    argv: list[str]
    display: str
    cwd: Path
    env: dict[str, str]
    timeout: float | None
    capture: bool = True  # False: inherit the terminal (interactive `run`)


@dataclass
class Outcome:
    exit_code: int | None = None
    signal_name: str | None = None
    timed_out: bool = False
    duration_s: float = 0.0
    peak_rss_kb: int | None = None
    spawn_error: str | None = None
    tail: list[str] = field(default_factory=list)
    output_lines: int = 0
    leftover_processes: bool = False

    @property
    def succeeded(self) -> bool:
        return self.exit_code == 0 and not self.timed_out and self.spawn_error is None

    @property
    def crashed(self) -> bool:
        if self.signal_name is not None and self.signal_name in {s.name for s in CRASH_SIGNALS}:
            return True
        # `sh -c` (and wrappers like `dotnet run`) report a child killed by signal N as exit 128+N.
        return self.exit_code is not None and self.exit_code - 128 in {int(s) for s in CRASH_SIGNALS}

    def describe(self) -> str:
        if self.spawn_error:
            return f"could not start: {self.spawn_error}"
        if self.timed_out:
            return f"timed out after {self.duration_s:.1f}s"
        if self.signal_name:
            return f"killed by {self.signal_name}"
        if self.exit_code == 127:
            return "exit 127 (command not found)"
        if self.crashed:
            return f"exit {self.exit_code} (shell-reported {signal.Signals(self.exit_code - 128).name})"
        return f"exit {self.exit_code}"


def run_command(spec: CommandSpec, log_path: Path | None, echo: TextIO | None = None) -> Outcome:
    outcome = Outcome()
    log = None
    if spec.capture and log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log = log_path.open("w", encoding="utf-8")
        log.write(f"{LOG_PREFIX}command: {spec.display}\n")
        log.write(f"{LOG_PREFIX}cwd: {spec.cwd}\n")
        log.write(f"{LOG_PREFIX}started: {datetime.now(timezone.utc).isoformat(timespec='seconds')}\n")
        log.flush()

    try:
        _execute(spec, outcome, log, echo)
    finally:
        if log is not None:
            log.write(f"{LOG_PREFIX}result: {outcome.describe()} in {outcome.duration_s:.3f}s\n")
            log.close()
    return outcome


def _execute(spec: CommandSpec, outcome: Outcome, log: TextIO | None, echo: TextIO | None) -> None:
    started = time.monotonic()
    try:
        proc = subprocess.Popen(
            spec.argv,
            cwd=spec.cwd,
            env=spec.env,
            stdin=subprocess.DEVNULL if spec.capture else None,
            stdout=subprocess.PIPE if spec.capture else None,
            stderr=subprocess.STDOUT if spec.capture else None,
            start_new_session=spec.capture,
        )
    except OSError as exc:
        outcome.spawn_error = f"{exc.strerror or exc} ({spec.argv[0]})"
        outcome.duration_s = time.monotonic() - started
        return

    tail: collections.deque[str] = collections.deque(maxlen=40)
    reader = None
    if spec.capture:
        reader = threading.Thread(target=_pump, args=(proc, log, echo, tail, outcome), daemon=True)
        reader.start()

    timer = None
    if spec.timeout:
        timer = threading.Timer(spec.timeout, _kill_tree, args=(proc.pid, outcome, spec.capture))
        timer.daemon = True
        timer.start()

    try:
        _, status, rusage = _wait4_retrying(proc.pid)
    except KeyboardInterrupt:
        _kill_tree(proc.pid, outcome, spec.capture, timed_out=False)
        _, status, rusage = _wait4_retrying(proc.pid)
        raise
    finally:
        outcome.duration_s = time.monotonic() - started
        if timer is not None:
            timer.cancel()

    code = os.waitstatus_to_exitcode(status)
    proc.returncode = code  # already reaped; stop Popen from waiting again
    if code < 0:
        outcome.signal_name = signal.Signals(-code).name
    else:
        outcome.exit_code = code
    outcome.peak_rss_kb = rusage.ru_maxrss or None

    if reader is not None:
        reader.join(DRAIN_SECONDS)
        if reader.is_alive():
            # Something the command started is still holding the output pipe open.
            outcome.leftover_processes = True
            _signal_group(proc.pid, signal.SIGKILL)
            reader.join(DRAIN_SECONDS)
    outcome.tail = list(tail)


def _wait4_retrying(pid: int) -> tuple[int, int, object]:
    while True:
        try:
            return os.wait4(pid, 0)
        except InterruptedError:
            continue


def _pump(proc: subprocess.Popen, log: TextIO | None, echo: TextIO | None, tail: collections.deque, outcome: Outcome) -> None:
    assert proc.stdout is not None
    for raw in proc.stdout:
        line = raw.decode("utf-8", "replace")
        outcome.output_lines += 1
        tail.append(line.rstrip("\n"))
        if log is not None:
            log.write(line)
        if echo is not None:
            echo.write(line)
            echo.flush()
    proc.stdout.close()


def _signal_group(pid: int, sig: signal.Signals) -> None:
    try:
        os.killpg(pid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def _kill_tree(pid: int, outcome: Outcome, own_group: bool, timed_out: bool = True) -> None:
    outcome.timed_out = timed_out
    if not own_group:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        return
    _signal_group(pid, signal.SIGTERM)
    deadline = time.monotonic() + KILL_GRACE_SECONDS
    while time.monotonic() < deadline:
        try:
            os.killpg(pid, 0)
        except (ProcessLookupError, PermissionError):
            return
        time.sleep(0.1)
    _signal_group(pid, signal.SIGKILL)


def read_output_lines(log_path: Path) -> list[str]:
    """Output lines from a captured log, without the controller's header/footer."""
    with log_path.open(encoding="utf-8", errors="replace") as handle:
        return [line.rstrip("\n") for line in handle if not line.startswith(LOG_PREFIX)]
