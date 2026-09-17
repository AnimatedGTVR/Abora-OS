"""`abora-labs validate`: everything that can be checked without running experiments."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .config import LabsConfig
from .discovery import Discovery
from .errors import LabsError
from .evaluation import load_evaluation
from .manifest import Experiment, argv_suggestion
from .safety import STAGES, lint_text
from .toolchain import missing, resolve_tools
from .workspace import Workspace

ERROR = "error"
WARNING = "warning"
SCRIPT_NAMES = ("Makefile", "GNUmakefile", "justfile")
SHELL_SUFFIXES = (".sh", ".bash", ".zsh", ".fish")
SCRIPT_SUFFIXES = (*SHELL_SUFFIXES, ".mk")


@dataclass(frozen=True)
class Problem:
    severity: str
    where: str
    message: str


def validate(ws: Workspace, config: LabsConfig, discovery: Discovery, experiments: list[Experiment], include_invalid: bool) -> list[Problem]:
    problems: list[Problem] = []
    if include_invalid:
        for error in discovery.invalid:
            for text in error.problems:
                problems.append(Problem(ERROR, ws.relative(error.path), text))

    known = discovery.by_id()
    for exp in experiments:
        where = ws.relative(exp.manifest_path)
        problems += _lint_commands(exp, where)
        problems += _lint_scripts(ws, config, exp)
        for status in missing(resolve_tools(exp.requires, config)):
            problems.append(Problem(WARNING, where, f"toolchain unavailable on this machine: {status.problem}"))
        for target in exp.compare_with:
            if target not in known:
                problems.append(Problem(ERROR, where, f"compare_with {target!r} does not match any experiment"))
        if "test" not in exp.commands:
            problems.append(Problem(WARNING, where, "no `commands.test`; comparisons will have no test results"))
        if exp.startup is None and exp.language not in ("sql", "make"):
            problems.append(Problem(WARNING, where, "no `metrics.startup`; startup time will not be measured"))

    for area in sorted({exp.area for exp in experiments}):
        try:
            load_evaluation(ws.experiments / area)
        except LabsError as exc:
            problems.append(Problem(ERROR, f"experiments/{area}/evaluation.toml", exc.message))
    return problems


def _lint_commands(exp: Experiment, where: str) -> list[Problem]:
    problems = []
    checks = [(stage, exp.commands.get(stage)) for stage in STAGES] + [("startup", exp.startup)]
    for stage, command in checks:
        if command is None:
            continue
        if command.shell:
            problems.append(
                Problem(
                    WARNING,
                    where,
                    f"`{stage}` is a shell string; prefer an argv list (e.g. {argv_suggestion(command, stage)}) "
                    "and move pipes, redirects or `&&` chains into a Makefile or the build tool",
                )
            )
        level = exp.safety.for_stage(stage)
        text = " ".join(command.argv)
        for finding in lint_text(text, where, exp.safety.acknowledge):
            if finding.rule.level > level:
                problems.append(
                    Problem(
                        ERROR,
                        where,
                        f"`{stage}` is declared {level.label} but its command {finding.rule.description} "
                        f"(rule `{finding.rule.id}`, needs {finding.rule.level.label}): {finding.excerpt}. "
                        f"Raise the stage's safety level, or add \"{finding.rule.id}\" to safety.acknowledge "
                        "if this is a false positive.",
                    )
                )
    return problems


def _lint_scripts(ws: Workspace, config: LabsConfig, exp: Experiment) -> list[Problem]:
    problems = []
    for path in _script_files(exp.directory, config.exclude_dirs):
        if path.name.endswith(SHELL_SUFFIXES):
            problems.append(
                Problem(
                    WARNING,
                    ws.relative(path),
                    "shell script: shell is no longer Abora's primary language; prefer a Makefile or a language from configs/languages.toml",
                )
            )
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            problems.append(Problem(WARNING, ws.relative(path), f"could not read for safety lint: {exc}"))
            continue
        for finding in lint_text(text, ws.relative(path), exp.safety.acknowledge):
            if finding.rule.level > exp.safety.level:
                problems.append(
                    Problem(
                        WARNING,
                        ws.relative(path),
                        f"script {finding.rule.description} (rule `{finding.rule.id}`) but {exp.id} is "
                        f"classified {exp.safety.level.label}: {finding.excerpt}",
                    )
                )
    return problems


def _script_files(directory: Path, exclude_dirs: tuple[str, ...]) -> list[Path]:
    found = []
    for current, dirnames, filenames in os.walk(directory):
        dirnames[:] = sorted(d for d in dirnames if d not in exclude_dirs and not d.startswith("."))
        for filename in sorted(filenames):
            if filename in SCRIPT_NAMES or filename.endswith(SCRIPT_SUFFIXES):
                found.append(Path(current) / filename)
    return found
