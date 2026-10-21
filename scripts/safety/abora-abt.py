#!/usr/bin/env python3
"""abora-abt: ABT, the Abora Transaction engine (part of ASA, the Abora Safety Architecture).

Every change ABT runs goes through the same steps, and stops safely at the first one that fails:

  PLAN      record what's about to happen, the current system generation and the failed units
  VALIDATE  run the caller's check (e.g. a dry build); a failure here has changed nothing
  SNAPSHOT  copy the config directory, so the change can be undone
  APPLY     run the change (e.g. nixos-rebuild switch)
  VERIFY    the new generation is the running one, no service newly failed, the caller's checks pass
  ROLLBACK  if APPLY or VERIFY failed: put the config back and switch to the generation from PLAN

Usage:
  abora-abt run --name NAME [--config DIR] [--validate CMD] [--verify CMD]... -- COMMAND...
  abora-abt begin --name NAME [--config DIR]       prints a transaction id; snapshots DIR now
  abora-abt commit ID [--validate CMD] [--verify CMD]... -- COMMAND...
  abora-abt abort ID                               restore the snapshot from begin, apply nothing
  abora-abt list [--limit N]
  abora-abt show ID
  abora-abt undo ID                                roll back a transaction that went through

`begin` + `commit` is for callers that edit the config themselves between the two (anix config set,
anix desktop set): the snapshot is taken before their edits, so a failed apply undoes the edits too.
`run` is begin and commit at once, for a change that's only the command.

Transactions are kept in $ABT_STATE_DIR (default /var/lib/abora/abt), one directory each, holding
transaction.json and the config snapshot. Exit status: 0 committed, 1 failed (and rolled back, unless
the rollback failed too, which says so loudly), 2 usage errors.
"""

from __future__ import annotations

import contextlib
import json
import os
import random
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

sys.path[:0] = [str(Path(__file__).resolve().parent.parent / "support"), str(Path(__file__).resolve().parent), "/etc/abora"]
from abora_core import dim_line, error, step, success, ui_setup, warning

state_dir = Path(os.environ.get("ABT_STATE_DIR") or "/var/lib/abora/abt")
system_profile = Path(os.environ.get("ABT_SYSTEM_PROFILE") or "/nix/var/nix/profiles/system")
current_system = Path(os.environ.get("ABT_CURRENT_SYSTEM") or "/run/current-system")
# Never part of a snapshot: ANIX's Git history and its own state live in the config dir, and
# rolling those back would lose the record of what happened.
SNAPSHOT_EXCLUDE = {".git", ".anix", "result"}
# Units that fail on their own while a system switches (they're restarted by the switch itself).
VERIFY_IGNORE_UNITS = ("nixos-rebuild-switch-to-configuration.service",)


class AbtError(Exception):
    pass


# ── state ─────────────────────────────────────────────────────────────────────

def new_id() -> str:
    return time.strftime("%Y%m%d-%H%M%S") + f"-{random.randrange(16**4):04x}"


def tx_dir(tx_id: str) -> Path:
    if not tx_id or "/" in tx_id or tx_id.startswith("."):
        raise AbtError(f"not a transaction id: {tx_id!r}")
    return state_dir / tx_id


def load(tx_id: str) -> dict:
    path = tx_dir(tx_id) / "transaction.json"
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise AbtError(f"no transaction {tx_id} in {state_dir}") from None


def save(tx: dict) -> None:
    directory = tx_dir(tx["id"])
    # Snapshots hold /etc/nixos, which has the hashed user password and can have Wi-Fi keys, so the
    # whole state directory is root-only.
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    state_dir.chmod(0o700)
    directory.mkdir(exist_ok=True, mode=0o700)
    tmp = directory / "transaction.json.tmp"
    tmp.write_text(json.dumps(tx, indent=2) + "\n", encoding="utf-8")
    tmp.replace(directory / "transaction.json")


