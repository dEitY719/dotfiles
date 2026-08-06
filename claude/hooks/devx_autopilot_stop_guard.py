#!/usr/bin/env python3
"""Claude Code Stop hook: harness-level guard for /devx-autopilot early-stop (issue #1138).

Reads a Stop event JSON from stdin, parses the conversation transcript, and
emits a `block` decision when the model tries to end its turn while a
devx:autopilot chain (Stage-B: plan -> issue -> mode -> implement -> pr ->
simplify -> pr-reply -> report) is still in progress.

Failure mode being mitigated: like gh:issue-flow, the model self-authors a
success-looking summary between chained Skill() calls and treats it as a
turn-ending answer, leaving the Stage-B chain half-run. Prose rules in
SKILL.md alone are not enough — the harness must mechanically force
continuation.

Why marker-based (not skill-count-based like gh_issue_flow_stop_guard.py):
autopilot's *inline* implementation mode runs no implement sub-skill at all,
so counting Skill() invocations would undercount a legitimately-complete
flow. Instead this guard tracks the ORDERED STEP MARKERS the SKILL.md emits
via `printf '[step:devx-autopilot/<id>] OK\\n'`. Because printf output lands
in a Bash `tool_result` block, the step-marker scan intentionally includes
tool_result payloads (fail-open direction is acceptable — a stray marker
merely lets a stop through, it never traps the user). The terminal scan, by
contrast, is restricted to `role=assistant` text (include_tool_results=False)
so the report-template.md text — which literally contains `[OK] devx:autopilot`
— cannot false-terminate the flow when read into a tool_result (mirrors the
gh-issue-flow L1.5 fix).

Safety rails (each is critical — never accidentally trap the user):
  - Empty / unreadable / malformed stdin → exit 0 (allow stop).
  - Missing or unreadable transcript_path → exit 0.
  - `stop_hook_active == True` → exit 0 (we already blocked once in this
    chain; bowing out prevents an infinite Stop→block→Stop loop).
  - No devx-autopilot boundary in the transcript → exit 0 (not our flow).
  - Terminal report marker present in assistant text → exit 0 (chain done).
  - Boundary went stale (N fresh user prompts since it) → exit 0 (#1275).
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
# cases. Default off so production runs stay silent. Enable with
# `DEVX_AUTOPILOT_STOP_GUARD_TRACE=1`.
_TRACE_ENABLED: bool = os.environ.get("DEVX_AUTOPILOT_STOP_GUARD_TRACE") == "1"

# Issue #1275 (ported from #1270 / PR #1272) — how many *fresh* user prompts
# may accumulate after a devx-autopilot boundary before the hook declares that
# boundary stale and fails open. Without this valve a boundary lives forever:
# `stop_hook_active` only prevents an infinite Stop→block→Stop loop *within*
# one turn, and it resets the moment the user sends a new message, so an
# abandoned Stage-B run that never emitted a terminal report would keep
# blocking every unrelated turn for the rest of the session (cross-turn
# session hijacking).
_DEFAULT_MAX_STALE_USER_TURNS: int = 3


def _trace(message: str, *, layer: str | None = None) -> None:
    """Emit an `[autopilot-stop-guard]` trace line on stderr when trace mode is on.

    `layer` is the protection layer the trace belongs to:
      - `L1`   — boundary detection (`_find_flow_boundary`)
      - `L1.5` — step-marker / terminal scan (`_scan_after_boundary`)
    Boundary *expiry* (#1275) is scored `L1.5` even though it invalidates an
    `L1` boundary: it is decided purely from the post-boundary window that
    `L1.5` owns, so it belongs with the scan it runs alongside.
    The tag is appended (not prepended) so substring-based test assertions
    like `[autopilot-stop-guard] allow:` keep matching.
    """
    if _TRACE_ENABLED:
        try:
            tag = f" layer={layer}" if layer else ""
            print(f"[autopilot-stop-guard] {message}{tag}", file=sys.stderr, flush=True)
        except OSError:
            pass


# Ordered Stage-B step IDs that MUST be emitted before the model may stop.
# `report` is terminal and handled separately (see TERMINAL_PATTERNS).
REQUIRED_STEPS: list[str] = [
    "plan",
    "issue",
    "mode",
    "implement",
    "pr",
    "simplify",
    "pr-reply",
]

# Human-facing label for each step, surfaced in the block reason.
_STEP_LABELS: dict[str, str] = {
    "plan": "Step 0a — Skill(superpowers:writing-plans)",
    "issue": "Step 0b — Skill(gh:issue-create)",
    "mode": "Step 1 — mode selection (log mode=<sdd|inline> reason=...)",
    "implement": "Step 2 — SDD skill OR inline TDD + Advisor 검증",
    "pr": "Step 3 — Skill(gh:pr, <ISSUE_NUM>)",
    "simplify": "Step 4 — Skill(simplify, <PR_NUM>)",
    "pr-reply": "Step 5 — Skill(gh-pr-reply, <PR_NUM>) (emit the marker even with no comments / [SKIP])",
}

# Strict step-marker regex. Requires the literal `[step:devx-autopilot/<id>] OK`
# so a partial `[step:devx-autopilot/plan]` without ` OK` does NOT match.
_STEP_MARKER_RE: re.Pattern[str] = re.compile(r"\[step:devx-autopilot/([a-z-]+)\]\s+OK\b")

# Terminal markers — presence in any *assistant text* block after the boundary
# means the flow has finished (or hard-failed) and the model may stop.
TERMINAL_PATTERNS: tuple[str, ...] = (
    "[step:devx-autopilot/report] OK",
    "[OK] devx:autopilot",
    "[FAIL] devx:autopilot",
)

# Issue #1275 — spans Claude Code injects into user-role messages that are
# NOT user prose. `<system-reminder>…</system-reminder>` blocks are harness
# chatter appended to otherwise-empty turns, so they must not make a message
# look like a fresh user prompt.
_SYSTEM_REMINDER_RE: re.Pattern[str] = re.compile(
    r"<system-reminder>.*?</system-reminder>",
    re.DOTALL,
)

# Issue #1275 — markers proving a `role=user` message is a skill expansion
# (Claude Code injects an invoked skill's SKILL.md body as a user-role
# message) rather than something the human typed. Any of these present ⇒
# flow machinery, not a fresh user turn.
_SKILL_EXPANSION_MARKERS: tuple[str, ...] = (
    "Base directory for this skill:",
    "<command-name>",
    "<command-message>",
    "<local-command-stdout>",
    "is already loaded above",
)

# Issue #1275 — markers proving a `role=user` message is a *harness
# injection*, i.e. text Claude Code itself wrote into the user channel, not a
# human turn. A different category from `_SKILL_EXPANSION_MARKERS` above
# (which identifies an expanded SKILL.md body), so it lives in its own tuple;
# both are consulted.
#
# WHY this exists (measured on gh-issue-flow's twin guard in PR #1272): a
# naive `role=user` count reported 102 "fresh prompts" on a real transcript of
# which only 4 were human — the rest were Stop-hook feedback blocks (Claude
# Code re-injects THIS hook's own `reason` string as a `role=user` text
# message) and `<task-notification>` background-subagent completions. The
# default limit of 3 would therefore be reached mid-flow with zero human
# involvement, disabling the guard exactly when it is needed. Stage-B runs
# `simplify` and `pr-reply`, which fan out background agents, so the
# `<task-notification>` case is the norm here too.
#
# `isMeta` on the outer transcript entry is the primary defense; this tuple is
# defense-in-depth for transcripts that lack the flag. `devx-autopilot
# incomplete:` is this hook's own block-reason prefix — exactly the string
# that gets re-injected — so it is the strongest single signal available.
_HARNESS_INJECTION_MARKERS: tuple[str, ...] = (
    "Stop hook feedback:",
    "devx-autopilot incomplete:",
    "<task-notification>",
    "[SYSTEM NOTIFICATION - NOT USER INPUT]",
    "<local-command-caveat>",
)

# Regex that marks the *start* of a devx-autopilot chain in a user message.
# Matches four real-world surfaces (mirrors gh_issue_flow_stop_guard.py):
#   (a) raw `/devx-autopilot ...` (or colon `/devx:autopilot ...`) at line start
#   (b) the `<command-name>/devx-autopilot</command-name>` wrapper Claude Code
#       emits when a user invokes the slash command interactively
#   (c) the `Base directory for this skill: …/devx-autopilot` expansion marker
#   (d) the SKILL.md H1 line `# devx:autopilot — …`
# `(?m)` anchors `^` to per-line starts. tool_result payloads are excluded by
# `_iter_text_blocks(..., include_tool_results=False)` at the call site.
_USER_BOUNDARY_RE: re.Pattern[str] = re.compile(
    r"""
    (?m)                                                          # multiline: ^ matches each line start
    (?:
        ^\s*/devx[-:]autopilot\b                                  # (a) raw slash command
        |
        <command-name>\s*/devx[-:]autopilot\s*</command-name>     # (b) Claude Code wrapped form
        |
        ^Base\s+directory\s+for\s+this\s+skill:\s+.*devx-autopilot\b  # (c) skill base dir
        |
        ^\#\s+devx:autopilot\s+—                                  # (d) SKILL.md H1
    )
    """,
    re.VERBOSE,
)
FLOW_SKILL_NAMES: set[str] = {"devx-autopilot", "devx:autopilot"}


def _allow(trace_reason: str = "", *, layer: str | None = None) -> int:
    """Allow the stop. Hook protocol: silent stdout + exit 0."""
    if trace_reason:
        _trace(f"allow: {trace_reason}", layer=layer)
    return 0


def _block(reason: str, *, layer: str | None = None) -> int:
    """Block the stop with a directive shown to the model."""
    json.dump({"decision": "block", "reason": reason}, sys.stdout)
    _trace("block: devx-autopilot incomplete — re-prompting model", layer=layer)
    return 0


def _iter_text_blocks(message: dict[str, Any], include_tool_results: bool = False) -> list[str]:
    """Return all text-bearing chunks in a message's content array.

    `include_tool_results` gates whether tool_result blocks contribute their
    text. Terminal detection uses the default `False` so report-template.md
    text read into a tool_result cannot false-terminate the flow. Step-marker
    scanning passes `True` because the SKILL.md printf markers land in Bash
    tool_result output (fail-open direction — acceptable, see module docstring).
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
    """Return the index of the most recent devx-autopilot START, or -1.

    Boundary signals (role-restricted to avoid false positives from file
    content read into tool_result blocks):
      - assistant message: tool_use of Skill(devx-autopilot | devx:autopilot)
      - user message: text content matches `_USER_BOUNDARY_RE` (four surfaces).
        `tool_result` blocks are excluded so a doc mentioning the command
        does not trip the boundary.
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


def _scan_after_boundary(messages: list[dict[str, Any]], start: int) -> tuple[bool, set[str]]:
    """Walk forward from the boundary.

    Returns (terminal_seen, set_of_step_ids_emitted).

    - Terminal detection is restricted to `role=assistant` text blocks with
      `include_tool_results=False`, and the boundary message itself is skipped
      (`start + 1`). This prevents report-template.md text (which literally
      contains `[OK] devx:autopilot`) — whether delivered as the expanded
      SKILL.md user block or read into a tool_result — from false-matching a
      terminal marker (mirrors gh-issue-flow's L1.5 fix).
    - Step-marker detection scans ALL roles WITH tool_results, because the
      SKILL.md `printf '[step:...] OK'` output lands in Bash tool_result.
    """
    terminal = False
    steps: set[str] = set()
    for entry in messages[start + 1 :]:
        msg = _message_payload(entry)
        role = msg.get("role")
        if role == "assistant":
            for text in _iter_text_blocks(msg, include_tool_results=False):
                if any(pat in text for pat in TERMINAL_PATTERNS):
                    terminal = True
        # Step markers can come from Bash tool_result or assistant echo.
        for text in _iter_text_blocks(msg, include_tool_results=True):
            for m in _STEP_MARKER_RE.finditer(text):
                sid = m.group(1)
                if sid in REQUIRED_STEPS:
                    steps.add(sid)
    return terminal, steps


def _max_stale_user_turns() -> int:
    """Read the boundary-expiry threshold from the environment (#1275).

    Env var: `DEVX_AUTOPILOT_STOP_GUARD_MAX_USER_TURNS`.
      - a valid non-negative int  → use it,
      - `0`                       → expiry disabled (never fail open on
                                    staleness alone),
      - unset / unparseable / negative → `_DEFAULT_MAX_STALE_USER_TURNS`
        (unset reaches the `ValueError` arm via the `""` default).
    Never raises — a bad value silently degrades to the default.
    """
    try:
        value = int(os.environ.get("DEVX_AUTOPILOT_STOP_GUARD_MAX_USER_TURNS", ""))
    except ValueError:
        return _DEFAULT_MAX_STALE_USER_TURNS
    return value if value >= 0 else _DEFAULT_MAX_STALE_USER_TURNS


def _count_fresh_user_prompts(messages: list[dict[str, Any]], start: int) -> int:
    """Count genuinely NEW user prompts after the boundary (#1275).

    A `role=user` transcript entry counts only when ALL of these hold:
      - the OUTER transcript entry is not flagged `isMeta` — Claude Code
        stamps that flag on Stop-hook feedback injections and skill
        expansions but never on a genuine human prompt. The flag lives on the
        entry, NOT on the inner `message` dict, which is why this loop
        inspects `entry` and `_message_payload(entry)` separately;
      - after collecting text (`include_tool_results=False`), joining, and
        deleting every `<system-reminder>…</system-reminder>` span, the
        remainder is non-empty. This is also what makes a tool-output-only
        message free: `tool_result` blocks contribute no text under
        `include_tool_results=False`, so such a message yields "" and is
        dropped here — which matters especially in this guard, whose step
        markers ride in Bash `tool_result` payloads. There is deliberately NO
        wholesale "has a tool_result block ⇒ skip" rule: a real human prompt
        bundled in the same turn as tool output must still count, otherwise a
        stale boundary can never expire;
      - the remainder contains none of `_SKILL_EXPANSION_MARKERS` (an invoked
        sub-skill's body injected as a user message — Stage-B expands several)
        nor any of `_HARNESS_INJECTION_MARKERS` (Stop-hook feedback,
        background-task notifications) — both are machinery generated by the
        flow itself.

    Drives boundary expiry — see `_DEFAULT_MAX_STALE_USER_TURNS` for why that
    valve has to exist at all.

    Never raises: `entry` is treated as "not meta" whenever it is not a dict
    or carries no flag, and every other access is already isinstance-guarded.
    """
    count = 0
    for entry in messages[start + 1 :]:
        if isinstance(entry, dict) and entry.get("isMeta"):
            continue
        msg = _message_payload(entry)
        if msg.get("role") != "user":
            continue
        joined = "\n".join(_iter_text_blocks(msg, include_tool_results=False))
        remainder = _SYSTEM_REMINDER_RE.sub("", joined).strip()
        if not remainder:
            continue
        if any(marker in remainder for marker in _SKILL_EXPANSION_MARKERS):
            continue
        if any(marker in remainder for marker in _HARNESS_INJECTION_MARKERS):
            continue
        count += 1
    return count


def _first_missing_step(steps: set[str]) -> str | None:
    """Return the first REQUIRED_STEPS id not yet emitted, or None if all done."""
    for sid in REQUIRED_STEPS:
        if sid not in steps:
            return sid
    return None


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
        return _allow("no devx-autopilot boundary in transcript", layer="L1")

    terminal, steps = _scan_after_boundary(messages, boundary)
    # Issue #1275 — the fresh-prompt count feeds nothing but the expiry valve
    # below, and counting is a second full pass over the transcript on the
    # turn-end hot path. Skip it whenever the result provably cannot be used
    # (flow already terminal, or expiry disabled); trace mode still forces it
    # so the L1.5 diagnostic line stays complete.
    limit = _max_stale_user_turns()
    fresh_prompts = (
        _count_fresh_user_prompts(messages, boundary) if _TRACE_ENABLED or (not terminal and limit > 0) else 0
    )
    if _TRACE_ENABLED:
        emitted = ",".join(s for s in REQUIRED_STEPS if s in steps) or "none"
        _trace(
            f"boundary={boundary} steps_seen={len(steps)}/{len(REQUIRED_STEPS)} ({emitted}) "
            f"terminal={terminal} fresh_user_prompts={fresh_prompts}",
            layer="L1.5",
        )
    if terminal:
        return _allow("terminal report marker present — flow finished", layer="L1.5")

    # Issue #1275 — stale-boundary expiry valve. Why `stop_hook_active` is not
    # enough on its own: see `_DEFAULT_MAX_STALE_USER_TURNS`.
    if limit > 0 and fresh_prompts >= limit:
        return _allow(
            f"stale boundary expiry — {fresh_prompts} fresh user prompt(s) since the "
            f"devx-autopilot boundary (limit {limit}); flow abandoned, failing open",
            layer="L1.5",
        )

    missing = _first_missing_step(steps)
    if missing is None:
        # All required steps emitted but no terminal report yet → ask for it.
        reason = (
            f"devx-autopilot incomplete: all {len(REQUIRED_STEPS)} Stage-B step "
            f"markers are present but no terminal report has been emitted yet. Per "
            f"the CRITICAL CONTRACT in claude/skills/devx-autopilot/SKILL.md, you "
            f"MUST continue immediately. Next action: Step 6 — emit the final "
            f"report per references/report-template.md ('[OK] devx:autopilot ...' or "
            f"'[FAIL] devx:autopilot ...') followed by "
            f"'[step:devx-autopilot/report] OK'. Output ZERO conversational text "
            f"before it — no recap, no per-step bullets, no progress headers."
        )
        return _block(reason, layer="L1.5")

    # `steps` only ever contains REQUIRED_STEPS members (filtered at
    # collection time in _scan_after_boundary), so its size is the seen count.
    seen_count = len(steps)
    label = _STEP_LABELS.get(missing, missing)
    reason = (
        f"devx-autopilot incomplete: {seen_count}/{len(REQUIRED_STEPS)} Stage-B "
        f"step markers emitted since the flow started, and no terminal report "
        f"('[OK] devx:autopilot' / '[FAIL] devx:autopilot') has been emitted yet. "
        f"Per the CRITICAL CONTRACT in claude/skills/devx-autopilot/SKILL.md, you "
        f"MUST continue immediately. Next action: {label}; when it completes emit "
        f"'[step:devx-autopilot/{missing}] OK'. Output ZERO conversational text — "
        f"no recap, no markdown summary, no per-step bullets, no progress headers — "
        f"just the next step's work and its completion marker."
    )
    return _block(reason, layer="L1.5")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Final fail-open. Never accidentally trap the user inside a turn.
        sys.exit(0)
