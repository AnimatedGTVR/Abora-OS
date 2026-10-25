# ANIX Language Extensions

ANIX can expose supported language adapters without changing NixOS's role as the system configuration engine. Adapters belong at clear boundaries and must provide predictable input, output, error handling, and tests.

Current experiments and language comparisons belong in Abora Labs. An experiment should not become a production dependency until it has a defined purpose, maintainer, packaging path, security review, and rollback plan.

For normal system work, use the stable ANIX commands documented in [ANIX](ANIX-V1.md). Developers should consult the source and `--help` output for the exact adapter interface in their branch.
