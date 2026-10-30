#!/usr/bin/env python3
"""Behaviour tests for ABT (scripts/safety/abora-abt.py), the Abora Transaction engine.

Run by scripts/check-scripts.py: prints [ok]/[fail] lines and exits 1 if any check failed. Each check
builds a fake NixOS system profile in a temp directory -- system -> system-N-link -> a generation
directory whose bin/switch-to-configuration points /run/current-system at it -- plus a fake nix-env,
so ABT's real switch/rollback commands run against something that behaves like the real thing.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ABT = REPO / "scripts" / "safety" / "abora-abt.py"
POSIX = os.name == "posix"
CHECKS = []


class Skip(Exception):
    pass


def check(name: str):
    def register(function):
        CHECKS.append((name, function))
        return function
    return register


def script(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!/bin/sh\nset -e\n{body}\n", encoding="utf-8")
    path.chmod(0o755)


class FakeSystem:
    """A system profile with generation 1 running, and a config directory."""

    def __init__(self, root: Path):
        self.root = root
        self.profiles = root / "profiles"
        self.profiles.mkdir()
        self.current = root / "current-system"
        self.config = root / "nixos"
        self.config.mkdir()
        (self.config / "flake.nix").write_text("{ original = true; }\n")
        (self.config / ".git").mkdir()
        (self.config / ".git" / "HEAD").write_text("ref: refs/heads/main\n")
        self.bin = root / "bin"
        self.make_generation(1)
        self.point_profile(1)
        self.current.symlink_to(self.generation(1))
        # nix-env -p PROFILE --switch-generation N
        script(self.bin / "nix-env", 'ln -sfn "system-$4-link" "$2"')
        # No systemd here: no failed units unless a check writes them.
        script(self.bin / "systemctl", f'cat "{root}/failed" 2>/dev/null || true')

    def generation(self, n: int) -> Path:
        return self.root / "store" / f"gen{n}"

    def make_generation(self, n: int) -> None:
        script(self.generation(n) / "bin" / "switch-to-configuration",
               f'ln -sfn "{self.generation(n)}" "{self.current}"; echo "$1" >> "{self.root}/activations"')
        (self.profiles / f"system-{n}-link").symlink_to(self.generation(n))

    def point_profile(self, n: int) -> None:
        link = self.profiles / "system"
        if link.is_symlink():
            link.unlink()
        link.symlink_to(f"system-{n}-link")

    def switch_command(self, n: int, edit: str = "") -> list[str]:
        """A stand-in for nixos-rebuild switch that builds and activates generation n."""
        body = (f'mkdir -p "{self.generation(n)}/bin"\n'
                f'printf \'#!/bin/sh\\nln -sfn "{self.generation(n)}" "{self.current}"\\n\' > "{self.generation(n)}/bin/switch-to-configuration"\n'
                f'chmod +x "{self.generation(n)}/bin/switch-to-configuration"\n'
                f'ln -sfn "{self.generation(n)}" "{self.profiles}/system-{n}-link"\n'
                f'ln -sfn "system-{n}-link" "{self.profiles}/system"\n'
                f'ln -sfn "{self.generation(n)}" "{self.current}"\n'
                f'{edit}')
        path = self.root / f"switch-{n}.sh"
        script(path, body)
        return [str(path)]

    def env(self) -> dict[str, str]:
        return {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "ABT_STATE_DIR": str(self.root / "state"),
                "ABT_SYSTEM_PROFILE": str(self.profiles / "system"), "ABT_CURRENT_SYSTEM": str(self.current),
                "ABT_NIX_ENV": str(self.bin / "nix-env"), "ABT_SYSTEMCTL": str(self.bin / "systemctl")}

    def abt(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(ABT), *args], env=self.env(), cwd=REPO,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def profile_number(self) -> str:
        return os.readlink(self.profiles / "system")

    def running(self) -> str:
        return os.path.realpath(self.current)

    def transactions(self) -> list[dict]:
        return [json.loads(p.read_text()) for p in sorted((self.root / "state").glob("*/transaction.json"))]


def fake_system():
    if not POSIX:
        raise Skip("needs symlinks and a POSIX shell")
    tmp = tempfile.TemporaryDirectory()
    return tmp, FakeSystem(Path(tmp.name))


@check("runtime: abt run commits a change that switches and verifies")
def _():
    tmp, system = fake_system()
    with tmp:
        done = system.abt("run", "--name", "test switch", "--config", str(system.config), "--", *system.switch_command(2))
        tx = system.transactions()[0]
        assert done.returncode == 0, done.stdout
        assert tx["state"] == "committed" and tx["after"]["generation"]["number"] == 2, tx
        assert [p["phase"] for p in tx["phases"] if p["status"] == "ok"] == ["PLAN", "SNAPSHOT", "APPLY", "VERIFY"], tx["phases"]
        assert system.running() == str(system.generation(2))
        mode = (system.root / "state").stat().st_mode & 0o777
        assert mode == 0o700, f"state dir is {oct(mode)}; snapshots hold /etc/nixos and must be root-only"


@check("runtime: abt rolls back the config and the generation when verification fails")
def _():
    tmp, system = fake_system()
    with tmp:
        edit = f'echo "{{ broken = true; }}" > "{system.config}/flake.nix"; touch "{system.config}/new-file.nix"'
        done = system.abt("run", "--name", "bad switch", "--config", str(system.config), "--verify", "false",
                          "--", *system.switch_command(2, edit))
        tx = system.transactions()[0]
        assert done.returncode == 1, done.stdout
        assert tx["state"] == "rolled-back", tx["state"]
        assert system.profile_number() == "system-1-link", system.profile_number()
        assert system.running() == str(system.generation(1)), system.running()
        assert (system.config / "flake.nix").read_text() == "{ original = true; }\n"
        assert not (system.config / "new-file.nix").exists(), "a file the change added survived the rollback"
        assert (system.config / ".git" / "HEAD").is_file(), "the rollback touched the config's Git history"


@check("runtime: abt treats a newly failed service as a failed change")
def _():
    tmp, system = fake_system()
    with tmp:
        (system.root / "failed").write_text("old-broken.service loaded failed failed Old\n")
        edit = f'echo "new-broken.service loaded failed failed New" >> "{system.root}/failed"'
        done = system.abt("run", "--name", "breaks a unit", "--", *system.switch_command(2, edit))
        tx = system.transactions()[0]
        verify = [p["detail"] for p in tx["phases"] if p["phase"] == "VERIFY"]
        assert done.returncode == 1 and tx["state"] == "rolled-back", tx["state"]
        assert verify == ["newly failed service(s): new-broken.service"], verify
        assert system.running() == str(system.generation(1))


@check("runtime: abt rejects a change whose validation fails, without applying it")
def _():
    tmp, system = fake_system()
    with tmp:
        marker = system.root / "applied"
        done = system.abt("run", "--name", "invalid", "--validate", "false", "--", "touch", str(marker))
        tx = system.transactions()[0]
        assert done.returncode == 1 and tx["state"] == "rejected", tx["state"]
        assert not marker.exists(), "APPLY ran after VALIDATE failed"


@check("runtime: abt begin/commit undoes the caller's edits when the apply fails")
def _():
    tmp, system = fake_system()
    with tmp:
        began = system.abt("begin", "--name", "set desktop", "--config", str(system.config))
        tx_id = began.stdout.strip().splitlines()[-1]  # stderr is merged in here; the id is the last line
        (system.config / "flake.nix").write_text("{ desktop = \"typo\"; }\n")
        done = system.abt("commit", tx_id, "--", "false")
        assert began.returncode == 0 and done.returncode == 1, done.stdout
        assert (system.config / "flake.nix").read_text() == "{ original = true; }\n", "the edit made between begin and commit survived"
        assert system.abt("commit", tx_id, "--", "true").returncode == 2, "a finished transaction committed twice"


@check("runtime: abt undo returns to the generation before a committed change")
def _():
    tmp, system = fake_system()
    with tmp:
        system.abt("run", "--name", "upgrade", "--config", str(system.config),
                   "--", *system.switch_command(2, f'echo "{{ new = true; }}" > "{system.config}/flake.nix"'))
        tx_id = system.transactions()[0]["id"]
        listed = system.abt("list")
        undone = system.abt("undo", tx_id)
        assert tx_id in listed.stdout and "1 → 2" in listed.stdout, listed.stdout
        assert undone.returncode == 0 and system.transactions()[0]["state"] == "undone", undone.stdout
        assert system.running() == str(system.generation(1)) and system.profile_number() == "system-1-link"
        assert (system.config / "flake.nix").read_text() == "{ original = true; }\n"


@check("runtime: abt refuses path-like transaction ids")
def _():
    tmp, system = fake_system()
    with tmp:
        for bad in ("../etc", ".hidden", "a/b"):
            done = system.abt("show", bad)
            assert done.returncode == 2 and "not a transaction id" in done.stdout, (bad, done.stdout)


@check("runtime: abt pending edits roll back with a failed apply, and restore-edits brings them back")
def _():
    tmp, system = fake_system()
    with tmp:
        first = system.abt("pending", "--name", "anix set", "--config", str(system.config))
        (system.config / "flake.nix").write_text("{ desktop = \"typo\"; }\n")
        second = system.abt("pending", "--name", "anix enable", "--config", str(system.config))
        (system.config / "extra.nix").write_text("{ }\n")
        ids = first.stdout.strip().splitlines()[-1], second.stdout.strip().splitlines()[-1]
        assert ids[0] == ids[1], f"the second edit opened another transaction: {ids}"
        failed = system.abt("run", "--name", "anix apply", "--config", str(system.config), "--", *system.switch_command(2, "exit 1"))
        tx = system.transactions()[0]
        assert failed.returncode == 1 and tx["id"] == ids[0] and tx["state"] == "rolled-back", (tx["state"], failed.stdout)
        assert (system.config / "flake.nix").read_text() == "{ original = true; }\n", "the edits survived the rollback"
        assert not (system.config / "extra.nix").exists()
        assert "anix undo --keep-edits " + ids[0] in failed.stdout, failed.stdout
        restored = system.abt("restore-edits", ids[0])
        assert restored.returncode == 0, restored.stdout
        assert (system.config / "flake.nix").read_text() == "{ desktop = \"typo\"; }\n" and (system.config / "extra.nix").is_file()
        # A later edit starts a fresh transaction: the rolled-back one is no longer pending.
        third = system.abt("pending", "--name", "anix set", "--config", str(system.config))
        assert third.stdout.strip().splitlines()[-1] != ids[0]


@check("runtime: anix and abora config open the pending transaction before every config edit")
def _():
    anix = (REPO / "scripts/core/anix.sh").read_text(encoding="utf-8")
    config = (REPO / "scripts/config/abora-config.sh").read_text(encoding="utf-8")
    for function in ("write_anix_raw_option", "do_set", "do_package"):
        body = anix[anix.index(f"\n{function}() {{"):]
        body = body[: body.index("\n}\n")]
        assert 'abora_abt_pending "anix config changes" "$config_dir" run_as_root' in body, f"anix.sh {function} doesn't"
    for function in ("write_string_option", "write_bool_option"):
        body = config[config.index(f"\n{function}() {{"):]
        body = body[: body.index("\n}\n")]
        assert 'abora_abt_pending "abora config changes" "$config_dir" run_as_root' in body, f"abora-config.sh {function} doesn't"
    probe = subprocess.run(["bash", "-c", f'source "{REPO}/scripts/core/abora-ui.sh"; PATH=/nonexistent; abora_abt_pending x /etc/nixos false; echo rc=$?'],
                           stdout=subprocess.PIPE, text=True)
    assert probe.stdout.strip() == "rc=0", "without abora-abt an edit must go ahead"


@check("runtime: every way Abora reaches a system also brings abt.py")
def _():
    # anix and the updater only use ABT when abora-abt is on PATH, so a system without it still
    # works -- but it's then a system without rollback-on-failure, which a release must not ship.
    places = {
        "nix/profiles/live.nix": ('"abora/abt.py".source = ../../scripts/safety/abora-abt.py', 'writeShellScriptBin "abora-abt"'),
        "nix/modules/installed-base.nix": ("./abt.py", '"abora/abt.py".source = abtScript', 'writeShellScriptBin "abora-abt"'),
        "scripts/install/abora-installer.sh": ("abora_core.py abt.py; do",),
        "scripts/install/abora-adopt-nixos.sh": ('"scripts/safety/abora-abt.py:abt.py"',),
        "scripts/support/abora-update.sh": ("scripts/safety/abora-abt.py\nEOF", '"$abora_dir/abt.py"'),
        "scripts/release/release-required-paths.txt": ("scripts/safety/abora-abt.py",),
    }
    for place, needles in places.items():
        text = (REPO / place).read_text(encoding="utf-8")
        for needle in needles:
            assert needle in text, f"{place} doesn't bring abt.py ({needle!r})"


@check("runtime: anix, abora config/apps and the updater run their switch through ABT")
def _():
    sites = {
        "scripts/core/anix.sh": ('abora_abt_prefix "anix apply" "$config_dir"', 'abora_abt_prefix "anix switch'),
        "scripts/config/abora-config.sh": ('abora_abt_prefix "abora config apply" "$config_dir"',),
        "scripts/apps/abora-apps.sh": ('abora_abt_prefix "abora apps" "$config_dir"',),
        "scripts/support/abora-update.sh": ('abora_abt_prefix "abora update" -', '"${ABORA_ABT_PREFIX[@]}" timeout "$switch_timeout"'),
    }
    for place, needles in sites.items():
        text = (REPO / place).read_text(encoding="utf-8")
        for needle in needles:
            assert needle in text, f"{place}: {needle!r}"
    lib = (REPO / "scripts/core/abora-ui.sh").read_text(encoding="utf-8")
    probe = subprocess.run(["bash", "-c", f'source "{REPO}/scripts/core/abora-ui.sh"; PATH=/nonexistent; abora_abt_prefix x /etc/nixos; echo "${{#ABORA_ABT_PREFIX[@]}}"'],
                           stdout=subprocess.PIPE, text=True)
    assert "abora_abt_prefix()" in lib and probe.stdout.strip() == "0", f"without abora-abt the prefix must be empty: {probe.stdout!r}"


def main() -> int:
    failed = False
    for name, function in CHECKS:
        try:
            function()
        except Skip as skip:
            print(f"[ok]   {name} (skipped: {skip})")
        except Exception:
            failed = True
            print(f"[fail] {name}")
            for line in traceback.format_exc().rstrip().splitlines():
                print(f"              {line}")
        else:
            print(f"[ok]   {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
