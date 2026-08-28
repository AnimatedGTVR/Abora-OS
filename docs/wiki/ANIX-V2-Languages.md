# ANIX v2 — choose your configuration language

ANIX v2 will let each project choose the language used to describe system
changes. The three built-in frontends will be:

1. **ANIX Native** — the short command language ANIX uses today
2. **MAKO** — readable scripts and reusable configuration logic
3. **ModuCPP** — a compiled C++-style frontend for native tooling

Additional languages can be installed as adapters. The language changes how a
plan is written, not how ANIX validates or applies it.

## One engine, several frontends

```text
ANIX Native ─┐
MAKO ────────┼─> ANIX Plan JSON ─> validate ─> diff/dry-build ─> apply
ModuCPP ─────┤
Other ───────┘
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
anix language use mako
anix language use moducpp
anix run workstation.mko
anix validate-plan plan.json
anix apply-plan plan.json
anix diff-plan workstation.mko
```

The selected default belongs in `.anix/config`; it is a tool preference, not
system state. A file extension or explicit `--language` flag may override it
for one run.

ANIX Native `.anix` files work now for `set`, `enable`, `disable`, `package
add`, and `package remove`. They apply as one state transaction. MAKO, ModuCPP,
and third-party execution becomes available when a matching adapter manifest
and command are installed; `anix language list` reports readiness honestly.
`anix diff-plan` compares any source or Plan JSON with current state and labels
operations `ADD`, `CHANGE`, `REMOVE`, or `SAME` without writing anything.

## ANIX Plan v1

Adapters write JSON to standard output and diagnostics to standard error:

```json
{
  "planVersion": 1,
  "language": "mako",
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

The workstation examples in `examples/anix-v2/` show the same gaming-enabled
plan in ANIX Native, MAKO, and ModuCPP:

```sh
anix run examples/anix-v2/workstation.anix
anix run examples/anix-v2/workstation.mko
anix run examples/anix-v2/workstation.moducpp
```

## Adapter manifest

An installed language adapter declares its executable and supported plan
version:

```json
{
  "id": "mako",
  "name": "MAKO",
  "extensions": [".mko"],
  "command": ["mko", "run"],
  "planVersion": 1
}
```

System adapters live in `/etc/anix/languages/`; user adapters may live in
`~/.config/anix/languages/`. ANIX resolves the command without a shell and
passes the source path as one argv value.

## Default frontend goals

### ANIX Native

The fastest path for direct system changes. Existing commands remain valid,
and a file form will group them into one reviewable transaction. See
`examples/anix-v2/simple.anix` for the smallest possible plan and
`examples/anix-v2/workstation.anix` for a multi-operation one.

### MAKO

MAKO now exposes a small `ANIX` package that builds a plan. It is suitable for
conditions, reusable functions, lists, and approachable automation without
generating Nix syntax. End an adapter script with `ANIX.finish()` so its plan is
written to the adapter output channel. See `examples/anix-v2/simple.mko` for
the smallest possible plan and `examples/anix-v2/workstation.mko` for a
multi-operation one.

### ModuCPP

ModuCPP now has a dedicated `add ANIX;` plan module and `moducpp-anix` command
rather than using engine scene APIs. Compilation happens as the normal user;
the resulting program emits a plan and never applies system changes itself.
ANIX reports the frontend ready when `moducpp-anix` is installed on `PATH`.

Abora OS ships `moducpp-anix` as its own package (`nix/pkgs/moducpp-anix.nix`,
built from `tools/moducpp-anix`) — it's on `PATH` on the live ISO and every
installed system, with no Modularity checkout required, since the script
embeds the small ANIX plan header it needs at compile time. Flake users can
also add it directly:

```nix
environment.systemPackages = [ abora.packages.${pkgs.system}.moducpp-anix ];
```

From a Modularity source checkout instead (e.g. while developing the header
itself), install the same script manually:

```bash
install -Dm755 tools/moducpp-anix ~/.local/bin/moducpp-anix
```

```moducpp
add ANIX;

int main() {
    ANIX::Plan plan;
    plan.Set("hostname", "everest");
    plan.Enable("bluetooth");
    plan.Package("firefox");
    plan.Finish();
    return 0;
}
```

See `examples/anix-v2/simple.moducpp` for the smallest possible plan,
`examples/anix-v2/workstation.moducpp` for a multi-operation one, and the
[official ModuCPP documentation](https://www.moduengine.xyz/docs), especially
the [complete guide](https://www.moduengine.xyz/docs/moducpp-guide) and
[language reference](https://www.moduengine.xyz/docs/moducpp-reference).

## Delivery order

1. **Done:** freeze and test the first ANIX Plan v1 operation subset.
2. **Done:** route supported v1 mutations through the transactional plan executor
   (`apply_plan_json` in `scripts/anix.sh` — every operation applies through
   the existing `set`/`enable`/`disable`/`package` writers, then one
   dry-build-and-confirm closes the whole plan).
3. **Done:** add `anix run`, `anix validate-plan`, and `anix apply-plan`.
4. **Done:** ship the first ANIX Native file frontend.
5. **Done:** ship the MAKO adapter and `using ANIX;` package.
6. **Done:** ship the standalone ModuCPP plan module and adapter contract, and
   package `moducpp-anix` (`nix/pkgs/moducpp-anix.nix`) so it's on `PATH` on
   the live ISO and every installed system without a Modularity checkout.
7. **Done:** `anix language list` reports readiness with a reason (missing
   command, bad manifest, unsupported plan version), and `anix diff-plan`
   compares real current state instead of assuming every operation is new.
8. **Done:** end-to-end coverage for `simple`/`workstation` examples across
   all three frontends, plus failure-path tests proving invalid plans,
   malformed JSON, unresolvable languages, and failing adapters never
   mutate `anix.nix` (`scripts/check-scripts.sh`).
9. Open third-party adapter discovery after the security boundary is tested.

ANIX v1 remains supported throughout v2. Existing commands become calls into
the plan executor rather than being removed.
