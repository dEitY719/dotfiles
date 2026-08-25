"""Tests for claude/hooks/gh_issue_flow_stop_guard.py (issue #383).

The hook is invoked as a Claude Code Stop event handler. It reads a JSON
event from stdin, optionally parses the conversation transcript at
event['transcript_path'], and either:

  - exits 0 with empty stdout  → allow the model to stop, OR
  - exits 0 with `{"decision":"block","reason":"..."}` on stdout
    → block the stop and re-prompt the model.

These tests assemble synthetic transcript fixtures (one JSONL line per
message) covering the full state space and assert the hook's stdout +
exit code.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / "claude" / "hooks" / "gh_issue_flow_stop_guard.py"


def _run_hook(
    stdin_payload: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Invoke the hook with the given stdin string and optional env overrides."""
    import os as _os

    final_env: dict[str, str] | None = None
    if env is not None:
        final_env = _os.environ.copy()
        final_env.update(env)
    return subprocess.run(
        ["python3", str(HOOK_PATH)],
        input=stdin_payload,
        capture_output=True,
        text=True,
        timeout=10,
        env=final_env,
    )


def _write_transcript(tmp_path: Path, messages: list[dict[str, Any]]) -> Path:
    """Write a list of dict messages to a JSONL transcript file."""
    p = tmp_path / "transcript.jsonl"
    with p.open("w", encoding="utf-8") as f:
        for m in messages:
            f.write(json.dumps(m) + "\n")
    return p


def _user_text(text: str) -> dict[str, Any]:
    """Build a user-typed message entry."""
    return {"type": "user", "message": {"role": "user", "content": text}}


def _assistant_text(text: str) -> dict[str, Any]:
    """Build an assistant text-only message entry."""
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": text}],
        },
    }


def _user_tool_result(text: str, tool_use_id: str = "toolu_test") -> dict[str, Any]:
    """Build a user message carrying a single tool_result block.

    Used to simulate Read/Bash tool output landing in the transcript — i.e.
    file content that happens to mention "/gh-issue-flow" but is NOT a
    user-typed command. `tool_use_id` is explicit because the #1270 Bash
    terminal channel pairs a command with its OWN result by that id
    (PR #1272 review).
    """
    return {
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tool_use_id,
                    "content": text,
                }
            ],
        },
    }


def _user_tool_result_blocks(texts: list[str], tool_use_id: str) -> dict[str, Any]:
    """Same as `_user_tool_result`, but `content` is a LIST of text blocks.

    Both shapes occur in real transcripts; the pairing lookup must read
    either one (#1270 / PR #1272 review).
    """
    return {
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tool_use_id,
                    "content": [{"type": "text", "text": t} for t in texts],
                }
            ],
        },
    }


def _user_meta_text(text: str) -> dict[str, Any]:
    """Build a user-role entry flagged `isMeta` on the OUTER entry (#1270).

    Claude Code stamps `isMeta: true` on the text it injects into the user
    channel itself (Stop-hook feedback, skill expansions) and never on a
    human prompt. The flag deliberately sits outside `message`, which is
    exactly what the pre-fix counter failed to look at.
    """
    return {"type": "user", "isMeta": True, "message": {"role": "user", "content": text}}


def _user_text_with_tool_result(text: str) -> dict[str, Any]:
    """Build a user message carrying BOTH human text and tool output (#1270).

    Real transcripts bundle these in one turn. The pre-fix counter skipped
    any message containing a tool_result wholesale, so the human half never
    counted and a stale boundary could not expire (Codex BLOCKER, PR #1272).
    """
    return {
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": "toolu_test_mixed",
                    "content": "tests: 42 passed",
                },
                {"type": "text", "text": text},
            ],
        },
    }


def _assistant_tool_use(name: str, tool_input: dict[str, Any], block_id: str | None = None) -> dict[str, Any]:
    """Build an assistant tool_use message for an arbitrary tool.

    Used by issue #1270 to prove that non-Bash tool inputs (Edit / Write)
    are never scanned for the terminal marker.
    """
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {
                    "type": "tool_use",
                    "id": block_id or f"toolu_{name.lower()}",
                    "name": name,
                    "input": tool_input,
                }
            ],
        },
    }


def _assistant_skill(skill: str, args: str = "") -> dict[str, Any]:
    """Build an assistant tool_use message invoking Skill(<skill>)."""
    return _assistant_tool_use("Skill", {"skill": skill, "args": args}, f"toolu_{skill}")


def _assistant_bash(command: str, block_id: str = "toolu_bash") -> dict[str, Any]:
    """Build an assistant tool_use message invoking Bash(command=...).

    Used by the issue #1270 fixtures where the model prints the Step 3
    report through a heredoc / printf instead of plain assistant text.
    `block_id` is explicit so a fixture can pair (or deliberately
    mis-pair) the command with its `tool_result`.
    """
    return _assistant_tool_use("Bash", {"command": command, "description": "run a command"}, block_id)


def _assistant_bash_no_id(command: str) -> dict[str, Any]:
    """A `Bash` tool_use block with NO `id` field (#1270 / PR #1272).

    Such a block can never be paired with a tool_result, so it must never
    terminate the flow.
    """
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {
                    "type": "tool_use",
                    "name": "Bash",
                    "input": {"command": command, "description": "run a command"},
                }
            ],
        },
    }


# The canonical 6-step gh-issue-flow chain, restated here on purpose: these
# tests drive the hook as a black box via subprocess and never import its
# EXPECTED_CHAIN, so a change to the chain must break the tests loudly.
_ALL_SIX_SUB_SKILLS = [
    "gh-issue-implement",
    "gh-commit",
    "gh-pr",
    "devx-pr-review-all",
    "gh-pr-resolve-conflict",
    "gh-pr-resolve-outdated",
]


def _full_chain_prefix() -> list[dict[str, Any]]:
    """Boundary + all six sub-skill invocations, with no Step 3 report yet."""
    return [_user_text("/gh-issue-flow 1270"), *(_assistant_skill(n) for n in _ALL_SIX_SUB_SKILLS)]


def _hook_event(transcript_path: Path | None, **extras: Any) -> str:
    """Build a Stop hook stdin payload."""
    payload: dict[str, Any] = {
        "hook_event_name": "Stop",
        "session_id": "test-session",
        "stop_hook_active": False,
    }
    if transcript_path is not None:
        payload["transcript_path"] = str(transcript_path)
    payload.update(extras)
    return json.dumps(payload)


def test_hook_script_exists_and_is_executable() -> None:
    assert HOOK_PATH.is_file(), f"Hook script missing: {HOOK_PATH}"
    # Either the +x bit OR being callable via `python3` is enough.
    # We exercise the python3 path in the rest of the suite.


