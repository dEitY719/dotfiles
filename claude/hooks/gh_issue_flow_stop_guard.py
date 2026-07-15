#!/usr/bin/env python3
"""Claude Code Stop hook: harness-level guard for /gh-issue-flow early-stop (issue #383).

Reads a Stop event JSON from stdin, parses the conversation transcript, and
emits a `block` decision when the model tries to end its turn while a
gh-issue-flow chain is still in progress (6 sub-skills + Step 3 report).

Failure mode being mitigated: the model self-authors a markdown success
report between Skill() calls in Step 2 of gh-issue-flow and treats that
report as a turn-ending answer, even though `--no-next-hint` suppressed
the sub-skill's own trailing `Next:` line. Prose rules in SKILL.md alone
are not enough — the harness must mechanically force continuation.

Safety rails (each is critical — never accidentally trap the user):
  - Empty / unreadable / malformed stdin → exit 0 (allow stop).
  - Missing or unreadable transcript_path → exit 0.
  - `stop_hook_active == True` → exit 0 (we already blocked once in this
    chain; bowing out prevents an infinite Stop→block→Stop loop).
  - No gh-issue-flow boundary in the transcript → exit 0 (not our flow).
  - Terminal Step 3 marker present → exit 0 (chain finished cleanly).
  - Any unexpected exception → exit 0 (fail open).

The hook only ever does two things: emit nothing (allow), or emit one JSON
object `{"decision":"block","reason":"..."}` on stdout (block + nudge).
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any

# Opt-in stderr trace to diagnose "hook is registered but never blocks"
# cases (issue #505, fix-plan C). Default off so production runs stay
# silent. Enable with `GH_ISSUE_FLOW_STOP_GUARD_TRACE=1`.
_TRACE_ENABLED: bool = os.environ.get("GH_ISSUE_FLOW_STOP_GUARD_TRACE") == "1"


def _trace(message: str, *, layer: str | None = None) -> None:
    """Emit a `[stop-guard]` trace line on stderr when trace mode is on.

    `layer` is the protection layer the trace belongs to (issue #608
    Acceptance Criteria: standardize trace fields):
      - `L1`   — boundary detection (`_find_flow_boundary`)
      - `L1.5` — terminal-marker / sub-skill scan (`_scan_after_boundary`)
      - `L2`   — state file (`.claude/.gh-issue-flow-state.json`, future)
      - `L3`   — heartbeat cron (`CronCreate(durable=true)`, future)
    The tag is appended (not prepended) so existing substring-based test
    assertions like `"[stop-guard] allow:"` keep matching.
    """
    if _TRACE_ENABLED:
        try:
            tag = f" layer={layer}" if layer else ""
            print(f"[stop-guard] {message}{tag}", file=sys.stderr, flush=True)
        except OSError:
            pass


# Sub-skill names accepted in either hyphen or colon namespace form.
# Order matters — it's the canonical 6-step gh-issue-flow chain.
EXPECTED_CHAIN: list[tuple[str, str]] = [
    ("gh-issue-implement", "gh:issue-implement"),
    ("gh-commit", "gh:commit"),
    ("gh-pr", "gh:pr"),
    ("devx-pr-review-all", "devx:pr-review-all"),
    ("gh-pr-resolve-conflict", "gh:pr-resolve-conflict"),
    ("gh-pr-resolve-outdated", "gh:pr-resolve-outdated"),
]
SUB_SKILL_NAMES: set[str] = {n for pair in EXPECTED_CHAIN for n in pair}

# Human-facing SKILL.md step labels, parallel to EXPECTED_CHAIN. These are
# NOT derived arithmetically because gh-pr-resolve-outdated is labeled
# "Step 2.5.1" in SKILL.md (it runs after the "Step 2.5" resolve-conflict
# step), not "Step 2.6". Keep this list in lockstep with EXPECTED_CHAIN.
STEP_LABELS: list[str] = [
    "Step 2.1",
    "Step 2.2",
    "Step 2.3",
    "Step 2.4",
    "Step 2.5",
    "Step 2.5.1",
]

# Terminal Step 3 markers — presence in any assistant text after the
# gh-issue-flow boundary means the flow has finished and the model may stop.
TERMINAL_PATTERNS: tuple[str, ...] = (
    "gh:issue-flow complete (#",
    "gh:issue-flow stopped at step",
    "gh-issue-flow complete (#",
    "gh-issue-flow stopped at step",
)

# Regex that marks the *start* of a gh-issue-flow chain in a user message.
# Matches four real-world forms that user-typed slash commands take in Claude
# Code transcripts (issues #607 / #609 / #608):
#
#   (a) Raw `/gh-issue-flow ...` (or colon form `/gh:issue-flow ...`) at the
#       start of a line — historical fixture form, still valid for tests
#       and for users who paste the command into a longer message.
#   (b) The `<command-name>/gh-issue-flow</command-name>` (or colon form)
#       wrapper that Claude Code emits when a user invokes the slash
#       command interactively.
#   (c) The `Base directory for this skill: …/gh-issue-flow` marker line
#       Claude Code emits when expanding a slash command into the
#       SKILL.md prompt (issue #608 — defense in depth against future
#       wrapper format drift; matches the resolved skill base path).
#   (d) The SKILL.md H1 line `# gh:issue-flow — Issue → PR composition`
#       (issue #608 — second wrapper-independent anchor, useful if the
#       `<command-name>` / `Base directory` lines ever stop being emitted).
#
# The `(?m)` prefix anchors `^` to per-line starts so a mid-sentence
# mention like "I was reading about /gh-issue-flow..." stays out.
# False-positive guards for `tool_result` payloads (e.g. SKILL.md being
# read by the model) are layered separately in `_iter_text_blocks(...,
# include_tool_results=False)`.
_USER_BOUNDARY_RE: re.Pattern[str] = re.compile(
    r"""
    (?m)                                                    # multiline: ^ matches each line start
    (?:
        ^\s*/gh[-:]issue-flow\b                             # (a) raw slash command
        |
        <command-name>\s*/gh[-:]issue-flow\s*</command-name>  # (b) Claude Code wrapped form
        |
        ^Base\s+directory\s+for\s+this\s+skill:\s+.*gh-issue-flow\b  # (c) skill base dir
        |
        ^\#\s+gh:issue-flow\s+—\s+Issue\s+→\s+PR\s+composition\s*$  # (d) SKILL.md H1
    )
    """,
    re.VERBOSE,
)
FLOW_SKILL_NAMES: set[str] = {"gh-issue-flow", "gh:issue-flow"}


def _allow(trace_reason: str = "", *, layer: str | None = None) -> int:
    """Allow the stop. Hook protocol: silent stdout + exit 0."""
    if trace_reason:
        _trace(f"allow: {trace_reason}", layer=layer)
    return 0


def _block(reason: str, *, layer: str | None = None) -> int:
    """Block the stop with a directive shown to the model."""
    json.dump({"decision": "block", "reason": reason}, sys.stdout)
    _trace("block: gh-issue-flow incomplete — re-prompting model", layer=layer)
    return 0


def _iter_text_blocks(message: dict[str, Any], include_tool_results: bool = False) -> list[str]:
    """Return all text-bearing chunks in a message's content array.

    `include_tool_results` gates whether tool_result blocks contribute their
    text. Default is `False` — a tool_result can carry arbitrary file
    contents (e.g. SKILL.md being read by the model), and substrings
    inside such payloads must not influence flow detection. Both
    boundary detection and terminal-marker scanning rely on the default;
    no caller in this module passes `True`. The parameter is kept (rather
    than removed) so future callers needing inclusive scans can opt in
    explicitly, but the safe default is now the default. In particular,
    the SKILL.md Step 3 template literally contains the lines
    `gh:issue-flow complete (#<N>)` and `gh:issue-flow stopped at step
    <i>/5` as instructions; if those were visible to the terminal scan
    via tool_result, every Read of SKILL.md during a flow would falsely
    flag completion (issue #608, layer L1.5; PR #635 review tightening).
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
                # tool_result.content can be a string or list of text blocks
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
    """Return the skill names invoked via Skill tool_use blocks in this message."""
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


def _find_flow_boundary(messages: list[dict[str, Any]]) -> int:
    """Return the index of the most recent gh-issue-flow START, or -1.

    Boundary signals (role-restricted to avoid false positives from file
    content read into tool_result blocks — see PR #386 review feedback):
      - assistant message: tool_use of Skill(gh-issue-flow | gh:issue-flow)
      - user message: text content matches `_USER_BOUNDARY_RE`, which
        recognizes both the raw `/gh-issue-flow ...` form (line start) and
        the `<command-name>/gh-issue-flow</command-name>` wrapper Claude
        Code emits when the user invokes the slash command interactively
        (issues #607 / #609). `tool_result` blocks are excluded so a file
        mentioning the command does not trip the boundary.
    """
    for i in range(len(messages) - 1, -1, -1):
        msg = _message_payload(messages[i])
        role = msg.get("role")
        if role == "assistant":
            for skill in _iter_skill_uses(msg):
                if skill in FLOW_SKILL_NAMES:
                    return i
        elif role == "user":
            for text in _iter_text_blocks(msg, include_tool_results=False):
                if _USER_BOUNDARY_RE.search(text):
                    return i
    return -1


def _scan_after_boundary(messages: list[dict[str, Any]], start: int) -> tuple[bool, list[str]]:
    """Walk forward from the boundary.

    Returns (terminal_seen, ordered_distinct_sub_skill_invocations).
    Sub-skill names are normalized to the hyphen form for comparison.

    Issue #608 (layer L1.5) — terminal-marker scan is restricted to
    `role=assistant` text blocks, with `include_tool_results=False`,
    and the boundary message itself is skipped (`start + 1`). The
    motivation: the SKILL.md body (delivered as a `role=user` text
    block when Claude Code expands a slash command) literally contains
    the lines
        gh:issue-flow complete (#<N>)
        gh:issue-flow stopped at step <i>/5
    as Step 3 *instructions*. Without this restriction the scan would
    false-match those template lines and fail-open on every real
    `/gh-issue-flow` invocation, defeating the harness guard. Sub-skill
    invocation tracking is already restricted to assistant `tool_use`
    blocks (`_iter_skill_uses` only inspects that block type), so the
    skill counter is unaffected — only the terminal-marker scan
    narrows.
    """
    terminal = False
    seen: list[str] = []
    for entry in messages[start + 1 :]:
        msg = _message_payload(entry)
        role = msg.get("role")
        if role == "assistant":
            for text in _iter_text_blocks(msg, include_tool_results=False):
                if any(pat in text for pat in TERMINAL_PATTERNS):
                    terminal = True
        for skill in _iter_skill_uses(msg):
            if skill not in SUB_SKILL_NAMES:
                continue
            normalized = skill.replace(":", "-")
            if normalized not in seen:
                seen.append(normalized)
    return terminal, seen


def _next_step_label(seen: list[str]) -> str:
    """Map the highest-index sub-skill seen to a human label for the *next* one."""
    canonical = [hyphen for hyphen, _ in EXPECTED_CHAIN]
    next_idx = 0
    for i, name in enumerate(canonical):
        if name in seen:
            next_idx = i + 1
    if next_idx >= len(canonical):
        return "Step 3 — emit the final 'gh:issue-flow complete (#N)' report"
    return f"{STEP_LABELS[next_idx]} — Skill({canonical[next_idx]})"


def main() -> int:
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

    messages = _load_transcript(p)
    if not messages:
        return _allow("transcript empty / unreadable")

    boundary = _find_flow_boundary(messages)
    if boundary < 0:
        return _allow("no gh-issue-flow boundary in transcript", layer="L1")

    terminal, seen = _scan_after_boundary(messages, boundary)
    if _TRACE_ENABLED:
        _trace(
            f"boundary={boundary} sub_skills_seen={len(seen)}/{len(EXPECTED_CHAIN)} "
            f"({','.join(seen) if seen else 'none'}) terminal={terminal}",
            layer="L1.5",
        )
    if terminal:
        return _allow("Step 3 terminal marker present — flow finished", layer="L1.5")

    next_label = _next_step_label(seen)
    reason = (
        f"gh-issue-flow incomplete: {len(seen)}/{len(EXPECTED_CHAIN)} sub-skills invoked since the "
        f"flow started, and no terminal Step 3 report ('gh:issue-flow complete' "
        f"or 'gh:issue-flow stopped at step') has been emitted yet. Per the "
        f"CRITICAL CONTRACT in claude/skills/gh-issue-flow/SKILL.md, you MUST "
        f"continue immediately. Next action: {next_label}. Output ZERO "
        f"conversational text — no recap, no markdown summary, no per-step "
        f"bullets, no progress headers — just the next Skill() call (or, if all "
        f"{len(EXPECTED_CHAIN)} sub-skills are already done, the Step 3 success/failure report "
        f"verbatim per the SKILL.md template)."
    )
    return _block(reason, layer="L1.5")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Final fail-open. Never accidentally trap the user inside a turn.
        sys.exit(0)