def log_phase(tx: dict, phase: str, status: str, detail: str = "") -> None:
    tx.setdefault("phases", []).append({"phase": phase, "status": status, "detail": detail, "at": time.strftime("%Y-%m-%dT%H:%M:%S%z")})
    save(tx)
    label = f"{phase:<9}"
    if status == "ok":
        success(f"{label} {detail}".rstrip())
    elif status == "skip":
        dim_line(f"–  {label} {detail}".rstrip())
    elif status == "start":
        step(f"{label} {detail}".rstrip())
    else:
        error(f"{label} {detail}".rstrip())


# ── system state ──────────────────────────────────────────────────────────────

def generation() -> dict:
    """The system profile's current generation: its link name (system-42-link) and store path."""
    try:
        link = os.readlink(system_profile)
    except OSError:
        return {}
    number = None
    name = os.path.basename(link)
    if name.startswith("system-") and name.endswith("-link"):
        try:
            number = int(name[len("system-"):-len("-link")])
        except ValueError:
            number = None
    target = system_profile.parent / link if not os.path.isabs(link) else Path(link)
    return {"link": name, "number": number, "path": os.path.realpath(target)}


def running_system() -> str:
    return os.path.realpath(current_system) if current_system.exists() else ""


def failed_units() -> list[str]:
    if not shutil.which("systemctl"):
        return []
    try:
        done = subprocess.run(["systemctl", "--failed", "--plain", "--no-legend", "--no-pager"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return sorted(line.split()[0] for line in done.stdout.splitlines() if line.split())


def snapshot(config: Path, destination: Path) -> int:
    """Tar the config directory (without SNAPSHOT_EXCLUDE). Returns the number of files."""
    count = 0
    destination.touch(mode=0o600)
    with tarfile.open(destination, "w:gz") as archive:
        for path in sorted(config.rglob("*")):
            relative = path.relative_to(config)
            if relative.parts[0] in SNAPSHOT_EXCLUDE:
                continue
            archive.add(path, arcname=str(relative), recursive=False)
            if path.is_file():
                count += 1
    return count


def restore(config: Path, source: Path) -> None:
    """Make the config directory match the snapshot: same files and contents, nothing extra."""
    with tarfile.open(source, "r:gz") as archive:
        members = archive.getmembers()
        kept = {Path(member.name) for member in members}
        for path in sorted(config.rglob("*"), reverse=True):
            relative = path.relative_to(config)
            if relative.parts[0] in SNAPSHOT_EXCLUDE or relative in kept:
                continue
            if path.is_dir() and not path.is_symlink():
                if not any(path.iterdir()):
                    path.rmdir()
            else:
                path.unlink()
        try:
            archive.extractall(config, members=members, filter="tar")
        except TypeError:  # Python before 3.12 (and the 3.8-3.11 backports) has no filter
            archive.extractall(config, members=members)


def run_command(argv: list[str], what: str) -> int:
    try:
        return subprocess.run(argv).returncode
    except OSError as exc:
        error(f"{what}: {exc}")
        return 127


# ── the transaction ───────────────────────────────────────────────────────────

def begin(name: str, config: str | None) -> dict:
    tx = {
        "id": new_id(),
        "name": name,
        "config": str(Path(config).resolve()) if config else None,
        "state": "open",
        "user": os.environ.get("SUDO_USER") or os.environ.get("USER") or "",
        "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "before": {"generation": generation(), "running": running_system(), "failed_units": failed_units()},
    }
    save(tx)
    log_phase(tx, "PLAN", "ok", f"{name} (generation {tx['before']['generation'].get('number', '?')})")
    if tx["config"]:
        config_path = Path(tx["config"])
        if not config_path.is_dir():
            tx["state"] = "rejected"
            log_phase(tx, "SNAPSHOT", "fail", f"config directory {config_path} doesn't exist")
            raise AbtError(f"config directory {config_path} doesn't exist")
        files = snapshot(config_path, tx_dir(tx["id"]) / "config.tar.gz")
        tx["snapshot"] = "config.tar.gz"
        log_phase(tx, "SNAPSHOT", "ok", f"{files} file(s) from {config_path}")
    else:
        log_phase(tx, "SNAPSHOT", "skip", "no config directory to snapshot")
    return tx


def rollback(tx: dict, reason: str) -> bool:
    log_phase(tx, "ROLLBACK", "start", reason)
    ok = True
    if tx.get("snapshot") and tx.get("config"):
        try:
            restore(Path(tx["config"]), tx_dir(tx["id"]) / tx["snapshot"])
            log_phase(tx, "ROLLBACK", "ok", f"config restored in {tx['config']}")
        except (OSError, tarfile.TarError) as exc:
            log_phase(tx, "ROLLBACK", "fail", f"couldn't restore the config: {exc}")
            ok = False
    before = tx["before"]["generation"]
    now = generation()
    if before.get("path") and now.get("path") and now["path"] != before["path"]:
        ok = switch_to(before) and ok
    elif before.get("path") and tx["before"]["running"] and running_system() != tx["before"]["running"]:
        ok = switch_to(before) and ok
    else:
        log_phase(tx, "ROLLBACK", "skip", "the running system never changed")
    tx["state"] = "rolled-back" if ok else "rollback-failed"
    save(tx)
    if not ok:
        error("The rollback didn't finish. The previous system is still in the boot menu:")
        dim_line(f"  reboot and pick generation {before.get('number', '?')}, or run: sudo nixos-rebuild switch --rollback")
    return ok


def switch_to(before: dict) -> bool:
    """Point the system profile back at `before` and activate it, like nixos-rebuild --rollback."""
    nix_env = os.environ.get("ABT_NIX_ENV") or "nix-env"
    if before.get("number") is not None:
        if run_command([nix_env, "-p", str(system_profile), "--switch-generation", str(before["number"])], "nix-env") != 0:
            error(f"couldn't make generation {before['number']} current again")
            return False
    activate = Path(before["path"]) / "bin" / "switch-to-configuration"
    if run_command([str(activate), "switch"], "switch-to-configuration") != 0:
        error(f"couldn't activate generation {before.get('number', '?')}")
        return False
    success(f"ROLLBACK  back on generation {before.get('number', '?')}")
    return True


def commit(tx: dict, command: list[str], validate: list[str], verify: list[list[str]]) -> int:
    if tx["state"] != "open":
        raise AbtError(f"transaction {tx['id']} is {tx['state']}, not open")
    tx["command"] = command
    tx["validate"] = validate
    tx["verify"] = verify
    save(tx)

    if validate:
        log_phase(tx, "VALIDATE", "start", shlex.join(validate))
        if run_command(validate, "validate") != 0:
            log_phase(tx, "VALIDATE", "fail", "the check failed; nothing was applied")
            restored = rollback(tx, "validation failed") if tx.get("snapshot") else True
            tx["state"] = "rejected" if restored else "rollback-failed"
            save(tx)
            return 1
        log_phase(tx, "VALIDATE", "ok")
    else:
        log_phase(tx, "VALIDATE", "skip", "no check given")

    log_phase(tx, "APPLY", "start", shlex.join(command))
    status = run_command(command, "apply")
    if status != 0:
        log_phase(tx, "APPLY", "fail", f"exit {status}")
        rollback(tx, "the change failed")
        return 1
    log_phase(tx, "APPLY", "ok")

    problems = verify_change(tx, verify)
    if problems:
        for problem in problems:
            log_phase(tx, "VERIFY", "fail", problem)
        rollback(tx, "verification failed")
        return 1
    log_phase(tx, "VERIFY", "ok", f"generation {generation().get('number', '?')} is running")
    tx["state"] = "committed"
    tx["after"] = {"generation": generation(), "running": running_system()}
    tx["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    save(tx)
    return 0


def verify_change(tx: dict, verify: list[list[str]]) -> list[str]:
    problems = []
    now, running = generation(), running_system()
    before = tx["before"]["generation"]
    # A switch makes the new generation current and running. (A build/boot/test that doesn't, or a
    # change that didn't touch the system at all, leaves both where they were, which is fine.)
    if now.get("path") and now.get("path") != before.get("path") and running and running != now["path"]:
        if not tx["command"] or "boot" not in tx["command"]:
            problems.append("the new generation was built but isn't the one running")
    new_failures = [unit for unit in failed_units() if unit not in tx["before"]["failed_units"] and unit not in VERIFY_IGNORE_UNITS]
    if new_failures:
        problems.append(f"newly failed service(s): {', '.join(new_failures)}")
    for check in verify:
        if run_command(check, "verify") != 0:
            problems.append(f"check failed: {shlex.join(check)}")
    return problems


def abort(tx: dict) -> int:
    if tx["state"] != "open":
        raise AbtError(f"transaction {tx['id']} is {tx['state']}, not open")
    ok = rollback(tx, "aborted before anything was applied")
    tx["state"] = "aborted" if ok else "rollback-failed"
    save(tx)
    return 0 if ok else 1


def undo(tx: dict) -> int:
    if tx["state"] != "committed":
        raise AbtError(f"only a committed transaction can be undone; {tx['id']} is {tx['state']}")
    ok = rollback(tx, f"undoing {tx['name']}")
    tx["state"] = "undone" if ok else "rollback-failed"
    save(tx)
    return 0 if ok else 1


def transactions() -> list[dict]:
    out = []
    if not state_dir.is_dir():
        return out
    for directory in sorted(state_dir.iterdir(), reverse=True):
        try:
            out.append(json.loads((directory / "transaction.json").read_text(encoding="utf-8")))
        except (OSError, ValueError):
            continue
    return out


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse(args: list[str]) -> tuple[dict, list[str]]:
    """Options before `--`, the command after it."""
    options = {"name": None, "config": None, "validate": [], "verify": [], "limit": 10, "positional": []}
    command: list[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            command = args[i + 1:]
            break
        if arg in ("--name", "--config", "--validate", "--verify", "--limit"):
            if i + 1 >= len(args):
                raise AbtError(f"{arg} needs a value")
            value = args[i + 1]
            key = arg[2:]
            if key in ("validate",):
                options[key] = shlex.split(value)
            elif key == "verify":
                options[key].append(shlex.split(value))
            elif key == "limit":
                options[key] = int(value)
            else:
                options[key] = value
            i += 2
            continue
        if arg.startswith("-"):
            raise AbtError(f"unknown option {arg}")
        options["positional"].append(arg)
        i += 1
    return options, command


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__.split("Transactions are kept")[0].rstrip())
        return 0 if argv else 2
    action, rest = argv[0], argv[1:]
    try:
        options, command = parse(rest)
        if action == "run":
            if not options["name"] or not command:
                raise AbtError("run needs --name and a command after --")
            tx = begin(options["name"], options["config"])
            return commit(tx, command, options["validate"], options["verify"])
        if action == "begin":
            if not options["name"]:
                raise AbtError("begin needs --name")
            # Only the id on stdout, so a caller can take it with $(abora-abt begin ...).
            with contextlib.redirect_stdout(sys.stderr):
                tx = begin(options["name"], options["config"])
            print(tx["id"])
            return 0
        if action in ("commit", "abort", "show", "undo"):
            if len(options["positional"]) != 1:
                raise AbtError(f"{action} needs one transaction id")
            tx = load(options["positional"][0])
            if action == "commit":
                if not command:
                    raise AbtError("commit needs a command after --")
                return commit(tx, command, options["validate"], options["verify"])
            if action == "abort":
                return abort(tx)
            if action == "undo":
                return undo(tx)
            json.dump(tx, sys.stdout, indent=2)
            print()
            return 0
        if action == "list":
            for tx in transactions()[: options["limit"]]:
                before = tx.get("before", {}).get("generation", {}).get("number", "?")
                after = tx.get("after", {}).get("generation", {}).get("number", "")
                arrow = f"{before} → {after}" if after else f"{before}"
                print(f"  {tx['id']}  {tx.get('state', '?'):<15} {arrow:<10} {tx.get('name', '')}")
            return 0
        raise AbtError(f"unknown action {action}")
    except AbtError as exc:
        error(f"abt: {exc}")
        return 2


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    ui_setup()
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
