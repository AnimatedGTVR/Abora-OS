"""`abora-labs new`: creating areas and implementations from the language pool."""

from __future__ import annotations

import json
from pathlib import Path

from .config import LabsConfig
from .errors import LabsError
from .evaluation import EVALUATION_NAME
from .manifest import MANIFEST_NAME, SLUG
from .safety import LEVEL_NAMES
from .workspace import Workspace


def _toml_string(value: str) -> str:
    return json.dumps(value)  # JSON string escaping is valid TOML basic-string escaping


def create_area(ws: Workspace, area: str) -> list[Path]:
    _check_slug("area", area)
    area_dir = ws.experiments / area
    created = []
    evaluation = area_dir / EVALUATION_NAME
    if not evaluation.exists():
        area_dir.mkdir(parents=True, exist_ok=True)
        evaluation.write_text(
            f"""# Human evaluation for the {area} area. Nothing in this file is measured.
# `abora-labs report {area}` prints it separately from measured metrics.

question = "What should Abora use for {area}?"

# Capabilities every implementation is judged against.
features = []

# One table per implementation directory, e.g.:
# [implementations.go]
# reviewer = "your-name"
# reviewed = 2026-01-31
# scores = {{ maintainability = 3, readability = 4 }}   # 1-5
# features = {{ "some feature" = "done" }}              # done | partial | missing | n/a
# notes = "Free-form observations."
""",
            encoding="utf-8",
        )
        created.append(evaluation)
    return created


def create_implementation(
    ws: Workspace,
    config: LabsConfig,
    area: str,
    implementation: str,
    language: str | None,
    safety: str,
    description: str | None,
) -> list[Path]:
    _check_slug("area", area)
    _check_slug("implementation", implementation)
    language = language or (implementation if implementation in config.languages else None)
    if language is None:
        raise LabsError(
            f"cannot infer a language from implementation name {implementation!r}",
            hint=f"Pass --language. Known languages: {', '.join(config.languages)}",
        )
    if language not in config.languages:
        raise LabsError(f"unknown language {language!r}", hint=f"Known languages: {', '.join(config.languages)}")
    if safety not in LEVEL_NAMES:
        raise LabsError(f"unknown safety level {safety!r}", hint=f"Use one of: {', '.join(LEVEL_NAMES)}")

    directory = ws.experiments / area / implementation
    if (directory / MANIFEST_NAME).exists():
        raise LabsError(f"{ws.relative(directory / MANIFEST_NAME)} already exists")

    created = create_area(ws, area)
    directory.mkdir(parents=True, exist_ok=True)
    manifest = directory / MANIFEST_NAME
    manifest.write_text(_manifest_text(config, area, implementation, language, safety, description), encoding="utf-8")
    created.append(manifest)
    return created


def _manifest_text(config: LabsConfig, area: str, implementation: str, language: str, safety: str, description: str | None) -> str:
    lang = config.languages[language]
    binary = f"{area}-{implementation}"

    def fill(value: object) -> object:
        if isinstance(value, str):
            return value.replace("{name}", binary)
        if isinstance(value, list):
            return [fill(v) for v in value]
        return value

    scaffold = {k: fill(v) for k, v in lang.scaffold.items()}
    lines = [
        f"# Abora Labs experiment: {area} implemented in {lang.display}.",
        "# Reference: docs/labs/manifest.md",
        "",
        f"name = {_toml_string(binary)}",
        f"description = {_toml_string(description or f'TODO: what this {lang.display} {area} implementation tries')}",
        f"area = {_toml_string(area)}",
        f"implementation = {_toml_string(implementation)}",
        f"language = {_toml_string(language)}",
        'status = "idea"',
        '# maintainer = ""',
        "dependencies = []",
        "",
        "[commands]",
    ]
    for stage in ("build", "test", "run", "clean"):
        if stage in scaffold:
            lines.append(f"{stage} = {_toml_string(scaffold[stage])}")
        else:
            lines.append(f"# {stage} = []")
    lines += ["", "[test]"]
    lines.append(f"format = {_toml_string(scaffold['test_format'])}" if "test_format" in scaffold else '# format = "labs"   # go | cargo | tap | labs')
    lines += [
        "",
        "[safety]",
        f"level = {_toml_string(safety)}",
        "# Per-stage levels may be lower than `level`, e.g. build = \"safe\".",
        "risks = []" if safety == "safe" else 'risks = ["TODO: describe what can go wrong"]',
        "",
        "[metrics]",
    ]
    artifacts = [a.replace("{name}", binary) for a in scaffold.get("artifacts", [])]
    lines.append(f"artifacts = {json.dumps(artifacts)}")
    lines.append(f"# startup = {_toml_string(scaffold['run'])}" if "run" in scaffold else '# startup = []')
    return "\n".join(lines) + "\n"


def _check_slug(kind: str, value: str) -> None:
    if not SLUG.match(value):
        raise LabsError(f"{kind} {value!r} must be lowercase letters, digits and dashes")
