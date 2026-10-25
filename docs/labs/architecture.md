# Labs Architecture

The standard-library Python controller in `automation/abora_labs/` discovers experiments, validates manifests, applies safety rules, runs stages, collects metrics, and writes JSON results.

A stage is skipped when undefined, blocked when policy forbids it, unavailable when tools are missing, and passed or failed after execution. VM-only and destructive experiments must never silently run on a normal host.

Measured results and human evaluation remain separate. Interrupted runs keep completed results, and every skipped or failed stage records a reason.
