# Updater downgrade guard: shared specification

Every `updater/*` implementation ports the same decision from Abora OS:
`guard_against_accidental_downgrade()` in `scripts/abora-update.sh`, as
already ported to C# in `tools/abora-update-resolver/DowngradeGuard.cs` and
`VersionUtil.cs`.

## Behaviour

- `tag_base_version(tag)`: strip one leading `v`, then keep the leading dotted
  numeric part (`v4.1-DEMO2` → `4.1`). If the value does not start with a
  digit, return it unchanged after stripping `v` (`edge` → `edge`).
- A version is *numeric* when it is non-empty and every `.`-separated part is
  a decimal integer that fits in a signed 32-bit int.
- `compare(a, b)`:
  - numeric sorts before non-numeric;
  - two non-numeric values compare byte-wise;
  - two numeric values compare part by part, missing parts count as `0`.
- `version_less_than(a, b)` = `a != b && compare(a, b) < 0`.
- `allows(current, selected_ref, allow_downgrade)`:
  `selected_ref == "edge"` or `allow_downgrade` → allow; otherwise allow
  unless `version_less_than(tag_base_version(selected_ref), current)`.

## CLI contract (for implementations that can read arguments)

```
downgrade-guard [--allow-downgrade] <current-version> <selected-ref>
```

Prints `allow` (exit 0) or `block` (exit 1). Usage errors exit 2.

## Test vectors

- `downgrade-cases.tsv`: `current  selected_ref  allow_downgrade(yes|no)  expected(allow|block)`
- `tag-base-cases.tsv`: `tag  expected_base`

Lines starting with `#` and blank lines are ignored. Fields are tab-separated.
Implementations should read these files rather than copying the cases, so
every language is tested against the same specification.
