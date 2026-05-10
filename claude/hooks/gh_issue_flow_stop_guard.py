#!/usr/bin/env python3
"""Claude Code Stop hook: harness-level guard for /gh-issue-flow early-stop (issue #383).

Reads a Stop event JSON from stdin, parses the conversation transcript, and
emits a `block` decision when the model tries to end its turn while a
gh-issue-flow chain is still in progress (5 sub-skills + Step 3 report).

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
import sys
from pathlib import Path
from typing import Any

# Opt-in stderr trace to diagnose "hook is registered but never blocks"
# cases (issue #505, fix-plan C). Default off so production runs stay
# silent. Enable with `GH_ISSUE_FLOW_STOP_GUARD_TRACE=1`.
_TRACE_ENABLED: bool = os.environ.get("GH_ISSUE_FLOW_STOP_GUARD_TRACE") == "1"


def _trace(message: str) -> None:
    """Emit a `[stop-guard]` trace line on stderr when trace mode is on."""
    if _TRACE_ENABLED:
        try:
            print(f"[stop-guard] {message}", file=sys.stderr, flush=True)
        except OSError:
            pass


# Sub-skill names accepted in either hyphen or colon namespace form.
# Order matters — it's the canonical 5-step gh-issue-flow chain.
EXPECTED_CHAIN: list[tuple[str, str]] = [
    ("gh-issue-implement", "gh:issue-implement"),
    ("gh-commit", "gh:commit"),
    ("gh-pr", "gh:pr"),
    ("devx-schedule", "devx:schedule"),
    ("gh-pr-resolve-conflict", "gh:pr-resolve-conflict"),
]
SUB_SKILL_NAMES: set[str] = {n for pair in EXPECTED_CHAIN for n in pair}

# Terminal Step 3 markers — presence in any assistant text after the
# gh-issue-flow boundary means the flow has finished and the model may stop.
TERMINAL_PATTERNS: tuple[str, ...] = (
    "gh:issue-flow complete (#",
    "gh:issue-flow stopped at step",
    "gh-issue-flow complete (#",
    "gh-issue-flow stopped at step",
)

# Tokens that mark the *start* of a gh-issue-flow chain. Either the user
# typed `/gh-issue-flow ...` or the assistant invoked `Skill(gh-issue-flow)`.
FLOW_START_TOKENS: tuple[str, ...] = (
    "/gh-issue-flow",
    "/gh:issue-flow",
)
FLOW_SKILL_NAMES: set[str] = {"gh-issue-flow", "gh:issue-flow"}


def _allow(trace_reason: str = "") -> int:
    """Allow the stop. Hook protocol: silent stdout + exit 0."""
    if trace_reason:
        _trace(f"allow: {trace_reason}")
    return 0


def _block(reason: str) -> int:
    """Block the stop with a directive shown to the model."""
    json.dump({"decision": "block", "reason": reason}, sys.stdout)
    _trace("block: gh-issue-flow incomplete — re-prompting model")
    return 0


def _iter_text_blocks(message: dict[str, Any], include_tool_results: bool = True) -> list[str]:
    """Return all text-bearing chunks in a message's content array.

    `include_tool_results` gates whether tool_result blocks contribute their
    text. Boundary detection (Step 1) sets it to False because a tool_result
    can carry arbitrary file contents — if a file the model reads happens to
    contain "/gh-issue-flow", the substring would otherwise falsely mark a
    flow boundary in an unrelated session. Terminal-marker scanning
    (Step 2) keeps it True so a sub-skill's stdout that prints the Step 3
    "complete (#N)" line still counts.
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
      - user message: text content begins with /gh-issue-flow or /gh:issue-flow
        (tool_result blocks excluded so a file mentioning the command does
        not trip the boundary)
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
                stripped = text.lstrip()
                for tok in FLOW_START_TOKENS:
                    if stripped.startswith(tok):
                        return i
    return -1


def _scan_after_boundary(messages: list[dict[str, Any]], start: int) -> tuple[bool, list[str]]:
    """Walk forward from the boundary.

    Returns (terminal_seen, ordered_distinct_sub_skill_invocations).
    Sub-skill names are normalized to the hyphen form for comparison.
    """
    terminal = False
    seen: list[str] = []
    for entry in messages[start:]:
        msg = _message_payload(entry)
        for text in _iter_text_blocks(msg):
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
    step_num = next_idx + 1  # 1-based for human display
    return f"Step 2.{step_num} — Skill({canonical[next_idx]})"


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
        return _allow("no gh-issue-flow boundary in transcript")

    terminal, seen = _scan_after_boundary(messages, boundary)
    if _TRACE_ENABLED:
        _trace(
            f"boundary={boundary} sub_skills_seen={len(seen)}/{len(EXPECTED_CHAIN)} "
            f"({','.join(seen) if seen else 'none'}) terminal={terminal}"
        )
    if terminal:
        return _allow("Step 3 terminal marker present — flow finished")

    next_label = _next_step_label(seen)
    reason = (
        f"gh-issue-flow incomplete: {len(seen)}/5 sub-skills invoked since the "
        f"flow started, and no terminal Step 3 report ('gh:issue-flow complete' "
        f"or 'gh:issue-flow stopped at step') has been emitted yet. Per the "
        f"CRITICAL CONTRACT in claude/skills/gh-issue-flow/SKILL.md, you MUST "
        f"continue immediately. Next action: {next_label}. Output ZERO "
        f"conversational text — no recap, no markdown summary, no per-step "
        f"bullets, no progress headers — just the next Skill() call (or, if all "
        f"5 sub-skills are already done, the Step 3 success/failure report "
        f"verbatim per the SKILL.md template)."
    )
    return _block(reason)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Final fail-open. Never accidentally trap the user inside a turn.
        sys.exit(0)
