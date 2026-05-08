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


def _run_hook(stdin_payload: str) -> subprocess.CompletedProcess[str]:
    """Invoke the hook with the given stdin string."""
    return subprocess.run(
        ["python3", str(HOOK_PATH)],
        input=stdin_payload,
        capture_output=True,
        text=True,
        timeout=10,
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
    """All 5 sub-skills + Step 3 marker present → allow stop."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-schedule"),
            _assistant_skill("gh-pr-resolve-conflict"),
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
    assert "1/5" in reason


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
    assert "2/5" in decision["reason"]


def test_mid_flow_after_all_5_blocks_for_step_3_report(tmp_path: Path) -> None:
    """All 5 sub-skills run but no terminal marker → block, ask for Step 3."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _assistant_skill("gh-commit"),
            _assistant_skill("gh-pr"),
            _assistant_skill("devx-schedule"),
            _assistant_skill("gh-pr-resolve-conflict"),
            # No Step 3 report yet.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "Step 3" in decision["reason"]
    assert "5/5" in decision["reason"]


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
    assert "1/5" in decision["reason"]


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
