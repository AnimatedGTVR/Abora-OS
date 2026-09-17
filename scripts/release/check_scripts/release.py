"""Tests of the Python release tooling (scripts/release/*.py)."""

from __future__ import annotations

import os
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

from .core import Check, Context, grep, test

REQUIRED_PATHS = "scripts/release/release-required-paths.txt"
PATH_LINE = re.compile(r"[A-Za-z0-9_./-]+")


def release_tag(ctx: Context) -> str:
    version = re.sub(r"[^A-Za-z0-9._-]", "", ctx.path("VERSION").read_text(encoding="utf-8").replace("\n", ""))
    return version if version[:1] in ("v", "V") else f"v{version}"


def release_files(ctx: Context) -> None:
    manifest_ok = subprocess.run(["scripts/check-release-files.py"], cwd=ctx.repo, stdout=subprocess.DEVNULL).returncode == 0
    ctx.result(manifest_ok, "runtime: release file manifest")

    # release-required-paths.txt is documented as mirroring abora-update.sh's
    # required_upstream_paths(), and silently drifted by 9 files before this check:
    # a file missing from it means `make check` can't catch a tag that every
    # `sudo abora update` against it would refuse. nix/pkgs/scenefx-0_5.nix is the one
    # intentional exception (an internal mango build input the updater never syncs).
    update_text = ctx.path("scripts/abora-update.sh").read_text(encoding="utf-8")
    block = re.search(r"^required_upstream_paths\(\) \{\n(.*?)^\}$", update_text, re.S | re.M)
    update_paths = {line for line in (block.group(1).splitlines() if block else []) if PATH_LINE.fullmatch(line) and line != "EOF"}
    release_paths = {line for line in ctx.path(REQUIRED_PATHS).read_text(encoding="utf-8").splitlines() if PATH_LINE.fullmatch(line)}
    missing = sorted(update_paths - release_paths)
    name = "runtime: release-required-paths.txt mirrors abora-update.sh's required_upstream_paths"
    if not ctx.result(bool(block) and not missing, name):
        ctx.detail("\n".join(f"missing from release-required-paths.txt: {path}" for path in missing))

    ctx.result(manifest_ok and Check(
        "runtime: release manifest includes ANIX adapters, Modularity skeleton, and gaming layer",
        *(grep("-q", f"^{path}$", REQUIRED_PATHS) for path in (
            "assets/anix-languages", "nix/pkgs/moducpp-anix.nix", "tools/moducpp-anix", "scripts/abora-build.sh",
            "scripts/abora-adopt-nixos.sh", "scripts/abora-gaming.sh", "scripts/abora-custom-packages.sh",
            "assets/Abora-LOGO.png", "assets/Abora-Text.png", "docs/wiki/Abora-Gaming.md",
            "docs/wiki/ANIX-V2-Languages.md", "docs/wiki/Updating-Abora.md", "vendor/modularity",
        )),
        *(test("-f", path) for path in (
            "assets/anix-languages/mako.json", "assets/anix-languages/moducpp.json", "nix/pkgs/moducpp-anix.nix",
            "tools/moducpp-anix", "vendor/modularity/README.md", "assets/Abora-LOGO.png", "assets/Abora-Text.png",
            "scripts/abora-gaming.sh", "docs/wiki/Abora-Gaming.md",
        )),
    ).conditions_hold(ctx), "runtime: release manifest includes ANIX adapters, Modularity skeleton, and gaming layer")


