# Labs Manifest Reference

Each implementation has `experiment.toml` with its name, language, status, commands, safety policy, metrics, test parser, timeouts, and optional Nix shell. Commands should use argument arrays; shell strings are supported only for compatibility and produce warnings.

Each area may contain:

- `shared/`: common specification and test vectors
- `evaluation.toml`: reviewer, date, feature status, scores, and notes
- implementation directories with one manifest each

Global defaults live in `configs/labs.toml`; local tool paths belong in `configs/labs.local.toml`. Language metadata lives in `configs/languages.toml`. Unknown keys are errors so misspellings cannot silently change a comparison.
