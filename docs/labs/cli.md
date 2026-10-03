# `abora-labs` command reference

```
abora-labs <command> [options]
```

`<target>` is `all`, an area (`updater`), or one implementation (`updater/go`).

| Command | Does |
|---|---|
| `list [target]` | Discovered experiments with language, status, safety level and toolchain availability |
| `status [target]` | The latest stored result of each experiment |
| `validate [target] [--strict]` | Manifests, safety lint, toolchains and evaluation files. `--strict` makes warnings errors |
| `new <area>` | Create an area with its `evaluation.toml`. Add `shared/` by hand |
| `new <area>/<impl> [--language L] [--safety S] [--description D]` | Create an implementation with a starter manifest |
| `build <target>` | Run the build stage |
| `test <target>` | Run the test stage. Does **not** build first |
| `clean <target>` | Run the clean stage |
| `check <target>` | Build, test and measure, recorded as one run |
| `run <area>/<impl> [-- args...]` | Run interactively. Output is not captured |
| `compare <area> [--no-run] [--format text\|markdown\|json]` | `check` every implementation in the area, then print the comparison |
| `report <area> [--format ...]` | Print the comparison from stored results without running anything |
| `logs <area>/<impl> [--stage build\|test\|clean] [--path]` | Print the newest log of a stage, or its path |

## Options

| Option | Commands | Meaning |
|---|---|---|
| `--root ROOT` | all | Labs checkout. Default: search upward for `configs/languages.toml`, or `$ABORA_LABS_ROOT` |
| `--out OUT` | all | Results directory. Default: `<root>/out/labs`, or `$ABORA_LABS_OUT` |
| `--color` / `--no-color` | all | Force color on or off |
| `-v`, `--verbose` | stage commands | Stream command output while it runs |
| `--allow-privileged` | stage commands | Allow `privileged` stages on this host. `vm_only` and `destructive` never run on the host |

## Environment

| Variable | Meaning |
|---|---|
| `ABORA_LABS_ROOT`, `ABORA_LABS_OUT` | Defaults for `--root` and `--out` |
| `ABORA_LABS_PYTHON` | Interpreter used by the launcher (default `python3`) |
| `ABORA_LABS_TOOL_<NAME>` | Path to one tool, overriding PATH and the configs |

Every stage command also receives `ABORA_LABS=1`, `ABORA_LABS_ROOT`,
`ABORA_LABS_EXPERIMENT` (`area/impl`), `ABORA_LABS_AREA_DIR`,
`ABORA_LABS_STAGE`, `ABORA_LABS_SAFETY` and `ABORA_LABS_SESSION`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Everything that was asked for ran and passed |
| 1 | A stage failed, crashed or timed out, or the harness hit an error |
| 2 | Bad arguments, or an invalid manifest or config |
| 3 | Nothing failed, but something was blocked by safety policy or its toolchain is unavailable |
