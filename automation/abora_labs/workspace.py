"""Locating the Labs checkout and its output directory."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .errors import LabsError

MARKER = Path("configs") / "languages.toml"


@dataclass(frozen=True)
class Workspace:
    root: Path
    out: Path

    @property
    def experiments(self) -> Path:
        return self.root / "experiments"

    @property
    def configs(self) -> Path:
        return self.root / "configs"

    def relative(self, path: Path) -> str:
        try:
            return str(path.resolve().relative_to(self.root))
        except ValueError:
            return str(path)

    @classmethod
    def locate(cls, root: str | None = None, out: str | None = None) -> Workspace:
        root_path = _find_root(root or os.environ.get("ABORA_LABS_ROOT"))
        out_value = out or os.environ.get("ABORA_LABS_OUT")
        out_path = Path(out_value).expanduser().resolve() if out_value else root_path / "out" / "labs"
        return cls(root=root_path, out=out_path)


def _find_root(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not (path / MARKER).is_file():
            raise LabsError(
                f"{path} is not an Abora Labs checkout (no {MARKER})",
                hint="Point --root or ABORA_LABS_ROOT at the repository root.",
            )
        return path
    current = Path.cwd().resolve()
    for candidate in (current, *current.parents):
        if (candidate / MARKER).is_file():
            return candidate
    raise LabsError(
        f"could not find an Abora Labs checkout above {current}",
        hint="Run from inside the repository, or use ./abora-labs, --root, or ABORA_LABS_ROOT.",
    )
