#!/usr/bin/env python3
"""Claude Code Stop hook: harness-level guard for /gh-issue-flow early-stop (issue #383).

Reads a `Stop` or `SubagentStop` event JSON from stdin, parses the
conversation transcript, and emits a `block` decision when the model tries
to end its turn while a gh-issue-flow chain is still in progress (6
sub-skills + Step 3 report).

Registered on BOTH turn-ending events (issue #1434): a subagent ending its
turn fires `SubagentStop`, never `Stop`, so an unattended `gh:issue-flow`
dispatched inside a subagent (#1389) would otherwise run with the harness
layer of the three-layer guard entirely absent.

Failure mode being mitigated: the model self-authors a markdown success
report between Skill() calls in Step 2 of gh-issue-flow and treats that
report as a turn-ending answer, even though `--no-next-hint` suppressed
the sub-skill's own trailing `Next:` line. Prose rules in SKILL.md alone
are not enough — the harness must mechanically force continuation.

Safety rails (each is critical — never accidentally trap the user):
  - Empty / unreadable / malformed stdin → exit 0 (allow stop).
  - Missing or unreadable transcript path → exit 0. On `SubagentStop` the
    *subagent's own* `agent_transcript_path` is the ONLY accepted source —
    the parent session's `transcript_path` is never read on that event,
    whether the subagent's key is absent, empty, or merely unreadable
    (measured, issue #1434; tightened by the PR #1438 review — see
    `_resolve_transcript_path`).
  - `stop_hook_active == True` → exit 0 (we already blocked once in this
    chain; bowing out prevents an infinite Stop→block→Stop loop).
  - No gh-issue-flow boundary in the transcript → exit 0 (not our flow).
  - Terminal Step 3 marker present → exit 0 (chain finished cleanly).
  - Boundary went stale (N fresh user prompts since it) → exit 0 (#1270).
  - `[flow:async-wait]` marker streak within the grace limit → exit 0
    (#1550 — work delegated to a background Agent, not abandoned).
  - Any unexpected exception → exit 0 (fail open).

Terminal-marker channels: assistant **text** blocks (canonical), plus a
`Bash` `tool_use` whose `input.command` carries the marker AND whose own
paired `tool_result` carries the marker together with a report field line
(`PR URL:` / `Resume after fix:`) — #1270 fallback, narrowed by the PR
#1272 review and again by #1274. Every non-`Bash` tool stays excluded, and
a `tool_result` is never read on its own (issue #608) — rationale and scope
guard live on `_scan_after_boundary`.

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

# Issue #1550 — how many CONSECUTIVE `[flow:async-wait]` markers may end a
# turn, with no intervening progress, before the guard resumes blocking.
# Rationale for a count instead of an agent-id comparison: see
# `_ASYNC_WAIT_RE`.
_DEFAULT_ASYNC_WAIT_LIMIT: int = 2

# Issue #1550 — the marker the model prints as plain assistant text right
# before ending a turn whose remaining work it has handed to a
# background/async `Agent` (the Advisor/Worker delegation the user's global
# CLAUDE.md mandates for multi-file implementation work). Shape:
#
#   [flow:async-wait] step=<skill>/<step> agent=<agent-id> reason=background-worker-delegated
#
# `agent` is required in the line — the transcript itself is the audit trail —
# but deliberately NOT captured and NOT used in any matching or streak logic.
# The issue's own fix plan proposed comparing the agent id across turns to
# detect "no progress", but that requires the model to reproduce one exact
# literal string turn after turn — fragile in exactly the situation the marker
# exists for. Counting consecutive occurrences with no intervening progress
# event is sufficient evidence of stagnation on its own, and needs nothing
# from the model but the marker.
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


# One entry per slot of the canonical 6-step gh-issue-flow chain; order
# matters. Each entry lists EVERY name that addresses that slot — the
# dotfiles-native pair (hyphen, colon) plus, since #1410 Phase 3, the
# post-migration pair the skill answers to once installed from its own
# plugin repo (D-12, issue #1678).
#
# Why both, and not a swap: NF-1 keeps the dotfiles originals in place until
# Phase 4, and the live automation in `shell-common/functions/gh_flow.sh` +
# `shell-common/tools/custom/issue_watcher_cron.sh` still dispatches the old
# slash commands. Narrowing this list to the new names would drop the
# harness guard off that operational path the moment it landed; ignoring the
# new names would leave anyone running the migrated plugin unguarded. Phase 4
# removes the old forms, here and there, together.
#
# Element 0 is the CANONICAL name of the slot: it is what `seen` records and
# what `_next_step_label` quotes back to the model. It stays the old hyphen
# form on purpose — the copy actually installed in this repo is still the one
# the model is being told to invoke.
EXPECTED_CHAIN: list[tuple[str, ...]] = [
    # `gh-issue-implement`'s hyphen form is unchanged by the migration; only
    # its colon form moves namespace (`gh:issue-implement` → `gh-issue:implement`).
    ("gh-issue-implement", "gh:issue-implement", "gh-issue:implement"),
    ("gh-commit", "gh:commit", "gh-pr-commit", "gh-pr:commit"),
    ("gh-pr", "gh:pr", "gh-pr-create", "gh-pr:create"),
    ("devx-pr-review-all", "devx:pr-review-all", "gh-verify-review-all", "gh-verify:review-all"),
    ("gh-pr-resolve-conflict", "gh:pr-resolve-conflict", "gh-resolve-conflict", "gh-resolve:conflict"),
    ("gh-pr-resolve-outdated", "gh:pr-resolve-outdated", "gh-resolve-outdated", "gh-resolve:outdated"),
]
SUB_SKILL_NAMES: set[str] = {n for forms in EXPECTED_CHAIN for n in forms}

# Alias → canonical slot name. This replaces the old `skill.replace(":", "-")`
# normalization, which only ever worked because a slot's colon and hyphen
# forms were the same string modulo the separator. That stops being true
# under the migration — `gh-pr:commit` normalizes to `gh-pr-commit`, which is
# NOT `gh-commit` — so the mapping has to be explicit or two aliases of one
# slot would count as two distinct steps.
_SUB_SKILL_CANONICAL: dict[str, str] = {n: forms[0] for forms in EXPECTED_CHAIN for n in forms}

# The one alias `_next_step_label` quotes alongside the canonical name, so a
# session running only the migrated plugin is told a skill it actually has.
# Spelled out per slot rather than taken positionally out of EXPECTED_CHAIN
# (`forms[-1]`): those tuples are alias *sets* whose order carries no meaning
# past element 0, so adding a form later would silently change which name the
# model is told to invoke (agy review, PR #1693). `_assert_hint_aliases_known`
# below turns any drift between the two into an import-time failure rather
# than a wrong hint at block time.
_SUB_SKILL_HINT_ALIAS: dict[str, str] = {
    "gh-issue-implement": "gh-issue:implement",
    "gh-commit": "gh-pr:commit",
    "gh-pr": "gh-pr:create",
    "devx-pr-review-all": "gh-verify:review-all",
    "gh-pr-resolve-conflict": "gh-resolve:conflict",
    "gh-pr-resolve-outdated": "gh-resolve:outdated",
}


def _assert_hint_aliases_known() -> None:
    """Every slot has exactly one hint alias, and it addresses that same slot.

    Runs at import. A hook that fails open on a malformed transcript must
    still refuse to ship an internally inconsistent chain table — a hint
    naming the wrong slot's skill would route the model to the wrong step.
    """
    for forms in EXPECTED_CHAIN:
        canonical = forms[0]
        alias = _SUB_SKILL_HINT_ALIAS.get(canonical)
        if alias is None:
            raise AssertionError(f"_SUB_SKILL_HINT_ALIAS is missing a hint for slot {canonical!r}")
        if alias not in forms:
            raise AssertionError(f"hint alias {alias!r} does not address slot {canonical!r} ({forms!r})")


_assert_hint_aliases_known()

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
# The `gh-flow:issue` / `gh-flow-issue` half is the post-migration name
# (#1678, D-12). Each pattern keeps the trailing space or `(#` that follows
# the skill name, which is also what keeps the sibling `gh-flow:issue-relay`
# out: its name continues with `-relay` exactly where these demand a space.
TERMINAL_PATTERNS: tuple[str, ...] = (
    "gh:issue-flow complete (#",
    "gh:issue-flow stopped at step",
    "gh-issue-flow complete (#",
    "gh-issue-flow stopped at step",
    "gh-flow:issue complete (#",
    "gh-flow:issue stopped at step",
    "gh-flow-issue complete (#",
    "gh-flow-issue stopped at step",
)

# Issue #1270 — terminal marker as it appears in the `Bash` fallback
# channel: matched against BOTH a tool_use `input.command` string and that
# same tool_use's paired `tool_result` (why: `_scan_after_boundary`).
# Deliberately STRICTER than TERMINAL_PATTERNS: it demands a literal digit
# exactly where the SKILL.md / report-template.md templates carry the
# placeholders `<N>` and `<i>`. A command that merely mentions or greps the
# template text — `grep "gh:issue-flow complete" SKILL.md`, `rg
# 'gh:issue-flow stopped at step'` — therefore cannot match, while a real
# report (`gh:issue-flow complete (#1270)`, `gh:issue-flow stopped at step
# 2/6`) does.
#
# The two namespaces are kept as SEPARATE alternatives rather than folded
# into one character class (#1678 Error Cases): `gh[-:]issue-flow` and
# `gh-flow[-:]issue` share no safe common shape, and a naive merge would
# widen the match in ways neither name intends. The shared report shape is
# factored out instead, so the two branches can never drift apart.
_TERMINAL_REPORT_SHAPE: str = r"(?:complete\s+\(#\d+\)|stopped\s+at\s+step\s+\d)"
_TERMINAL_COMMAND_RE: re.Pattern[str] = re.compile(
    rf"(?:gh[-:]issue-flow|gh-flow[-:]issue)\s+{_TERMINAL_REPORT_SHAPE}",
)

# Issue #1274 — report-SHAPE requirement, applied to the paired
# `tool_result` only (never to the command; why: `_scan_after_boundary`).
# `_TERMINAL_COMMAND_RE` alone still let `grep "gh:issue-flow complete
# (#1270)" some.log` terminate a flow: the command carries the literal-digit
# marker and grep echoes the matched line straight back into the
# tool_result, so both halves of the #1272 pair were satisfied by a plain
# log search. A real Step 3 report is never one line — per
# `claude/skills/gh-issue-flow/references/report-template.md` the success
# form always carries a `PR URL:` line and the failure form a `Resume after
# fix:` line, neither of which a single grepped marker line reproduces.
# Kept as its own pattern (not folded into `_TERMINAL_COMMAND_RE`) because
# the two run against different halves of the pair.
_TERMINAL_REPORT_FIELDS: tuple[str, ...] = ("PR URL:", "Resume after fix:")

# Issue #1270 — spans Claude Code injects into user-role messages that are
# NOT user prose. `<system-reminder>…</system-reminder>` blocks are harness
# chatter appended to otherwise-empty turns, so they must not make a message
# look like a fresh user prompt.
_SYSTEM_REMINDER_RE: re.Pattern[str] = re.compile(
    r"<system-reminder>.*?</system-reminder>",
    re.DOTALL,
)


def _line_anchored_alternation(markers: tuple[str, ...], shapes: tuple[str, ...] = ()) -> re.Pattern[str]:
    """Compile markers into one `(?m)^`-anchored alternation (#1281).

    An unanchored `marker in text` test fired on any occurrence, so a human
    asking "what does 'Stop hook feedback:' mean?" had that whole turn
    discarded from the fresh-prompt count. Real harness injections always
    open a line with their marker (same reasoning as `_USER_BOUNDARY_RE`),
    so line-start anchoring keeps every genuine injection matched while
    letting a quoted marker mid-sentence stay a human turn.

    `markers` are literals (escaped — they carry `<`, `>`, `[`, `]`).
    `shapes` are already-regex fragments, for injections whose literal
    prefix is variable and so cannot be expressed as a fixed marker.
    """
    return re.compile(r"(?m)^(?:" + "|".join([re.escape(m) for m in markers] + list(shapes)) + r")")


# Issue #1270 — markers proving a `role=user` message is a skill expansion
# (Claude Code injects an invoked skill's SKILL.md body as a user-role
# message) rather than something the human typed. Any of these *at the start
# of a line* ⇒ flow machinery, not a fresh user turn.
_SKILL_EXPANSION_MARKERS: tuple[str, ...] = (
    "Base directory for this skill:",
    "<command-name>",
    "<command-message>",
    "<local-command-stdout>",
)

# Issue #1281 — the "already loaded" injection is the one skill-expansion
# signal that never *opens* a line with its own words. Claude Code emits the
# whole message as `Skill <name> is already loaded above; instructions
# unchanged. Arguments: …`, so the bare literal `is already loaded above`
# only ever appears mid-line. Under line anchoring that literal could never
# match — which would hand the #1270 over-count straight back for this one
# case (harness text counted as a human prompt, driving the stale-boundary
# valve toward premature self-defeat). Expressed as a shape instead, matching
# the real sentence structure.
_SKILL_EXPANSION_SHAPES: tuple[str, ...] = (r"Skill\s+\S+\s+is already loaded above",)

_SKILL_EXPANSION_RE: re.Pattern[str] = _line_anchored_alternation(
    _SKILL_EXPANSION_MARKERS,
    _SKILL_EXPANSION_SHAPES,
)

# Issue #1270 (PR #1272 review) — markers proving a `role=user` message is a
# *harness injection*, i.e. text Claude Code itself wrote into the user
# channel, not a human turn. A different category from
# `_SKILL_EXPANSION_MARKERS` above (which identifies an expanded SKILL.md
# body), so it lives in its own tuple; both are consulted.
#
# WHY this exists: measured on a real 2489-entry gh-issue-flow transcript,
# `_count_fresh_user_prompts` reported 102 "fresh prompts" of which only 4
# were human — 62 were Stop-hook feedback blocks (Claude Code re-injects
# THIS hook's own `reason` string as a `role=user` text message) and 40 were
# `<task-notification>` background-subagent completions. The default limit
# of 3 was therefore reached at entry 322 with 1/6 sub-skills done, so the
# guard disabled itself mid-flow with zero human involvement — and
# `devx:pr-review-all` (Step 2.4 of the very chain guarded here) fans out
# three background agents, guaranteeing that outcome.
#
# `isMeta` on the outer transcript entry is the primary defense; this tuple
# is defense-in-depth for transcripts that lack the flag. `gh-issue-flow
# incomplete:` is this hook's own block-reason prefix — exactly the string
# that gets re-injected — so it is the strongest single signal available.
_HARNESS_INJECTION_MARKERS: tuple[str, ...] = (
    "Stop hook feedback:",
    "gh-issue-flow incomplete:",
    "<task-notification>",
    "[SYSTEM NOTIFICATION - NOT USER INPUT]",
    "<local-command-caveat>",
)
_HARNESS_INJECTION_RE: re.Pattern[str] = _line_anchored_alternation(_HARNESS_INJECTION_MARKERS)

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
# Each of the four has a primed twin (a')–(d') for the post-migration
# `gh-flow:issue` / `gh-flow-issue` namespace (#1678, D-12). Those twins end
# on `(?![\w-])` rather than `\b`: a word boundary sits between `issue` and
# the `-relay` of the sibling `gh-flow:issue-relay`, so `\b` would arm this
# six-step chain guard on a skill that has no such chain.
#
# (c') allows arbitrary path segments between `gh-flow` and `/issue` because
# an installed plugin's base directory is not `<plugin>/skills/<skill>` —
# measured, the two real Claude Code layouts are
# `plugins/marketplaces/gh-flow-skills/skills/issue` and
# `plugins/cache/gh-flow-skills/gh-flow/<version>/skills/issue`. A pattern
# pinned to one nesting depth silently matches neither.
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
        |
        ^\s*/gh-flow[-:]issue(?![\w-])                       # (a') new namespace
        |
        <command-name>\s*/gh-flow[-:]issue\s*</command-name>  # (b') new namespace
        |
        ^Base\s+directory\s+for\s+this\s+skill:\s+
            .*gh-flow(?:-issue(?![\w-])|[\w./-]*/issue(?![\w-]))  # (c') new namespace
        |
        ^\#\s+gh-flow:issue\s+—\s+Issue\s+→\s+PR\s+composition\s*$  # (d') new namespace
    )
    """,
    re.VERBOSE,
)
FLOW_SKILL_NAMES: set[str] = {
    "gh-issue-flow",
    "gh:issue-flow",
    "gh-flow-issue",
    "gh-flow:issue",
}


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


