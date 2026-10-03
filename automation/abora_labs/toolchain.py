"""Resolving the tools an experiment needs, before anything runs.

Lookup order for a tool named `vanta`:
  1. ABORA_LABS_TOOL_VANTA environment variable
  2. [tools.vanta] path in configs/labs.toml / labs.local.toml
  3. `vanta` on PATH
A missing tool makes the experiment "unavailable" rather than "failed".
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .config import LabsConfig


@dataclass(frozen=True)
class ToolStatus:
    name: str
    path: Path | None
    source: str  # "env", "config", "PATH", or "missing"
    problem: str | None = None

    @property
    def available(self) -> bool:
        return self.path is not None


def _env_name(tool: str) -> str:
    return "ABORA_LABS_TOOL_" + re.sub(r"[^A-Za-z0-9]", "_", tool).upper()


def resolve_tool(name: str, config: LabsConfig) -> ToolStatus:
    env_value = os.environ.get(_env_name(name))
    if env_value:
        return _check_explicit(name, Path(env_value).expanduser(), "env", f"${_env_name(name)}")
    configured = config.tool(name).path
    if configured is not None:
        return _check_explicit(name, configured, "config", f"[tools.{name}] path")
    found = shutil.which(name)
    if found:
        return ToolStatus(name, Path(found), "PATH")
    return ToolStatus(
        name,
        None,
        "missing",
        f"`{name}` not found on PATH; install it, enter a Nix shell that provides it, "
        f"or set [tools.{name}] path in configs/labs.local.toml",
    )


def _check_explicit(name: str, path: Path, source: str, origin: str) -> ToolStatus:
    if path.is_file() and os.access(path, os.X_OK):
        return ToolStatus(name, path.resolve(), source)
    return ToolStatus(name, None, "missing", f"{origin} points at {path}, which is not an executable file")


def resolve_tools(names: tuple[str, ...], config: LabsConfig) -> list[ToolStatus]:
    return [resolve_tool(name, config) for name in names]


def missing(statuses: list[ToolStatus]) -> list[ToolStatus]:
    return [status for status in statuses if not status.available]


def path_env(statuses: list[ToolStatus], base: str | None = None) -> str:
    """PATH with the directories of explicitly configured tools first."""
    base = os.environ.get("PATH", "") if base is None else base
    extra = []
    for status in statuses:
        if status.path is not None and status.source in ("env", "config"):
            directory = str(status.path.parent)
            if directory not in extra:
                extra.append(directory)
    return os.pathsep.join([*extra, base]) if extra else base


def tool_version(status: ToolStatus, config: LabsConfig) -> str | None:
    if status.path is None:
        return None
    args = config.tool(status.name).version_args
    try:
        completed = subprocess.run(
            [str(status.path), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    for line in completed.stdout.decode("utf-8", "replace").splitlines():
        if line.strip():
            return line.strip()[:160]
    return None
