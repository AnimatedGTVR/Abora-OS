"""Result storage.

Layout under the output directory (default out/labs/, gitignored):

    sessions/<session-id>/session.json           what was invoked, git state, every result
    sessions/<session-id>/<area>/<impl>/<stage>.log
    latest/<area>/<impl>.json                    newest result per stage, plus metrics

Results are plain JSON so any language (or `jq`) can read them. `latest` is
updated as each stage finishes, so an interrupted session still keeps what
it completed.
"""

from __future__ import annotations

import json
import os
import platform
import secrets
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .workspace import Workspace

SCHEMA_VERSION = 1

# Stage result statuses.
PASSED = "passed"
FAILED = "failed"
CRASHED = "crashed"
TIMEOUT = "timeout"
ERROR = "error"  # the controller could not execute the command
BLOCKED = "blocked"  # safety policy refused
UNAVAILABLE = "unavailable"  # missing toolchain
SKIPPED = "skipped"  # nothing to run, or an earlier stage did not pass

BAD_STATUSES = {FAILED, CRASHED, TIMEOUT, ERROR}
NOT_RUN_STATUSES = {BLOCKED, UNAVAILABLE}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass
class StageResult:
    experiment: str
    stage: str
    status: str
    reason: str | None = None
    command: str | None = None
    safety: str | None = None
    started_at: str = field(default_factory=now_iso)
    duration_s: float | None = None
    exit_code: int | None = None
    signal: str | None = None
    peak_rss_kb: int | None = None
    log: str | None = None
    tests: dict[str, int] | None = None
    warning_lines_heuristic: int | None = None
    session: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class ResultStore:
    def __init__(self, ws: Workspace):
        self.ws = ws
        self.out = ws.out

    def latest_path(self, experiment_id: str) -> Path:
        return self.out / "latest" / f"{experiment_id}.json"

    def latest(self, experiment_id: str) -> dict[str, Any] | None:
        path = self.latest_path(experiment_id)
        if not path.is_file():
            return None
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"warning: ignoring unreadable result file {path}: {exc}", file=sys.stderr)
            return None

    def start_session(self, argv: list[str]) -> Session:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        session_id = f"{stamp}-{secrets.token_hex(3)}"
        return Session(self, session_id, argv)

    def update_latest(self, experiment_id: str, key: str, value: dict[str, Any]) -> None:
        current = self.latest(experiment_id) or {"schema": SCHEMA_VERSION, "experiment": experiment_id, "stages": {}}
        if key == "metrics":
            current["metrics"] = value
        else:
            current["stages"][key] = value
        current["updated_at"] = now_iso()
        _write_json(self.latest_path(experiment_id), current)


class Session:
    def __init__(self, store: ResultStore, session_id: str, argv: list[str]):
        self.store = store
        self.id = session_id
        self.directory = store.out / "sessions" / session_id
        self.data: dict[str, Any] = {
            "schema": SCHEMA_VERSION,
            "id": session_id,
            "argv": argv,
            "started_at": now_iso(),
            "finished_at": None,
            "host": {
                "platform": platform.platform(),
                "python": platform.python_version(),
            },
            "git": git_state(store.ws.root),
            "results": [],
            "metrics": {},
        }
        self._write()

    def log_path(self, experiment_id: str, stage: str) -> Path:
        return self.directory / experiment_id / f"{stage}.log"

    def record(self, result: StageResult) -> None:
        result.session = self.id
        self.data["results"].append(result.to_dict())
        self.store.update_latest(result.experiment, result.stage, result.to_dict())
        self._write()

    def record_metrics(self, experiment_id: str, metrics: dict[str, Any]) -> None:
        metrics = {**metrics, "session": self.id, "measured_at": now_iso()}
        self.data["metrics"][experiment_id] = metrics
        self.store.update_latest(experiment_id, "metrics", metrics)
        self._write()

    def finish(self) -> None:
        self.data["finished_at"] = now_iso()
        self._write()

    def _write(self) -> None:
        _write_json(self.directory / "session.json", self.data)


def git_state(root: Path) -> dict[str, Any] | None:
    try:
        commit = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10, check=True
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain"], capture_output=True, text=True, timeout=30, check=True
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return {"commit": commit, "dirty": bool(dirty)}


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