def _text_from_sub_blocks(content: list[Any]) -> list[str]:
    """Return the text of every `{"type": "text", "text": ...}` sub-block.

    `tool_result.content` is a plain string in some transcripts and a list
    of text sub-blocks in others; this handles the list shape. Shared by
    `_iter_text_blocks`'s tool_result branch and `_iter_tool_results` so the
    same extraction logic isn't duplicated across both.
    """
    parts: list[str] = []
    for sub in content:
        if isinstance(sub, dict) and sub.get("type") == "text":
            st = sub.get("text")
            if isinstance(st, str):
                parts.append(st)
    return parts


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
                    parts.extend(_text_from_sub_blocks(rc))
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


def _iter_bash_tool_uses(message: dict[str, Any]) -> list[tuple[str, str]]:
    """Return `(id, input.command)` for every `Bash` tool_use block (#1270).

    `Bash` is the ONLY tool name ever inspected here — never `Write` /
    `Edit` / anything else. That scope is load-bearing; see
    `_scan_after_boundary`.

    Unlike `_iter_tool_use_inputs`, the block `id` is kept: the terminal
    channel must pair a command with its OWN `tool_result` (PR #1272
    review). A block carrying no usable string `id` cannot be paired, so it
    is dropped here rather than passed on as unpairable — it must never
    terminate the flow.

    Every level is isinstance-checked so a malformed transcript entry can
    only yield fewer results, never an exception — the hook must fail open.
    """
    out: list[tuple[str, str]] = []
    content = message.get("content")
    if not isinstance(content, list):
        return out
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "tool_use" or block.get("name") != "Bash":
            continue
        block_id = block.get("id")
        if not isinstance(block_id, str) or not block_id:
            continue
        tool_input = block.get("input")
        if not isinstance(tool_input, dict):
            continue
        command = tool_input.get("command")
        if isinstance(command, str):
            out.append((block_id, command))
    return out


