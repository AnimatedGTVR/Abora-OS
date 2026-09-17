#!/usr/bin/env python3
"""Glob-based repo sweep, independent of check-scripts.py's hardcoded file lists.

Walks every .sh, .nix, .py, .md, .yml/.yaml, .json/.jsonc and .desktop file
actually on disk (skipping out/, .git/, vendor/ and the TinyPM/ submodule --
like vendor/, third-party-shaped with its own conventions and CI) and
validates each by type, plus every extensionless-but-shebanged shell script
(e.g. tools/moducpp-anix), every wallpaper theme .conf (sourced as shell), and
every ANIX v2 source file (.anix/.mko/.moducpp) via `anix diff-plan`, so a new
file that nobody registered anywhere still gets checked.

Usage:
  check-all-files.py                     run the sweep
  check-all-files.py --list-files EXT [ROOT]
                                         print the files the sweep would visit for one
                                         extension (used by check-scripts.py's tests)

Exit status: 1 on any failure or elevated warning ([warn+]), else 0.
"""

from __future__ import annotations

import json
import os
import py_compile
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from abora_release import repo_root

PRUNE_PATHS = ("out", ".git", "vendor", "TinyPM")  # only at the repo root
PRUNE_NAMES = ("obj", "bin", "target")  # at any depth: C#/Rust build output git ignores
GREP_EXCLUDE_DIRS = ("out", ".git", "vendor", "TinyPM")
SHEBANG_SHELL = re.compile(rb"^#! ?/.*\b(bash|sh)$")
MD_LINK = re.compile(r"\]\([^)]+\)")
HEADING = re.compile(r"^#+\s")
FENCE_OPEN = re.compile(r"^```(sh|bash|nix)\s*$")
SOURCE_ONLY_MARKER = "Source this file; do not execute it directly"


def find_files(root: Path, ext: str) -> list[str]:
    """Regular files named *.ext, excluding generated output, git internals and vendored code.

    Build directories named obj/bin/target are pruned at any depth: each C# project under
    tools/ ignores them through its own .gitignore, which a filesystem walk can't see, and a
    stale or interrupted build could otherwise leave broken generated JSON to be "checked"."""
    return sorted(_walk(root, lambda path: path.name.endswith(f".{ext}")))


def find_shebang_scripts(root: Path) -> list[str]:
    """Executable files with no extension but a bash/sh shebang, like tools/moducpp-anix."""

    def is_shell_script(path: Path) -> bool:
        if "." in path.name or not os.access(path, os.X_OK):
            return False
        try:
            with path.open("rb") as handle:
                head = handle.read(64)
        except OSError:
            return False
        return any(SHEBANG_SHELL.search(line) for line in head.split(b"\n"))

    return sorted(_walk(root, is_shell_script))


def _walk(root: Path, wanted) -> list[str]:
    found = []
    for current, dirnames, filenames in os.walk(root):
        relative = Path(current).relative_to(root)
        dirnames[:] = [
            d for d in dirnames
            if d not in PRUNE_NAMES and not (relative == Path(".") and d in PRUNE_PATHS)
        ]
        for filename in filenames:
            path = Path(current) / filename
            if not path.is_symlink() and path.is_file() and wanted(path):
                found.append((relative / filename).as_posix())
    return found


