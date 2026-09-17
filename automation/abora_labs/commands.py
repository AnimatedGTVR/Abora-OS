"""Command handlers. Each returns a process exit code."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

from . import results as r
from .comparison import build_comparison, members
from .config import LabsConfig, load_config
from .discovery import Discovery, discover, select
from .errors import EXIT_FAILED, EXIT_NOT_RUN, EXIT_OK, EXIT_USAGE, LabsError
from .manifest import Experiment
from .pipeline import Options, Pipeline
from .render import render
from .scaffold import create_area, create_implementation
from .toolchain import missing, resolve_tools
from .ui import UI
from .validation import ERROR, validate
from .workspace import Workspace


@dataclass
class Context:
    ws: Workspace
    config: LabsConfig
    discovery: Discovery
    store: r.ResultStore


def _context(args: argparse.Namespace) -> Context:
    ws = Workspace.locate(args.root, args.out)
    config = load_config(ws)
    return Context(ws, config, discover(ws, config), r.ResultStore(ws))


def _exit_code(results: list[r.StageResult]) -> int:
    statuses = {res.status for res in results}
    if statuses & r.BAD_STATUSES:
        return EXIT_FAILED
    if statuses & r.NOT_RUN_STATUSES:
        return EXIT_NOT_RUN
    return EXIT_OK


def _warn_invalid(ctx: Context, ui: UI) -> None:
    if ctx.discovery.invalid:
        ui.warn(f"{len(ctx.discovery.invalid)} invalid manifest(s) ignored; run `abora-labs validate` for details")


# -- read-only commands -----------------------------------------------------


def cmd_list(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    experiments = select(ctx.ws, ctx.discovery, args.target)
    rows = []
    for exp in experiments:
        absent = missing(resolve_tools(exp.requires, ctx.config))
        tools = "ok" if not absent else ui.status(r.UNAVAILABLE) + " (" + ", ".join(t.name for t in absent) + ")"
        rows.append([exp.id, ctx.config.languages[exp.language].display, exp.status, exp.safety.level.label, tools])
    if args.target in (None, "all"):
        for error in ctx.discovery.invalid:
            rows.append([ctx.ws.relative(error.path.parent), "?", ui.status("invalid"), "?", "-"])
    if not rows:
        ui.print("No experiments yet. Create one with `abora-labs new <area>/<implementation>`.")
        return EXIT_OK
    ui.table(["EXPERIMENT", "LANGUAGE", "STATUS", "SAFETY", "TOOLCHAIN"], rows)
    return EXIT_OK


def cmd_status(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    experiments = select(ctx.ws, ctx.discovery, args.target)
    rows = []
    for exp in experiments:
        latest = ctx.store.latest(exp.id) or {}
        stages = latest.get("stages") or {}
        build = stages.get("build", {}).get("status")
        test = stages.get("test") or {}
        tests = test.get("tests")
        rows.append(
            [
                exp.id,
                ui.status(build) if build else "-",
                ui.status(test["status"]) if test else "-",
                f"{tests['passed']}/{tests['total']}" if tests else "-",
                latest.get("updated_at") or "never",
            ]
        )
    if not rows:
        ui.print("No experiments found.")
        return EXIT_OK
    ui.table(["EXPERIMENT", "BUILD", "TEST", "TESTS", "UPDATED"], rows)
    _warn_invalid(ctx, ui)
    return EXIT_OK


def cmd_validate(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    whole = args.target in (None, "all")
    experiments = select(ctx.ws, ctx.discovery, args.target)
    problems = validate(ctx.ws, ctx.config, ctx.discovery, experiments, include_invalid=whole)
    errors = [p for p in problems if p.severity == ERROR]
    warnings = [p for p in problems if p.severity != ERROR]
    for problem in problems:
        tag = ui.style(problem.severity, "31" if problem.severity == ERROR else "33")
        ui.print(f"{tag} {problem.where}: {problem.message}")
    ui.print(f"{len(experiments)} experiment(s) checked: {len(errors)} error(s), {len(warnings)} warning(s)")
    if errors or (args.strict and warnings):
        return EXIT_USAGE
    return EXIT_OK


def cmd_new(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ws = Workspace.locate(args.root, args.out)
    config = load_config(ws)
    parts = args.target.strip("/").split("/")
    if len(parts) == 1:
        created = create_area(ws, parts[0])
    elif len(parts) == 2:
        created = create_implementation(ws, config, parts[0], parts[1], args.language, args.safety, args.description)
    else:
        raise LabsError(f"{args.target!r} is not <area> or <area>/<implementation>")
    if not created:
        ui.print(f"experiments/{parts[0]} already exists; nothing created")
    for path in created:
        ui.print(f"created {ws.relative(path)}")
    if len(parts) == 2:
        ui.print(f"next: add sources, edit the manifest, then `abora-labs validate {args.target}`")
    return EXIT_OK


def cmd_report(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    _require_area(ctx, args.area)
    _emit_report(ctx, ui, args, build_comparison(ctx.ws, ctx.store, ctx.discovery, args.area))
    return EXIT_OK


def cmd_logs(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    exp = _single(ctx, args.target)
    stage = ((ctx.store.latest(exp.id) or {}).get("stages") or {}).get(args.stage)
    if not stage or not stage.get("log"):
        raise LabsError(
            f"no stored {args.stage} log for {exp.id}",
            hint=f"Run `abora-labs {args.stage if args.stage != 'test' else 'check'} {exp.id}` first.",
        )
    path = ctx.ws.root / stage["log"]
    if args.path:
        ui.print(str(path))
        return EXIT_OK
    if not path.is_file():
        raise LabsError(f"log file {path} is gone", hint="Results under out/ may have been cleaned.")
    ui.out.write(path.read_text(encoding="utf-8", errors="replace"))
    return EXIT_OK


# -- executing commands -----------------------------------------------------


def _preflight(ctx: Context, experiments: list[Experiment]) -> None:
    """Refuse to execute experiments whose manifest or safety lint has errors."""
    problems = [p for p in validate(ctx.ws, ctx.config, ctx.discovery, experiments, include_invalid=False) if p.severity == ERROR]
    if problems:
        details = "\n".join(f"  - {p.where}: {p.message}" for p in problems)
        raise LabsError(f"refusing to run; validation errors:\n{details}", hint="Fix these, then re-run.")


def _pipeline(ctx: Context, args: argparse.Namespace, ui: UI, argv: list[str]) -> tuple[Pipeline, r.Session]:
    session = ctx.store.start_session(["abora-labs", *argv])
    options = Options(allow_privileged=args.allow_privileged, verbose=args.verbose)
    return Pipeline(ctx.ws, ctx.config, session, ui, options), session


def cmd_stage(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    experiments = select(ctx.ws, ctx.discovery, args.target)
    _preflight(ctx, experiments)
    pipeline, session = _pipeline(ctx, args, ui, argv)
    collected: list[r.StageResult] = []
    try:
        for exp in experiments:
            if args.command == "check":
                collected += pipeline.check(exp)
            else:
                collected.append(pipeline.stage(exp, args.command))
    finally:
        session.finish()
    _summary(ui, session, collected)
    return _exit_code(collected)


def cmd_run(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    exp = _single(ctx, args.target)
    _preflight(ctx, [exp])
    extra = tuple(args.args[1:] if args.args[:1] == ["--"] else args.args)
    pipeline, session = _pipeline(ctx, args, ui, argv)
    try:
        result = pipeline.stage(exp, "run", extra_args=extra, capture=False)
    finally:
        session.finish()
    return _exit_code([result])


def cmd_compare(args: argparse.Namespace, ui: UI, argv: list[str]) -> int:
    ctx = _context(args)
    _require_area(ctx, args.area)
    code = EXIT_OK
    if not args.no_run:
        experiments = members(ctx.discovery, args.area)
        _preflight(ctx, experiments)
        pipeline, session = _pipeline(ctx, args, ui, argv)
        collected: list[r.StageResult] = []
        try:
            for exp in experiments:
                collected += pipeline.check(exp)
        finally:
            session.finish()
        _summary(ui, session, collected)
        code = _exit_code(collected)
        ui.print()
    comparison = build_comparison(ctx.ws, ctx.store, ctx.discovery, args.area)
    if not args.no_run:
        (session.directory / "comparison.json").write_text(json.dumps(comparison, indent=2) + "\n", encoding="utf-8")
    _emit_report(ctx, ui, args, comparison)
    return code


# -- helpers ----------------------------------------------------------------


def _single(ctx: Context, target: str) -> Experiment:
    if "/" not in target:
        raise LabsError(f"{target!r} names an area; this command needs one implementation", hint="Use <area>/<implementation>.")
    return select(ctx.ws, ctx.discovery, target)[0]


def _require_area(ctx: Context, area: str) -> None:
    if "/" in area:
        raise LabsError(f"{area!r} is an implementation; compare and report take an area", hint=f"Try `{area.split('/')[0]}`.")
    select(ctx.ws, ctx.discovery, area)


def _emit_report(ctx: Context, ui: UI, args: argparse.Namespace, comparison: dict) -> None:
    text = render(comparison, args.format)
    if args.output:
        path = Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        ui.print(f"report written to {path}")
    else:
        ui.out.write(text)


def _summary(ui: UI, session: r.Session, collected: list[r.StageResult]) -> None:
    counts: dict[str, int] = {}
    for result in collected:
        counts[result.status] = counts.get(result.status, 0) + 1
    summary = ", ".join(f"{n} {ui.status(status)}" for status, n in sorted(counts.items()))
    ui.print()
    ui.print(f"session {session.id}: {summary or 'nothing ran'}")
    ui.print(ui.dim(f"results: {session.directory}"))
