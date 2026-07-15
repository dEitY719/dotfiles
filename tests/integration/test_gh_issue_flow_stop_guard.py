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


def _user_tool_result(text: str) -> dict[str, Any]:
    """Build a user message carrying a single tool_result block.

    Used to simulate Read/Bash tool output landing in the transcript — i.e.
    file content that happens to mention "/gh-issue-flow" but is NOT a
    user-typed command.
    """
    return {
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": "toolu_test",
                    "content": text,
                }
            ],
        },
    }


def _assistant_skill(skill: str, args: str = "") -> dict[str, Any]:
    """Build an assistant tool_use message invoking Skill(<skill>)."""
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {
                    "type": "tool_use",
                    "id": f"toolu_{skill}",
                    "name": "Skill",
                    "input": {"skill": skill, "args": args},
                }
            ],
        },
    }


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


def test_pr_review_all_next_step_after_gh_pr(tmp_path: Path) -> None:
    """After gh-pr (3 seen), the next-step hint routes to Step 2.4 —
    Skill(devx:pr-review-all) — which itself runs the gemini ∥ codex ∥
    /simplify quality gate (with commit+push) and schedules the deferred
    pr-reply. gh-issue-flow no longer dispatches the gate inline, so the
    reminder must NOT reference the old inline 2.3.1/2.3.2/2.3.3 gate or
    devx:schedule."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            # No Step 3 report yet.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    reason = decision["reason"]
    assert "Step 2.4" in reason
    assert "devx:pr-review-all" in reason
    assert "3/6" in reason
    # New next-step content: the delegated skill runs the quality gate.
    assert "simplify" in reason
    assert "pr-review" in reason
    # Old inline-gate / devx:schedule content must be gone.
    assert "devx-schedule" not in reason
    assert "devx:schedule" not in reason
    assert "2.3.1" not in reason
    assert "2.3.2" not in reason
    assert "2.3.3" not in reason


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
    assert "devx:pr-review-all" in reason
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
    # Still only 1/5 — the unrelated skills must not bump the counter.
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
    # The boundary scan summary should report 1/5 sub-skills seen.
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
