# ANIX v2 — choose your configuration language

ANIX v2 describes system changes in a file instead of one command at a time. The built-in format is
**ANIX Native** (`.anix`). Other languages can be installed as adapters. Abora OS ships none: ModuCPP and
MAKO were removed in 4.2.

The language changes how a plan is written, not how ANIX validates or applies it.

## One engine, several frontends

```text
ANIX Native ─┐
Adapters ────┴─> ANIX Plan JSON ─> validate ─> diff/dry-build ─> apply
```

Every frontend must produce the same versioned **ANIX Plan**. Only the ANIX
core may modify `.anix/state.json`, call `nixos-rebuild`, or request elevated
permissions. Language adapters run without root access.

This preserves the v1 safety model:

- typed and independently validated values
- atomic state writes
- a visible diff before activation
- automatic dry-builds for risky changes
- normal NixOS generations and rollback
- hand-written `anix.nix` overrides still win

## Choosing a language

The first working interface is:

```sh
anix language list
anix language use anix
anix run workstation.anix
anix validate-plan plan.json
anix apply-plan plan.json
anix diff-plan workstation.anix
```

The selected default belongs in `.anix/config`; it is a tool preference, not
system state. A file extension or explicit `--language` flag may override it
for one run.

ANIX Native `.anix` files work now for `set`, `enable`, `disable`, `package
add`, and `package remove`. They apply as one state transaction. Third-party
languages become available when a matching adapter manifest and command are
installed; `anix language list` reports readiness honestly.
`anix diff-plan` compares any source or Plan JSON with current state and labels
operations `ADD`, `CHANGE`, `REMOVE`, or `SAME` without writing anything.

## ANIX Plan v1

Adapters write JSON to standard output and diagnostics to standard error:

```json
{
  "planVersion": 1,
  "language": "anix",
  "operations": [
    { "op": "set", "key": "hostname", "value": "everest" },
    { "op": "enable", "feature": "bluetooth" },
    { "op": "enable", "feature": "gaming" },
    { "op": "enable", "feature": "gaming.steam" },
    { "op": "enable", "feature": "gaming.big-picture" },
    { "op": "enable", "feature": "gaming.controllers" },
    { "op": "enable", "feature": "gaming.mangohud" },
    { "op": "enable", "feature": "gaming.gamemode" },
    { "op": "package.add", "name": "firefox" }
  ]
}
```

The core rejects unknown versions, operations, keys, and value types before
touching state. Plans cannot contain shell fragments. Commands for systemd
units remain structured argv arrays and retain the v1 allowlists.

The workstation example in `examples/anix-v2/` shows a gaming-enabled plan:

```sh
anix run examples/anix-v2/workstation.anix
```

## Adapter manifest

An installed language adapter declares its executable and supported plan
version:

```json
{
  "id": "mylang",
  "name": "My Language",
  "extensions": [".mylang"],
  "command": ["mylang-anix"],
  "planVersion": 1
}
```

System adapters live in `/etc/anix/languages/`; user adapters may live in
`~/.config/anix/languages/`. ANIX resolves the command without a shell and
passes the source path as one argv value.

## The built-in frontend

### ANIX Native

The fastest path for direct system changes. Existing commands remain valid,
and a file form will group them into one reviewable transaction. See
`examples/anix-v2/simple.anix` for the smallest possible plan and
`examples/anix-v2/workstation.anix` for a multi-operation one.

## Delivery order

1. **Done:** freeze and test the first ANIX Plan v1 operation subset.
2. **Done:** route supported v1 mutations through the transactional plan executor
   (`apply_plan_json` in `scripts/anix.sh` — every operation applies through
   the existing `set`/`enable`/`disable`/`package` writers, then one
   dry-build-and-confirm closes the whole plan).
3. **Done:** add `anix run`, `anix validate-plan`, and `anix apply-plan`.
4. **Done:** ship the first ANIX Native file frontend.
5. **Removed in 4.2:** the ModuCPP frontend and its `moducpp-anix` package.
6. **Done:** `anix language list` reports readiness with a reason (missing
   command, bad manifest, unsupported plan version), and `anix diff-plan`
   compares real current state instead of assuming every operation is new.
7. **Done:** end-to-end coverage for the `simple`/`workstation` examples, plus
   failure-path tests proving invalid plans,
   malformed JSON, unresolvable languages, and failing adapters never
   mutate `anix.nix` (`scripts/core/tests/anix.test.sh`).
8. Open third-party adapter discovery after the security boundary is tested.

ANIX v1 remains supported throughout v2. Existing commands become calls into
the plan executor rather than being removed.