class Sweep:
    def __init__(self, root: Path):
        self.root = root
        color = sys.stdout.isatty() and not os.environ.get("NO_COLOR") and os.environ.get("TERM") != "dumb"
        codes = {
            "green": "\033[38;5;77m", "red": "\033[38;5;203m", "yellow": "\033[38;5;222m",
            "orange": "\033[38;5;208m", "dim": "\033[38;5;242m", "cyan": "\033[38;5;44m",
            "bold": "\033[1m", "nc": "\033[0m",
        }
        self.c = codes if color else dict.fromkeys(codes, "")
        self.failed = self.warned = self.elevated = False
        self.counts = dict.fromkeys(("sh", "nix", "py", "md", "orphan", "anix", "yaml", "json", "desktop", "conf", "anix_skipped"), 0)
        self.has = {tool: shutil.which(tool) is not None for tool in ("shellcheck", "nix-instantiate", "jq", "dotnet")}
        self.plan_tool: Path | None = None
        self.yaml = _load_yaml()

    # ── output ──
    def out(self, text: str) -> None:
        print(text, flush=True)

    def ok(self, message: str) -> None:
        self.out(f"{self.c['green']}[ok]{self.c['nc']}   {message}")

    def fail(self, message: str) -> None:
        self.out(f"{self.c['red']}[fail]{self.c['nc']} {message}")
        self.failed = True

    def warn(self, message: str) -> None:
        """Printed and tallied, never stops the run: conventions with legitimate exceptions."""
        self.out(f"{self.c['yellow']}[warn]{self.c['nc']} {message}")
        self.warned = True

    def warn_elevated(self, message: str) -> None:
        """A real static-analysis finding: syntactically fine, but blocks the run like a failure."""
        self.out(f"{self.c['orange']}[warn+]{self.c['nc']} {message}")
        self.warned = self.elevated = True

    def dim(self, message: str) -> None:
        self.out(f"{self.c['dim']}{message}{self.c['nc']}")

    def section(self, title: str) -> None:
        self.out(f"\n{self.c['bold']}{self.c['cyan']}{title}{self.c['nc']}")

    def indented(self, text: str) -> None:
        for line in text.splitlines():
            self.out(f"    {line}")

    # ── helpers ──
    def run(self, argv: list[str], **kwargs) -> subprocess.CompletedProcess:
        return subprocess.run(argv, cwd=self.root, capture_output=True, text=True, **kwargs)

    def bash_parses(self, path: Path | str) -> bool:
        return self.run(["bash", "-n", str(path)]).returncode == 0

    def text(self, file: str) -> str:
        return (self.root / file).read_text(encoding="utf-8", errors="replace")

    # ── plan tool ──
    def build_plan_tool(self) -> None:
        """`anix diff-plan` needs a real abora-plan-tool. Build a Debug one (faster than the
        AOT publish the Nix package uses) and expose it through ABORA_PLAN_TOOL_BIN."""
        project = self.root / "tools/abora-plan-tool/AboraPlanTool.csproj"
        if not (self.has["dotnet"] and project.is_file()):
            return
        build = self.run(["dotnet", "build", str(project), "-c", "Debug"], env={**os.environ, "MSBuildEnableWorkloadResolver": "false"})
        if build.returncode != 0:
            return
        dll = self.root / "tools/abora-plan-tool/bin/Debug/net10.0/abora-plan-tool.dll"
        handle, name = tempfile.mkstemp(prefix="abora-plan-tool-")
        with os.fdopen(handle, "w") as wrapper:
            wrapper.write(f"#!/usr/bin/env python3\nimport os, sys\nos.execvp('dotnet', ['dotnet', {str(dll)!r}, *sys.argv[1:]])\n")
        os.chmod(name, 0o755)
        self.plan_tool = Path(name)
        os.environ["ABORA_PLAN_TOOL_BIN"] = name

    # ── shell scripts ──
    def check_shell(self, file: str) -> None:
        self.counts["sh"] += 1
        path = self.root / file
        body = self.text(file)
        source_only = file.startswith("TinyPM/src/lib/") or SOURCE_ONLY_MARKER in body

        if self.bash_parses(file):
            self.ok(f"syntax (bash): {file}")
        else:
            self.fail(f"syntax (bash): {file}")
            return

        if not source_only:
            if not os.access(path, os.X_OK):
                self.fail(f"not executable: {file}")
            if not body.startswith("#!"):
                self.fail(f"missing shebang: {file}")

        # set -euo pipefail (one line or split) is the repo convention. Not a hard failure:
        # a few entry points opt out on purpose (abora-installer.sh keeps running after a
        # failed step so its recovery UI can show), and source-only libraries must never set it.
        if not source_only and not (
            re.search(r"set -[a-zA-Z]*e", body)
            and re.search(r"set -[a-zA-Z]*u|set -o nounset", body)
            and "pipefail" in body
        ):
            self.warn(f"no 'set -euo pipefail' (or equivalent split form): {file}")

        if not self.has["shellcheck"]:
            return
        # SC1091 (can't follow a runtime-resolved `source`) is intentional repo-wide: scripts
        # source abora-ui.sh through $ABORA_UI_LIB or /etc/abora/ui.sh.
        lint = self.run(["shellcheck", "-e", "SC1091", "-f", "gcc", file])
        if lint.returncode == 0:
            self.ok(f"shellcheck: {file}")
            return
        lines = (lint.stdout + lint.stderr).splitlines()
        by_level = {level: [l for l in lines if f": {level}:" in l] for level in ("error", "warning", "note")}
        errors, warnings, notes = (len(by_level[k]) for k in ("error", "warning", "note"))
        # Only errors block: CI's lint step runs with -S error, and most scripts carry
        # pre-existing warning/note style nits that were never treated as blocking.
        if errors:
            self.fail(f"shellcheck: {file} ({errors} error(s), {warnings} warning(s), {notes} note(s))")
            self.indented("\n".join(by_level["error"]))
        elif warnings:
            self.warn(f"shellcheck: {file} ({warnings} warning(s), {notes} note(s), no errors)")
            self.indented("\n".join(by_level["warning"]))
        else:
            self.warn(f"shellcheck: {file} ({notes} note(s) only)")
            self.indented("\n".join(by_level["note"]))

    # ── nix ──
    def check_nix(self, file: str, nix_files_text: dict[str, str]) -> None:
        self.counts["nix"] += 1
        if self.has["nix-instantiate"]:
            if self.run(["nix-instantiate", "--parse", file]).returncode == 0:
                self.ok(f"parse (nix): {file}")
            else:
                self.fail(f"parse (nix): {file}")
                return
        self.check_nix_referenced(file, nix_files_text)

    def check_nix_referenced(self, file: str, nix_files_text: dict[str, str]) -> None:
        """Warn about nix/ files no other .nix file mentions by name. A heuristic text search,
        not a dependency graph: a hit means "double check by hand", not "delete it"."""
        base = file.rsplit("/", 1)[-1]
        if not file.startswith("nix/") or base == "default.nix":
            return
        referenced = any(base in text and f"./{file}" not in path for path, text in nix_files_text.items())
        if not referenced:
            self.counts["orphan"] += 1
            self.warn(f"possibly orphaned (not imported anywhere): {file}")

    def nix_texts(self) -> dict[str, str]:
        """Every .nix file `grep -r --exclude-dir=out,.git,vendor,TinyPM` would read, keyed "./path"."""
        texts = {}
        for current, dirnames, filenames in os.walk(self.root):
            dirnames[:] = [d for d in dirnames if d not in GREP_EXCLUDE_DIRS and not (Path(current) / d).is_symlink()]
            for filename in filenames:
                path = Path(current) / filename
                if filename.endswith(".nix") and not path.is_symlink():
                    try:
                        texts["./" + path.relative_to(self.root).as_posix()] = path.read_text(encoding="utf-8", errors="replace")
                    except OSError:
                        pass
        return texts

    # ── python ──
    def check_python(self, file: str) -> None:
        self.counts["py"] += 1
        try:
            py_compile.compile(str(self.root / file), doraise=True)
            self.ok(f"compile (python): {file}")
        except (py_compile.PyCompileError, OSError):
            self.fail(f"compile (python): {file}")

    # ── wallpaper theme .conf ──
    def check_theme_conf(self, file: str) -> None:
        """assets/wallpaper-themes/*.conf are shell assignments abora-theme-sync.sh sources
        directly, so a syntax error breaks theme sync exactly like a broken script would."""
        self.counts["conf"] += 1
        if self.bash_parses(file):
            self.ok(f"syntax (conf, sourced as shell): {file}")
        else:
            self.fail(f"syntax (conf, sourced as shell): {file}")

    # ── markdown ──
    @staticmethod
    def slugify(heading: str) -> str:
        """The anchor GitHub-style renderers generate: lowercase, drop anything but
        [a-z0-9 _-], then runs of spaces become one hyphen."""
        return re.sub(r" +", "-", re.sub(r"[^a-z0-9 _-]", "", heading.lower()))

    def heading_slugs(self, path: Path) -> list[str]:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return []
        return [self.slugify(re.sub(r"^#+\s*", "", line)) for line in lines if HEADING.match(line)]

    def check_markdown_links(self, file: str) -> None:
        self.counts["md"] += 1
        directory = (self.root / file).parent
        broken = False
        for line in self.text(file).splitlines():
            for match in MD_LINK.finditer(line):
                link = match.group(0)[2:-1]
                target, has_anchor, anchor = link.partition("#")
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                if target and not (directory / target).exists():
                    self.dim(f"  broken link: {file} -> {link}")
                    broken = True
                    continue
                if has_anchor and anchor:
                    heading_file = directory / target if target else self.root / file
                    if not heading_file.is_file():
                        continue
                    if anchor not in self.heading_slugs(heading_file):
                        shown = f"{Path(file).parent.as_posix()}/{target}" if target else file
                        self.dim(f'  broken anchor: {file} -> {link} (no heading slugs to "{anchor}" in {shown})')
                        broken = True
        if broken:
            self.fail(f"links: {file}")
        else:
            self.ok(f"links: {file}")

    def check_markdown_code_blocks(self, file: str) -> None:
        """Syntax-check every complete ```sh/```bash/```nix block. Blocks that open with a
        `$ ` prompt are illustrative and skipped; nix blocks are often fragments, so a nix
        parse failure is only a note."""
        content = self.text(file)
        # Like `while read`, a final line with no trailing newline is never seen.
        lines = content.split("\n")[:-1]
        blocks: list[tuple[str, str]] = []
        lang, block = None, ""
        for line in lines:
            if lang is None:
                if match := FENCE_OPEN.match(line):
                    lang, block = match.group(1), ""
                continue
            if line == "```":
                blocks.append((lang, block))
                lang = None
                continue
            block += line + "\n"

        if not blocks:
            return
        failed = False
        with tempfile.TemporaryDirectory() as tmp:
            for number, (lang, block) in enumerate(blocks, start=1):
                if re.match(r"\s*\$ ", block):
                    continue
                block_file = Path(tmp) / f"block_{number}.{'nix' if lang == 'nix' else 'sh'}"
                block_file.write_text(block + "\n", encoding="utf-8")
                if lang == "nix":
                    if self.has["nix-instantiate"] and self.run(["nix-instantiate", "--parse", str(block_file)]).returncode != 0:
                        self.dim(f"  note: ```nix block #{number} in {file} does not parse standalone (may be a fragment)")
                elif not self.bash_parses(block_file):
                    self.dim(f"  broken code block: ```{lang} block #{number} in {file} does not parse")
                    failed = True
        if failed:
            self.fail(f"code blocks: {file}")
        else:
            self.ok(f"code blocks ({len(blocks)}): {file}")

    # ── ANIX v2 plans ──
    def check_anix_plan(self, file: str) -> None:
        """`anix diff-plan` parses, compiles and validates a plan without applying anything.
        A missing language adapter (MKO/ModuCPP toolchains install separately) is an
        environment gap, so it counts as skipped rather than failed."""
        self.counts["anix"] += 1
        if not self.has["jq"] or not (self.root / "scripts/anix.sh").is_file() or self.plan_tool is None:
            self.counts["anix_skipped"] += 1
            return
        result = subprocess.run(["bash", "scripts/anix.sh", "diff-plan", file], cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if result.returncode == 0:
            self.ok(f"anix diff-plan: {file}")
        elif "No language adapter found" in result.stdout:
            self.counts["anix_skipped"] += 1
            self.out(f"[ok]   anix diff-plan: {file} (adapter not installed, skipped)")
        else:
            self.fail(f"anix diff-plan: {file}")
            self.indented("\n".join(l for l in result.stdout.splitlines() if re.search("✗|error", l)))

    # ── YAML ──
    def check_yaml(self, file: str) -> None:
        """Workflows mostly: a YAML error is invisible locally and only surfaces when CI can't
        parse the workflow. Without PyYAML, only tab indentation is checked (YAML forbids tabs,
        so it can't false-positive; a duplicate-key scan would, since steps repeat keys)."""
        self.counts["yaml"] += 1
        if self.yaml is not None:
            try:
                with (self.root / file).open(encoding="utf-8") as handle:
                    self.yaml.safe_load(handle)
                self.ok(f"yaml: {file}")
            except Exception as exc:  # noqa: BLE001 - any parser error is a failed check
                self.fail(f"yaml: {file}")
                self.indented(str(exc))
            return
        if any(line.startswith("\t") for line in self.text(file).splitlines()):
            self.fail(f"yaml (basic): {file} (tab-indentation — YAML forbids tabs)")
        else:
            self.ok(f"yaml (basic, no parser available): {file}")

    # ── JSON ──
    @staticmethod
    def json_error(text: str) -> str | None:
        """None if `text` is JSON whose value is truthy for `jq -e` (not null/false), else why not."""
        try:
            value = json.loads(text)
        except ValueError as exc:
            return str(exc)
        return f"top-level value is {json.dumps(value)}" if value is None or value is False else None

    def check_json(self, file: str) -> None:
        self.counts["json"] += 1
        error = self.json_error(self.text(file))
        if error is None:
            self.ok(f"json: {file}")
        else:
            self.fail(f"json: {file}")
            self.indented(error)

    def check_jsonc(self, file: str) -> None:
        """JSON, or JSON after dropping *whole-line* // comments. Inline // is left alone: telling
        a comment from "https://" inside a string needs a tokenizer, not a regex."""
        self.counts["json"] += 1
        text = self.text(file)
        if self.json_error(text) is None:
            self.ok(f"jsonc: {file}")
            return
        stripped = "\n".join(line for line in text.splitlines() if not re.match(r"\s*//", line))
        if self.json_error(stripped) is None:
            self.ok(f"jsonc: {file} (parsed after stripping whole-line // comments)")
        else:
            self.fail(f"jsonc: {file}")
            self.indented(self.json_error(text) or "")

    # ── .desktop ──
    def check_desktop_file(self, file: str) -> None:
        """The mistakes that actually break a launcher, not full Desktop Entry spec validation."""
        self.counts["desktop"] += 1
        lines = self.text(file).splitlines()
        bad = False
        if not any(line.startswith("[Desktop Entry]") for line in lines):
            self.dim(f"  missing [Desktop Entry] group header: {file}")
            bad = True
        for key in ("Type", "Name"):
            if not any(line.startswith(f"{key}=") for line in lines):
                self.dim(f"  missing required key {key}=: {file}")
                bad = True
        entry_type = next((line[len("Type="):] for line in lines if line.startswith("Type=")), "")
        if entry_type == "Application" and not any(line.startswith("Exec=") for line in lines):
            self.dim(f"  Type=Application but no Exec=: {file}")
            bad = True
        if bad:
            self.fail(f"desktop entry: {file}")
        else:
            self.ok(f"desktop entry: {file}")

    # ── run ──
    def run_all(self) -> int:
        self.build_plan_tool()
        try:
            return self._run_sections()
        finally:
            if self.plan_tool is not None:
                self.plan_tool.unlink(missing_ok=True)

    def _run_sections(self) -> int:
        root, c = self.root, self.c

        self.section("Shell scripts")
        if not self.has["shellcheck"]:
            self.ok("shellcheck unavailable (lint checks skipped, syntax checks still run)")
        for file in find_files(root, "sh") + find_shebang_scripts(root):
            self.check_shell(file)

        self.section("Nix files")
        if not self.has["nix-instantiate"]:
            self.ok("nix-instantiate unavailable (nix parse checks skipped)")
        nix_texts = self.nix_texts()
        for file in find_files(root, "nix"):
            self.check_nix(file, nix_texts)

        self.section("Python files")
        for file in find_files(root, "py"):
            self.check_python(file)

        self.section("Wallpaper theme .conf files (sourced as shell)")
        for file in find_files(root, "conf"):
            if "wallpaper-themes/" in file:
                self.check_theme_conf(file)

        self.section("Markdown files (links, anchors, fenced code blocks)")
        for file in find_files(root, "md"):
            self.check_markdown_links(file)
            self.check_markdown_code_blocks(file)

        self.section("ANIX v2 plan sources (anix diff-plan, non-destructive)")
        if not self.has["jq"]:
            self.ok("jq unavailable (anix plan checks skipped)")
        for ext in ("anix", "mko", "moducpp"):
            for file in find_files(root, ext):
                self.check_anix_plan(file)

        self.section("YAML files (GitHub Actions workflows, etc.)")
        if self.yaml is None:
            self.ok('no YAML parser available (python3 -c "import yaml" failed); falling back to basic checks')
        for file in find_files(root, "yml") + find_files(root, "yaml"):
            self.check_yaml(file)

        self.section("JSON files")
        for file in find_files(root, "json"):
            self.check_json(file)
        for file in find_files(root, "jsonc"):
            self.check_jsonc(file)

        self.section(".desktop files")
        for file in find_files(root, "desktop"):
            self.check_desktop_file(file)

        n = self.counts
        self.out(
            f"\n{c['dim']}{n['sh']} shell, {n['nix']} nix ({n['orphan']} possibly orphaned), {n['py']} python, "
            f"{n['conf']} theme conf, {n['md']} markdown, {n['anix']} anix plan(s, {n['anix_skipped']} skipped), "
            f"{n['yaml']} yaml, {n['json']} json/jsonc, {n['desktop']} desktop file(s) checked.{c['nc']}"
        )
        if self.warned and not self.elevated and not self.failed:
            self.out(f"\n{c['yellow']}No hard failures, but warnings were printed above — review them.{c['nc']}")
        if self.failed:
            print(f"\n{c['red']}One or more checks failed.{c['nc']}", file=sys.stderr)
            return 1
        if self.elevated:
            print(
                f"\n{c['bold']}{c['orange']}[warn+] elevated warnings were found above — these are real findings "
                f"(e.g. shellcheck), not style nits. Stopping.{c['nc']}",
                file=sys.stderr,
            )
            return 1
        self.out(f"\n{c['bold']}{c['green']}All files passed.{c['nc']}")
        return 0


def _load_yaml():
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError:
        return None
    return yaml


def main(argv: list[str]) -> int:
    if argv[:1] == ["--list-files"]:
        if len(argv) not in (2, 3):
            print("usage: check-all-files.py --list-files EXT [ROOT]", file=sys.stderr)
            return 2
        root = Path(argv[2]) if len(argv) == 3 else repo_root(__file__)
        for file in find_files(root, argv[1]):
            print(file)
        return 0
    if argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return Sweep(repo_root(__file__)).run_all()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
