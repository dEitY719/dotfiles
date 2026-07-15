#!/usr/bin/env python3
"""Claude Code Stop hook: mechanical step-skip guard for standalone multi-step skills (issue #753).

Generalizes the boundary-detection / counting logic from
`gh_issue_flow_stop_guard.py` (#383) into a catalog-driven guard that
backstops INNER steps of individually-invoked skills (gh:issue-implement,
gh:pr, gh:commit, …). The motivation is identical: prompt rules in
SKILL.md alone are insufficient — the harness must mechanically force
the model to emit a completion marker per step before allowing turn end.

Sister hook of `gh_issue_flow_stop_guard.py`:
  - That one guards the OUTER 5-sub-skill chain of `/gh-issue-flow`.
  - This one guards INNER required-step emit of each catalog skill.
  - Both can coexist on the Stop hook chain — if either says block, the
    model is re-prompted with the union of their reasons.

Step ID emit contract:
  Each protected SKILL.md emits a literal `[step:<skill>/<id>] OK` line
  at the end of every required step (typically via `printf` in a Bash
  block). The hook scans assistant text AND tool_result blocks for
  these markers — tool_result is required because `printf` output from
  a Bash tool call lands there, not in assistant text.

Safety rails (each critical — never accidentally trap the user):
  - Empty / unreadable / malformed stdin → exit 0 (allow stop).
  - Missing or unreadable transcript_path → exit 0.
  - `stop_hook_active == True` → exit 0 (already blocked once in this
    chain; bowing out prevents an infinite Stop→block→Stop loop).
  - No catalog skill boundary in the transcript → exit 0 (not our flow).
  - Catalog file missing / unparseable YAML → exit 0 (fail-open + warn).
  - `GH_SKILL_GUARD_BYPASS=1` → exit 0 (manual escape hatch).
  - All required step IDs present after the most recent boundary → exit 0.
  - Any unexpected exception → exit 0 (fail open).

The hook only ever does two things: emit nothing (allow), or emit one
JSON object `{"decision":"block","reason":"..."}` on stdout (block + nudge).
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover — PyYAML is in dev deps; this is a defensive fallback
    yaml = None  # type: ignore[assignment]

# Opt-in stderr trace for debugging. Default off so production stays silent.
_TRACE_ENABLED: bool = os.environ.get("GH_SKILL_GUARD_TRACE") == "1"

# Manual escape hatch (issue #753 acceptance criteria).
_BYPASS_ENABLED: bool = os.environ.get("GH_SKILL_GUARD_BYPASS") == "1"

# Default catalog path — co-located with this hook. Override with
# `GH_SKILL_GUARD_CATALOG=/abs/path/to/yml` (used by tests).
_DEFAULT_CATALOG: Path = Path(__file__).resolve().parent / "skill_step_catalog.yml"

# Regex that captures literal `[step:<skill>/<id>] OK` markers in transcript
# text. `OK` is the discriminator that keeps the pattern unique enough that
# accidental documentation reads of the catalog/hook source don't trigger
# false positives (the catalog YAML stores the bare ids without the wrapper,
# and the hook source uses the regex form which doesn't satisfy the literal).
_STEP_EMIT_RE: re.Pattern[str] = re.compile(
    r"\[step:(?P<skill>[A-Za-z0-9_:.-]+)/(?P<step>[A-Za-z0-9_.-]+)\]\s+OK\b",
)


def _trace(message: str, *, layer: str | None = None) -> None:
    """Emit a `[skill-guard]` trace line on stderr when trace mode is on.

    `layer` mirrors the `gh_issue_flow_stop_guard.py` taxonomy:
      - `L1`   — boundary detection (`_find_catalog_boundaries`)
      - `L1.5` — step-emit scan (`_scan_steps_after_boundary`)
      - `L2`   — catalog load failure (`_load_catalog`)
    """
    if _TRACE_ENABLED:
        try:
            tag = f" layer={layer}" if layer else ""
            print(f"[skill-guard] {message}{tag}", file=sys.stderr, flush=True)
        except OSError:
            pass


def _allow(trace_reason: str = "", *, layer: str | None = None) -> int:
    """Allow the stop. Hook protocol: silent stdout + exit 0."""
    if trace_reason:
        _trace(f"allow: {trace_reason}", layer=layer)
    return 0


def _block(reason: str, *, layer: str | None = None) -> int:
    """Block the stop with a directive shown to the model."""
    json.dump({"decision": "block", "reason": reason}, sys.stdout)
    _trace("block: catalog skill incomplete — re-prompting model", layer=layer)
    return 0


def _load_catalog(path: Path) -> dict[str, dict[str, Any]]:
    """Load the YAML catalog. Returns {} on any failure (fail-open)."""
    if yaml is None:
        _trace("PyYAML not importable — catalog disabled", layer="L2")
        return {}
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        _trace(f"catalog unreadable: {exc}", layer="L2")
        return {}
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:  # type: ignore[attr-defined]
        _trace(f"catalog YAML invalid: {exc}", layer="L2")
        return {}
    if not isinstance(data, dict):
        _trace("catalog top-level is not a mapping", layer="L2")
        return {}
    # Light schema normalization — only keep entries that have a `required`
    # list. Missing `enforce` defaults to False (warn-only).
    out: dict[str, dict[str, Any]] = {}
    for skill, body in data.items():
        if not isinstance(skill, str) or not isinstance(body, dict):
            continue
        required = body.get("required")
        if not isinstance(required, list) or not all(isinstance(s, str) for s in required):
            continue
        out[skill] = {
            "enforce": bool(body.get("enforce", False)),
            "description": str(body.get("description", "")),
            "required": list(required),
        }
    return out


def _build_boundary_regex(catalog: dict[str, dict[str, Any]]) -> re.Pattern[str]:
    """Build a multi-skill boundary regex from the catalog keys.

    Mirrors `gh_issue_flow_stop_guard.py._USER_BOUNDARY_RE` but lifted to a
    union over all catalog-listed skills. The four boundary surfaces from
    issue #608 still apply per-skill:
      (a) raw slash-command at line start
      (b) `<command-name>/<skill></command-name>` wrapper
      (c) `Base directory for this skill: …/<skill>` marker
      (d) the SKILL.md H1 line `# <skill> — …`
    """
    if not catalog:
        return re.compile(r"(?!x)x")  # match nothing
    names = sorted(catalog.keys())
    # Each name may appear in hyphen form (e.g. gh-pr) or colon namespace
    # form (gh:pr) — accept both at match time. The hyphen→colon mapping
    # is reversible because skill names don't contain colons in storage.
    name_alts: list[str] = []
    for n in names:
        hyphenated = re.escape(n)
        colonized = re.escape(n.replace("-", ":"))
        if hyphenated == colonized:
            name_alts.append(hyphenated)
        else:
            name_alts.append(f"(?:{hyphenated}|{colonized})")
    union = "|".join(name_alts)
    return re.compile(
        rf"""
        (?m)                                                    # multiline: ^ matches each line start
        (?:
            ^\s*/({union})(?![\w:-])                            # (a) raw slash command (hyphen/colon siblings excluded)
            |
            <command-name>\s*/({union})\s*</command-name>       # (b) wrapped form
            |
            ^Base\s+directory\s+for\s+this\s+skill:\s+.*?/({union})\s*$  # (c) skill base dir
            |
            ^\#\s+({union})\s+—\s+                              # (d) SKILL.md H1 line
        )
        """,
        re.VERBOSE,
    )


def _iter_text_blocks(message: dict[str, Any], include_tool_results: bool = False) -> list[str]:
    """Return all text-bearing chunks in a message's content array.

    `include_tool_results=False` is the safe default for boundary
    detection (file content mentioning a slash command must not trip the
    flow start). For step-marker scanning, callers pass True because the
    Bash printf output lives inside tool_result blocks.
    """
    parts: list[str] = []
    content = message.get("content")
    if isinstance(content, str):
        parts.append(content)
    elif isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text":
                t = block.get("text")
                if isinstance(t, str):
                    parts.append(t)
            elif btype == "tool_result" and include_tool_results:
                rc = block.get("content")
                if isinstance(rc, str):
                    parts.append(rc)
                elif isinstance(rc, list):
                    for sub in rc:
                        if isinstance(sub, dict) and sub.get("type") == "text":
                            st = sub.get("text")
                            if isinstance(st, str):
                                parts.append(st)
    return parts


def _iter_skill_uses(message: dict[str, Any]) -> list[str]:
    """Return Skill tool_use names invoked in this message."""
    out: list[str] = []
    content = message.get("content")
    if not isinstance(content, list):
        return out
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "tool_use":
            continue
        if block.get("name") != "Skill":
            continue
        tool_input = block.get("input")
        if not isinstance(tool_input, dict):
            continue
        skill = tool_input.get("skill")
        if isinstance(skill, str):
            out.append(skill)
    return out


def _load_transcript(path: Path) -> list[dict[str, Any]]:
    """Best-effort JSONL load. Skips malformed lines, never raises."""
    out: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    out.append(obj)
    except OSError:
        return []
    return out


def _message_payload(entry: dict[str, Any]) -> dict[str, Any]:
    """Return the inner `message` dict if present, else the entry itself."""
    inner = entry.get("message")
    return inner if isinstance(inner, dict) else entry


def _normalize_skill(name: str) -> str:
    """Map colon-namespace form (gh:pr) to canonical hyphen form (gh-pr)."""
    return name.replace(":", "-")


def _find_latest_catalog_boundary(
    messages: list[dict[str, Any]],
    catalog: dict[str, dict[str, Any]],
    boundary_re: re.Pattern[str],
) -> tuple[int, str] | None:
    """Return (index, skill_name) of the most recent catalog skill boundary.

    Boundary signals (role-restricted to avoid false positives from
    documentation reads landing in tool_result blocks):
      - assistant message: Skill tool_use whose name is in the catalog
      - user message: text content matches `boundary_re`

    Returns None when no catalog skill boundary is present.
    """
    for i in range(len(messages) - 1, -1, -1):
        msg = _message_payload(messages[i])
        role = msg.get("role")
        if role == "assistant":
            for skill in _iter_skill_uses(msg):
                normalized = _normalize_skill(skill)
                if normalized in catalog:
                    return (i, normalized)
        elif role == "user":
            for text in _iter_text_blocks(msg, include_tool_results=False):
                match = boundary_re.search(text)
                if not match:
                    continue
                # `_build_boundary_regex` wraps each of the 4 surfaces
                # (a/b/c/d) in a capturing group, so exactly one of
                # `match.groups()` is non-None and holds the matched
                # skill name (hyphen or colon form). `_normalize_skill`
                # collapses the form to the catalog key.
                matched_skill = next(g for g in match.groups() if g is not None)
                return (i, _normalize_skill(matched_skill))
    return None


def _next_catalog_boundary_after(
    messages: list[dict[str, Any]],
    start: int,
    catalog: dict[str, dict[str, Any]],
    boundary_re: re.Pattern[str],
) -> int:
    """Return the index of the next catalog skill boundary after `start`, or len(messages)."""
    for i in range(start + 1, len(messages)):
        msg = _message_payload(messages[i])
        role = msg.get("role")
        if role == "assistant":
            for skill in _iter_skill_uses(msg):
                if _normalize_skill(skill) in catalog:
                    return i
        elif role == "user":
            for text in _iter_text_blocks(msg, include_tool_results=False):
                if boundary_re.search(text):
                    return i
    return len(messages)


def _scan_steps_in_section(
    messages: list[dict[str, Any]],
    start: int,
    end: int,
    skill: str,
) -> set[str]:
    """Walk messages[start+1:end] and collect emitted step IDs for `skill`.

    Steps are detected by literal `[step:<skill>/<id>] OK` markers. Both
    assistant text AND tool_result blocks contribute — the Bash printf
    output from SKILL.md lands in tool_result.

    Note: we also collect colon-form `[step:gh:issue-implement/...]` IDs
    by normalizing the skill prefix at match time.
    """
    seen: set[str] = set()
    for entry in messages[start + 1 : end]:
        msg = _message_payload(entry)
        for text in _iter_text_blocks(msg, include_tool_results=True):
            for m in _STEP_EMIT_RE.finditer(text):
                matched_skill = _normalize_skill(m.group("skill"))
                if matched_skill != skill:
                    continue
                seen.add(m.group("step"))
    return seen


def main() -> int:
    if _BYPASS_ENABLED:
        return _allow("GH_SKILL_GUARD_BYPASS=1")

    raw = sys.stdin.read()
    if not raw.strip():
        return _allow("empty stdin")
    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        return _allow("malformed stdin JSON")
    if not isinstance(event, dict):
        return _allow("event is not a JSON object")

    if event.get("stop_hook_active"):
        return _allow("stop_hook_active=True (already blocked once)")

    transcript_path = event.get("transcript_path")
    if not isinstance(transcript_path, str) or not transcript_path:
        return _allow("missing transcript_path")
    p = Path(transcript_path)
    if not p.is_file():
        return _allow(f"transcript file not found: {transcript_path}")

    catalog_path_env = os.environ.get("GH_SKILL_GUARD_CATALOG")
    catalog_path = Path(catalog_path_env) if catalog_path_env else _DEFAULT_CATALOG
    catalog = _load_catalog(catalog_path)
    if not catalog:
        return _allow(f"catalog empty / unloadable: {catalog_path}", layer="L2")

    messages = _load_transcript(p)
    if not messages:
        return _allow("transcript empty / unreadable")

    boundary_re = _build_boundary_regex(catalog)
    boundary = _find_latest_catalog_boundary(messages, catalog, boundary_re)
    if boundary is None:
        return _allow("no catalog skill boundary in transcript", layer="L1")

    boundary_idx, skill = boundary
    entry = catalog[skill]
    required: list[str] = entry["required"]
    enforce: bool = entry["enforce"]

    end_idx = _next_catalog_boundary_after(messages, boundary_idx, catalog, boundary_re)
    seen = _scan_steps_in_section(messages, boundary_idx, end_idx, skill)
    missing = [step for step in required if step not in seen]

    if _TRACE_ENABLED:
        _trace(
            f"skill={skill} boundary={boundary_idx} section_end={end_idx} "
            f"seen={sorted(seen) or 'none'} missing={missing or 'none'} enforce={enforce}",
            layer="L1.5",
        )

    if not missing:
        return _allow(f"{skill}: all required steps emitted", layer="L1.5")

    if not enforce:
        return _allow(f"{skill}: missing steps but enforce=false", layer="L1.5")

    description = entry.get("description") or skill
    missing_list = ", ".join(missing)
    reason = (
        f"{skill} ({description}) incomplete: missing required step "
        f"emit(s) [{missing_list}]. The SKILL.md for this skill declares "
        f"these steps must each emit a literal `[step:{skill}/<id>] OK` "
        f"line (typically via a printf at the end of the step's Bash "
        f"block) before turn-end. Continue the skill from where it "
        f"stopped, emitting the missing markers. Set GH_SKILL_GUARD_BYPASS=1 "
        f"to override for one turn. Output zero conversational text "
        f"between the remaining steps."
    )
    return _block(reason, layer="L1.5")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Final fail-open. Never accidentally trap the user inside a turn.
        sys.exit(0)
