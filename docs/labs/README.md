# Abora Labs

Abora Labs is how Abora decides what each part of the OS should be written in.
Instead of arguing about languages, an *area* (the updater, the installer
planner, ...) gets one shared specification, several *implementations* in
different languages, and a controller that builds, tests and measures them all
the same way.

```sh
./abora-labs list                 # what exists, and whether its toolchain is installed
./abora-labs compare updater      # check every updater implementation, print the table
./abora-labs report updater       # the same table from stored results, runs nothing
```

## The language pool

These are the languages Abora draws from, grouped by the boundary they usually
serve. The grouping is guidance for where to start an experiment, not a rule:
Labs never refuses a language for an area, and the comparison decides.

```
Abora
├── native/system boundary      C, C++, Rust, Zig
├── app/service boundary        C#, Go, Vanta
├── high-assurance/specialized  Ada/SPARK, SQL
├── tooling                     Python, Ruby, Makefile
└── required foundation         Nix
```

Each language is declared once in [`configs/languages.toml`](../../configs/languages.toml)
(source extensions, required tools, starter commands). Nix is not in that file:
it is the foundation every shipped component is built with, and an experiment
opts into a Nix dev shell with `nix_shell` in its manifest.

## Layout

```
abora-labs                          launcher (python3 -m abora_labs)
automation/abora_labs/              the controller
configs/labs.toml                   global settings (timeouts, tool overrides)
configs/labs.local.toml             machine-specific overrides, gitignored
configs/languages.toml              the language pool
experiments/<area>/shared/          the specification and test vectors for an area
experiments/<area>/evaluation.toml  human review: scores, feature checklist, notes
experiments/<area>/<impl>/          one implementation, described by experiment.toml
out/labs/                           results and logs, gitignored
```

## Areas

| Area | Question | Implementations |
|---|---|---|
| [`updater`](../../experiments/updater/shared/README.md) | The downgrade guard from `scripts/abora-update.sh` | C, C#, Go, Vanta (numeric-only) |

## From experiment to Abora

An experiment's `status` records where it stands:
`idea` → `experimental` → `promising` → `candidate`, or `rejected` / `archived`.

A `candidate` becomes part of Abora the same way the existing native tools did
(`tools/abora-update-resolver`, `tools/abora-installer`): source under
`tools/<name>/`, a derivation in `nix/pkgs/<name>.nix`, wired into `flake.nix`,
and called from the Bash script it replaces. Labs code itself never ships.

## Further reading

- [manifest.md](manifest.md): every key in `experiment.toml`, `evaluation.toml` and the configs
- [cli.md](cli.md): commands, options, exit codes
- [architecture.md](architecture.md): how the controller runs and records a stage