def test_empty_stdin_allows_stop() -> None:
    result = _run_hook("")
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_malformed_json_stdin_allows_stop() -> None:
    result = _run_hook("this is not json {{{")
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_stdin_not_a_dict_allows_stop() -> None:
    result = _run_hook(json.dumps([1, 2, 3]))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_missing_transcript_path_allows_stop() -> None:
    result = _run_hook(json.dumps({"hook_event_name": "Stop"}))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_unreadable_transcript_path_allows_stop(tmp_path: Path) -> None:
    fake = tmp_path / "does-not-exist.jsonl"
    result = _run_hook(_hook_event(fake))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_no_flow_boundary_in_transcript_allows_stop(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("just chatting about something else"),
            _assistant_text("sure, here's an answer to that unrelated question."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_stop_hook_active_short_circuits(tmp_path: Path) -> None:
    """Even if mid-flow, stop_hook_active=true must allow the stop.

    Otherwise we form an infinite Stop→block→Stop loop within a chain.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement", "42 direct origin --no-next-hint"),
        ],
    )
    payload = _hook_event(transcript, stop_hook_active=True)
    result = _run_hook(payload)
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_completed_flow_allows_stop(tmp_path: Path) -> None:
    """All 6 sub-skills + Step 3 marker present → allow stop."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-pr-review-all"),
            _assistant_skill("gh-pr-resolve-conflict"),
            _assistant_skill("gh-pr-resolve-outdated"),
            _assistant_text("gh:issue-flow complete (#42)\n  PR URL: https://github.com/example/repo/pull/99"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_stopped_marker_also_allows_stop(tmp_path: Path) -> None:
    """The 'stopped at step' failure marker counts as terminal too."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_text("gh:issue-flow stopped at step 1/5 (gh:issue-implement)"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_mid_flow_after_step_2_1_blocks_with_next_hint(tmp_path: Path) -> None:
    """Only gh-issue-implement called → block, naming gh-commit as next."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement", "42 direct origin --no-next-hint"),
            # The model writes a fake-looking success block but no Step 3 marker.
            _assistant_text("gh:issue-implement #42 complete\n  Mode: direct\n  Tests: 42 passed, 0 failed"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "expected a block decision, got nothing"
    decision = json.loads(result.stdout)
    assert decision.get("decision") == "block"
    reason = decision.get("reason", "")
    assert "gh-commit" in reason
    assert "Step 2.2" in reason
    assert "1/6" in reason


def test_mid_flow_skill_call_with_colon_namespace_counted(tmp_path: Path) -> None:
    """Skill names like 'gh:issue-implement' (colon form) count too."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh:issue-implement"),
            _assistant_skill("gh:commit"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-pr" in decision["reason"]
    assert "Step 2.3" in decision["reason"]
    assert "2/6" in decision["reason"]


def test_mid_flow_after_all_6_blocks_for_step_3_report(tmp_path: Path) -> None:
    """All 6 sub-skills run but no terminal marker → block, ask for Step 3."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-pr-review-all"),
            _assistant_skill("gh-pr-resolve-conflict"),
            _assistant_skill("gh-pr-resolve-outdated"),
            # No Step 3 report yet.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "Step 3" in decision["reason"]
    assert "6/6" in decision["reason"]


def test_mid_flow_after_resolve_conflict_blocks_for_resolve_outdated(tmp_path: Path) -> None:
    """5 sub-skills through gh-pr-resolve-conflict, no terminal → block,
    naming gh-pr-resolve-outdated (Step 2.5.1) as the next step."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-pr-review-all"),
            _assistant_skill("gh-pr-resolve-conflict"),
            # No Step 3 report yet — resolve-outdated still pending.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    reason = decision["reason"]
    assert "gh-pr-resolve-outdated" in reason
    assert "Step 2.5.1" in reason
    assert "5/6" in reason


def test_missing_pr_review_all_blocks_naming_step_2_4(tmp_path: Path) -> None:
    """A run that reaches gh-pr but has not yet invoked devx:pr-review-all
    (Step 2.4) → block, and the reason names that step as the next action."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            # devx:pr-review-all NOT invoked; model authors a fake wrap-up.
            _assistant_text("gh:pr #42 opened — PR URL: https://x/pull/9\nAll done!"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    reason = decision["reason"]
    assert "devx-pr-review-all" in reason
    assert "Step 2.4" in reason
    assert "3/6" in reason


def test_skill_invocation_via_assistant_works_as_boundary(tmp_path: Path) -> None:
    """Boundary can be a Skill(gh-issue-flow) tool_use, not just user text."""
    transcript = _write_transcript(
        tmp_path,
        [
            _assistant_skill("gh-issue-flow", "42"),
            _assistant_skill("gh-issue-implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_unrelated_skill_after_boundary_not_counted(tmp_path: Path) -> None:
    """Random other Skill() calls don't advance the gh-issue-flow counter."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("some-unrelated-skill"),
            _assistant_skill("another-helper"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    # Still only 1/6 — the unrelated skills must not bump the counter.
    assert "1/6" in decision["reason"]


def test_malformed_jsonl_lines_skipped(tmp_path: Path) -> None:
    """Garbage lines in the middle of the transcript don't crash the hook."""
    p = tmp_path / "transcript.jsonl"
    with p.open("w", encoding="utf-8") as f:
        f.write(json.dumps(_user_text("/gh-issue-flow 42")) + "\n")
        f.write("not valid json at all {{{\n")
        f.write(json.dumps(_assistant_skill("gh-issue-implement")) + "\n")
        f.write("\n")  # blank line
    result = _run_hook(_hook_event(p))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_tool_result_mentioning_command_not_treated_as_boundary(tmp_path: Path) -> None:
    """File content read by the model that contains "/gh-issue-flow" must
    NOT be treated as the user invoking the command (PR #386 review fix).

    Regression for the boundary-detection false positive: previously,
    `_find_flow_boundary` did `tok in text` across all blocks including
    tool_result, so any session that read this skill's own SKILL.md (which
    documents `/gh-issue-flow ...`) would be flagged as in-flow and stops
    would be blocked.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("can you read the gh-issue-flow SKILL.md and explain it?"),
            # Simulate a Read tool_result returning the SKILL.md content,
            # which legitimately contains the command string.
            _user_tool_result(
                "# gh:issue-flow — Issue → PR composition\n\n"
                "Use when the user runs /gh-issue-flow N or /gh:issue-flow N.\n"
                "Step 2.1 invokes Skill(gh-issue-implement) ...\n"
            ),
            _assistant_text("Here's how the skill works: ..."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    # No real /gh-issue-flow boundary anywhere — must allow stop.
    assert result.stdout.strip() == "", (
        f"Hook treated tool_result file content as a flow boundary. stdout={result.stdout!r}"
    )


def test_command_only_at_start_of_user_text_counts(tmp_path: Path) -> None:
    """User text that *mentions* /gh-issue-flow mid-sentence is NOT a
    command; only text starting with the token counts as a boundary
    (PR #386 review fix — preferred form per gemini suggestion).
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text(
                "I was reading the docs about /gh-issue-flow and got confused — "
                "could you summarize how Step 2.x chains together?"
            ),
            _assistant_text("Sure — here's a summary: ..."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Hook treated mid-sentence mention of /gh-issue-flow as a command. stdout={result.stdout!r}"
    )


def test_command_with_leading_whitespace_still_counts(tmp_path: Path) -> None:
    """Leading whitespace before /gh-issue-flow is tolerated (typo-friendly)
    so users who paste with indent still get the chain protection.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("   /gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


@pytest.mark.parametrize(
    "exec_form",
    [
        ["python3", str(HOOK_PATH)],
        [str(HOOK_PATH)],  # via shebang
    ],
)
def test_hook_callable_two_ways(tmp_path: Path, exec_form: list[str]) -> None:
    """Both `python3 hook.py` and direct `./hook.py` (via shebang) work."""
    transcript = _write_transcript(
        tmp_path,
        [_user_text("just an unrelated chat")],
    )
    result = subprocess.run(
        exec_form,
        input=_hook_event(transcript),
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Trace mode (issue #505, fix-plan C)
# ---------------------------------------------------------------------------


def test_trace_off_by_default_no_stderr(tmp_path: Path) -> None:
    """Without GH_ISSUE_FLOW_STOP_GUARD_TRACE=1, stderr stays clean."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    # Block decision on stdout; nothing on stderr.
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert result.stderr == ""


def test_trace_on_emits_block_diagnostics(tmp_path: Path) -> None:
    """With trace enabled, stderr describes the boundary + decision."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    # Trace lines all share the [stop-guard] prefix.
    assert "[stop-guard]" in result.stderr
    # The boundary scan summary should report 1/6 sub-skills seen.
    assert "sub_skills_seen=1/6" in result.stderr
    assert "block:" in result.stderr


def test_trace_on_emits_allow_reason_for_no_boundary(tmp_path: Path) -> None:
    """Allow path should also report its reason when trace mode is on."""
    transcript = _write_transcript(
        tmp_path,
        [_user_text("just a chat unrelated to gh-issue-flow")],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert "[stop-guard] allow:" in result.stderr
    assert "no gh-issue-flow boundary" in result.stderr


def test_trace_on_emits_allow_reason_for_terminal_marker(tmp_path: Path) -> None:
    """Completed-flow allow path also reports its reason under trace."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-pr-review-all"),
            _assistant_skill("gh-pr-resolve-conflict"),
            _assistant_skill("gh-pr-resolve-outdated"),
            _assistant_text("gh:issue-flow complete (#42)"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert "Step 3 terminal marker" in result.stderr
    assert "sub_skills_seen=6/6" in result.stderr


# ---------------------------------------------------------------------------
# Wrapped slash-command boundary (issues #607 / #609)
#
# When a user invokes `/gh-issue-flow N` interactively, Claude Code does not
# place the raw command in the transcript. Instead it writes a multi-line
# user message of the form:
#
#     <command-message>gh-issue-flow</command-message>
#     <command-name>/gh-issue-flow</command-name>
#     <command-args>N</command-args>
#     Base directory for this skill: .../skills/gh-issue-flow
#     # gh:issue-flow — Issue → PR composition
#     ...(SKILL.md body)...
#     ARGUMENTS: N
#
# The pre-#607 boundary detector used `lstrip().startswith("/gh-issue-flow")`,
# which never matched this wrapped form — so every Stop event in a real
# `/gh-issue-flow` session fell through to fail-open and the chain stopped
# the moment the model emitted any prose between sub-skills. These fixtures
# reproduce the actual transcript form and pin down the regression.
# ---------------------------------------------------------------------------


def _user_slash_command(skill_name: str, args: str) -> dict[str, Any]:
    """Build a user message in the format Claude Code writes to transcripts.

    Mirrors the `<command-message>/<command-name>/<command-args>` triple
    plus the SKILL.md body that follows when the user invokes a slash
    command interactively. The fixture reproduces enough of the real
    transcript shape to drive boundary detection without bloating the
    test payload with a full SKILL.md.
    """
    content = (
        f"<command-message>{skill_name}</command-message>\n"
        f"<command-name>/{skill_name}</command-name>\n"
        f"<command-args>{args}</command-args>\n"
        f"Base directory for this skill: /tmp/skills/{skill_name}\n"
        f"# {skill_name}\n"
        f"ARGUMENTS: {args}\n"
    )
    return {"type": "user", "message": {"role": "user", "content": content}}


def test_wrapped_slash_command_recognized_as_flow_start(tmp_path: Path) -> None:
    """`<command-name>/gh-issue-flow</command-name>` must mark a boundary."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_slash_command("gh-issue-flow", "457"),
            _assistant_skill("gh-issue-implement", "457 direct origin --no-next-hint"),
            _assistant_text("gh:issue-implement #457 complete\n  Tests: 12 passed"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Hook must recognize the <command-name>/gh-issue-flow</command-name> "
        f"wrapped form as a flow boundary. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-commit" in decision["reason"]
    assert "Step 2.2" in decision["reason"]


def test_wrapped_slash_command_colon_namespace_recognized(tmp_path: Path) -> None:
    """The colon-namespace form `<command-name>/gh:issue-flow</command-name>`
    must also be recognized — Claude Code occasionally emits either form
    depending on how the skill is registered.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_slash_command("gh:issue-flow", "457"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-pr" in decision["reason"]
    assert "Step 2.3" in decision["reason"]


def test_wrapped_command_inside_tool_result_does_not_trigger(tmp_path: Path) -> None:
    """A `<command-name>/gh-issue-flow</command-name>` substring landing in
    a tool_result block (e.g. the model reads a doc that quotes Claude
    Code's wrapping format) must NOT be treated as a real invocation —
    the existing `include_tool_results=False` guard still applies to the
    new regex matcher.
    """
    wrapped_inside_doc = (
        "Example: when a user types /gh-issue-flow N, the transcript looks like\n"
        "\n"
        "    <command-name>/gh-issue-flow</command-name>\n"
        "    <command-args>N</command-args>\n"
        "\n"
        "and the hook treats that as the flow start.\n"
    )
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("can you read the docs about the gh-issue-flow stop hook?"),
            _user_tool_result(wrapped_inside_doc),
            _assistant_text("Sure — the hook ..."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        "Hook treated <command-name> string inside a tool_result as a real "
        f"slash-command invocation. stdout={result.stdout!r}"
    )


def test_wrapped_command_full_session_blocks_with_step_2_2_reason(
    tmp_path: Path,
) -> None:
    """End-to-end shape of the production regression in #607 / #609:

    user invokes /gh-issue-flow → Claude Code wraps it in <command-name>
    tags → assistant invokes Skill(gh-issue-implement) → assistant emits
    a self-authored success summary and tries to stop. The hook must
    block and route the model to Step 2.2.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_slash_command("gh-issue-flow", "457"),
            _assistant_skill("gh-issue-implement", "457 direct origin --no-next-hint"),
            _assistant_text(
                "gh:issue-implement complete for #457.\n\n"
                "Summary\n"
                "  Issue:        #457 feat(db): index strategy\n"
                "  Mode:         direct\n"
                "  Files:        1 new\n"
                "  Tests:        12 passed\n\n"
                "[ai-metrics:gh-issue-implement] ~7 min — will be included "
                "in gh-commit metrics\n"
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    reason = decision["reason"]
    assert "Step 2.2" in reason
    assert "gh-commit" in reason
    assert "1/6" in reason


# ---------------------------------------------------------------------------
# Issue #608 — L1 boundary expansion (surfaces c, d) + L1.5 scan-scope fix
#
# Two motivations layered together:
#
# 1. **L1 (defense-in-depth boundary surfaces).** Add the `Base directory
#    for this skill: …/gh-issue-flow` marker line and the SKILL.md H1
#    `# gh:issue-flow — Issue → PR composition` as additional boundary
#    anchors so the hook keeps working even if Claude Code ever changes
#    the `<command-name>` wrapper format (preserves chain protection
#    across CLI version drift).
# 2. **L1.5 (terminal-scan scope).** The 5th regression on this issue's
#    own ancestor (#383 → #607 → #608) was *not* a missing boundary —
#    it was that `_scan_after_boundary` matched `TERMINAL_PATTERNS`
#    against the SKILL.md body delivered as a `role=user` text block.
#    The template literally contains the lines
#        gh:issue-flow complete (#<N>)
#        gh:issue-flow stopped at step <i>/5
#    as Step 3 instructions, so the scan saw a terminal marker before
#    any sub-skill ran and fail-opened every invocation. Restricting
#    the scan to `role=assistant` text (excluding the boundary message
#    itself) fixes the false-match. These tests pin the fix down.
# ---------------------------------------------------------------------------


# Two literal lines that the real SKILL.md prompt body contains as Step 3
# template instructions. If the hook's terminal scan ever regresses back
# to reading user-role text, either line will trip a false `terminal=True`.
_SKILL_TEMPLATE_FALSE_POSITIVE = (
    "## Step 3: Report\n"
    "\n"
    "If all steps succeeded:\n"
    "```\n"
    "gh:issue-flow complete (#<N>)\n"
    "  [OK] Step 1: gh:issue-implement\n"
    "```\n"
    "If a step failed:\n"
    "```\n"
    "gh:issue-flow stopped at step <i>/5 (<skill-name>)\n"
    "```\n"
)


def _user_skill_base_dir_marker(skill_name: str = "gh-issue-flow") -> dict[str, Any]:
    """User message containing only the `Base directory for this skill:` line.

    Mirrors the line Claude Code emits when expanding a slash command,
    isolated so the test exercises surface (c) without depending on the
    `<command-name>` wrapper also being present.
    """
    content = f"Base directory for this skill: /home/user/.claude/skills/{skill_name}\n"
    return {"type": "user", "message": {"role": "user", "content": content}}


def _user_skill_h1_marker() -> dict[str, Any]:
    """User message containing only the SKILL.md H1 header line.

    Exercises surface (d) — the H1 anchor — in isolation.
    """
    content = "# gh:issue-flow — Issue → PR composition\n"
    return {"type": "user", "message": {"role": "user", "content": content}}


def test_base_dir_marker_recognized_as_flow_start(tmp_path: Path) -> None:
    """Surface (c): `Base directory for this skill: …/gh-issue-flow` marks the flow."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_skill_base_dir_marker(),
            _assistant_skill("gh-issue-implement", "608 direct origin --no-next-hint"),
            _assistant_text("gh:issue-implement #608 complete\n  Tests: 12 passed"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Hook must recognize 'Base directory for this skill: …/gh-issue-flow' "
        f"as a flow boundary. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "Step 2.2" in decision["reason"]


def test_base_dir_marker_does_not_match_unrelated_skill(tmp_path: Path) -> None:
    """Surface (c) only matches when the path ends with gh-issue-flow.

    False-positive guard: a base-directory line for some *other* skill
    (e.g. `gh-issue-implement` or `gh-issue-flow-archive`) must not be
    treated as a gh-issue-flow boundary.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            # Different skill — no boundary expected.
            _user_skill_base_dir_marker(skill_name="gh-issue-implement"),
            _assistant_text("ok, working on something else"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Hook treated a non-gh-issue-flow skill base directory as a flow boundary. stdout={result.stdout!r}"
    )


def test_skill_h1_marker_recognized_as_flow_start(tmp_path: Path) -> None:
    """Surface (d): the SKILL.md H1 line marks the flow boundary."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_skill_h1_marker(),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "Step 2.3" in decision["reason"]
    assert "gh-pr" in decision["reason"]


def test_skill_h1_mid_sentence_does_not_match(tmp_path: Path) -> None:
    """Surface (d) requires the H1 to occupy its own line.

    A mid-sentence quote like "the file starts with # gh:issue-flow — Issue
    → PR composition and ..." must not trip the boundary.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text(
                "I was reading the source — it has the line "
                "# gh:issue-flow — Issue → PR composition embedded in a paragraph."
            ),
            _assistant_text("ok"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Hook treated a mid-sentence H1 mention as a flow boundary. stdout={result.stdout!r}"
    )


def test_base_dir_marker_inside_tool_result_does_not_trigger(tmp_path: Path) -> None:
    """False-positive guard: `Base directory for this skill: …` inside a
    `tool_result` block (e.g. the model reads a doc that quotes the
    line) must not be treated as a real invocation.
    """
    doc_excerpt = (
        "Each skill invocation begins with a banner like\n"
        "    Base directory for this skill: /home/user/.claude/skills/gh-issue-flow\n"
        "which the hook detects as a boundary.\n"
    )
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("can you read the stop-guard docs?"),
            _user_tool_result(doc_excerpt),
            _assistant_text("Sure — here's a summary."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Hook treated a `Base directory` line inside tool_result as a flow boundary. stdout={result.stdout!r}"
    )


def test_skill_h1_inside_tool_result_does_not_trigger(tmp_path: Path) -> None:
    """False-positive guard for surface (d) — H1 line inside a tool_result."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("explain the gh-issue-flow SKILL.md"),
            _user_tool_result(
                "# gh:issue-flow — Issue → PR composition\n\n(rest of SKILL.md body that the model just read)\n"
            ),
            _assistant_text("It chains 5 sub-skills..."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Hook treated an H1 line inside tool_result as a flow boundary. stdout={result.stdout!r}"
    )


def test_skill_template_text_in_user_message_does_not_false_terminate(
    tmp_path: Path,
) -> None:
    """L1.5 (issue #608 root cause): SKILL.md template lines literally
    containing `gh:issue-flow complete (#<N>)` and `gh:issue-flow stopped
    at step <i>/5` must NOT count as a terminal marker.

    Reproduction of the 5th regression: when a user types
    `/gh-issue-flow N`, Claude Code expands the SKILL.md body inline as
    a `role=user` text block. The body contains the Step 3 template
    *as instructions*. Before this fix, `_scan_after_boundary` saw the
    template text, set `terminal=True`, and the hook fail-opened on
    every real invocation. The fix restricts the terminal scan to
    `role=assistant` text blocks. This fixture is the production-shape
    transcript that must still produce a `block` decision.
    """
    # User message contains BOTH the wrapped slash command (boundary)
    # AND the SKILL.md Step 3 template lines (would-be false-terminator).
    boundary_with_template = (
        "<command-message>gh-issue-flow</command-message>\n"
        "<command-name>/gh-issue-flow</command-name>\n"
        "<command-args>608</command-args>\n"
        "Base directory for this skill: /home/user/.claude/skills/gh-issue-flow\n"
        "\n"
        "# gh:issue-flow — Issue → PR composition\n"
        "\n" + _SKILL_TEMPLATE_FALSE_POSITIVE + "ARGUMENTS: 608\n"
    )
    transcript = _write_transcript(
        tmp_path,
        [
            {
                "type": "user",
                "message": {"role": "user", "content": boundary_with_template},
            },
            _assistant_skill("gh-issue-implement", "608 direct origin --no-next-hint"),
            _assistant_text("gh:issue-implement #608 complete\n  Files: 2 changed\n  Tests: 32 passed"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Hook fail-opened on a real /gh-issue-flow invocation — the SKILL.md "
        "template text in the user message false-matched TERMINAL_PATTERNS. "
        f"stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "Step 2.2" in decision["reason"]
    assert "gh-commit" in decision["reason"]
    assert "1/6" in decision["reason"]


def test_skill_template_text_in_tool_result_does_not_false_terminate(
    tmp_path: Path,
) -> None:
    """L1.5 variant: model reads the SKILL.md or hook source as a
    tool_result during a real flow → must still block.

    Defensive check: even if a `Read`/`Bash` tool surfaces the
    TERMINAL_PATTERNS strings inside a `tool_result` block during an
    active chain, the terminal scan must not be tricked into allowing
    the stop. With the assistant-only scope, tool_result blocks (which
    live inside `role=user` messages per the Anthropic content-block
    model) are excluded automatically.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 608"),
            _assistant_skill("gh-issue-implement"),
            # Model reads the hook source while inside the flow.
            _user_tool_result(
                "TERMINAL_PATTERNS: tuple[str, ...] = (\n"
                '    "gh:issue-flow complete (#",\n'
                '    "gh:issue-flow stopped at step",\n'
                "    ...\n"
                ")\n"
            ),
            _assistant_text("Now committing...\n"),  # No real terminal marker.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Hook fail-opened — tool_result containing the TERMINAL_PATTERNS "
        f"source text was treated as a real terminal report. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "1/6" in decision["reason"]


def test_real_terminal_marker_in_assistant_text_still_allows_stop(
    tmp_path: Path,
) -> None:
    """L1.5 must not over-correct: a real assistant-authored Step 3
    report MUST still terminate the scan and allow the stop.

    Pairs with the false-positive tests above — guards against an
    accidental "block everything forever" regression.
    """
    boundary_with_template = (
        "<command-name>/gh-issue-flow</command-name>\n"
        "Base directory for this skill: /home/user/.claude/skills/gh-issue-flow\n" + _SKILL_TEMPLATE_FALSE_POSITIVE
    )
    transcript = _write_transcript(
        tmp_path,
        [
            {
                "type": "user",
                "message": {"role": "user", "content": boundary_with_template},
            },
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-pr-review-all"),
            _assistant_skill("gh-pr-resolve-conflict"),
            _assistant_skill("gh-pr-resolve-outdated"),
            # Real Step 3 success report — assistant role, real terminal marker.
            _assistant_text("gh:issue-flow complete (#608)\n  PR URL: https://x/pull/9"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        "Hook blocked a properly-completed flow — assistant-authored Step 3 "
        f"terminal marker was not recognized. stdout={result.stdout!r}"
    )


def test_trace_emits_layer_field_for_block(tmp_path: Path) -> None:
    """Issue #608 acceptance criteria: trace lines carry a `layer=...`
    field so multi-layer fix attribution is greppable."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 608"),
            _assistant_skill("gh-issue-implement"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    # The summary line (boundary + sub-skill count) is layer L1.5.
    assert "layer=L1.5" in result.stderr, f"Expected layer=L1.5 in trace output, got stderr={result.stderr!r}"


def test_trace_emits_layer_field_for_no_boundary_allow(tmp_path: Path) -> None:
    """Allow path on the L1 (boundary) side must also tag itself."""
    transcript = _write_transcript(
        tmp_path,
        [_user_text("hello world, no flow here")],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert "layer=L1" in result.stderr, (
        f"Expected layer=L1 on the no-boundary allow trace, got stderr={result.stderr!r}"
    )


# ---------------------------------------------------------------------------
# Issue #1270 — F-1: a Bash-emitted Step 3 report is terminal, but ONLY when
# the command AND its own paired `tool_result` both carry the marker
# (PR #1272 review, Codex BLOCKER — a command string alone proves the model
# mentioned the marker, not that it emitted a report). `tool_result` on its
# own (issue #608) and non-`Bash` tool inputs stay non-terminal. Mechanism
# and rationale: claude/skills/gh-issue-flow/references/stop-guard.md step 4.
# ---------------------------------------------------------------------------

_BASH_REPORT_HEREDOC = (
    "cat <<'EOF'\n"
    "gh:issue-flow complete (#1270)\n"
    "  [OK] Step 1: gh:issue-implement\n"
    "  PR URL: https://github.com/example/repo/pull/99\n"
    "EOF\n"
)
_BASH_REPORT_HEREDOC_STDOUT = (
    "gh:issue-flow complete (#1270)\n"
    "  [OK] Step 1: gh:issue-implement\n"
    "  PR URL: https://github.com/example/repo/pull/99\n"
)


@pytest.mark.parametrize(
    ("command", "stdout_text"),
    [
        pytest.param(_BASH_REPORT_HEREDOC, _BASH_REPORT_HEREDOC_STDOUT, id="heredoc"),
        pytest.param(
            "printf 'gh:issue-flow complete (#42)\\n  PR URL: https://github.com/example/repo/pull/7\\n'",
            "gh:issue-flow complete (#42)\n  PR URL: https://github.com/example/repo/pull/7\n",
            id="printf",
        ),
        pytest.param(
            "echo 'gh:issue-flow stopped at step 2/6 (gh:commit)\\n\\nResume after fix:\\n  /gh-pr-resolve-conflict 7'",
            "gh:issue-flow stopped at step 2/6 (gh:commit)\n\nResume after fix:\n  /gh-pr-resolve-conflict 7\n",
            id="stopped-at-step",
        ),
    ],
)
def test_bash_emitted_terminal_report_allows_stop(tmp_path: Path, command: str, stdout_text: str) -> None:
    """F-1: a Step 3 report printed through Bash terminates the flow — the
    command matches and its paired `tool_result` proves it reached stdout."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash(command, "toolu_report"),
            _user_tool_result(stdout_text, "toolu_report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        "Hook blocked a completed flow whose Step 3 report was emitted through "
        f"Bash. command={command!r} stdout={result.stdout!r}"
    )


def test_bash_terminal_report_list_shaped_tool_result_allows_stop(tmp_path: Path) -> None:
    """F-1: `tool_result.content` may be a list of text blocks, not just a
    plain string — the pairing lookup must read either shape."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash(_BASH_REPORT_HEREDOC, "toolu_report"),
            _user_tool_result_blocks(
                ["gh:issue-flow complete (#1270)", "  PR URL: https://github.com/example/repo/pull/99"],
                "toolu_report",
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"Hook ignored a list-shaped tool_result when pairing. stdout={result.stdout!r}"


def test_bash_terminal_report_split_mid_token_still_allows_stop(tmp_path: Path) -> None:
    """PR #1279 codex review: sub-blocks are fragments of ONE stdout string,
    not separate lines — nothing guarantees a split lands on a line boundary.
    Concatenating with `""` (not `"\\n"`) must reconstruct the original text
    even when a fragment splits mid-word, so a genuine report is still
    recognized instead of regressing to the #1270 'block forever' bug."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash(_BASH_REPORT_HEREDOC, "toolu_report"),
            _user_tool_result_blocks(
                ["gh:issue-flow compl", "ete (#1270)\n  PR URL: https://github.com/example/repo/pull/99"],
                "toolu_report",
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Hook missed a genuine report whose marker was split mid-token across sub-blocks. stdout={result.stdout!r}"
    )


def test_bash_report_redirected_to_file_does_not_terminate(tmp_path: Path) -> None:
    """PR #1272 Codex BLOCKER: the command carries the marker but redirects
    it into a file, so the `tool_result` is empty — no report ever surfaced
    as the completion signal and the flow must keep blocking."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash(
                "cat <<'EOF' > /tmp/report.txt\ngh:issue-flow complete (#1270)\nEOF\n",
                "toolu_redirect",
            ),
            _user_tool_result("", "toolu_redirect"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Hook treated a marker-bearing command whose output was redirected to a "
        f"file as a real Step 3 report. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_bash_marker_in_comment_with_unrelated_output_does_not_terminate(
    tmp_path: Path,
) -> None:
    """PR #1272 Codex BLOCKER, second shape: the marker sits in a shell
    comment, so the paired `tool_result` carries unrelated text."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash(
                "# next up: gh:issue-flow complete (#1270)\ngit status --short\n",
                "toolu_comment",
            ),
            _user_tool_result(" M claude/hooks/gh_issue_flow_stop_guard.py\n", "toolu_comment"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"Hook terminated on a marker that only appeared in a shell comment. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_marker_in_tool_result_without_matching_command_does_not_terminate(
    tmp_path: Path,
) -> None:
    """Issue #608 case, restated under pairing: the `tool_result` carries the
    marker but the command that produced it (`cat` of the template) cannot
    match `_TERMINAL_COMMAND_RE`, so no pair forms. Condition 2 alone is
    never enough."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash("cat claude/skills/gh-issue-flow/references/report-template.md", "toolu_cat"),
            _user_tool_result(
                "If all steps succeeded:\n```\ngh:issue-flow complete (#<N>)\n```\n",
                "toolu_cat",
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"Hook terminated on a tool_result whose command never matched. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_bash_terminal_report_with_mismatched_tool_use_id_does_not_terminate(
    tmp_path: Path,
) -> None:
    """The marker-bearing `tool_result` must belong to THAT tool_use — a
    result carried under a different `tool_use_id` forms no pair."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash(_BASH_REPORT_HEREDOC, "toolu_A"),
            _user_tool_result(_BASH_REPORT_HEREDOC_STDOUT, "toolu_B"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"Hook paired a tool_result with the wrong tool_use. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


def test_bash_tool_use_without_id_does_not_terminate(tmp_path: Path) -> None:
    """A `Bash` tool_use with no `id` cannot be paired with anything, so it
    must never terminate — even with a marker-bearing result nearby."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash_no_id(_BASH_REPORT_HEREDOC),
            _user_tool_result(_BASH_REPORT_HEREDOC_STDOUT, "toolu_report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"Hook terminated on an unpairable Bash tool_use. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


def test_bash_grep_of_template_text_does_not_terminate(tmp_path: Path) -> None:
    """F-1 false-positive guard: a command that merely greps the template
    text carries no literal issue/step digit, so the stricter Bash regex
    must not match it — the flow keeps blocking."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _assistant_bash('grep "gh:issue-flow complete" claude/skills/gh-issue-flow/SKILL.md'),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"Hook fail-opened on a grep of the Step 3 template text. stdout={result.stdout!r}"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "1/6" in decision["reason"]


# ---------------------------------------------------------------------------
# Issue #1274 — the residual false positive PR #1272 left behind: a `grep` of
# a REAL, already-completed report line satisfies both halves of the pair
# (literal-digit marker in the command, the same line echoed back as stdout).
# Fixed by demanding the full report SHAPE on the result side — the marker
# line plus a `PR URL:` / `Resume after fix:` field line, which one grepped
# line cannot reproduce.
# ---------------------------------------------------------------------------


def test_bash_grep_of_real_report_line_does_not_terminate(tmp_path: Path) -> None:
    """Issue #1274: `grep "gh:issue-flow complete (#1270)" some.log` echoes
    exactly the line it searched for, so before #1274 both halves of the
    #1272 pair matched and a live flow terminated on a log search. The result
    carries no `PR URL:` / `Resume after fix:` field, so it is not a report
    and the flow must keep blocking."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_full_chain_prefix(),
            _assistant_bash('grep "gh:issue-flow complete (#1270)" some.log', "toolu_grep"),
            _user_tool_result("gh:issue-flow complete (#1270)\n", "toolu_grep"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"Hook treated a grep echo of one real report line as a Step 3 report. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_report_template_still_carries_the_fields_the_hook_matches() -> None:
    """Issue #1274 drift guard (not a hook-behavior test).

    The Bash channel now requires a report *field* line in the paired
    `tool_result`, and those field names live in the report template the
    model is told to emit. If the template is ever edited to rename or drop
    `PR URL:` / `Resume after fix:`, the hook's matching would silently go
    stale — real reports would stop being recognized and the flow would
    block forever (the #1270 bug, reintroduced). Fail loudly here instead."""
    template = (REPO_ROOT / "claude" / "skills" / "gh-issue-flow" / "references" / "report-template.md").read_text(
        encoding="utf-8"
    )
    assert "PR URL:" in template, (
        "The success report template no longer contains 'PR URL:' — update "
        "_TERMINAL_REPORT_FIELDS in claude/hooks/gh_issue_flow_stop_guard.py (#1274)."
    )
    assert "Resume after fix:" in template, (
        "The failure report template no longer contains 'Resume after fix:' — update "
        "_TERMINAL_REPORT_FIELDS in claude/hooks/gh_issue_flow_stop_guard.py (#1274)."
    )


def test_template_text_in_tool_result_of_bash_cat_does_not_terminate(
    tmp_path: Path,
) -> None:
    """F-1 false-positive guard: `cat`ing the template puts the real
    placeholder text in a `tool_result`, which stays out of scope (#608).
    The `cat` command itself has no digit, so nothing terminates."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _assistant_bash("cat claude/skills/gh-issue-flow/references/report-template.md"),
            _user_tool_result(
                "If all steps succeeded:\n"
                "```\n"
                "gh:issue-flow complete (#<N>)\n"
                "```\n"
                "If a step failed:\n"
                "```\n"
                "gh:issue-flow stopped at step <i>/6 (<skill-name>)\n"
                "```\n"
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"Hook treated template text inside a tool_result as terminal. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_edit_and_write_tool_inputs_are_not_scanned_for_terminal(
    tmp_path: Path,
) -> None:
    """F-1 scope guard: only `Bash` tool inputs are scanned.

    Editing SKILL.md / report-template.md legitimately puts a real-looking
    `gh:issue-flow complete (#1270)` string into an `Edit.new_string` or
    `Write.content` — exactly what the #1270 change itself did. Those must
    never terminate the flow.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _assistant_tool_use(
                "Edit",
                {
                    "file_path": "claude/skills/gh-issue-flow/references/report-template.md",
                    "old_string": "example report",
                    "new_string": "example report: gh:issue-flow complete (#1270)",
                },
            ),
            _assistant_tool_use(
                "Write",
                {
                    "file_path": "notes.md",
                    "content": "gh:issue-flow stopped at step 3/6 (gh:pr)",
                },
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"Hook scanned a non-Bash tool input for the terminal marker. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "1/6" in decision["reason"]


# ---------------------------------------------------------------------------
# Issue #1270 — F-2: stale boundary expiry. After N fresh user prompts
# (default 3, `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS`, `0` = disabled)
# the boundary is abandoned and the hook fails open. What counts as
# "fresh", and why the valve is needed at all:
# claude/skills/gh-issue-flow/references/stop-guard.md step 5.
# ---------------------------------------------------------------------------


def test_three_fresh_user_prompts_expire_the_boundary(tmp_path: Path) -> None:
    """F-2: 3 unrelated user prompts after an unfinished flow → allow."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text("actually, forget that — what does mise tasks list?"),
            _assistant_text("It lists the repo's lint/test tasks."),
            _user_text("thanks. now show me the zsh env file"),
            _assistant_text("Here it is."),
            _user_text("what is the p10k prompt config path?"),
            _assistant_text("~/.p10k.zsh"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"Stale gh-issue-flow boundary kept blocking unrelated turns. stdout={result.stdout!r}"
    )


def test_boundary_expiry_reported_in_trace(tmp_path: Path) -> None:
    """F-2: the expiry allow-path names itself under trace mode."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text("unrelated question one"),
            _user_text("unrelated question two"),
            _user_text("unrelated question three"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert "stale boundary expiry" in result.stderr, f"stderr={result.stderr!r}"
    assert "fresh_user_prompts=3" in result.stderr, f"stderr={result.stderr!r}"
    assert "layer=L1.5" in result.stderr


def test_two_fresh_user_prompts_still_block(tmp_path: Path) -> None:
    """F-2 boundary condition: below the limit the guard keeps blocking."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text("wait, is the PR going to close the issue?"),
            _assistant_text("Yes, via Closes #1270."),
            _user_text("ok continue"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"Expected a block below the expiry limit. stdout={result.stdout!r}"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "1/6" in decision["reason"]


def test_skill_expansion_user_messages_are_not_fresh_prompts(tmp_path: Path) -> None:
    """F-2: Claude Code injects an invoked skill's body as a user-role
    message. Those are flow machinery and must not expire the boundary."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text("Base directory for this skill: /home/user/.claude/skills/gh-issue-implement\n"),
            _assistant_skill("gh-commit"),
            _user_slash_command("gh-commit", ""),
            _user_text("<command-name>/gh-commit</command-name>\n<command-args></command-args>\n"),
            _user_text("<local-command-stdout>ok</local-command-stdout>"),
            _user_text("Skill /gh-commit is already loaded above; instructions unchanged. Arguments: "),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Skill-expansion user messages were miscounted as fresh user prompts "
        f"and expired the boundary. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_tool_result_messages_are_not_fresh_prompts(tmp_path: Path) -> None:
    """F-2: tool output rides in `role=user` messages but is not a prompt."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_tool_result("tests: 42 passed"),
            _user_tool_result("commit abc123 created"),
            _user_tool_result("PR https://x/pull/9 opened"),
            _user_tool_result("review posted"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"tool_result messages were miscounted as fresh user prompts. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_system_reminder_only_user_message_is_not_a_fresh_prompt(
    tmp_path: Path,
) -> None:
    """F-2: a user message consisting solely of a `<system-reminder>` span
    is harness chatter, not a human turn."""
    reminder = "<system-reminder>\nThis is a reminder about file state.\nIt spans lines.\n</system-reminder>"
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text(reminder),
            _user_text(reminder),
            _user_text(reminder),
            _user_text(reminder),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"A <system-reminder>-only message was counted as a fresh prompt. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_expiry_disabled_by_env_zero(tmp_path: Path) -> None:
    """F-2: `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS=0` never expires."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            *[_user_text(f"unrelated prompt {i}") for i in range(5)],
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "0"},
    )
    assert result.returncode == 0
    assert result.stdout.strip(), f"Expiry ran even though it was disabled with =0. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


def test_expiry_limit_configurable_via_env(tmp_path: Path) -> None:
    """F-2: a custom non-zero limit is honoured (1 prompt is enough here)."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text("never mind, different topic now"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"stdout={result.stdout!r}"


def test_invalid_expiry_env_falls_back_to_default(tmp_path: Path) -> None:
    """F-2: an unparseable / negative value degrades to the default of 3."""
    two_prompts = [
        _user_text("/gh-issue-flow 1270"),
        _assistant_skill("gh-issue-implement"),
        _user_text("question one"),
        _user_text("question two"),
    ]
    transcript = _write_transcript(tmp_path, two_prompts)
    for bad in ("not-a-number", "-1", ""):
        result = _run_hook(
            _hook_event(transcript),
            env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": bad},
        )
        assert result.returncode == 0
        assert result.stdout.strip(), f"value {bad!r} did not fall back to the default limit"
        assert json.loads(result.stdout)["decision"] == "block"


# ---------------------------------------------------------------------------
# Issue #1270 / PR #1272 review — fresh-prompt counter over-counting.
#
# Measured on a real 2489-entry gh-issue-flow transcript: 102 "fresh
# prompts" of which only 4 were human. 62 were Stop-hook feedback blocks
# (Claude Code re-injects the hook's own `reason` as a `role=user` message)
# and 40 were `<task-notification>` background-subagent completions — so the
# limit of 3 was hit at entry 322 with 1/6 sub-skills done and the guard
# disabled itself mid-flow. `devx:pr-review-all` (Step 2.4 of the guarded
# chain) fans out three background agents, which makes that self-defeat the
# normal case rather than an edge case.
#
# Two independent fixes are pinned below: `isMeta` on the OUTER entry plus
# harness-injection markers (over-count), and counting a mixed
# text + tool_result turn (under-count, Codex BLOCKER).
# ---------------------------------------------------------------------------


def test_ismeta_user_messages_are_not_fresh_prompts(tmp_path: Path) -> None:
    """`isMeta: true` on the outer entry means harness text, never a human."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_meta_text("please continue with the next step"),
            _user_meta_text("keep going, do not stop"),
            _user_meta_text("resume the chain now"),
            _user_meta_text("another injected line"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"isMeta entries were miscounted as fresh user prompts. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


def test_stop_hook_feedback_messages_are_not_fresh_prompts(tmp_path: Path) -> None:
    """The hook's own `reason`, re-injected as user text, must not count.

    This is the self-defeat loop: every block the guard emits came back as
    a "fresh user prompt" and three of them expired the guard's own boundary.
    """
    feedback = (
        "Stop hook feedback: gh-issue-flow incomplete: 1/6 sub-skills invoked since "
        "the flow started, and no terminal Step 3 report has been emitted yet. "
        "Next action: Step 2.2 — Skill(gh-commit)."
    )
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text(feedback),
            _user_text(feedback),
            _user_text(feedback),
            _user_text(feedback),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"Stop-hook feedback was miscounted as fresh user prompts. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


def test_task_notification_messages_are_not_fresh_prompts(tmp_path: Path) -> None:
    """Background-subagent completion notices are harness, not human."""
    notice = "<task-notification>Agent 'codex-review' (id: agent_1) has completed.</task-notification>"
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text(notice),
            _user_text(notice),
            _user_text(notice),
            _user_text(notice),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"<task-notification> was miscounted as fresh user prompts. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


def test_system_notification_messages_are_not_fresh_prompts(tmp_path: Path) -> None:
    """`[SYSTEM NOTIFICATION - NOT USER INPUT]` says so on the tin."""
    notice = "[SYSTEM NOTIFICATION - NOT USER INPUT] Background command exited with code 0."
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text(notice),
            _user_text(notice),
            _user_text(notice),
            _user_text(notice),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"[SYSTEM NOTIFICATION] was miscounted as fresh user prompts. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_mixed_text_and_tool_result_message_counts_as_fresh_prompt(
    tmp_path: Path,
) -> None:
    """A human prompt bundled with tool output still counts (Codex BLOCKER).

    Skipping such messages wholesale meant a genuinely abandoned flow could
    keep blocking forever whenever the user typed while a tool was in flight.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_text_with_tool_result("stop that — what does mise tasks list?"),
            _user_text_with_tool_result("and where is the zsh env file?"),
            _user_text_with_tool_result("last one: the p10k config path?"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        "Human text bundled alongside a tool_result was not counted, so the "
        f"stale boundary kept blocking. stdout={result.stdout!r}"
    )


def test_tool_result_only_message_still_not_a_fresh_prompt(tmp_path: Path) -> None:
    """Regression guard: dropping the wholesale skip must not let bare tool
    output start counting — `include_tool_results=False` yields empty text,
    and the existing emptiness check drops it."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1270"),
            _assistant_skill("gh-issue-implement"),
            _user_tool_result("tests: 42 passed"),
            _user_tool_result("commit abc123 created"),
            _user_tool_result("PR https://x/pull/9 opened"),
            _user_tool_result("review posted"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"tool_result-only messages were counted as fresh prompts. stdout={result.stdout!r}"
    assert json.loads(result.stdout)["decision"] == "block"


# ---------------------------------------------------------------------------
# Issue #1281 (PR #1278 review, agy + codex) — the marker checks were
# unanchored substring tests, so a human merely *quoting* a marker had the
# whole turn dropped from the fresh-prompt count. Under-count ⇒ the stale
# boundary could not expire. Markers are now `(?m)^`-anchored.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("label", "prompt"),
    [
        (
            "stop-hook-feedback",
            "I got confused — what does 'Stop hook feedback:' actually mean in this hook?",
        ),
        (
            "task-notification",
            "Where in the transcript does a <task-notification> block show up?",
        ),
        (
            "base-directory",
            "Explain why 'Base directory for this skill:' is treated as machinery.",
        ),
    ],
)
def test_quoted_marker_mid_sentence_still_counts_as_fresh_prompt(tmp_path: Path, label: str, prompt: str) -> None:
    """A marker quoted mid-sentence is human prose, not a harness injection."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1281"),
            _assistant_skill("gh-issue-implement"),
            _user_text(prompt),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"A human turn quoting the {label} marker mid-sentence was discarded, "
        f"so the stale boundary never expired. stdout={result.stdout!r}"
    )


def test_already_loaded_injection_alone_is_not_a_fresh_prompt(tmp_path: Path) -> None:
    """The real "already loaded" injection must still be recognised (#1281).

    Its literal marker text sits mid-line — Claude Code writes the whole
    message as `Skill <name> is already loaded above; …` — so line anchoring
    the bare literal would have stopped matching it and handed the #1270
    over-count back. Isolated here on purpose: the multi-marker
    `test_skill_expansion_user_messages_are_not_fresh_prompts` fixture also
    carries `Base directory for this skill:`, so it stayed green through
    exactly that regression.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1281"),
            _assistant_skill("gh-issue-implement"),
            _user_text("Skill /gh-issue-flow is already loaded above; instructions unchanged. Arguments: 1281"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "The 'Skill <name> is already loaded above' injection was counted as a "
        f"fresh user prompt and expired the boundary. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_marker_quoted_at_true_line_start_is_still_not_a_fresh_prompt(tmp_path: Path) -> None:
    """Known residual limitation, not a regression (PR #1285 review, agy+codex).

    A human who quotes/pastes a marker verbatim as the FIRST thing on a
    line (e.g. a code block or transcript excerpt, as opposed to a
    mid-sentence mention) is indistinguishable from a genuine harness
    injection under `(?m)^` anchoring, and is still excluded from the
    fresh-prompt count. This is not new: the old unanchored substring
    check already excluded this exact case (any occurrence matched), so
    #1281 narrows the false-positive class without eliminating it. Fixing
    it fully needs structural signal beyond line position (see #1275 P-3
    shared-lib consolidation) — out of scope here. Pinned so a future
    change doesn't silently alter this boundary either direction.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1281"),
            _assistant_skill("gh-issue-implement"),
            _user_text("Stop hook feedback: I'm quoting this exactly to ask you about it."),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "A line-initial quoted marker should still be excluded from the fresh-prompt "
        f"count, matching pre-#1281 behavior. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


# ---------------------------------------------------------------------------
# Issue #1434 — the `SubagentStop` path. The guard used to be registered on
# `Stop` only, so a `gh:issue-flow` chain running inside a subagent (the
# unattended issue-watcher dispatch, #1389) lost the harness layer of the
# three-layer guard entirely.
#
# Registering on `SubagentStop` is necessary but NOT sufficient. The MEASURED
# `SubagentStop` payload carries BOTH transcript keys:
#
#     transcript_path        -> the PARENT session's transcript
#     agent_transcript_path  -> the subagent's OWN transcript
#
# so a naive registration would parse the parent, find no flow boundary, and
# fail open — a silent no-op. The hook therefore prefers
# `agent_transcript_path`, and never falls back to the parent when the chosen
# path is unreadable (a parent's unfinished flow must not block an unrelated
# subagent).
#
# Every fixture below mirrors the measured payload/entry shapes recorded on
# the issue so the tests cannot drift away from the real harness contract.
# ---------------------------------------------------------------------------

SETTINGS_PATH = REPO_ROOT / "claude" / "settings.json"

_GUARD_COMMAND_FRAGMENT = "gh_issue_flow_stop_guard.py"


def _write_named_transcript(tmp_path: Path, name: str, messages: list[dict[str, Any]]) -> Path:
    """Write a JSONL transcript under an explicit file name.

    `_write_transcript` always uses `transcript.jsonl`, but a `SubagentStop`
    fixture needs TWO distinct transcripts (parent + subagent) inside the
    same `tmp_path`.
    """
    p = tmp_path / name
    with p.open("w", encoding="utf-8") as f:
        for m in messages:
            f.write(json.dumps(m) + "\n")
    return p


def _subagent_hook_event(
    agent_transcript: Path | None,
    parent_transcript: Path | None,
    **extras: Any,
) -> str:
    """Build a `SubagentStop` hook stdin payload (measured shape, #1434).

    Keys mirror the payload dumped from a live probe session: `agent_id`,
    `agent_type`, `session_id`, `stop_hook_active`, `transcript_path` (the
    PARENT) and `agent_transcript_path` (the SUBAGENT). Either transcript
    key can be omitted by passing `None`, which is how the fail-open rails
    are exercised.
    """
    payload: dict[str, Any] = {
        "hook_event_name": "SubagentStop",
        "agent_id": "agent-test-1434",
        "agent_type": "general-purpose",
        "session_id": "test-parent-session",
        "stop_hook_active": False,
    }
    if parent_transcript is not None:
        payload["transcript_path"] = str(parent_transcript)
    if agent_transcript is not None:
        payload["agent_transcript_path"] = str(agent_transcript)
    payload.update(extras)
    return json.dumps(payload)


def _mid_flow_messages(issue: str = "1434") -> list[dict[str, Any]]:
    """Boundary + one sub-skill, no Step 3 report — the blockable state."""
    return [
        _user_text(f"/gh-issue-flow {issue}"),
        _assistant_skill("gh-issue-implement", f"{issue} direct origin --no-next-hint"),
    ]


def _unrelated_messages() -> list[dict[str, Any]]:
    """A transcript with no gh-issue-flow boundary anywhere."""
    return [
        _user_text("summarize this directory for me"),
        _assistant_text("here is the summary you asked for."),
    ]


def _write_subagent_pair(
    tmp_path: Path,
    agent_messages: list[dict[str, Any]] | None,
    parent_messages: list[dict[str, Any]] | None,
) -> tuple[Path | None, Path | None]:
    """Write the subagent + parent transcripts, returning both paths."""
    agent = None if agent_messages is None else _write_named_transcript(tmp_path, "agent-1434.jsonl", agent_messages)
    parent = None if parent_messages is None else _write_named_transcript(tmp_path, "parent.jsonl", parent_messages)
    return agent, parent


# --- The core fix: judge the SUBAGENT's transcript, not the parent's -------


def test_subagent_stop_mid_flow_blocks(tmp_path: Path) -> None:
    """Mid-flow SUBAGENT transcript + boundary-free parent → block (#1434).

    This is the regression the whole issue is about: before the fix the hook
    read `transcript_path` (the parent), found no boundary, and allowed the
    subagent to stop mid-chain with no error and no warning.
    """
    agent, parent = _write_subagent_pair(tmp_path, _mid_flow_messages(), _unrelated_messages())
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "The subagent's own mid-flow transcript was ignored (the parent's was "
        f"parsed instead), so the guard was a silent no-op. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-issue-flow incomplete" in decision["reason"]


def test_subagent_stop_does_not_inherit_parent_flow(tmp_path: Path) -> None:
    """Boundary-free SUBAGENT transcript + mid-flow parent → allow (#1434).

    The inverse contamination: a parent session holding a half-finished flow
    must never block an unrelated subagent's turn.
    """
    agent, parent = _write_subagent_pair(tmp_path, _unrelated_messages(), _mid_flow_messages())
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"The parent session's unfinished flow blocked an unrelated subagent. stdout={result.stdout!r}"
    )


def test_subagent_transcript_missing_file_does_not_fall_back_to_parent(tmp_path: Path) -> None:
    """A chosen-but-unreadable subagent transcript fails open (#1434).

    Falling back to `transcript_path` here would judge the subagent by the
    parent's flow state — exactly the cross-contamination the preference
    order exists to prevent.
    """
    _, parent = _write_subagent_pair(tmp_path, None, _mid_flow_messages())
    missing = tmp_path / "subagents" / "agent-does-not-exist.jsonl"
    result = _run_hook(_subagent_hook_event(missing, parent))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"An unreadable agent_transcript_path fell back to the parent transcript. stdout={result.stdout!r}"
    )


def test_subagent_stop_terminal_marker_allows_stop(tmp_path: Path) -> None:
    """A Step 3 report in the SUBAGENT transcript ends the chain."""
    agent, parent = _write_subagent_pair(
        tmp_path,
        [
            _user_text("/gh-issue-flow 1434"),
            *(_assistant_skill(n) for n in _ALL_SIX_SUB_SKILLS),
            _assistant_text("gh:issue-flow complete (#1434)\n  PR URL: https://github.com/example/repo/pull/1435"),
        ],
        _unrelated_messages(),
    )
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_subagent_stop_hook_active_short_circuits(tmp_path: Path) -> None:
    """U-3: the infinite-loop valve is present on `SubagentStop` too.

    Measured: the first `SubagentStop` carries `stop_hook_active=False` and
    the event re-fired after a block carries `True`.
    """
    agent, parent = _write_subagent_pair(tmp_path, _mid_flow_messages(), _unrelated_messages())
    result = _run_hook(_subagent_hook_event(agent, parent, stop_hook_active=True))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_subagent_stop_trace_names_the_transcript_source(tmp_path: Path) -> None:
    """Trace mode must show WHICH transcript the decision came from (#1434).

    Without this field, "the guard is a no-op" and "the guard read the wrong
    session" look identical in a log.
    """
    agent, parent = _write_subagent_pair(tmp_path, _mid_flow_messages(), _unrelated_messages())
    result = _run_hook(
        _subagent_hook_event(agent, parent),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert json.loads(result.stdout)["decision"] == "block"
    assert "[stop-guard]" in result.stderr
    assert "transcript_source=agent_transcript_path" in result.stderr


def test_stop_event_trace_names_transcript_path_source(tmp_path: Path) -> None:
    """A plain `Stop` event carries only `transcript_path` — traced as such."""
    transcript = _write_transcript(tmp_path, _mid_flow_messages())
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_ISSUE_FLOW_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert json.loads(result.stdout)["decision"] == "block"
    assert "transcript_source=transcript_path" in result.stderr


# --- U-2: boundary detection on the subagent-specific entry surfaces -------


def _subagent_base_dir_marker() -> dict[str, Any]:
    """The skill-expansion marker Claude Code injects as a user message."""
    return _user_text(
        "Base directory for this skill: /home/tester/.claude/skills/gh-issue-flow\n"
        "Use this to resolve relative paths in the instructions below."
    )


@pytest.mark.parametrize(
    ("label", "boundary_entry"),
    [
        # Measured: the subagent transcript's FIRST entry is the dispatch
        # prompt as plain user text, exactly this shape.
        ("dispatch-prompt-user-text", _user_text("/gh-issue-flow 1434")),
        ("assistant-skill-tool-use", _assistant_skill("gh-issue-flow", "1434")),
        ("skill-expansion-base-dir", _subagent_base_dir_marker()),
    ],
)
def test_subagent_boundary_surfaces_all_block(tmp_path: Path, label: str, boundary_entry: dict[str, Any]) -> None:
    """Every entry surface that can start a flow inside a subagent (#1434)."""
    agent, parent = _write_subagent_pair(
        tmp_path,
        [boundary_entry, _assistant_text("working on it")],
        _unrelated_messages(),
    )
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"Boundary surface {label!r} was not detected in the subagent transcript. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_real_subagent_entry_shapes_parse_and_block(tmp_path: Path) -> None:
    """The MEASURED subagent JSONL shape parses cleanly (#1434, U-2).

    Real subagent entries carry `isSidechain` / `agentId` siblings next to
    `message`, and the stream also contains `{"type": "attachment"}` entries
    that have no `role` at all. None of that may raise, and none of it may
    hide the boundary sitting in the first entry.
    """
    agent, parent = _write_subagent_pair(
        tmp_path,
        [
            {
                "type": "user",
                "isSidechain": True,
                "agentId": "agent-test-1434",
                "uuid": "11111111-1111-1111-1111-111111111111",
                "message": {"role": "user", "content": "/gh-issue-flow 1434"},
            },
            {"type": "attachment", "attachment": {"type": "file", "path": "/tmp/context.md"}},
            {
                "type": "assistant",
                "isSidechain": True,
                "message": {
                    "role": "assistant",
                    "content": [{"type": "thinking", "thinking": "plan the chain"}],
                },
            },
            {
                "type": "assistant",
                "isSidechain": True,
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "toolu_probe",
                            "name": "Bash",
                            "input": {"command": "git status --porcelain"},
                        }
                    ],
                },
            },
            {
                "type": "user",
                "isSidechain": True,
                "message": {
                    "role": "user",
                    "content": [{"type": "tool_result", "tool_use_id": "toolu_probe", "content": ""}],
                },
            },
            {
                "type": "assistant",
                "isSidechain": True,
                "message": {"role": "assistant", "content": [{"type": "text", "text": "done"}]},
            },
        ],
        _unrelated_messages(),
    )
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        f"The measured subagent transcript shape broke boundary detection. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


# --- Every fail-open rail still holds under a SubagentStop payload ---------


@pytest.mark.parametrize(
    ("label", "stdin_payload"),
    [
        ("empty-stdin", ""),
        ("malformed-json", "this is not json {{{"),
        ("json-not-a-dict", json.dumps([{"hook_event_name": "SubagentStop"}])),
        (
            "both-transcript-keys-missing",
            json.dumps(
                {
                    "hook_event_name": "SubagentStop",
                    "agent_id": "agent-test-1434",
                    "agent_type": "general-purpose",
                    "session_id": "test-parent-session",
                    "stop_hook_active": False,
                }
            ),
        ),
        (
            "empty-string-transcript-keys",
            json.dumps(
                {
                    "hook_event_name": "SubagentStop",
                    "agent_transcript_path": "",
                    "transcript_path": "",
                    "stop_hook_active": False,
                }
            ),
        ),
    ],
)
def test_subagent_stdin_level_fail_open_rails(label: str, stdin_payload: str) -> None:
    """The stdin-level rails are unchanged on the `SubagentStop` path."""
    result = _run_hook(stdin_payload)
    assert result.returncode == 0, label
    assert result.stdout.strip() == "", f"{label} should fail open. stdout={result.stdout!r}"


def test_subagent_no_boundary_in_either_transcript_allows_stop(tmp_path: Path) -> None:
    """An issue-flow-unrelated subagent stop is untouched by the guard."""
    agent, parent = _write_subagent_pair(tmp_path, _unrelated_messages(), _unrelated_messages())
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_subagent_empty_transcript_file_allows_stop(tmp_path: Path) -> None:
    """An existing-but-empty subagent transcript fails open."""
    agent, parent = _write_subagent_pair(tmp_path, [], _mid_flow_messages())
    result = _run_hook(_subagent_hook_event(agent, parent))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_subagent_stale_boundary_expiry_still_applies(tmp_path: Path) -> None:
    """The #1270 stale-boundary valve survives on the `SubagentStop` path."""
    agent, parent = _write_subagent_pair(
        tmp_path,
        [
            *_mid_flow_messages(),
            _user_text("actually, forget that — what is the weather like?"),
        ],
        _unrelated_messages(),
    )
    result = _run_hook(
        _subagent_hook_event(agent, parent),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"The stale boundary did not expire. stdout={result.stdout!r}"


def test_subagent_stale_boundary_expiry_disabled_by_zero(tmp_path: Path) -> None:
    """`GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS=0` disables expiry here too."""
    agent, parent = _write_subagent_pair(
        tmp_path,
        [
            *_mid_flow_messages(),
            _user_text("one unrelated question"),
            _user_text("and another one"),
            _user_text("and a third"),
            _user_text("and a fourth"),
        ],
        _unrelated_messages(),
    )
    result = _run_hook(
        _subagent_hook_event(agent, parent),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "0"},
    )
    assert result.returncode == 0
    assert json.loads(result.stdout)["decision"] == "block"


# --- Registration: the gap this issue is actually about -------------------


def _registered_hook_commands(event: str) -> list[str]:
    """Return the `command` strings registered on one hook event."""
    settings = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    commands: list[str] = []
    for group in settings.get("hooks", {}).get(event, []):
        for hook in group.get("hooks", []):
            command = hook.get("command")
            if isinstance(command, str):
                commands.append(command)
    return commands


@pytest.mark.parametrize("event", ["Stop", "SubagentStop"])
def test_guard_is_registered_on_both_turn_ending_events(event: str) -> None:
    """The tracked SSOT must register the guard on `Stop` AND `SubagentStop`.

    This is the test that would have caught #1434: the guard existed, was
    correct, and simply never ran for a subagent because `SubagentStop` was
    not in `claude/settings.json` at all.
    """
    commands = _registered_hook_commands(event)
    assert any(_GUARD_COMMAND_FRAGMENT in c for c in commands), (
        f"{_GUARD_COMMAND_FRAGMENT} is not registered on the {event} hook event "
        f"in {SETTINGS_PATH}. Registered commands: {commands}"
    )


# ---------------------------------------------------------------------------
# Issue #1434 (blast-radius addendum) — which valves are actually LIVE on the
# `SubagentStop` path.
#
# The #1270 stale-boundary valve counts *fresh user prompts* after the
# boundary. A subagent transcript has no human turns at all: its user-role
# entries are the dispatch prompt (which IS the boundary, and the count
# starts at boundary + 1), tool_results (no text under
# `include_tool_results=False`), and harness injections such as `Stop hook
# feedback:` (excluded by `_HARNESS_INJECTION_RE`). So on this path the
# expiry valve can effectively never fire, which makes `stop_hook_active` the
# ONLY live valve there. Both halves of that statement are pinned below.
# ---------------------------------------------------------------------------


def test_subagent_harness_entries_never_expire_the_boundary(tmp_path: Path) -> None:
    """Nothing a subagent transcript contains can expire the boundary (#1434).

    Every user-role entry a subagent accumulates after the boundary is
    machinery — this hook's own re-injected block reason, background
    `<task-notification>` blocks, skill expansions, and tool output — and all
    of them are excluded from the fresh-prompt count. Run at the tightest
    non-disabled limit (1) the boundary still stands, so the expiry valve is
    inert on the `SubagentStop` path.

    That is acceptable, but it is WHY `stop_hook_active` is load-bearing
    here: it is the only remaining valve bounding the guard to one block per
    stop-chain (measured — the `SubagentStop` re-fired after a block carries
    `stop_hook_active=True`). If `stop_hook_active` ever regressed on this
    path there would be no second line of defence, so
    `test_subagent_stop_hook_active_short_circuits` must never be relaxed.
    """
    agent, parent = _write_subagent_pair(
        tmp_path,
        [
            *_mid_flow_messages(),
            _user_tool_result("tests: 42 passed", tool_use_id="toolu_subagent_1"),
            _user_text("Stop hook feedback:\ngh-issue-flow incomplete: 1/6 sub-skills invoked since the flow started."),
            _user_text("<task-notification>Agent 'reviewer' finished.</task-notification>"),
            _user_text(
                "Base directory for this skill: /home/tester/.claude/skills/gh-commit\nResolve relative paths with it."
            ),
            _user_meta_text("Skill gh-commit is already loaded above; instructions unchanged."),
        ],
        _unrelated_messages(),
    )
    result = _run_hook(
        _subagent_hook_event(agent, parent),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Harness-generated subagent entries were counted as fresh user prompts "
        f"and expired the boundary. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"


def test_subagent_dispatch_prompt_is_boundary_not_a_fresh_prompt(tmp_path: Path) -> None:
    """The dispatch prompt is the boundary, so it is NOT also counted (#1434).

    A subagent's first transcript entry is the dispatch prompt as plain user
    text — a genuine `role=user` entry with no `isMeta` flag and no harness
    marker, i.e. exactly the shape `_count_fresh_user_prompts` counts. It
    does not double-count only because the count window opens at
    `boundary + 1` and this entry IS the boundary. Pinned because the
    alternative (counting it) would expire the boundary on the very first
    stop at `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS=1`, silently disabling
    the guard for every unattended dispatch.
    """
    agent, parent = _write_subagent_pair(tmp_path, _mid_flow_messages(), _unrelated_messages())
    result = _run_hook(
        _subagent_hook_event(agent, parent),
        env={"GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "The dispatch prompt was counted as a fresh user prompt on top of being "
        f"the boundary, expiring it immediately. stdout={result.stdout!r}"
    )
    assert json.loads(result.stdout)["decision"] == "block"
