# Abora Labs architecture

The controller is a standard-library-only Python package in
`automation/abora_labs/`, started by the `abora-labs` launcher. It has no
dependencies so it runs on a fresh Abora or NixOS install with only `python3`.

## Principles

- **Measured and judged stay apart.** Metrics come from runs. Scores and notes
  come from `evaluation.toml`. Reports never blend them into one number.
- **Every decision is recorded.** A stage that was skipped, blocked or
  unavailable is stored with its reason, the same way a stage that ran is.
- **Nothing fails quietly.** A test parser that recognises nothing says so,
  and a test run that exits 0 while reporting FAIL is marked failed.
- **The host is protected by policy, not trust.** `vm_only` and `destructive`
  stages have no override on the host.

## Modules

| Module | Role |
|---|---|
| `cli.py`, `commands.py` | Argument parsing and one function per command |
| `workspace.py` | Finding the Labs root and output directory |
| `config.py`, `tomlread.py` | Loading `labs.toml`, `labs.local.toml`, `languages.toml` with strict key checking |
| `discovery.py`, `manifest.py` | Finding `experiment.toml` files and validating them into `Experiment` objects |
| `safety.py` | Safety levels, the host policy and the command lint |
| `toolchain.py` | Resolving required tools, PATH and versions |
| `pipeline.py` | Running a stage: the decision order below |
| `runner.py` | Process execution: timeouts, output capture, peak memory |
| `testparsers.py` | Counting tests in `go`, `cargo`, `tap` and `labs` output |
| `metrics.py` | Source lines, artifact sizes, warning heuristic, startup timing |
| `results.py` | Session and latest-result storage |
| `evaluation.py` | Loading `evaluation.toml` |
| `comparison.py`, `render.py` | Building and printing the comparison table |
| `validation.py` | The `validate` command's checks |
| `scaffold.py` | `new` |
| `ui.py`, `errors.py` | Output formatting, error types and exit codes |

## Running a stage

For every stage, `pipeline.py` decides in this order:

1. Is there a command for the stage? If not: **skipped**.
2. Does the safety policy allow it on this host? If not: **blocked**.
3. Are the required tools present? If not: **unavailable**.
4. Run it in the implementation directory, then classify the outcome:
   **passed**, **failed**, **crashed** (SIGSEGV, SIGABRT, SIGBUS, SIGILL or
   SIGFPE), **timeout**, or **error** (the command could not be started).

If the experiment sets `nix_shell`, the command is wrapped in
`nix develop <ref> --command`.

## Results

```
out/labs/sessions/<session-id>/session.json          invocation, git state, every result
out/labs/sessions/<session-id>/<area>/<impl>/<stage>.log
out/labs/latest/<area>/<impl>.json                   newest result per stage, plus metrics
```

Results are plain JSON. `latest` is updated as each stage finishes, so an
interrupted session keeps what it completed. `report` reads only `latest`.
