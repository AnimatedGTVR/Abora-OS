"""Finding experiments on disk and resolving command-line targets.

Layout contract: experiments/<area>/<implementation>/experiment.toml.
Nothing is hardcoded; adding a directory with a manifest adds an experiment.
Broken manifests are collected, not fatal, so `list` and `validate` can
still show everything else.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .config import LabsConfig
from .errors import LabsError, ManifestError
from .manifest import MANIFEST_NAME, Experiment, load_manifest
from .workspace import Workspace


@dataclass
class Discovery:
    experiments: list[Experiment] = field(default_factory=list)
    invalid: list[ManifestError] = field(default_factory=list)

    def by_id(self) -> dict[str, Experiment]:
        return {exp.id: exp for exp in self.experiments}

    def areas(self) -> list[str]:
        return sorted({exp.area for exp in self.experiments})


def discover(ws: Workspace, config: LabsConfig) -> Discovery:
    result = Discovery()
    if not ws.experiments.is_dir():
        return result
    for path in sorted(ws.experiments.rglob(MANIFEST_NAME)):
        depth = len(path.relative_to(ws.experiments).parts)
        if depth != 3:
            result.invalid.append(
                ManifestError(path, ["manifests must live at experiments/<area>/<implementation>/experiment.toml"])
            )
            continue
        try:
            result.experiments.append(load_manifest(path, config))
        except ManifestError as exc:
            result.invalid.append(exc)

    names: dict[str, str] = {}
    for exp in result.experiments:
        if exp.name in names:
            result.invalid.append(
                ManifestError(exp.manifest_path, [f"`name` {exp.name!r} is already used by {names[exp.name]}"])
            )
        names.setdefault(exp.name, exp.id)
    return result


def select(ws: Workspace, discovery: Discovery, target: str | None) -> list[Experiment]:
    """Resolve `all`/None, `<area>`, or `<area>/<implementation>` to experiments."""
    if target in (None, "all"):
        return list(discovery.experiments)

    target = target.strip("/")
    for error in discovery.invalid:
        rel = ws.relative(error.path.parent)
        if rel == f"experiments/{target}" or rel.startswith(f"experiments/{target}/"):
            raise error

    if "/" in target:
        exp = discovery.by_id().get(target)
        if exp:
            return [exp]
    else:
        matches = [exp for exp in discovery.experiments if exp.area == target]
        if matches:
            return matches

    known = ", ".join(discovery.areas()) or "none yet"
    raise LabsError(
        f"no experiment matches {target!r}",
        hint=f"Targets are <area> or <area>/<implementation>. Known areas: {known}. "
        "Create one with `abora-labs new <area>/<implementation>`.",
    )
