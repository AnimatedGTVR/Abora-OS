"""Building a comparison of implementations from stored results.

The comparison is a plain dict (so `report --format json` is the model
itself). It never runs anything; `compare` runs `check` first, `report` does not.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable

from .discovery import Discovery
from .evaluation import AreaEvaluation, load_evaluation
from .manifest import Experiment
from .results import CRASHED, ResultStore, now_iso
from .workspace import Workspace


@dataclass(frozen=True)
class Metric:
    key: str
    label: str
    kind: str  # "measured", "heuristic", or "declared"
    extract: Callable[[dict[str, Any]], Any]


def _stage(latest: dict[str, Any], stage: str) -> dict[str, Any]:
    return (latest.get("stages") or {}).get(stage) or {}


def _metrics(latest: dict[str, Any]) -> dict[str, Any]:
    return latest.get("metrics") or {}


def _tests(latest: dict[str, Any], key: str) -> Any:
    tests = _stage(latest, "test").get("tests")
    return tests.get(key) if tests else None


def _startup(latest: dict[str, Any]) -> Any:
    startup = _metrics(latest).get("startup") or {}
    return startup.get("median_s")


def _nested(latest: dict[str, Any], *keys: str) -> Any:
    value: Any = _metrics(latest)
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


METRICS: tuple[Metric, ...] = (
    Metric("build_status", "Build", "measured", lambda l: _stage(l, "build").get("status")),
    Metric("build_time_s", "Build time", "measured", lambda l: _stage(l, "build").get("duration_s")),
    Metric("build_peak_rss_kb", "Build peak memory", "measured", lambda l: _stage(l, "build").get("peak_rss_kb")),
    Metric("test_status", "Tests", "measured", lambda l: _stage(l, "test").get("status")),
    Metric("tests_passed", "Tests passed", "measured", lambda l: _tests(l, "passed")),
    Metric("tests_total", "Tests found", "measured", lambda l: _tests(l, "total")),
    Metric("test_time_s", "Test time", "measured", lambda l: _stage(l, "test").get("duration_s")),
    Metric("test_peak_rss_kb", "Test peak memory", "measured", lambda l: _stage(l, "test").get("peak_rss_kb")),
    Metric("crashes", "Crashed stages", "measured", lambda l: sum(1 for s in (l.get("stages") or {}).values() if s.get("status") == CRASHED)),
    Metric("artifact_bytes", "Artifact size", "measured", lambda l: _nested(l, "artifacts", "bytes")),
    Metric("startup_median_s", "Startup (median)", "measured", _startup),
    Metric("source_lines", "Source lines", "measured", lambda l: _nested(l, "source", "lines")),
    Metric("source_files", "Source files", "measured", lambda l: _nested(l, "source", "files")),
    Metric("warning_lines", "Build warning lines", "heuristic", lambda l: _stage(l, "build").get("warning_lines_heuristic")),
    Metric("dependencies", "Dependencies", "declared", lambda l: _metrics(l).get("dependencies_declared")),
)


def members(discovery: Discovery, area: str) -> list[Experiment]:
    """The area's implementations plus any `compare_with` targets they name."""
    by_id = discovery.by_id()
    selected = [exp for exp in discovery.experiments if exp.area == area]
    for exp in list(selected):
        for target in exp.compare_with:
            other = by_id.get(target)
            if other and other not in selected:
                selected.append(other)
    return selected


def build_comparison(ws: Workspace, store: ResultStore, discovery: Discovery, area: str) -> dict[str, Any]:
    experiments = members(discovery, area)
    evaluation = load_evaluation(ws.experiments / area)
    notes: list[str] = []
    rows = []
    commits: set[str] = set()

    known_ids = {exp.id for exp in discovery.experiments}
    for exp in discovery.experiments:
        for target in exp.compare_with:
            if exp.area == area and target not in known_ids:
                notes.append(f"{exp.id} lists compare_with {target!r}, which does not exist")

    for exp in experiments:
        latest = store.latest(exp.id)
        if latest is None:
            notes.append(f"{exp.id} has no stored results; run `abora-labs check {exp.id}`")
            latest = {}
        commit = _session_commit(store, latest)
        if commit:
            commits.add(commit)
        rows.append(
            {
                "id": exp.id,
                "name": exp.name,
                "language": exp.language,
                "lifecycle": exp.status,
                "safety": exp.safety.level.label,
                "risks": list(exp.safety.risks),
                "updated_at": latest.get("updated_at"),
                "commit": commit,
                "toolchain": _metrics(latest).get("toolchain") or {},
                "startup": _metrics(latest).get("startup"),
                "measured": {metric.key: metric.extract(latest) for metric in METRICS} if latest else {},
                "human": _human(evaluation, exp),
            }
        )
    if len(commits) > 1:
        notes.append("results come from different git commits; re-run `abora-labs compare` for a like-for-like view")
    if evaluation is None:
        notes.append(f"no experiments/{area}/evaluation.toml; the human evaluation section is empty")
    else:
        for name in evaluation.implementations:
            if not any(exp.area == area and exp.implementation == name for exp in experiments):
                notes.append(f"evaluation.toml reviews {name!r}, which is not an implementation in {area}")

    return {
        "area": area,
        "generated_at": now_iso(),
        "question": evaluation.question if evaluation else None,
        "features": list(evaluation.features) if evaluation else [],
        "metrics": [{"key": m.key, "label": m.label, "kind": m.kind} for m in METRICS],
        "implementations": rows,
        "notes": notes,
    }


def _human(evaluation: AreaEvaluation | None, exp: Experiment) -> dict[str, Any] | None:
    if evaluation is None or exp.area != evaluation.path.parent.name:
        return None
    review = evaluation.implementations.get(exp.implementation)
    if review is None:
        return None
    completeness = review.completeness(evaluation.features)
    return {
        "reviewer": review.reviewer,
        "reviewed": review.reviewed,
        "scores": review.scores,
        "features": review.features,
        "completeness": {"points": completeness[0], "of": completeness[1]} if completeness else None,
        "notes": review.notes,
    }


def _session_commit(store: ResultStore, latest: dict[str, Any]) -> str | None:
    sessions = {s.get("session") for s in (latest.get("stages") or {}).values() if s.get("session")}
    if not sessions:
        return None
    newest = max(sessions)
    path = store.out / "sessions" / newest / "session.json"
    try:
        git = json.loads(path.read_text(encoding="utf-8")).get("git") or {}
    except (OSError, json.JSONDecodeError):
        return None
    commit = git.get("commit")
    if not commit:
        return None
    return commit[:10] + ("-dirty" if git.get("dirty") else "")
