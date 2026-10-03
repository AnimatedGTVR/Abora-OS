#!/usr/bin/env python3
"""Clean-checkout ISO build for a dedicated build VM/box.

Clones (or fast-forward pulls) the repo into its own workspace instead of
building whatever local working tree happens to be checked out, then runs that
checkout's build-iso the same way a local `make iso` would. Meant for a
persistent build machine, not a one-off developer build.

Environment overrides (empty counts as unset):
  ABORA_VM_WORKSPACE  default /var/tmp/abora-vm-build
  ABORA_REPO_DIR      checkout location (default $ABORA_VM_WORKSPACE/abora-os)
  ABORA_OUT_DIR       build output (default $ABORA_VM_WORKSPACE/out)
  ABORA_REPO_URL      default https://github.com/AnimatedGTVR/Abora-OS.git
  ABORA_REPO_BRANCH   default edge
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from abora_release import env


def run(argv: list[str], **kwargs) -> None:
    try:
        status = subprocess.run(argv, **kwargs).returncode
    except OSError as exc:
        print(f"{argv[0]}: {exc.strerror}", file=sys.stderr)
        raise SystemExit(127) from exc
    if status != 0:
        raise SystemExit(status)


def main() -> int:
    workspace = Path(env("ABORA_VM_WORKSPACE") or "/var/tmp/abora-vm-build")
    repo_dir = Path(env("ABORA_REPO_DIR") or workspace / "abora-os")
    out_dir = Path(env("ABORA_OUT_DIR") or workspace / "out")
    repo_url = env("ABORA_REPO_URL") or "https://github.com/AnimatedGTVR/Abora-OS.git"
    branch = env("ABORA_REPO_BRANCH") or "edge"

    if not shutil.which("git"):
        print("git command not found.", file=sys.stderr)
        return 1
    if not shutil.which("nix"):
        print("nix command not found. Install Nix with flakes support first.", file=sys.stderr)
        return 1

    workspace.mkdir(parents=True, exist_ok=True)

    if not (repo_dir / ".git").is_dir():
        # --branch matters: a plain clone checks out the repo's default HEAD
        # (stable), silently building the wrong branch on exactly the case this
        # script exists for, a fresh or reset persistent build workspace.
        run(["git", "clone", "--branch", branch, repo_url, str(repo_dir)])
    else:
        run(["git", "-C", str(repo_dir), "fetch", "origin", branch])
        run(["git", "-C", str(repo_dir), "checkout", branch])
        run(["git", "-C", str(repo_dir), "pull", "--ff-only", "origin", branch])

    # Branches that predate the Python port only have build-iso.sh.
    build_iso = next(
        (f"./scripts/{name}" for name in ("build-iso.py", "build-iso.sh") if (repo_dir / "scripts" / name).exists()),
        "./scripts/build-iso.py",
    )
    run([build_iso], cwd=repo_dir, env={**os.environ, "ABORA_OUT_DIR": str(out_dir)})

    print()
    print("Build complete.")
    print(f"ISO output directory: {out_dir}", flush=True)
    run(["ls", "-lah", str(out_dir)])
    return 0


if __name__ == "__main__":
    sys.exit(main())
