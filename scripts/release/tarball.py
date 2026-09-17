"""Deterministic-order .tar.gz writing for the release packagers.

Entries are written exactly as listed, with explicit modes, so an archive's
layout never depends on a staging directory, the umask, or `cp` flags.
"""

from __future__ import annotations

import fnmatch
import grp
import io
import os
import pwd
import tarfile
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Entry:
    """One archive member.

    source=None and data=None: a directory.
    data: a regular file with these bytes.
    source: a copy of that file or symlink.
    mode=None copies like `cp -a`: the source's own permission bits, symlinks kept as symlinks.
    A fixed mode copies like `install -m`: symlinks are followed.
    """

    name: str
    source: Path | None = None
    mode: int | None = 0o755
    data: bytes | None = None


def tree_entries(source_dir: Path, prefix: str, exclude: tuple[str, ...] = ()) -> list[Entry]:
    """Everything under source_dir (not the directory itself), keeping modes and symlinks,
    skipping any path component that matches an `exclude` glob."""
    entries = []
    for current, dirnames, filenames in os.walk(source_dir):
        dirnames[:] = sorted(d for d in dirnames if not _excluded(d, exclude))
        relative = Path(current).relative_to(source_dir)
        base = prefix if relative == Path(".") else f"{prefix}/{relative.as_posix()}"
        for directory in dirnames:
            path = Path(current) / directory
            if path.is_symlink():
                entries.append(Entry(f"{base}/{directory}", path, None))
            else:
                entries.append(Entry(f"{base}/{directory}", None, path.stat().st_mode & 0o7777))
        for filename in sorted(f for f in filenames if not _excluded(f, exclude)):
            entries.append(Entry(f"{base}/{filename}", Path(current) / filename, None))
    return entries


def _excluded(name: str, exclude: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in exclude)


def write_tar_gz(path: Path, entries: list[Entry], exclude: tuple[str, ...] = ()) -> None:
    uid, gid = os.getuid(), os.getgid()
    uname = _lookup(lambda: pwd.getpwuid(uid).pw_name)
    gname = _lookup(lambda: grp.getgrgid(gid).gr_name)
    now = int(time.time())

    with tarfile.open(path, "w:gz", format=tarfile.GNU_FORMAT) as archive:
        for entry in entries:
            if any(_excluded(part, exclude) for part in entry.name.split("/")):
                continue
            info = tarfile.TarInfo(entry.name)
            info.uid, info.gid, info.uname, info.gname = uid, gid, uname, gname
            info.mtime = now
            payload = None

            if entry.data is not None:
                info.type = tarfile.REGTYPE
                info.size = len(entry.data)
                info.mode = 0o644 if entry.mode is None else entry.mode
                payload = io.BytesIO(entry.data)
            elif entry.source is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755 if entry.mode is None else entry.mode
            elif entry.source.is_symlink() and entry.mode is None:
                # Only `cp -a`-style copies keep symlinks; a fixed mode means `install`, which follows them.
                info.type = tarfile.SYMTYPE
                info.linkname = os.readlink(entry.source)
                info.mode = 0o777
                info.mtime = int(entry.source.lstat().st_mtime)
            else:
                stat = entry.source.stat()
                info.type = tarfile.REGTYPE
                info.size = stat.st_size
                info.mode = stat.st_mode & 0o7777 if entry.mode is None else entry.mode
                info.mtime = int(stat.st_mtime) if entry.mode is None else now
                payload = entry.source.open("rb")

            try:
                archive.addfile(info, payload)
            finally:
                if payload is not None:
                    payload.close()


def _lookup(get) -> str:
    try:
        return get()
    except KeyError:
        return ""
