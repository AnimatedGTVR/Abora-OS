"""Stage execution: the order of checks before a command is allowed to run.

For every stage the controller decides, in this order:
  1. is there a command for the stage?          no  -> skipped
  2. does the safety policy allow it here?       no  -> blocked
  3. are the required tools present?             no  -> unavailable
  4. run it, then classify the outcome           -> passed/failed/crashed/timeout/error
Every decision is recorded, including the ones that did not run anything.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

from . import metrics as m
from . import results as r
from .config import LabsConfig
from .manifest import Command, Experiment
from .runner import CommandSpec, Outcome, read_output_lines, run_command
from .safety import host_decision
from .testparsers import PARSERS
from .toolchain import ToolStatus, missing, path_env, resolve_tools, tool_version
from .ui import UI, human_seconds
from .workspace import Workspace

FAILURE_TAIL_LINES = 15


@dataclass
class Options:
    allow_privileged: bool = False
    verbose: bool = False


class Pipeline:
    def __init__(self, ws: Workspace, config: LabsConfig, session: r.Session, ui: UI, options: Options):
        self.ws = ws
        self.config = config
        self.session = session
        self.ui = ui
        self.options = options
        self._tools: dict[str, list[ToolStatus]] = {}

    # -- building blocks ---------------------------------------------------

    def tools(self, exp: Experiment) -> list[ToolStatus]:
        if exp.id not in self._tools:
            self._tools[exp.id] = resolve_tools(exp.requires, self.config)
        return self._tools[exp.id]

    def _spec(self, exp: Experiment, stage: str, command: Command, capture: bool) -> CommandSpec:
        level = exp.safety.for_stage(stage)
        env = dict(os.environ)
        env.update(
            PATH=path_env(self.tools(exp)),
            ABORA_LABS="1",
            ABORA_LABS_ROOT=str(self.ws.root),
            ABORA_LABS_EXPERIMENT=exp.id,
            ABORA_LABS_AREA_DIR=str(exp.directory.parent),
            ABORA_LABS_STAGE=stage,
            ABORA_LABS_SAFETY=level.label,
            ABORA_LABS_SESSION=self.session.id,
        )
        argv = command.to_argv()
        display = command.display
        if exp.nix_shell:
            ref = f"{self.ws.root}{exp.nix_shell}" if exp.nix_shell.startswith("#") else exp.nix_shell
            argv = ["nix", "develop", ref, "--command", *argv]
            display = f"[nix develop {exp.nix_shell}] {display}"
        return CommandSpec(
            argv=argv,
            display=display,
            cwd=exp.directory,
            env=env,
            timeout=exp.timeouts.get(stage, self.config.timeout_seconds),
            capture=capture,
        )

    def _precheck(self, exp: Experiment, stage: str, result: r.StageResult) -> bool:
        """Fill in `result` and return False if the stage must not run."""
        level = exp.safety.for_stage(stage)
        decision = host_decision(level, self.options.allow_privileged)
        if not decision.allowed:
            result.status, result.reason = r.BLOCKED, decision.reason
            return False
        absent = missing(self.tools(exp))
        if absent:
            result.status = r.UNAVAILABLE
            result.reason = "; ".join(t.problem or t.name for t in absent)
            return False
        return True

    # -- stages ------------------------------------------------------------

    def stage(self, exp: Experiment, stage: str, extra_args: tuple[str, ...] = (), capture: bool = True) -> r.StageResult:
        level = exp.safety.for_stage(stage)
        result = r.StageResult(experiment=exp.id, stage=stage, status=r.SKIPPED, safety=level.label)
        command = exp.commands.get(stage)
        if command is None:
            result.reason = f"no `commands.{stage}` in experiment.toml"
        else:
            command = command.with_args(extra_args)
            result.command = command.display
            if self._precheck(exp, stage, result):
                self._execute(exp, stage, command, capture, result)
        self.session.record(result)
        self._report(result)
        return result

    def skip(self, exp: Experiment, stage: str, reason: str) -> r.StageResult:
        result = r.StageResult(
            experiment=exp.id, stage=stage, status=r.SKIPPED, reason=reason, safety=exp.safety.for_stage(stage).label
        )
        self.session.record(result)
        self._report(result)
        return result

    def _execute(self, exp: Experiment, stage: str, command: Command, capture: bool, result: r.StageResult) -> None:
        spec = self._spec(exp, stage, command, capture)
        log_path = self.session.log_path(exp.id, stage) if capture else None
        self.ui.print(self.ui.dim(f"-> {exp.id} {stage}: {spec.display}"))
        echo = self.ui.out if (self.options.verbose and capture) else None
        outcome = run_command(spec, log_path, echo=echo)

        result.duration_s = round(outcome.duration_s, 6)
        result.exit_code = outcome.exit_code
        result.signal = outcome.signal_name
        result.peak_rss_kb = outcome.peak_rss_kb
        if log_path is not None:
            result.log = self.ws.relative(log_path)
        _classify(outcome, result)

        lines = read_output_lines(log_path) if (log_path is not None and log_path.is_file()) else []
        if stage == "build":
            result.warning_lines_heuristic = m.warning_lines_heuristic(lines)
        if stage == "test" and exp.test_format and log_path is not None:
            counts = PARSERS[exp.test_format](lines)
            result.tests = counts.to_dict()
            if result.status == r.PASSED and counts.failed:
                result.status = r.FAILED
                result.reason = f"{counts.failed} test(s) reported FAIL although the command exited 0"
            elif result.status == r.PASSED and counts.total == 0:
                result.reason = f"no tests recognised by the `{exp.test_format}` parser"
        if outcome.leftover_processes:
            extra = "background processes kept the output open and were killed"
            result.reason = f"{result.reason}; {extra}" if result.reason else extra
        if result.status in r.BAD_STATUSES and capture and not self.options.verbose:
            self._print_tail(outcome)

    def check(self, exp: Experiment) -> list[r.StageResult]:
        """build -> test -> metrics, as one recorded unit."""
        build = self.stage(exp, "build")
        build_ok = build.status == r.PASSED or (build.status == r.SKIPPED and "build" not in exp.commands)
        if build_ok:
            test = self.stage(exp, "test")
        else:
            test = self.skip(exp, "test", f"build did not pass ({build.status})")
        self.measure(exp, build_ok)
        return [build, test]

    # -- metrics -----------------------------------------------------------

    def measure(self, exp: Experiment, build_ok: bool) -> dict[str, Any]:
        language = self.config.languages[exp.language]
        data: dict[str, Any] = {
            "language": exp.language,
            "source": m.source_lines(exp.directory, language, self.config.exclude_dirs),
            "dependencies_declared": len(exp.dependencies),
            "toolchain": {t.name: tool_version(t, self.config) for t in self.tools(exp) if t.available},
            "artifacts": m.artifact_sizes(exp.directory, exp.artifacts) if build_ok else None,
            "startup": self._startup(exp, build_ok),
        }
        self.session.record_metrics(exp.id, data)
        return data

    def _startup(self, exp: Experiment, build_ok: bool) -> dict[str, Any] | None:
        if exp.startup is None:
            return None
        probe = r.StageResult(experiment=exp.id, stage="startup", status=r.SKIPPED)
        if not build_ok:
            return {"status": r.SKIPPED, "reason": "build did not pass"}
        if not self._precheck(exp, "startup", probe):
            return {"status": probe.status, "reason": probe.reason}

        spec = self._spec(exp, "startup", exp.startup, capture=True)
        spec.timeout = exp.timeouts.get("startup", 60.0)
        runs = self.config.startup_runs
        self.ui.print(self.ui.dim(f"-> {exp.id} startup x{runs} (+1 warm-up): {spec.display}"))
        samples: list[float] = []
        for index in range(runs + 1):
            outcome = run_command(spec, log_path=None)
            if not outcome.succeeded:
                return {"status": r.FAILED, "reason": f"startup run {index + 1}: {outcome.describe()}"}
            if index > 0:
                samples.append(outcome.duration_s)
        return {"status": r.PASSED, "runs": runs, **m.summarize_timings(samples)}

    # -- output ------------------------------------------------------------

    def _report(self, result: r.StageResult) -> None:
        timing = f" in {human_seconds(result.duration_s)}" if result.duration_s is not None else ""
        tests = ""
        if result.tests and result.tests["total"]:
            tests = f" ({result.tests['passed']}/{result.tests['total']} tests passed)"
        line = f"   {result.experiment} {result.stage}: {self.ui.status(result.status)}{timing}{tests}"
        if result.reason:
            line += self.ui.dim(f" - {result.reason}")
        self.ui.print(line)
        if result.log and result.status in r.BAD_STATUSES:
            self.ui.print(f"   log: {result.log}")

    def _print_tail(self, outcome: Outcome) -> None:
        for line in outcome.tail[-FAILURE_TAIL_LINES:]:
            self.ui.print(self.ui.dim(f"   | {line}"))


def _classify(outcome: Outcome, result: r.StageResult) -> None:
    if outcome.spawn_error:
        result.status, result.reason = r.ERROR, outcome.describe()
    elif outcome.timed_out:
        result.status, result.reason = r.TIMEOUT, outcome.describe()
    elif outcome.crashed:
        result.status, result.reason = r.CRASHED, outcome.describe()
    elif outcome.exit_code != 0:
        result.status, result.reason = r.FAILED, outcome.describe()
    else:
        result.status = r.PASSED
