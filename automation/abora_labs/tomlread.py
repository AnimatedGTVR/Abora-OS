"""Strict TOML loading.

Manifests are hand-written, so typos must be loud: unknown keys are errors,
wrong types are errors, and every problem in a file is collected before
failing so one run shows all of them.
"""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

from .errors import ManifestError


def load_toml(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError:
        raise ManifestError(path, ["file does not exist"]) from None
    except tomllib.TOMLDecodeError as exc:
        raise ManifestError(path, [f"TOML syntax error: {exc}"]) from None


class TableReader:
    """Reads typed values from one TOML table, recording problems instead of raising."""

    def __init__(self, data: dict[str, Any], problems: list[str], prefix: str = ""):
        self.data = data
        self.problems = problems
        self.prefix = prefix
        self.seen: set[str] = set()

    def _key(self, key: str) -> str:
        return f"{self.prefix}{key}"

    def _get(self, key: str, required: bool) -> Any:
        self.seen.add(key)
        if key not in self.data:
            if required:
                self.problems.append(f"missing required key `{self._key(key)}`")
            return None
        return self.data[key]

    def str(self, key: str, required: bool = False, default: str | None = None) -> str | None:
        value = self._get(key, required)
        if value is None:
            return default
        if not isinstance(value, str) or (required and not value.strip()):
            self.problems.append(f"`{self._key(key)}` must be a non-empty string")
            return default
        return value

    def choice(self, key: str, choices: tuple[str, ...], required: bool = False) -> str | None:
        value = self.str(key, required)
        if value is not None and value not in choices:
            self.problems.append(
                f"`{self._key(key)}` is {value!r}; expected one of: {', '.join(choices)}"
            )
            return None
        return value

    def str_list(self, key: str) -> tuple[str, ...]:
        value = self._get(key, False)
        if value is None:
            return ()
        if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
            self.problems.append(f"`{self._key(key)}` must be a list of strings")
            return ()
        return tuple(value)

    def number(self, key: str, default: float | None = None, minimum: float = 0) -> float | None:
        value = self._get(key, False)
        if value is None:
            return default
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= minimum:
            self.problems.append(f"`{self._key(key)}` must be a number greater than {minimum}")
            return default
        return float(value)

    def table(self, key: str) -> TableReader:
        value = self._get(key, False)
        if value is None:
            value = {}
        elif not isinstance(value, dict):
            self.problems.append(f"`{self._key(key)}` must be a table")
            value = {}
        return TableReader(value, self.problems, prefix=f"{self._key(key)}.")

    def raw(self, key: str) -> Any:
        return self._get(key, False)

    def reject_unknown(self) -> None:
        for key in self.data:
            if key not in self.seen:
                self.problems.append(f"unknown key `{self._key(key)}`")


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged
