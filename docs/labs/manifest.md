# Labs file reference

## `experiments/<area>/<implementation>/experiment.toml`

`abora-labs new <area>/<implementation> --language <key>` writes a starting
manifest. Unknown keys are errors, so a typo cannot be silently ignored.

### Top level

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | Slug (`a-z`, `0-9`, `-`), conventionally `<area>-<implementation>` |
| `description` | yes | One line: what this implementation tries |
| `area` | yes | Must equal the parent directory name |
| `implementation` | yes | Must equal the directory name |
| `language` | yes | A key from `configs/languages.toml` |
| `status` | yes | `idea`, `experimental`, `promising`, `candidate`, `rejected`, `archived` |
| `maintainer` | no | Who to ask about it |
| `requires` | no | Tools needed on PATH. Defaults to the language's `requires` |
| `dependencies` | no | Third-party libraries used. Reported as a count |
| `compare_with` | no | Other `<area>/<implementation>` targets to include in its comparison |
| `nix_shell` | no | Run every stage inside `nix develop <ref>`. A ref starting with `#` is relative to the Labs root flake. Adds `nix` to `requires` |

### `[commands]`

`build`, `test`, `run`, `clean`. Each is optional. The value is either:

- an argv list, executed directly (**preferred**):
  `build = ["go", "build", "-trimpath", "-o", "bin/downgrade-guard", "."]`
- a string, run with `sh -c`.

Shell is no longer Abora's primary language: it is easy to break and hard to
make safe. String commands still run, but `validate` warns about each one and
suggests an argv list, and it also warns about `.sh`/`.bash` files in an
implementation. Work that needs several steps, pipes or redirects is better
placed in the implementation's build tool, such as a Makefile (see
`experiments/updater/vanta/Makefile`) or CMake workflow presets.

Commands run with the implementation directory as the working directory, so
the area's specification is always at `../shared`.

`test` does not build first. `abora-labs check` runs build, then test.

### `[test]`

| Key | Meaning |
|---|---|
| `format` | How to count tests in the output: `go`, `cargo`, `tap`, `labs` |

The `labs` format is for languages without a test framework. Print one line per test:

```
LABS-TEST: PASS <name>
LABS-TEST: FAIL <name>
LABS-TEST: SKIP <name>
```

A test stage that exits 0 but reports any failure is recorded as failed.

### `[safety]`

| Key | Meaning |
|---|---|
| `level` | The most dangerous thing any stage does: `safe`, `privileged`, `vm_only`, `destructive` |
| `build`, `test`, `run`, `clean` | Per-stage level. May be lower than `level`, never higher |
| `risks` | What can go wrong. Required unless `level = "safe"` |
| `acknowledge` | Lint rule ids that are expected (e.g. `["mount"]`), so `validate` stops warning |

| Level | Meaning | On the host |
|---|---|---|
| `safe` | Current user, touches only its own directory | runs |
| `privileged` | Root or host state changes, no data loss expected | only with `--allow-privileged` |
| `vm_only` | Needs a disposable VM | never |
| `destructive` | Can destroy disks, partitions or bootloaders | never |

`validate` lints commands for obvious mismatches (a `safe` stage calling
`mkfs`, `sudo`, `nixos-rebuild switch`, ...). The lint is a tripwire, not a
sandbox: it cannot see what a compiled program does.

### `[metrics]`

| Key | Meaning |
|---|---|
| `artifacts` | Files or directories whose size is reported, relative to the implementation |
| `startup` | Command timed `startup_runs` times after one warm-up; the median is reported |

### `[timeouts]`

Seconds per stage (`build`, `test`, `run`, `clean`, `startup`), overriding
`defaults.timeout_seconds`.

## `experiments/<area>/evaluation.toml`

Human judgement. It is never computed and reports print it separately from
measured metrics.

```toml
question = "What should Abora use for updater?"
features = ["reads refs from argv", "rejects 32-bit overflow"]

[implementations.go]
reviewer = "AnimatedGTVR"
reviewed = 2026-09-13
scores = { maintainability = 4, readability = 4 }   # each 1-5
features = { "reads refs from argv" = "done" }      # done | partial | missing | n/a
notes = "Free-form observations."
```

Completeness counts `done` as 1 and `partial` as 0.5. Features marked `n/a`
are left out of the total, and features with no entry count as `missing`.

## `experiments/<area>/shared/`

There is no fixed schema. By convention it holds a `README.md` specification
and data-driven test vectors (e.g. tab-separated files) that every
implementation reads, so all languages are tested against the same cases. An
implementation that cannot read files yet may mirror the vectors by hand, but
it must say so and report the cases it cannot express as `SKIP`.

## `configs/labs.toml` and `configs/labs.local.toml`

`labs.local.toml` is merged over `labs.toml` and is gitignored.

```toml
[defaults]
timeout_seconds = 900
startup_runs = 5

[source]
exclude_dirs = ["bin", "obj", "target", ...]   # never counted as source

[tools.vanta]
path = "~/Work/Vanta/target/release/vanta"     # its directory is prepended to PATH
version_args = []                              # arguments that print a version
```

A single tool can also be pointed at with `ABORA_LABS_TOOL_<NAME>=/path`.

## `configs/languages.toml`

One table per language key:

| Key | Meaning |
|---|---|
| `display` | Name shown in reports |
| `extensions`, `filenames` | Which files count as source for line metrics |
| `requires` | Default `requires` for experiments in this language |
| `scaffold` | Commands `abora-labs new` writes. `{name}` becomes `<area>-<implementation>`. Also accepts `test_format` and `artifacts` |
