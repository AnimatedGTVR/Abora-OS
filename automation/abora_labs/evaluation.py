"""Human evaluation: experiments/<area>/evaluation.toml.

This is where judgement lives (maintainability, feature completeness, notes).
It is never computed and never mixed into the measured metrics; reports print
it in a separate section with the reviewer's name and date.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from pathlib import Path

from .errors import ManifestError
from .tomlread import TableReader, load_toml

EVALUATION_NAME = "evaluation.toml"
FEATURE_STATES = ("done", "partial", "missing", "n/a")
SCORE_RANGE = (1, 5)


@dataclass(frozen=True)
class ImplementationReview:
    implementation: str
    reviewer: str | None
    reviewed: str | None
    scores: dict[str, int]
    features: dict[str, str]
    notes: str | None

    def completeness(self, features: tuple[str, ...]) -> tuple[float, int] | None:
        """(points, applicable features): done=1, partial=0.5, missing=0, n/a excluded."""
        applicable = [f for f in features if self.features.get(f) != "n/a"]
        if not applicable:
            return None
        points = sum({"done": 1.0, "partial": 0.5}.get(self.features.get(f, "missing"), 0.0) for f in applicable)
        return points, len(applicable)


@dataclass(frozen=True)
class AreaEvaluation:
    path: Path
    question: str | None
    features: tuple[str, ...]
    implementations: dict[str, ImplementationReview] = field(default_factory=dict)


def load_evaluation(area_dir: Path) -> AreaEvaluation | None:
    path = area_dir / EVALUATION_NAME
    if not path.is_file():
        return None
    problems: list[str] = []
    top = TableReader(load_toml(path), problems)
    question = top.str("question")
    features = top.str_list("features")
    reviews = {}
    impls = top.table("implementations")
    for name in list(impls.data):
        entry = impls.table(name)
        reviewed = entry.raw("reviewed")
        if isinstance(reviewed, (dt.date, dt.datetime)):
            reviewed = reviewed.isoformat()
        elif reviewed is not None and not isinstance(reviewed, str):
            problems.append(f"`implementations.{name}.reviewed` must be a date")
            reviewed = None
        scores = _scores(entry.raw("scores"), f"implementations.{name}.scores", problems)
        feature_states = _features(entry.raw("features"), features, f"implementations.{name}.features", problems)
        reviews[name] = ImplementationReview(
            implementation=name,
            reviewer=entry.str("reviewer"),
            reviewed=reviewed,
            scores=scores,
            features=feature_states,
            notes=entry.str("notes"),
        )
        entry.reject_unknown()
    top.reject_unknown()
    if problems:
        raise ManifestError(path, problems)
    return AreaEvaluation(path, question, features, reviews)


def _scores(value: object, key: str, problems: list[str]) -> dict[str, int]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        problems.append(f"`{key}` must be a table of name = 1..5")
        return {}
    scores = {}
    low, high = SCORE_RANGE
    for name, score in value.items():
        if isinstance(score, bool) or not isinstance(score, int) or not low <= score <= high:
            problems.append(f"`{key}.{name}` must be an integer from {low} to {high}")
            continue
        scores[name] = score
    return scores


def _features(value: object, declared: tuple[str, ...], key: str, problems: list[str]) -> dict[str, str]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        problems.append(f"`{key}` must be a table of \"feature\" = \"done|partial|missing|n/a\"")
        return {}
    states = {}
    for name, state in value.items():
        if name not in declared:
            problems.append(f"`{key}` mentions {name!r}, which is not in the area's `features` list")
        elif state not in FEATURE_STATES:
            problems.append(f"`{key}.{name}` is {state!r}; expected one of: {', '.join(FEATURE_STATES)}")
        else:
            states[name] = state
    return states
