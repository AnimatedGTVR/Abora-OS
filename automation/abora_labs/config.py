"""Global configuration: configs/labs.toml, configs/labs.local.toml, configs/languages.toml."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .errors import ManifestError
from .tomlread import TableReader, deep_merge, load_toml
from .workspace import Workspace

SCAFFOLD_KEYS = ("build", "test", "run", "clean", "test_format", "artifacts")


@dataclass(frozen=True)
class Language:
    key: str
    display: str
    extensions: tuple[str, ...]
    filenames: tuple[str, ...]
    requires: tuple[str, ...]
    scaffold: dict[str, Any] = field(default_factory=dict)

    def owns(self, path: Path) -> bool:
        return path.name in self.filenames or path.suffix in self.extensions


@dataclass(frozen=True)
class ToolConfig:
    name: str
    path: Path | None
    version_args: tuple[str, ...]


@dataclass(frozen=True)
class LabsConfig:
    languages: dict[str, Language]
    tools: dict[str, ToolConfig]
    timeout_seconds: float
    startup_runs: int
    exclude_dirs: tuple[str, ...]

    def tool(self, name: str) -> ToolConfig:
        return self.tools.get(name) or ToolConfig(name=name, path=None, version_args=("--version",))


def load_config(ws: Workspace) -> LabsConfig:
    labs_path = ws.configs / "labs.toml"
    data = load_toml(labs_path)
    local_path = ws.configs / "labs.local.toml"
    if local_path.is_file():
        data = deep_merge(data, load_toml(local_path))

    problems: list[str] = []
    top = TableReader(data, problems)
    defaults = top.table("defaults")
    timeout = defaults.number("timeout_seconds", default=900.0)
    runs = defaults.number("startup_runs", default=5.0)
    defaults.reject_unknown()
    source = top.table("source")
    exclude = source.str_list("exclude_dirs")
    source.reject_unknown()

    tools: dict[str, ToolConfig] = {}
    tools_table = top.table("tools")
    for name in list(tools_table.data):
        entry = tools_table.table(name)
        path = entry.str("path")
        version_raw = entry.raw("version_args")
        version_args = entry.str_list("version_args") if version_raw is not None else ("--version",)
        entry.reject_unknown()
        tools[name] = ToolConfig(
            name=name,
            path=Path(path).expanduser() if path else None,
            version_args=version_args,
        )
    top.reject_unknown()
    if problems:
        raise ManifestError(labs_path, problems)

    return LabsConfig(
        languages=load_languages(ws.configs / "languages.toml"),
        tools=tools,
        timeout_seconds=timeout or 900.0,
        startup_runs=max(1, int(runs or 5)),
        exclude_dirs=exclude,
    )


def load_languages(path: Path) -> dict[str, Language]:
    data = load_toml(path)
    problems: list[str] = []
    languages: dict[str, Language] = {}
    for key, value in data.items():
        if not isinstance(value, dict):
            problems.append(f"`{key}` must be a table")
            continue
        reader = TableReader(value, problems, prefix=f"{key}.")
        display = reader.str("display", required=True) or key
        extensions = reader.str_list("extensions")
        filenames = reader.str_list("filenames")
        requires = reader.str_list("requires")
        scaffold_reader = reader.table("scaffold")
        scaffold = {k: scaffold_reader.raw(k) for k in SCAFFOLD_KEYS if k in scaffold_reader.data}
        scaffold_reader.reject_unknown()
        reader.reject_unknown()
        if not extensions and not filenames:
            problems.append(f"`{key}` needs `extensions` or `filenames`")
        languages[key] = Language(key, display, extensions, filenames, requires, scaffold)
    if problems:
        raise ManifestError(path, problems)
    return languages
