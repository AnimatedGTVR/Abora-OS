# ASA: the Abora Safety Architecture

ASA is how Abora OS keeps system changes safe by default: a change either works completely, or the system
goes back to exactly how it was. It's made of what NixOS already gives every Abora system (generations, and
the boot menu that lists them) plus three Abora pieces:

| Piece | What it does |
| --- | --- |
| **ABT**, the Abora Transaction engine | runs a system change as a transaction (below) |
| `anix doctor` | finds what's broken, explains it, and repairs it (see [Recovery](Recovery.md#doctor)) |
| ANIX snapshots | Git history of `/etc/nixos` (`anix save`) |

## ABT transactions

Every change ABT runs goes through the same six steps and stops safely at the first one that fails:

| Step | What happens | If it fails |
| --- | --- | --- |
| PLAN | records the change, the current generation, and which services have already failed | — |
| VALIDATE | runs the caller's check, for example a dry build | nothing was changed |
| SNAPSHOT | copies `/etc/nixos` (without `.git` and `.anix`) | — |
| APPLY | runs the change, normally `nixos-rebuild switch` | ROLLBACK |
| VERIFY | the new generation is the one running, no service newly failed, the caller's checks pass | ROLLBACK |
| ROLLBACK | puts `/etc/nixos` back as it was and switches to the generation from PLAN | says so, and how to boot the old one |

These run as transactions today:

- `anix apply`, `anix switch nix <profile>`
- `anix config apply` (`abora config apply`)
- `anix apps` (`abora apps`) when it rebuilds
- `anix update` (`abora update`): the final switch. The updater keeps its own backups of the files it
  rewrites, so ABT doesn't snapshot the config there; it verifies the switch and goes back to the previous
  generation if it fails.

`anix rollback` itself isn't one: it's the way back.

## Using it

```sh
anix history          # recent transactions: id, result, generation before → after, what ran
anix undo <id>        # go back to before a transaction that went through
```

`anix undo` restores that transaction's config snapshot and switches to the generation it started from.
Newer generations stay in the boot menu, so an undo can be undone with `anix rollback`.

Results in `anix history`:

| Result | Meaning |
| --- | --- |
| `committed` | applied and verified |
| `rejected` | VALIDATE failed; nothing changed |
| `rolled-back` | APPLY or VERIFY failed, and the system is back where it started |
| `rollback-failed` | the rollback didn't finish; reboot and pick the previous generation in the boot menu |
| `undone` | went through, then `anix undo` reversed it |

## For tool authors

Shell tools wrap their switch with `abora_abt_prefix` from `abora-ui.sh`:

```sh
abora_abt_prefix "my tool apply" "$config_dir"
run_as_root "${ABORA_ABT_PREFIX[@]}" nixos-rebuild switch --flake "$config_dir#abora"
```

The prefix is empty when `abora-abt` isn't installed (plain NixOS, or a system part-way through an update
from 4.1) or `ABORA_NO_ABT=1` is set, so the command runs exactly as before. A tool that edits the config
and then applies it can open the transaction before its edits, so a failed apply undoes them too:

```sh
id="$(abora-abt begin --name "set desktop" --config /etc/nixos)"
# ... edit /etc/nixos ...
abora-abt commit "$id" --validate "nixos-rebuild dry-build --flake /etc/nixos#abora" \
    -- nixos-rebuild switch --flake /etc/nixos#abora
```

`abora-abt run` is `begin` and `commit` in one step. Transactions live in `/var/lib/abora/abt`, readable
only by root, because the snapshots contain `/etc/nixos` (the hashed user password, possibly Wi-Fi keys).

## What's next

- `anix desktop set`, `anix gaming`, and `anix config set gpu` edit the config and apply it in one command;
  moving them to `begin`/`commit` makes a failed apply undo the edit as well, not only the generation.
- The installer and `anix recovery` from the live USB: a failed install can't roll back to a generation
  that doesn't exist yet, so there ASA means keeping the logs and an exact explanation (see the installer's
  failure hints).
