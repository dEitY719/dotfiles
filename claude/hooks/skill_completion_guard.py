#!/usr/bin/env python3
"""Claude Code Stop hook: mechanical step-skip guard for standalone multi-step skills (issue #753).

Generalizes the boundary-detection / counting logic from
`gh_issue_flow_stop_guard.py` (#383) into a catalog-driven guard that
backstops INNER steps of individually-invoked skills (gh-issue:implement,
gh-pr:create, gh-pr:commit, …). The motivation is identical: prompt rules in
SKILL.md alone are insufficient — the harness must mechanically force
the model to emit a completion marker per step before allowing turn end.

Sister hook of `gh_issue_flow_stop_guard.py`:
  - That one guards the OUTER 6-sub-skill chain of `/gh-flow:issue`.
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
  - Every still-missing step covered by a `[flow:async-wait]` marker
    within the grace limit → exit 0 (#1550 — work delegated to a
    background Agent, not abandoned).
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

# Issue #1550 — how many CONSECUTIVE `[flow:async-wait]` markers may stand in
# for one still-unemitted required step before the guard resumes blocking it.
_DEFAULT_ASYNC_WAIT_LIMIT: int = 2

# Issue #1550 — the marker the model prints as plain assistant text right
# before ending a turn whose remaining work it has handed to a
# background/async `Agent` (the Advisor/Worker delegation the user's global
# CLAUDE.md mandates for multi-file implementation work). Shape:
#
#   [flow:async-wait] step=<skill>/<step> agent=<agent-id> reason=background-worker-delegated
#
# Identical pattern to the one in `gh_issue_flow_stop_guard.py` — the two
# hooks read the same marker, they just derive different things from it (that
# one counts a streak per chain, this one per required step id).
#
# `agent` is required in the line — the transcript itself is the audit trail —
# but deliberately NOT captured and NOT used in any matching logic: making the
# grace depend on the model reproducing one exact literal id string turn after
# turn would be fragile in precisely the situation the marker exists for. A
# repeated marker with no intervening step emit is sufficient evidence of
# stagnation on its own.
#
# Scanned in `role=assistant` text blocks ONLY, with
# `include_tool_results=False` — asymmetric with `_STEP_EMIT_RE` above, which
# must read `tool_result` because the step markers come from a `printf` in a
# Bash call. This marker is only ever the model's own turn-ending prose, and a
# `tool_result` can carry arbitrary file content — including this file and
# the gh-flow:issue skill's `references/stop-guard.md`, both of which now
# document the marker literally. Reading tool_results here would
# false-positive on any `Read` of those files (the issue #608 precedent).
#
# Optional spaces around each `=` and optional double-quotes around each
# value are tolerated (agy review, PR #1594 FOLLOW-UP) — an LLM asked to
# reproduce a fixed-format line is prone to exactly this class of minor
# formatting drift, and a rigid regex turns that drift into a spurious block
# instead of the grace it was supposed to grant.
_ASYNC_WAIT_RE: re.Pattern[str] = re.compile(
    r'(?m)^\[flow:async-wait\]\s+step\s*=\s*"?(?P<step>[^\s"]+)"?'
    r'\s+agent\s*=\s*"?[^\s"]+"?\s+reason\s*=\s*"?background-worker-delegated"?\s*$'
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


def _separator_agnostic_pattern(name: str) -> str:
    """Return a regex alternative matching `name` with `-` or `:` separators.

    Regex counterpart of `_normalize_skill`, which collapses the colon form
    back to the canonical hyphen form after a match. A catalog key is always
    stored hyphenated (`gh-pr-create`), but the live command form puts a colon
    at the plugin-namespace boundary: `/gh-pr:create` (#1677). The pre-#1689
    pair — the whole name hyphenated OR the whole name colonized
    (`gh:pr:create`) — covered neither that spelling nor any other mixture, so
    no boundary surface matched a migrated skill and the guard silently failed
    open for it. Letting each separator vary independently accepts all 2**k
    spellings in a single alternative.

    Sibling exclusion is unaffected: surface (a)'s `(?![\\w:-])` lookahead is
    what rejects `/gh-pr-review` and `/gh-pr:review` as `gh-pr` (#1164).
    """
    return "[-:]".join(re.escape(part) for part in name.split("-"))


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
    union = "|".join(_separator_agnostic_pattern(n) for n in names)
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


def _async_wait_grace_limit() -> int:
    """Read the async-wait grace limit from the environment (#1550).

    Env var: `GH_SKILL_GUARD_ASYNC_WAIT_LIMIT`.
      - a valid non-negative int  → use it,
      - `0`                       → grace disabled (the very first marker
                                    occurrence already blocks),
      - unset / unparseable / negative → `_DEFAULT_ASYNC_WAIT_LIMIT`
        (unset reaches the `ValueError` arm via the `""` default).
    Never raises — a bad value silently degrades to the default.
    """
    try:
        value = int(os.environ.get("GH_SKILL_GUARD_ASYNC_WAIT_LIMIT", ""))
    except ValueError:
        return _DEFAULT_ASYNC_WAIT_LIMIT
    return value if value >= 0 else _DEFAULT_ASYNC_WAIT_LIMIT


def _count_async_waits_in_section(
    messages: list[dict[str, Any]],
    start: int,
    end: int,
    skill: str,
) -> dict[str, int]:
    """Count TRAILING consecutive `[flow:async-wait]` turns, per step id (#1550).

    A step's count is how many of the TRAILING consecutive assistant
    messages in the section (walking backward from the section's last
    message) carried THAT step's marker — not a flat total across the whole
    section. codex + agy review (PR #1594) both flagged the original
    flat-total version: an early marker for a step kept excusing it forever
    after, even on a later turn whose own latest message named no marker at
    all (or a real `[step:.../...] OK` for a DIFFERENT step, or plain
    prose). The walk stops the instant a message fails to renew a given
    step's claim, so the model must keep re-asserting the wait, turn after
    turn, for grace to keep applying to that step.

    Each assistant message contributes AT MOST 1 to a step's streak — a
    per-message "did this turn name this step" set, not a count of regex
    matches within it — so a single turn that happens to mention the marker
    more than once (e.g. quoted inside explanatory prose) cannot burn
    through the grace limit by itself (agy review).

    Only `role=assistant` text blocks are read, with
    `include_tool_results=False` — see `_ASYNC_WAIT_RE` for why that is
    asymmetric with the step-emit scan and must stay that way.

    The captured `step=` value is `<skill>/<step-id>`; its skill half goes
    through `_normalize_skill` before comparison, so
    `step=gh:issue-implement/implement` and
    `step=gh-issue-implement/implement` are both accepted. A value that does
    not name this section's skill is ignored — grace never crosses skills.
    """
    per_message_steps: list[set[str]] = []
    for entry in messages[start + 1 : end]:
        msg = _message_payload(entry)
        if msg.get("role") != "assistant":
            continue
        steps_here: set[str] = set()
        for text in _iter_text_blocks(msg, include_tool_results=False):
            for m in _ASYNC_WAIT_RE.finditer(text):
                matched_skill, _, step_id = m.group("step").rpartition("/")
                if not matched_skill or not step_id:
                    continue
                if _normalize_skill(matched_skill) != skill:
                    continue
                steps_here.add(step_id)
        per_message_steps.append(steps_here)

    all_steps: set[str] = set().union(*per_message_steps) if per_message_steps else set()
    counts: dict[str, int] = {}
    for step_id in all_steps:
        streak = 0
        for steps_here in reversed(per_message_steps):
            if step_id not in steps_here:
                break
            streak += 1
        if streak:
            counts[step_id] = streak
    return counts


def _async_wait_reprieved(
    messages: list[dict[str, Any]],
    start: int,
    end: int,
    skill: str,
    missing: list[str],
    limit: int,
) -> tuple[list[str], dict[str, int]]:
    """Partition `missing` by the async-wait grace (#1550).

    Returns `(still_missing, reprieved_counts)`. A step id is *reprieved*
    when its marker count is `> 0` and `<= limit`: the model said on the
    record that the work is delegated and in flight. Zero markers means it
    never said anything (no free pass), and a count past `limit` means it
    kept saying it with no step emit in between — stagnation, so the step
    returns to the blocked list.

    The reprieved counts come back alongside the surviving subset purely so
    the caller's trace line can name what was excused and why.

    Applies uniformly to every catalog skill — there is deliberately no
    special case for `gh-issue-implement`, and the catalog schema is
    unchanged.

    The `limit > 0 and missing` test is a pure walk-skip on the healthy path:
    with either falsy the comprehension below is already unsatisfiable, so
    the scan could not have changed the answer.
    """
    counts = _count_async_waits_in_section(messages, start, end, skill) if limit > 0 and missing else {}
    reprieved = {step: counts[step] for step in missing if 0 < counts.get(step, 0) <= limit}
    return [step for step in missing if step not in reprieved], reprieved


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

    # Issue #1550 — a step whose work was delegated to a background/async
    # Agent cannot honestly emit its `OK` marker yet, but the turn ending is
    # a legitimate wait, not abandonment. Steps that said so via
    # `[flow:async-wait]` (within the grace limit) drop out of the blocking
    # set; everything else stays outstanding and is what the model is told
    # about.
    async_wait_limit = _async_wait_grace_limit()
    outstanding, reprieved = _async_wait_reprieved(messages, boundary_idx, end_idx, skill, missing, async_wait_limit)

    if _TRACE_ENABLED:
        reprieved_desc = ", ".join(f"{step}={reprieved[step]}" for step in sorted(reprieved)) or "none"
        _trace(
            f"skill={skill} boundary={boundary_idx} section_end={end_idx} "
            f"seen={sorted(seen) or 'none'} missing={missing or 'none'} "
            f"async_wait_limit={async_wait_limit} async_wait_reprieved={reprieved_desc} "
            f"outstanding={outstanding or 'none'} enforce={enforce}",
            layer="L1.5",
        )

    if not outstanding:
        qualifier = " or async-wait-reprieved" if reprieved else ""
        return _allow(f"{skill}: all required steps emitted{qualifier}", layer="L1.5")

    if not enforce:
        return _allow(f"{skill}: missing steps but enforce=false", layer="L1.5")

    description = entry.get("description") or skill
    missing_list = ", ".join(outstanding)
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
