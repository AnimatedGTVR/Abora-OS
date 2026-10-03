"""Rendering a comparison (see comparison.py) as terminal text or Markdown.

Measured metrics and human evaluation are always printed as separate tables.
Metrics are rows and implementations are columns, which stays readable as the
metric list grows.
"""

from __future__ import annotations

import json
from typing import Any

from .ui import human_bytes, human_seconds, pad, visible_len

KIND_MARK = {"measured": "", "heuristic": " (heuristic)", "declared": " (declared)"}


def _format(key: str, value: Any) -> str:
    if value is None:
        return "-"
    if key.endswith("_s"):
        return human_seconds(value)
    if key.endswith("_rss_kb"):
        return human_bytes(value * 1024)
    if key.endswith("_bytes"):
        return human_bytes(value)
    return str(value)


def _measured_table(comparison: dict[str, Any]) -> tuple[list[str], list[list[str]]]:
    impls = comparison["implementations"]
    headers = ["Metric", *[i["id"] for i in impls]]
    rows = [
        ["Language", *[i["language"] for i in impls]],
        ["Safety", *[i["safety"] for i in impls]],
    ]
    for metric in comparison["metrics"]:
        label = metric["label"] + KIND_MARK[metric["kind"]]
        rows.append([label, *[_format(metric["key"], i["measured"].get(metric["key"])) for i in impls]])
    rows.append(["Measured at", *[(i["updated_at"] or "never") for i in impls]])
    rows.append(["Commit", *[(i["commit"] or "-") for i in impls]])
    return headers, rows


def _human_table(comparison: dict[str, Any]) -> tuple[list[str], list[list[str]]] | None:
    impls = comparison["implementations"]
    if not any(i["human"] for i in impls):
        return None
    headers = ["Evaluation", *[i["id"] for i in impls]]
    rows = [["Lifecycle status", *[i["lifecycle"] for i in impls]]]
    score_names = sorted({name for i in impls if i["human"] for name in i["human"]["scores"]})
    for name in score_names:
        rows.append([f"{name} (1-5)", *[str((i["human"] or {}).get("scores", {}).get(name, "-")) for i in impls]])
    rows.append(["Feature completeness", *[_completeness(i["human"]) for i in impls]])
    for feature in comparison["features"]:
        rows.append([f"  {feature}", *[((i["human"] or {}).get("features") or {}).get(feature, "-") for i in impls]])
    rows.append(["Reviewer", *[_reviewer(i["human"]) for i in impls]])
    return headers, rows


def _completeness(human: dict[str, Any] | None) -> str:
    if not human or not human.get("completeness"):
        return "-"
    c = human["completeness"]
    return f"{c['points']:g}/{c['of']}"


def _reviewer(human: dict[str, Any] | None) -> str:
    if not human:
        return "not reviewed"
    return f"{human.get('reviewer') or 'unknown'} ({human.get('reviewed') or 'undated'})"


def _text_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    widths = [max(visible_len(r[i]) for r in [headers, *rows]) for i in range(len(headers))]
    lines = ["  ".join(pad(h, widths[i]) for i, h in enumerate(headers)).rstrip()]
    lines.append("  ".join("-" * w for w in widths))
    lines += ["  ".join(pad(c, widths[i]) for i, c in enumerate(row)).rstrip() for row in rows]
    return lines


def _md_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def _md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(_md_cell(h) for h in headers) + " |"]
    lines.append("|" + "|".join("---" for _ in headers) + "|")
    lines += ["| " + " | ".join(_md_cell(c) for c in row) + " |" for row in rows]
    return lines


def render(comparison: dict[str, Any], fmt: str) -> str:
    if fmt == "json":
        return json.dumps(comparison, indent=2) + "\n"
    markdown = fmt == "markdown"
    table = _md_table if markdown else _text_table
    h1, h2 = ("# ", "## ") if markdown else ("", "")
    out: list[str] = [f"{h1}Abora Labs comparison: {comparison['area']}", ""]
    if comparison["question"]:
        out += [f"Question: {comparison['question']}", ""]
    if not comparison["implementations"]:
        return "\n".join(out + ["No implementations found."]) + "\n"

    out += [f"{h2}Measured metrics", ""]
    out += table(*_measured_table(comparison))
    out += ["", "Measured values come from the most recent stored run of each implementation.",
            "(heuristic) values are approximate; (declared) values come from experiment.toml.", ""]

    out += [f"{h2}Human evaluation (not measured)", ""]
    human = _human_table(comparison)
    out += table(*human) if human else ["No human evaluation recorded."]
    notes = [(i["id"], i["human"]["notes"]) for i in comparison["implementations"] if i["human"] and i["human"].get("notes")]
    for impl_id, text in notes:
        out += ["", f"{impl_id}: {text.strip()}"]
    out.append("")

    risky = [i for i in comparison["implementations"] if i["risks"]]
    if risky:
        out += [f"{h2}Declared risks", ""]
        out += [f"- {i['id']} ({i['safety']}): {'; '.join(i['risks'])}" for i in risky]
        out.append("")

    toolchains = [(i["id"], i["toolchain"]) for i in comparison["implementations"] if i["toolchain"]]
    if toolchains:
        out += [f"{h2}Toolchains", ""]
        for impl_id, tools in toolchains:
            out += [f"- {impl_id}: " + "; ".join(f"{k}: {v or 'version unknown'}" for k, v in tools.items())]
        out.append("")

    if comparison["notes"]:
        out += [f"{h2}Notes", ""]
        out += [f"- {note}" for note in comparison["notes"]]
        out.append("")
    return "\n".join(out)
