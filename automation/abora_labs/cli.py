"""Argument parsing for `abora-labs`. Command behaviour lives in commands.py."""

from __future__ import annotations

import argparse
import sys

from . import __version__, commands
from .errors import EXIT_USAGE, LabsError
from .safety import LEVEL_NAMES
from .ui import UI

TARGET_HELP = "`all`, an area (installer), or one implementation (installer/zig)"


def _common(parser: argparse.ArgumentParser, executes: bool) -> None:
    group = parser.add_argument_group("common options")
    group.add_argument("--root", help="Labs checkout (default: search upward, or $ABORA_LABS_ROOT)")
    group.add_argument("--out", help="results directory (default: <root>/out/labs, or $ABORA_LABS_OUT)")
    color = group.add_mutually_exclusive_group()
    color.add_argument("--color", dest="color", action="store_true", default=None, help="force colored output")
    color.add_argument("--no-color", dest="color", action="store_false", help="disable colored output")
    if executes:
        group.add_argument("-v", "--verbose", action="store_true", help="stream command output while it runs")
        group.add_argument(
            "--allow-privileged",
            action="store_true",
            help="allow stages classified `privileged` to run on this host (vm_only/destructive never run here)",
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="abora-labs",
        description="Create, build, test, compare and report on Abora Labs experiments.",
        epilog="Exit codes: 0 ok, 1 something failed, 2 usage/manifest error, 3 blocked or unavailable.",
    )
    parser.add_argument("--version", action="version", version=f"abora-labs {__version__}")
    sub = parser.add_subparsers(dest="command", metavar="<command>", required=True)

    def add(name: str, help_text: str, handler, executes: bool = False) -> argparse.ArgumentParser:
        p = sub.add_parser(name, help=help_text, description=help_text)
        p.set_defaults(handler=handler)
        _common(p, executes)
        return p

    p = add("list", "list discovered experiments", commands.cmd_list)
    p.add_argument("target", nargs="?", help=TARGET_HELP)

    p = add("status", "show the latest stored result of each experiment", commands.cmd_status)
    p.add_argument("target", nargs="?", help=TARGET_HELP)

    p = add("validate", "check manifests, safety lint, toolchains and evaluations", commands.cmd_validate)
    p.add_argument("target", nargs="?", help=TARGET_HELP)
    p.add_argument("--strict", action="store_true", help="treat warnings as errors")

    p = add("new", "create an area, or an implementation inside an area", commands.cmd_new)
    p.add_argument("target", help="<area> or <area>/<implementation>")
    p.add_argument("--language", help="language key from configs/languages.toml (default: the implementation name)")
    p.add_argument("--safety", default="safe", choices=LEVEL_NAMES, help="overall safety level (default: safe)")
    p.add_argument("--description", help="one-line description")

    for name, help_text in (
        ("build", "run the build stage"),
        ("test", "run the test stage (does not build first; use `check`)"),
        ("clean", "run the clean stage"),
        ("check", "build, test and measure metrics, recorded as one run"),
    ):
        p = add(name, help_text, commands.cmd_stage, executes=True)
        p.add_argument("target", help=TARGET_HELP)

    p = add("run", "run one implementation interactively (output is not captured)", commands.cmd_run, executes=True)
    p.add_argument("target", help="<area>/<implementation>")
    p.add_argument("args", nargs=argparse.REMAINDER, help="arguments passed to the run command (after --)")

    p = add("compare", "check every implementation in an area, then print the comparison", commands.cmd_compare, executes=True)
    p.add_argument("area")
    p.add_argument("--no-run", action="store_true", help="use stored results only (same as `report`)")
    _report_options(p)

    p = add("report", "print a comparison from stored results without running anything", commands.cmd_report)
    p.add_argument("area")
    _report_options(p)

    p = add("logs", "print the newest log of an implementation's stage", commands.cmd_logs)
    p.add_argument("target", help="<area>/<implementation>")
    p.add_argument("--stage", default="build", choices=("build", "test", "clean"), help="stage (default: build)")
    p.add_argument("--path", action="store_true", help="print only the log's path")
    return parser


def _report_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--format", default="text", choices=("text", "markdown", "json"))
    parser.add_argument("--output", help="write the report to this file instead of stdout")


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    args = build_parser().parse_args(argv)
    ui = UI(color=args.color, verbose=getattr(args, "verbose", False))
    try:
        return args.handler(args, ui, argv)
    except LabsError as exc:
        ui.error(exc.message, exc.hint)
        return exc.exit_code
    except KeyboardInterrupt:
        ui.error("interrupted; results recorded so far are kept")
        return 130
    except BrokenPipeError:
        return EXIT_USAGE
