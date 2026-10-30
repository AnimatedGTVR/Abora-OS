"""Abora's shared core for its Python tools: the terminal UI and redacting secrets.

The support tools (doctor, recovery, welcome, check-full, support-report, hardware-test) each used
to carry their own copy of this code, kept identical by tests, because an update from Abora 4.0 or
4.1 copied every tool by a fixed list and a new shared file would never have arrived. Updates
install new files since 4.1.1, so this is now one module, the start of the Unified Abora Core.

Where it lives: beside the tools in a checkout, on the live ISO and in the hardware-test package;
in /etc/abora on an installed system (where each tool is its own file in the Nix store). Each tool
adds both places to its import path before importing it.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

# ── UI ────────────────────────────────────────────────────────────────────────
# The Python port of the abora-ui.sh primitives.

BLUE = "\033[38;5;33m"
ACCENT = "\033[38;5;87m"
CYAN = "\033[38;5;44m"
YELLOW = "\033[38;5;222m"
WHITE = "\033[1;97m"
DIM = "\033[38;5;242m"
FAINT = "\033[38;5;237m"
GREEN = "\033[38;5;77m"
RED = "\033[38;5;203m"
NC = "\033[0m"


def ui_setup() -> None:
    # Line buffering keeps our output ordered with the child processes we run.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)


def ui_version() -> str:
    if os.environ.get("ABORA_VERSION"):
        return os.environ["ABORA_VERSION"]
    try:
        return "".join(Path("/etc/abora/VERSION").read_text(encoding="utf-8").split())
    except OSError:
        return "v4.2 Solstice"


def ui_cols() -> int:
    return shutil.get_terminal_size((80, 24)).columns


def rule() -> None:
    print(f"  {FAINT}{'─' * (ui_cols() - 4)}{NC}")


def brand_header() -> None:
    inner = max(ui_cols() - 6, 18)
    left, right = "  ▸ ABORA OS", f"{ui_version()}  "
    max_left = max(inner - len(right) - 1, 6)
    if len(left) > max_left:
        left = left[: max_left - 3] + "..."
    pad = max(inner - len(left) - len(right), 1)
    print(f"{BLUE}╭{'─' * inner}╮{NC}")
    print(f"{BLUE}│{NC}{WHITE}{left}{NC}{' ' * pad}{DIM}{right}{NC}{BLUE}│{NC}")
    print(f"{BLUE}╰{'─' * inner}╯{NC}")


def banner(title: str = "", subtitle: str = "") -> None:
    print()
    brand_header()
    if title:
        print(f"\n  {WHITE}{title}{NC}")
    if subtitle:
        print(f"  {DIM}{subtitle}{NC}")
    print()
    rule()
    print()


def info(message: str) -> None:
    print(f"  {BLUE}·{NC}  {message}")


def success(message: str) -> None:
    print(f"  {GREEN}✓{NC}  {GREEN}{message}{NC}")


def warning(message: str) -> None:
    print(f"  {YELLOW}!{NC}  {YELLOW}{message}{NC}")


def error(message: str) -> None:
    print(f"  {RED}✗{NC}  {RED}{message}{NC}", file=sys.stderr)


def step(message: str) -> None:
    print(f"  {CYAN}▸{NC}  {message}")


def dim_line(message: str) -> None:
    print(f"  {DIM}{message}{NC}")


def kv(key: str, value: str, width: int = 18) -> None:
    print(f"  {BLUE}│{NC}  {DIM}{key:<{width}}{NC}  {CYAN}{value}{NC}")


def _card_inner() -> int:
    return min(max(ui_cols() - 6, 20), 70)


def card_start(title: str = "") -> None:
    inner = _card_inner()
    if title:
        body = f"{ACCENT} {title} " + "─" * max(inner - len(title) - 3, 0)
    else:
        body = "─" * inner
    print(f"  {BLUE}╭─{body}╮{NC}")


def card_end() -> None:
    print(f"  {BLUE}╰{'─' * (_card_inner() + 1)}╯{NC}")


# ── redaction ─────────────────────────────────────────────────────────────────
# Obvious secrets: `key = value` / `key: value` credential pairs, and user:password@ URLs. Ported
# from the sed script these tools used, keeping its POSIX longest-match semantics where Python's
# first-match would differ.

# The key list has to cover networking.wireless.networks.*.psk: NixOS stores the plaintext Wi-Fi passphrase
# there, and configuration.nix is copied into these reports verbatim. The '' alternative catches Nix indented
# strings (psk = ''secret''): without it the ordinary single-quote branch matches the leading '' as an empty value
# and leaves the passphrase in the report. It redacts to end of line so an unterminated indented string still fails
# closed. The authorization rule is separate because a header puts the credential after a scheme word
# ("Bearer <token>"), which the key=value rule cannot reach -- dmesg and journalctl carry those routinely. It also
# runs to end of line, because a Digest header keeps credentials in later parameters (realm=, response=) well past
# the first space.
SECRET_KEY = re.compile(r"(^|[^A-Za-z0-9_])(hashedPassword|password|passwd|psk|pskRaw|preSharedKey|secret|token|api[_-]?key)(\s*[:=]\s*)", re.IGNORECASE)
SECRET_VALUES = (re.compile(r'"[^"]*"'), re.compile(r"''.*"), re.compile(r"'[^']*'"), re.compile(r"[^\s;]+"))
AUTHORIZATION = re.compile(r"((?:proxy-)?authorization\s*:\s*)((?:bearer|basic|token|digest)\s+)?.*", re.IGNORECASE)
# The trailing "@" is what makes this a credential URL: without it any bare
# "word:word" (timestamps, host:port) would be redacted too.
CREDENTIAL_URL = re.compile(r"(github\.com/\S+://)?([^\s@/]+):([^\s@]+)@")

# A Nix indented string spanning several lines --
#   psk = ''
#     passphrase
#   '';
# -- would have its opening line redacted while the passphrase sat untouched on the next line, which reads as
# sanitised and is not. So credential blocks are collapsed first (the opening line stays, the body and closing
# line are dropped). A block opens only on a credential key, so an ordinary indented string such as
# extraConfig = '' ... '' passes through intact.
CREDENTIAL_BLOCK_OPEN = re.compile(r"(hashedpassword|password|passwd|psk|pskraw|presharedkey|secret|token|api[_-]?key)[ \t]*[:=][ \t]*''")


def collapse_credential_blocks(text: str) -> str:
    out, in_block = [], False
    for line in text.split("\n"):
        if in_block:
            if line.count("''") > 0:
                in_block = False
            continue
        if CREDENTIAL_BLOCK_OPEN.search(line.lower()) and line.count("''") == 1 and re.search(r"''[ \t]*$", line):
            in_block = True
        out.append(line)
    return "\n".join(out)


def redact_line(line: str) -> str:
    out, pos = [], 0
    search_from = 0
    while (key := SECRET_KEY.search(line, search_from)) is not None:
        # sed takes the longest of the value alternatives, not the first.
        value_end = max((m.end() for p in SECRET_VALUES if (m := p.match(line, key.end()))), default=None)
        if value_end is None:
            search_from = key.start() + 1
            continue
        out.append(line[pos:key.end()] + '"[redacted]"')
        pos = search_from = value_end
    out.append(line[pos:])
    line = AUTHORIZATION.sub(lambda m: m.group(1) + (m.group(2) or "") + "[redacted]", "".join(out))
    return CREDENTIAL_URL.sub("[redacted-user]:[redacted]@", line)


def redact(text: str) -> str:
    return "\n".join(redact_line(line) for line in collapse_credential_blocks(text).split("\n"))