def _iter_tool_results(message: dict[str, Any]) -> list[tuple[str, str]]:
    """Return `(tool_use_id, text)` for every tool_result block (#1270).

    The ONLY caller is `_scan_after_boundary`'s pairing lookup, and only for
    an id whose `Bash` command already matched `_TERMINAL_COMMAND_RE`. This
    is the single place in the module where a `tool_result` may be read at
    all; the general `include_tool_results=False` rule (issue #608) stands
    everywhere else, including boundary detection and the text-block
    terminal scan.

    `tool_result.content` is a plain string in some transcripts and a list
    of `{"type": "text", "text": ...}` blocks in others, so both shapes are
    handled via `_text_from_sub_blocks` (shared with `_iter_text_blocks`). A
    block with no usable string `tool_use_id` is dropped — it can never form
    a pair.

    Exactly ONE tuple is emitted per tool_result block: when `content` is a
    list, its text sub-blocks are concatenated first. Claude Code may split
    one command's stdout across several text sub-blocks, so the #1274 check
    — marker line AND a report field line in the SAME result — would miss a
    genuine report whose two lines landed in different sub-blocks.
    Concatenation restores the single logical payload the caller reasons
    about.

    Joined with `""`, not `"\\n"` (PR #1279 codex review): the sub-blocks are
    fragments of ONE underlying stdout string, and nothing guarantees the
    split points fall on line boundaries. Inserting a synthetic `"\\n"`
    between two fragments that split mid-token (e.g. `"gh:issue-flow compl"`
    + `"ete (#42)"`) would sever the very marker this function exists to
    detect — the opposite of `_count_fresh_user_prompts`'s join, which
    concatenates distinct, already-line-bounded *messages* and so safely
    uses `"\\n"` as a paragraph separator.
    """
    out: list[tuple[str, str]] = []
    content = message.get("content")
    if not isinstance(content, list):
        return out
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_result":
            continue
        tool_use_id = block.get("tool_use_id")
        if not isinstance(tool_use_id, str) or not tool_use_id:
            continue
        rc = block.get("content")
        if isinstance(rc, str):
            out.append((tool_use_id, rc))
        elif isinstance(rc, list):
            parts = _text_from_sub_blocks(rc)
            if parts:
                out.append((tool_use_id, "".join(parts)))
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
    Sub-skill names are normalized to their slot's canonical name.

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

    Issue #1270 widens the scan by exactly one channel: an assistant `Bash`
    `tool_use`. When the model prints the Step 3 report via `cat <<'EOF' …
    EOF` or `printf`, the report text lands in that tool_use's
    `input.command` (and in its `tool_result`), never in an assistant text
    block — so before #1270 the flow could never terminate and the stale
    boundary blocked every later turn in the session.

    That channel is **pair-matched** (PR #1272 review, Codex BLOCKER).
    Both of these must hold:
      1. `_TERMINAL_COMMAND_RE` matches the `input.command` of a `Bash`
         tool_use, AND
      2. the `tool_result` whose `tool_use_id` equals THAT tool_use's `id`
         matches `_TERMINAL_COMMAND_RE` *and* one of `_TERMINAL_REPORT_FIELDS`
         (issue #1274).
    Condition 1 alone only proves the model *mentioned* the marker, not
    that it *emitted* a report: `cat <<'EOF' > /tmp/report.txt` redirects
    the text to a file, and a marker inside a script comment or a
    templating command never surfaces either. Condition 2 is what proves
    the report actually reached stdout — a redirect produces no stdout, so
    the pair never forms.

    Requiring the pair does NOT reopen issue #608 (SKILL.md read into a
    `tool_result`): that path can only ever satisfy condition 2, because
    the command doing the reading (`Read`, `cat SKILL.md`) can never
    satisfy condition 1 — `_TERMINAL_COMMAND_RE` demands a literal digit
    where the templates carry `<N>` / `<i>`. The pair requirement is
    strictly narrower than either half on its own.

    Issue #1274 narrows condition 2 further: the paired `tool_result` must
    also carry a report *field* line (`_TERMINAL_REPORT_FIELDS` — `PR
    URL:` for the success form, `Resume after fix:` for the failure form).
    The marker line alone used to be enough, which let `grep
    "gh:issue-flow complete (#1270)" some.log` terminate a live flow: the
    command holds a literal-digit marker and grep echoes the matched line
    back, satisfying both halves without any report being produced. A real
    Step 3 report is multi-line and always carries one of those fields, so
    demanding the full shape splits the two cases apart. The requirement is
    deliberately placed on the result only — the command side stays the
    plain marker match, so a heredoc that prints the report still qualifies
    regardless of how the field line is quoted or built.

    Residual risk after #1274, stated honestly: a context-grep that happens
    to pull a real report's field line along with its marker line — e.g.
    `grep -A5 "gh:issue-flow complete (#1270)" some.log` over a log that
    stores a genuine past report. That is markedly more contrived than the
    bare `grep` it replaces (concrete issue number, matching the *live*
    flow's number, plus a context flag wide enough to reach the field
    line), which is the point of the narrowing.

    **Only `Bash` is scanned — never `Write`, `Edit`, or any other tool.**
    Editing `SKILL.md` or `references/report-template.md` puts real
    template text into an `Edit.new_string` / `Write.content` (this very
    change does exactly that), so scanning those inputs would
    false-terminate any flow that touches the skill's own files. Outside
    the pairing lookup above, `tool_result` remains excluded for the #608
    reason.
    """
    terminal = False
    seen: list[str] = []
    # Ids of `Bash` tool_uses whose command matched but whose paired
    # tool_result has not been seen yet. The result arrives in a LATER
    # `role=user` entry than the tool_use, so the candidate has to be
    # carried across iterations of this single forward walk.
    pending_bash_ids: set[str] = set()
    for entry in messages[start + 1 :]:
        msg = _message_payload(entry)
        role = msg.get("role")
        # `terminal` is monotonic, so once it is set the marker work on
        # every later message is pure waste on the turn-end hot path (that
        # includes growing `pending_bash_ids`). The loop itself cannot
        # break — `seen` must keep accumulating so the trace still reports
        # the full sub-skill count.
        if role == "assistant" and not terminal:
            for text in _iter_text_blocks(msg, include_tool_results=False):
                if any(pat in text for pat in TERMINAL_PATTERNS):
                    terminal = True
                    break
            if not terminal:
                for block_id, command in _iter_bash_tool_uses(msg):
                    if _TERMINAL_COMMAND_RE.search(command):
                        pending_bash_ids.add(block_id)
        elif role == "user" and not terminal and pending_bash_ids:
            for tool_use_id, text in _iter_tool_results(msg):
                if (
                    tool_use_id in pending_bash_ids
                    and _TERMINAL_COMMAND_RE.search(text)
                    # #1274 — a bare marker line can be a grep echo; a real
                    # report also carries `PR URL:` / `Resume after fix:`.
                    and any(field in text for field in _TERMINAL_REPORT_FIELDS)
                ):
                    terminal = True
                    break
        for skill in _iter_skill_uses(msg):
            if skill not in SUB_SKILL_NAMES:
                continue
            normalized = _SUB_SKILL_CANONICAL[skill]
            if normalized not in seen:
                seen.append(normalized)
    return terminal, seen


def _async_wait_streak(messages: list[dict[str, Any]], boundary: int) -> int:
    """Count TRAILING consecutive `[flow:async-wait]`-bearing turns (#1550).

    A streak of N means: the last N assistant messages since the last
    progress event EACH carried the marker, with no gap. It is deliberately
    NOT a flat total of every marker seen in that window — codex + agy
    review (PR #1594) both flagged the original flat-total version: it let
    ONE early marker grant grace forever after, because a later stop attempt
    whose own latest turn carried no marker at all still inherited the old
    count. The fix here is to walk backward and stop the count dead the
    first time a message fails to renew the claim — so the model must
    re-assert the wait on every turn it wants graced, not just once.

    "Progress event" for the OUTER chain is a sub-skill `Skill()` invocation:
    the chain moved forward, so whatever the model was waiting on is done —
    walking BACKWARD from the end and stopping there answers that in one
    partial pass. When no sub-skill ran at all, the walk runs back to the
    boundary.

    Each assistant message contributes AT MOST 1 to the streak (a boolean
    "did this turn carry the marker", not a count of matches within it) —
    agy also flagged that `sum(finditer)` let a turn with multiple marker
    lines (e.g. one quoted inside explanatory prose) burn through the grace
    limit in a single turn.

    Markers are read from `role=assistant` text blocks only, with
    `include_tool_results=False` — see `_ASYNC_WAIT_RE` for why that is
    deliberately asymmetric with the sister hook's `[step:.../...] OK` scan
    and must stay that way.

    Never raises; a malformed entry can only yield a smaller count.
    """
    streak = 0
    for entry in reversed(messages[boundary + 1 :]):
        msg = _message_payload(entry)
        if any(skill in SUB_SKILL_NAMES for skill in _iter_skill_uses(msg)):
            break
        if msg.get("role") != "assistant":
            continue
        has_marker = any(_ASYNC_WAIT_RE.search(text) for text in _iter_text_blocks(msg, include_tool_results=False))
        if not has_marker:
            break
        streak += 1
    return streak


def _env_int(name: str, default: int) -> int:
    """Read a non-negative int knob from the environment, or `default`.

    Shared by `_async_wait_grace_limit` (#1550) and `_max_stale_user_turns`
    (#1270), which had identical bodies:
      - a valid non-negative int → use it (`0` means "disabled"),
      - unset / unparseable / negative → `default` (unset reaches the
        `ValueError` arm via the `""` default).
    Never raises — a bad value silently degrades to the default.
    """
    try:
        value = int(os.environ.get(name, ""))
    except ValueError:
        return default
    return value if value >= 0 else default


def _async_wait_grace_limit() -> int:
    """Read the async-wait grace limit from the environment (#1550).

    Env var: `GH_ISSUE_FLOW_STOP_GUARD_ASYNC_WAIT_LIMIT`; `0` disables the
    grace entirely (the very first marker occurrence already blocks).
    """
    return _env_int("GH_ISSUE_FLOW_STOP_GUARD_ASYNC_WAIT_LIMIT", _DEFAULT_ASYNC_WAIT_LIMIT)


def _max_stale_user_turns() -> int:
    """Read the boundary-expiry threshold from the environment (#1270).

    Env var: `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS`; `0` disables expiry
    entirely (never fail open on staleness alone).
    """
    return _env_int("GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS", _DEFAULT_MAX_STALE_USER_TURNS)


def _count_fresh_user_prompts(messages: list[dict[str, Any]], start: int) -> int:
    """Count genuinely NEW user prompts after the boundary (#1270).

    A `role=user` transcript entry counts only when ALL of these hold:
      - the OUTER transcript entry is not flagged `isMeta` — Claude Code
        stamps that flag on Stop-hook feedback injections and skill
        expansions but never on a genuine human prompt (PR #1272 review).
        The flag lives on the entry, NOT on the inner `message` dict, which
        is why this loop inspects `entry` and `_message_payload(entry)`
        separately;
      - after collecting text (`include_tool_results=False`), joining, and
        deleting every `<system-reminder>…</system-reminder>` span, the
        remainder is non-empty. This is also what makes a tool-output-only
        message free: `tool_result` blocks contribute no text under
        `include_tool_results=False`, so such a message yields "" and is
        dropped here. There is deliberately NO wholesale "has a tool_result
        block ⇒ skip" rule (PR #1272 review, Codex BLOCKER): a real human
        prompt bundled in the same turn as tool output must still count,
        otherwise a stale boundary can never expire;
      - the remainder starts no line with `_SKILL_EXPANSION_RE` (an invoked
        skill's body injected as a user message) nor `_HARNESS_INJECTION_RE`
        (Stop-hook feedback, background-task notifications) — both are
        machinery generated by the flow itself. Line-anchored, not substring
        (#1281): a human quoting one of those strings mid-sentence is still
        a fresh prompt.

    Drives boundary expiry — see `_DEFAULT_MAX_STALE_USER_TURNS` for why
    that valve has to exist at all.

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
        if _SKILL_EXPANSION_RE.search(remainder):
            continue
        if _HARNESS_INJECTION_RE.search(remainder):
            continue
        count += 1
    return count


def _next_step_label(seen: list[str]) -> str:
    """Map the highest-index sub-skill seen to a human label for the *next* one.

    Both names of the slot are quoted (#1678): the canonical dotfiles one the
    model is most likely to have installed, and the post-migration alias. A
    session running the `gh-flow-skills` plugin has only the latter, so naming
    the canonical form alone would answer a block with an instruction to invoke
    a skill that does not exist there. The canonical name stays first and
    unparenthesised, which is also what keeps the existing
    `"Step 2.2 — Skill(gh-commit)"` substring assertions matching.

    The alias comes from `_SUB_SKILL_HINT_ALIAS`, keyed by slot — never from
    a position inside the slot's alias tuple.
    """
    canonical = [forms[0] for forms in EXPECTED_CHAIN]
    next_idx = 0
    for i, name in enumerate(canonical):
        if name in seen:
            next_idx = i + 1
    if next_idx >= len(canonical):
        return "Step 3 — emit the final 'gh:issue-flow complete (#N)' / 'gh-flow:issue complete (#N)' report"
    alias = _SUB_SKILL_HINT_ALIAS[canonical[next_idx]]
    return f"{STEP_LABELS[next_idx]} — Skill({canonical[next_idx]}) (or Skill({alias}))"


def _resolve_transcript_path(event: dict[str, Any]) -> tuple[str | None, str]:
    """Pick the transcript this event is really about (issue #1434).

    `SubagentStop` carries BOTH keys: `transcript_path` is the PARENT
    session's transcript and `agent_transcript_path` is the subagent's own
    (measured, issue #1434). The subagent's is the one whose turn is ending,
    so it wins whenever present. `Stop` events carry only `transcript_path`.

    Returns `(path, source_key)`, or `(None, "")` when no acceptable key
    holds a non-empty string. The source key is returned so the L1 trace can
    name which transcript the decision was made from — the difference between
    "the guard is a no-op" and "the guard read the wrong session" is
    otherwise invisible in a log.

    On `SubagentStop` the subagent's own key is the ONLY acceptable source
    (PR #1438, agy review). The preference chain used to be unconditional, so
    a `SubagentStop` whose `agent_transcript_path` was missing or empty fell
    straight through to the PARENT's `transcript_path` — exactly the
    cross-session contamination the paragraph below forbids: a parent holding
    a half-finished flow would block an unrelated subagent's turn. Such an
    event now resolves to `(None, "")` and `main()` fails open instead.

    ONLY the literal event name `"SubagentStop"` narrows the lookup. Any
    other event — `Stop`, or a payload carrying no `hook_event_name` at all —
    keeps the plain preference order (`agent_transcript_path` first, then
    `transcript_path`), so nothing outside the subagent path changes.

    Deliberately NOT a fallback chain on readability either: `main()` fails
    open if the *chosen* path does not exist rather than retrying the other
    key. A subagent whose transcript is unreadable must never be judged by
    its parent's flow state — the parent session can hold a half-finished
    flow that has nothing to do with this subagent, and using it would block
    an unrelated turn.
    """
    if event.get("hook_event_name") == "SubagentStop":
        value = event.get("agent_transcript_path")
        if isinstance(value, str) and value:
            return value, "agent_transcript_path"
        return None, ""
    for key in ("agent_transcript_path", "transcript_path"):
        value = event.get(key)
        if isinstance(value, str) and value:
            return value, key
    return None, ""


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

    transcript_path, transcript_source = _resolve_transcript_path(event)
    if transcript_path is None:
        return _allow("missing transcript_path")
    _trace(f"transcript_source={transcript_source} transcript_path={transcript_path}", layer="L1")
    p = Path(transcript_path)
    if not p.is_file():
        # No fallback to the other key on purpose (#1434) — why:
        # `_resolve_transcript_path`.
        return _allow(f"transcript file not found: {transcript_path} (transcript_source={transcript_source})")

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
    # Issue #1550 — same hot-path discipline as the fresh-prompt count above:
    # the streak feeds nothing but the grace valve, so skip the walk whenever
    # its result provably cannot be used. Trace mode forces it so the L1.5
    # diagnostic line stays complete.
    async_wait_limit = _async_wait_grace_limit()
    async_wait_streak = (
        _async_wait_streak(messages, boundary) if _TRACE_ENABLED or (not terminal and async_wait_limit > 0) else 0
    )
    if _TRACE_ENABLED:
        _trace(
            f"boundary={boundary} sub_skills_seen={len(seen)}/{len(EXPECTED_CHAIN)} "
            f"({','.join(seen) if seen else 'none'}) terminal={terminal} "
            f"fresh_user_prompts={fresh_prompts} "
            f"async_wait_streak={async_wait_streak} async_wait_limit={async_wait_limit}",
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

    # Issue #1550 — async-wait grace. Sits AFTER the terminal and
    # stale-boundary checks on purpose: both of those still take priority,
    # so this valve only ever changes the outcome on the path that would
    # otherwise block. A streak inside the limit means the model told us,
    # on the record, that it delegated the outstanding work to a background
    # Agent and is waiting — not that it abandoned the flow. Past the limit
    # the marker stops buying anything and the ordinary block resumes.
    # (`limit <= 0` needs no separate guard: it makes the range unsatisfiable.)
    if 0 < async_wait_streak <= async_wait_limit:
        return _allow(
            f"async-wait grace ({async_wait_streak}/{async_wait_limit}) — background "
            f"delegation in progress, not abandonment",
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
