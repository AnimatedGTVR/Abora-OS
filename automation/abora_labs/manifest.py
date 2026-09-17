"""experiment.toml: the per-implementation manifest.

Reference: docs/labs/manifest.md. The file lives at
experiments/<area>/<implementation>/experiment.toml and the `area` and
`implementation` keys must match those directory names, so the path and the
metadata can never silently disagree.
"""

from __future__ import annotations

import json
import re
import shlex
from dataclasses import dataclass, field
from pathlib import Path

from .config import LabsConfig
from .errors import ManifestError
from .safety import LEVEL_NAMES, STAGES, Level
from .testparsers import PARSERS
from .tomlread import TableReader, load_toml

MANIFEST_NAME = "experiment.toml"
STATUSES = ("idea", "experimental", "promising", "candidate", "rejected", "archived")
SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")
TARGET = re.compile(r"^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*$")


@dataclass(frozen=True)
class Command:
    """An argv list (exec'd directly, preferred) or a shell string (run with `sh -c`).

    Shell is no longer Abora's primary language: it is easy to break and hard to
    make safe. String commands still work, but `validate` warns about them."""

    argv: tuple[str, ...]
    shell: bool = False

    @property
    def display(self) -> str:
        return self.argv[0] if self.shell else shlex.join(self.argv)

    def with_args(self, args: tuple[str, ...]) -> Command:
        if not args:
            return self
        if self.shell:
            return Command((f"{self.argv[0]} {shlex.join(args)}",), shell=True)
        return Command(self.argv + args)

    def to_argv(self) -> list[str]:
        return ["sh", "-c", self.argv[0]] if self.shell else list(self.argv)


@dataclass(frozen=True)
class SafetyProfile:
    level: Level
    stage_levels: dict[str, Level]
    risks: tuple[str, ...]
    acknowledge: tuple[str, ...]

    def for_stage(self, stage: str) -> Level:
        if stage == "startup":
            stage = "run"
        return self.stage_levels.get(stage, self.level)


@dataclass(frozen=True)
class Experiment:
    directory: Path
    name: str
    description: str
    area: str
    implementation: str
    language: str
    status: str
    maintainer: str | None
    requires: tuple[str, ...]
    dependencies: tuple[str, ...]
    compare_with: tuple[str, ...]
    nix_shell: str | None
    commands: dict[str, Command]
    test_format: str | None
    safety: SafetyProfile
    artifacts: tuple[str, ...]
    startup: Command | None
    timeouts: dict[str, float] = field(default_factory=dict)

    @property
    def id(self) -> str:
        return f"{self.area}/{self.implementation}"

    @property
    def manifest_path(self) -> Path:
        return self.directory / MANIFEST_NAME


def _command(value: object, key: str, problems: list[str]) -> Command | None:
    if value is None:
        return None
    if isinstance(value, list) and value and all(isinstance(v, str) and v for v in value):
        return Command(tuple(value))
    if isinstance(value, str) and value.strip():
        return Command((value,), shell=True)
    problems.append(f"`{key}` must be a non-empty list of strings (argv, preferred) or a shell string")
    return None


def argv_suggestion(command: Command, stage: str) -> str:
    """An argv list to use instead of a shell string, for warning messages."""
    value = command.argv[0]
    return json.dumps(shlex.split(value) if _splittable(value) else ["make", stage])


def _splittable(value: str) -> bool:
    try:
        words = shlex.split(value)
    except ValueError:
        return False
    return bool(words) and not any(w in {"&&", "||", "|", ";", ">", "<", ">>"} or w.startswith(("<", ">")) for w in words)


def load_manifest(path: Path, config: LabsConfig) -> Experiment:
    problems: list[str] = []
    top = TableReader(load_toml(path), problems)
    directory = path.parent

    name = top.str("name", required=True) or ""
    description = top.str("description", required=True) or ""
    area = top.str("area", required=True) or ""
    implementation = top.str("implementation", required=True) or ""
    language = top.str("language", required=True) or ""
    status = top.choice("status", STATUSES, required=True) or "experimental"
    maintainer = top.str("maintainer")
    requires = top.str_list("requires")
    dependencies = top.str_list("dependencies")
    compare_with = top.str_list("compare_with")
    nix_shell = top.str("nix_shell")

    for key, value in (("name", name), ("area", area), ("implementation", implementation)):
        if value and not SLUG.match(value):
            problems.append(f"`{key}` {value!r} must be lowercase letters, digits and dashes")
    if area and area != directory.parent.name:
        problems.append(f"`area` is {area!r} but the manifest is under experiments/{directory.parent.name}/")
    if implementation and implementation != directory.name:
        problems.append(f"`implementation` is {implementation!r} but the directory is named {directory.name!r}")
    if language and language not in config.languages:
        problems.append(f"`language` {language!r} is not in configs/languages.toml ({', '.join(config.languages)})")
    for target in compare_with:
        if not TARGET.match(target):
            problems.append(f"`compare_with` entry {target!r} must look like <area>/<implementation>")

    commands_table = top.table("commands")
    commands = {}
    for stage in STAGES:
        command = _command(commands_table.raw(stage), f"commands.{stage}", problems)
        if command:
            commands[stage] = command
    commands_table.reject_unknown()

    test_table = top.table("test")
    test_format = test_table.choice("format", tuple(PARSERS))
    test_table.reject_unknown()

    safety = _safety(top.table("safety"), problems)

    metrics_table = top.table("metrics")
    artifacts = metrics_table.str_list("artifacts")
    startup = _command(metrics_table.raw("startup"), "metrics.startup", problems)
    metrics_table.reject_unknown()

    timeouts_table = top.table("timeouts")
    timeouts = {}
    for stage in (*STAGES, "startup"):
        value = timeouts_table.number(stage)
        if value is not None:
            timeouts[stage] = value
    timeouts_table.reject_unknown()

    top.reject_unknown()
    if problems:
        raise ManifestError(path, problems)

    if not requires and language in config.languages:
        requires = config.languages[language].requires
    if nix_shell and "nix" not in requires:
        requires = (*requires, "nix")

    return Experiment(
        directory=directory,
        name=name,
        description=description,
        area=area,
        implementation=implementation,
        language=language,
        status=status,
        maintainer=maintainer,
        requires=requires,
        dependencies=dependencies,
        compare_with=compare_with,
        nix_shell=nix_shell,
        commands=commands,
        test_format=test_format,
        safety=safety,
        artifacts=artifacts,
        startup=startup,
        timeouts=timeouts,
    )


def _safety(table: TableReader, problems: list[str]) -> SafetyProfile:
    level_name = table.choice("level", LEVEL_NAMES, required=True)
    level = Level.parse(level_name) if level_name else Level.DESTRUCTIVE
    stage_levels = {}
    for stage in STAGES:
        stage_name = table.choice(stage, LEVEL_NAMES)
        if stage_name is None:
            continue
        stage_level = Level.parse(stage_name)
        if stage_level > level:
            problems.append(
                f"`safety.{stage}` is {stage_level.label} but the overall `safety.level` is "
                f"{level.label}; the overall level must be the most dangerous stage"
            )
        stage_levels[stage] = stage_level
    risks = table.str_list("risks")
    acknowledge = table.str_list("acknowledge")
    table.reject_unknown()
    if level > Level.SAFE and not risks:
        problems.append(f"`safety.level` is {level.label}; list what can go wrong in `safety.risks`")
    return SafetyProfile(level, stage_levels, risks, acknowledge)