def packages_and_metadata(ctx: Context, tag: str) -> None:
    # Build real throwaway packages and manifests instead of grepping source: this
    # logic would otherwise only be exercised by a real `make release`.
    with tempfile.TemporaryDirectory(prefix="abora-check-release-") as tmp:
        work = Path(tmp)
        anix_out = work / "anix-package-out"
        name = "runtime: standalone ANIX package bundles v2 language support and gaming docs"
        built = subprocess.run(["scripts/package-anix.py"], cwd=ctx.repo, env=_env(ABORA_OUT_DIR=str(anix_out)), stdout=subprocess.DEVNULL)
        packages = sorted((anix_out / "packages").glob("anix-*-abora-*.tar.gz")) if built.returncode == 0 else []
        listing = work / "anix-package-files.txt"
        if packages:
            with tarfile.open(packages[0]) as archive:
                listing.write_text("".join(f"{member.name}{'/' if member.isdir() else ''}\n" for member in archive.getmembers()))
        ctx.result(bool(packages) and all(ctx.grep("-q", entry, str(listing)) for entry in (
            "anix/share/anix/languages/mako.json",
            "anix/share/anix/languages/moducpp.json",
            "anix/share/anix/tools/moducpp-anix",
            "anix/share/anix/docs/wiki/ANIX-V2-Languages.md",
            "anix/share/anix/docs/wiki/Abora-Gaming.md",
        )), name)

        out = work / "metadata"
        for directory in ("iso", "packages", "release"):
            (out / directory).mkdir(parents=True)
        for edition in ("cosmic", "hyprland", "gnome", "kde", "other"):
            (out / "iso" / f"abora-{edition}-test-x86_64-{tag}.iso").touch()
        (out / "packages" / f"tinypm-v0.0.0-abora-{tag}.tar.gz").touch()
        (out / "packages" / f"anix-v0.0.0-abora-{tag}.tar.gz").touch()
        sums = out / "release" / f"SHA256SUMS-{tag}.txt"
        generated = subprocess.run(["scripts/release-metadata.py"], cwd=ctx.repo, env=_env(ABORA_OUT_DIR=str(out), ABORA_RELEASE_STAMP="test"), stdout=subprocess.DEVNULL)
        ctx.result(
            generated.returncode == 0
            and sums.is_file()
            and (out / "release" / f"RELEASE_MANIFEST-{tag}.txt").is_file()
            and (out / "release" / f"RELEASE_NOTES-{tag}.md").is_file()
            and all(ctx.grep("-q", f"abora-{edition}-test-x86_64-{tag}.iso", str(sums)) for edition in ("cosmic", "hyprland", "gnome", "kde", "other"))
            and ctx.grep("-q", f"tinypm-v0.0.0-abora-{tag}.tar.gz", str(sums))
            and ctx.grep("-q", f"anix-v0.0.0-abora-{tag}.tar.gz", str(sums)),
            "runtime: release-metadata checksum generation includes every edition",
        )

        fallback = work / "fallback"
        for directory in ("iso", "packages", "release"):
            (fallback / directory).mkdir(parents=True)
        for edition in ("cosmic", "gnome"):
            (fallback / "iso" / f"abora-{edition}-2026.01.01-x86_64-{tag}.iso").touch()
        for edition in ("cosmic", "hyprland", "gnome", "kde", "other"):
            (fallback / "iso" / f"abora-{edition}-2026.07.27-x86_64-{tag}.iso").touch()
        fallback_sums = fallback / "release" / f"SHA256SUMS-{tag}.txt"
        generated = subprocess.run(["scripts/release-metadata.py"], cwd=ctx.repo, env=_env(ABORA_OUT_DIR=str(fallback)), stdout=subprocess.DEVNULL)
        ctx.result(
            generated.returncode == 0
            and fallback_sums.is_file()
            and ctx.grep("-q", f"abora-cosmic-2026.07.27-x86_64-{tag}.iso", str(fallback_sums))
            and ctx.grep("-q", f"abora-other-2026.07.27-x86_64-{tag}.iso", str(fallback_sums))
            and not ctx.grep("-q", "2026.01.01", str(fallback_sums)),
            "runtime: release-metadata falls back to newest local ISO stamp",
        )

        empty = work / "empty"
        empty.mkdir()
        guard = subprocess.run(["scripts/release-metadata.py"], cwd=ctx.repo, env=_env(ABORA_OUT_DIR=str(empty)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        ctx.result(ctx.grep("-q", "No ISO files found", stdin=guard.stdout), "runtime: release-metadata empty-dir guard")


def workflows(ctx: Context) -> None:
    Check(
        "runtime: GitHub workflows publish generated release bundle paths",
        grep("-q", "out/iso/.*iso", ".github/workflows/build-iso.yml"),
        lambda c: c.grep("-q", "edge", stdin=c.grep_output("-A2", "branches:", ".github/workflows/build-iso.yml")),
        lambda c: c.grep("-q", "edge", stdin=c.grep_output("-A2", "branches:", ".github/workflows/publish-tinypm-package.yml")),
        grep("-q", "edge only", ".github/workflows/flake-check.yml"),
        grep("-q", "vendor/tinypm/Cargo.toml", ".github/workflows/publish-tinypm-package.yml"),
        grep("-q", "out/packages/tinypm", ".github/workflows/build-iso.yml"),
        grep("-q", "out/packages/anix", ".github/workflows/build-iso.yml"),
        grep("-q", "out/release/SHA256SUMS", ".github/workflows/build-iso.yml"),
        grep("-q", "out/packages/tinypm", ".github/workflows/release-iso.yml"),
        grep("-q", "out/packages/anix", ".github/workflows/release-iso.yml"),
        grep("-q", "out/release/RELEASE_NOTES", ".github/workflows/release-iso.yml"),
        grep("-q", "Abora OS v4 Everest (${tag})", ".github/workflows/release-iso.yml"),
    ).run(ctx)
    Check(
        "runtime: TinyPM container builds the real Rust binaries",
        grep("-q", "COPY --from=build /build/target/release/tinypm /usr/local/bin/tinypm", "packaging/tinypm/Dockerfile"),
        grep("-q", "COPY --from=build /build/target/release/grab /usr/local/bin/grab", "packaging/tinypm/Dockerfile"),
        grep("-q", "cargo build --release --locked", "packaging/tinypm/Dockerfile"),
        test("-f", "vendor/tinypm/Cargo.toml"),
        test("-f", "vendor/tinypm/src/bin/grab.rs"),
    ).run(ctx)


def file_sweep_listing(ctx: Context) -> None:
    # check-all-files must prune obj/bin/target: C# and Rust leave generated JSON there
    # that git ignores but a filesystem walk would otherwise "check" as source.
    with tempfile.TemporaryDirectory(prefix="abora-check-findfiles-") as tmp:
        tree = Path(tmp)
        for directory in ("nix/pkgs", "tools/fake-project/obj/Debug", "tools/rust-crate/target/debug"):
            (tree / directory).mkdir(parents=True)
        (tree / "nix/pkgs/real-deps.json").write_text('{"real": true}\n')
        (tree / "tools/fake-project/obj/Debug/project.assets.json").write_text('{"generated": true}\n')
        (tree / "tools/rust-crate/target/debug/build.json").write_text('{"generated": true}\n')
        listed = subprocess.run(["scripts/check-all-files.py", "--list-files", "json", str(tree)], cwd=ctx.repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        output = listed.stdout if listed.returncode == 0 else listed.stdout + "<listing failed>"
    name = "runtime: check-all-files' find_files() excludes generated build artifacts"
    passed = (
        ctx.grep("-qx", "nix/pkgs/real-deps.json", stdin=output)
        and not ctx.grep("-q", "obj/Debug/project.assets.json", stdin=output)
        and not ctx.grep("-q", "target/debug/build.json", stdin=output)
    )
    if not ctx.result(passed, name):
        ctx.detail(f"found: {output}")


def rebuild_vm_branch(ctx: Context) -> None:
    # A fresh-workspace clone without --branch silently built the default branch
    # (stable) instead of the requested one. Runs the real script against a local
    # two-branch repo; its build step is expected to fail here, only the clone matters.
    if subprocess.run(["git", "--version"], stdout=subprocess.DEVNULL).returncode != 0:
        ctx.ok("git unavailable (rebuild-vm branch test skipped)")
        return
    with tempfile.TemporaryDirectory(prefix="abora-check-vm-") as tmp:
        source, workspace = Path(tmp) / "repo", Path(tmp) / "workspace"
        source.mkdir()

        def git(*args: str) -> None:
            subprocess.run(["git", "-C", str(source), *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        git("init", "-q")
        git("config", "user.email", "a@b.c")
        git("config", "user.name", "test")
        (source / "MARKER.txt").write_text("stable-fake\n")
        git("checkout", "-q", "-b", "stable")
        git("add", "MARKER.txt")
        git("commit", "-q", "-m", "stable")
        git("checkout", "-q", "-b", "edge")
        (source / "MARKER.txt").write_text("edge-fake\n")
        git("commit", "-q", "-am", "edge")
        git("symbolic-ref", "HEAD", "refs/heads/stable")
        git("checkout", "-q", "stable")

        subprocess.run(
            [str(ctx.path("scripts/rebuild-vm.py"))], cwd="/tmp",
            env=_env(ABORA_VM_WORKSPACE=str(workspace), ABORA_REPO_URL=str(source), ABORA_REPO_BRANCH="edge"),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        checkout = workspace / "abora-os"
        branch = subprocess.run(["git", "-C", str(checkout), "branch", "--show-current"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
        marker = (checkout / "MARKER.txt").read_text().strip() if (checkout / "MARKER.txt").is_file() else ""
    if not ctx.result(branch == "edge" and marker == "edge-fake", "runtime: rebuild-vm clones the requested branch on a fresh workspace"):
        ctx.detail(f"branch after: {branch}, marker after: {marker} (wanted edge / edge-fake)")


def _env(**values: str) -> dict[str, str]:
    return {**os.environ, **values}


def run(ctx: Context) -> None:
    tag = release_tag(ctx)
    release_files(ctx)
    packages_and_metadata(ctx, tag)
    workflows(ctx)
    file_sweep_listing(ctx)
    rebuild_vm_branch(ctx)
