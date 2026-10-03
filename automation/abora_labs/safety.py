"""Safety classification and the host execution policy.

Levels are ordered by how much isolation an action needs:

    SAFE < PRIVILEGED < VM_ONLY < DESTRUCTIVE

The policy is deliberately simple and has no override for the two top levels:
the host executor will never run a VM_ONLY or DESTRUCTIVE stage. When a VM
executor exists it gets its own decision function; the host rules stay.

The command lint is a tripwire for honest mistakes (a stage declared `safe`
that obviously runs `mkfs`). It is not a sandbox and cannot see what a
compiled program does at runtime.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import IntEnum

STAGES = ("build", "test", "run", "clean")


class Level(IntEnum):
    SAFE = 0
    PRIVILEGED = 1
    VM_ONLY = 2
    DESTRUCTIVE = 3

    @property
    def label(self) -> str:
        return self.name.lower()

    @classmethod
    def parse(cls, value: str) -> Level:
        return cls[value.upper()]


LEVEL_NAMES = tuple(level.label for level in Level)

LEVEL_MEANING = {
    Level.SAFE: "runs as the current user and only touches its own directory",
    Level.PRIVILEGED: "needs root or changes host state, but is not expected to destroy data",
    Level.VM_ONLY: "must run in a disposable VM or test environment",
    Level.DESTRUCTIVE: "can destroy data (disks, partitions, bootloaders); VM only, never the host",
}


@dataclass(frozen=True)
class Decision:
    allowed: bool
    reason: str


def host_decision(level: Level, allow_privileged: bool) -> Decision:
    if level is Level.SAFE:
        return Decision(True, "safe on host")
    if level is Level.PRIVILEGED:
        if allow_privileged:
            return Decision(True, "privileged stage allowed by --allow-privileged")
        return Decision(False, "privileged stage; re-run with --allow-privileged to run it on this host")
    if level is Level.VM_ONLY:
        return Decision(False, "vm_only stage; requires a VM executor (not implemented yet), never runs on the host")
    return Decision(False, "destructive stage; requires a VM executor (not implemented yet), never runs on the host")


@dataclass(frozen=True)
class LintRule:
    id: str
    level: Level
    pattern: re.Pattern[str]
    description: str


def _rule(rule_id: str, level: Level, pattern: str, description: str) -> LintRule:
    return LintRule(rule_id, level, re.compile(pattern), description)


LINT_RULES: tuple[LintRule, ...] = (
    _rule("mkfs", Level.DESTRUCTIVE, r"\bmkfs(\.\w+)?\b|\bmkswap\b", "creates a filesystem"),
    _rule("wipefs", Level.DESTRUCTIVE, r"\bwipefs\b|\bblkdiscard\b", "wipes a block device"),
    _rule("partition", Level.DESTRUCTIVE, r"\b(sfdisk|sgdisk|gdisk|fdisk|parted|cfdisk)\b", "edits a partition table"),
    _rule("dd-device", Level.DESTRUCTIVE, r"\bdd\b[^|;&\n]*\bof=/dev/", "writes raw data to a device"),
    _rule("redirect-device", Level.DESTRUCTIVE, r">\s*/dev/(sd|hd|vd|nvme|mmcblk|disk)", "writes to a block device"),
    _rule("bootloader", Level.DESTRUCTIVE, r"\bgrub-install\b|\bbootctl\s+(install|update|remove)\b|\befibootmgr\b", "changes the bootloader"),
    _rule("nixos-install", Level.DESTRUCTIVE, r"\bnixos-install\b", "installs NixOS onto a target"),
    _rule("luks-format", Level.DESTRUCTIVE, r"\bcryptsetup\s+(luksFormat|erase)\b", "formats an encrypted volume"),
    _rule("rm-root", Level.DESTRUCTIVE, r"\brm\s+(-\w+\s+)*(/|/\*|~/?)(\s|$)", "removes the root or home directory"),
    _rule("sudo", Level.PRIVILEGED, r"\b(sudo|doas|pkexec|run0)\b", "elevates privileges"),
    _rule("nixos-rebuild", Level.PRIVILEGED, r"\bnixos-rebuild\s+(switch|boot|test)\b", "changes the running NixOS system"),
    _rule("mount", Level.PRIVILEGED, r"(^|[\s;&|(])(u?mount)\s", "mounts or unmounts filesystems"),
    _rule("kernel-module", Level.PRIVILEGED, r"\b(modprobe|insmod|rmmod)\b", "loads or unloads kernel modules"),
    _rule("systemctl-system", Level.PRIVILEGED, r"\bsystemctl\s+(?!--user)(start|stop|restart|enable|disable|mask)\b", "changes system services"),
    _rule("sysctl-write", Level.PRIVILEGED, r"\bsysctl\s+-w\b", "changes kernel parameters"),
)


@dataclass(frozen=True)
class LintFinding:
    rule: LintRule
    where: str
    excerpt: str


def lint_text(text: str, where: str, acknowledged: tuple[str, ...] = ()) -> list[LintFinding]:
    findings = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        for rule in LINT_RULES:
            if rule.id not in acknowledged and rule.pattern.search(stripped):
                findings.append(LintFinding(rule, where, stripped[:120]))
    return findings
