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
  - Boundary went stale (N fresh user prompts since it) → exit 0 (#1270).
  - Any unexpected exception → exit 0 (fail open).

Terminal-marker channels: assistant **text** blocks (canonical), plus the
`input.command` of assistant `Bash` `tool_use` blocks (#1270 fallback).
`tool_result` (issue #608) and every non-`Bash` tool stay excluded — the
rationale and the scope guard live on `_scan_after_boundary`.

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

# Issue #1270 — how many *fresh* user prompts may accumulate after a
# gh-issue-flow boundary before the hook declares that boundary stale and
# fails open. Without this valve a boundary lives forever: `stop_hook_active`
# only prevents an infinite Stop→block→Stop loop *within* one turn, and it
# resets the moment the user sends a new message, so a flow that never
# emitted a Step 3 marker would keep blocking every unrelated turn for the
# rest of the session (cross-turn session hijacking).
_DEFAULT_MAX_STALE_USER_TURNS: int = 3


def _trace(message: str, *, layer: str | None = None) -> None:
    """Emit a `[stop-guard]` trace line on stderr when trace mode is on.

    `layer` is the protection layer the trace belongs to (issue #608
    Acceptance Criteria: standardize trace fields):
      - `L1`   — boundary detection (`_find_flow_boundary`)
      - `L1.5` — terminal-marker / sub-skill scan (`_scan_after_boundary`)
      - `L2`   — state file (`.claude/.gh-issue-flow-state.json`, future)
      - `L3`   — heartbeat cron (`CronCreate(durable=true)`, future)
    Boundary *expiry* (#1270) is scored `L1.5` even though it invalidates an
    `L1` boundary: it is decided purely from the post-boundary window that
    `L1.5` owns, so it belongs with the scan it runs alongside.
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

# Issue #1270 — terminal marker as it appears inside a `Bash` tool_use
# `input.command` string (why that channel exists: `_scan_after_boundary`).
# Deliberately STRICTER than TERMINAL_PATTERNS: it demands a literal digit
# exactly where the SKILL.md / report-template.md templates carry the
# placeholders `<N>` and `<i>`. A command that merely mentions or greps the
# template text — `grep "gh:issue-flow complete" SKILL.md`, `rg
# 'gh:issue-flow stopped at step'` — therefore cannot match, while a real
# report (`gh:issue-flow complete (#1270)`, `gh:issue-flow stopped at step
# 2/6`) does.
_TERMINAL_COMMAND_RE: re.Pattern[str] = re.compile(
    r"gh[-:]issue-flow\s+(?:complete\s+\(#\d+\)|stopped\s+at\s+step\s+\d)",
)

# Issue #1270 — spans Claude Code injects into user-role messages that are
# NOT user prose. `<system-reminder>…</system-reminder>` blocks are harness
# chatter appended to otherwise-empty turns, so they must not make a message
# look like a fresh user prompt.
_SYSTEM_REMINDER_RE: re.Pattern[str] = re.compile(
    r"<system-reminder>.*?</system-reminder>",
    re.DOTALL,
)

# Issue #1270 — markers proving a `role=user` message is a skill expansion
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


def _iter_tool_use_inputs(message: dict[str, Any], tool_name: str, input_key: str) -> list[str]:
    """Return `input[<input_key>]` of every `<tool_name>` tool_use block.

    Every level is isinstance-checked so a malformed transcript entry can
    only yield fewer results, never an exception — the hook must fail open.
    """
    out: list[str] = []
    content = message.get("content")
    if not isinstance(content, list):
        return out
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "tool_use":
            continue
        if block.get("name") != tool_name:
            continue
        tool_input = block.get("input")
        if not isinstance(tool_input, dict):
            continue
        value = tool_input.get(input_key)
        if isinstance(value, str):
            out.append(value)
    return out


def _iter_skill_uses(message: dict[str, Any]) -> list[str]:
    """Return the skill names invoked via Skill tool_use blocks in this message."""
    return _iter_tool_use_inputs(message, "Skill", "skill")


def _iter_bash_commands(message: dict[str, Any]) -> list[str]:
    """Return the `input.command` strings of `Bash` tool_use blocks (#1270).

    `Bash` is the ONLY tool name ever passed here — never `Write` / `Edit` /
    anything else. That scope is load-bearing; see `_scan_after_boundary`.
    """
    return _iter_tool_use_inputs(message, "Bash", "command")


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

    Issue #1270 widens the scan by exactly one channel: the `input.command`
    string of an assistant `Bash` `tool_use` block, matched against the
    stricter `_TERMINAL_COMMAND_RE`. When the model prints the Step 3
    report via `cat <<'EOF' … EOF` or `printf`, the report text lands in
    that command string (and in a `tool_result`), never in an assistant
    text block — so before #1270 the flow could never terminate and the
    stale boundary blocked every later turn in the session.

    **Only `Bash` is scanned — never `Write`, `Edit`, or any other tool.**
    Editing `SKILL.md` or `references/report-template.md` puts real
    template text into an `Edit.new_string` / `Write.content` (this very
    change does exactly that), so scanning those inputs would
    false-terminate any flow that touches the skill's own files.
    `tool_result` remains excluded for the #608 reason above.
    """
    terminal = False
    seen: list[str] = []
    for entry in messages[start + 1 :]:
        msg = _message_payload(entry)
        role = msg.get("role")
        # `terminal` is monotonic, so once it is set the marker work on
        # every later message is pure waste on the turn-end hot path. The
        # loop itself cannot break — `seen` must keep accumulating so the
        # trace still reports the full sub-skill count.
        if role == "assistant" and not terminal:
            for text in _iter_text_blocks(msg, include_tool_results=False):
                if any(pat in text for pat in TERMINAL_PATTERNS):
                    terminal = True
                    break
            if not terminal:
                for command in _iter_bash_commands(msg):
                    if _TERMINAL_COMMAND_RE.search(command):
                        terminal = True
                        break
        for skill in _iter_skill_uses(msg):
            if skill not in SUB_SKILL_NAMES:
                continue
            normalized = skill.replace(":", "-")
            if normalized not in seen:
                seen.append(normalized)
    return terminal, seen


def _max_stale_user_turns() -> int:
    """Read the boundary-expiry threshold from the environment (#1270).

    Env var: `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS`.
      - a valid non-negative int  → use it,
      - `0`                       → expiry disabled (never fail open on
                                    staleness alone),
      - unset / unparseable / negative → `_DEFAULT_MAX_STALE_USER_TURNS`
        (unset reaches the `ValueError` arm via the `""` default).
    Never raises — a bad value silently degrades to the default.
    """
    try:
        value = int(os.environ.get("GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS", ""))
    except ValueError:
        return _DEFAULT_MAX_STALE_USER_TURNS
    return value if value >= 0 else _DEFAULT_MAX_STALE_USER_TURNS


def _count_fresh_user_prompts(messages: list[dict[str, Any]], start: int) -> int:
    """Count genuinely NEW user prompts after the boundary (#1270).

    A `role=user` transcript entry counts only when ALL of these hold:
      - it carries no `tool_result` block — tool output is transported as a
        user-role message but is not a user prompt;
      - after collecting text (`include_tool_results=False`), joining, and
        deleting every `<system-reminder>…</system-reminder>` span, the
        remainder is non-empty;
      - the remainder contains none of `_SKILL_EXPANSION_MARKERS` — those
        identify Claude Code's injection of an invoked skill's body, i.e.
        flow machinery generated by the chain itself.

    Drives boundary expiry — see `_DEFAULT_MAX_STALE_USER_TURNS` for why
    that valve has to exist at all.
    """
    count = 0
    for entry in messages[start + 1 :]:
        msg = _message_payload(entry)
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, list) and any(
            isinstance(block, dict) and block.get("type") == "tool_result" for block in content
        ):
            continue
        joined = "\n".join(_iter_text_blocks(msg, include_tool_results=False))
        remainder = _SYSTEM_REMINDER_RE.sub("", joined).strip()
        if not remainder:
            continue
        if any(marker in remainder for marker in _SKILL_EXPANSION_MARKERS):
            continue
        count += 1
    return count


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
    # Issue #1270 — the fresh-prompt count feeds nothing but the expiry
    # valve below, and counting is a second full pass over the transcript
    # on the turn-end hot path. Skip it whenever the result provably cannot
    # be used (flow already terminal, or expiry disabled); trace mode still
    # forces it so the L1.5 diagnostic line stays complete.
    limit = _max_stale_user_turns()
    fresh_prompts = (
        _count_fresh_user_prompts(messages, boundary) if _TRACE_ENABLED or (not terminal and limit > 0) else 0
    )
    if _TRACE_ENABLED:
        _trace(
            f"boundary={boundary} sub_skills_seen={len(seen)}/{len(EXPECTED_CHAIN)} "
            f"({','.join(seen) if seen else 'none'}) terminal={terminal} "
            f"fresh_user_prompts={fresh_prompts}",
            layer="L1.5",
        )
    if terminal:
        return _allow("Step 3 terminal marker present — flow finished", layer="L1.5")

    # Issue #1270 — stale-boundary expiry valve. Why `stop_hook_active` is
    # not enough on its own: see `_DEFAULT_MAX_STALE_USER_TURNS`.
    if limit > 0 and fresh_prompts >= limit:
        return _allow(
            f"stale boundary expiry — {fresh_prompts} fresh user prompt(s) since the "
            f"gh-issue-flow boundary (limit {limit}); flow abandoned, failing open",
            layer="L1.5",
        )

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
