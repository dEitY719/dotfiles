"""Tests for claude/hooks/devx_autopilot_stop_guard.py (issue #1138).

The hook is invoked as a Claude Code Stop event handler. It reads a JSON
event from stdin, optionally parses the conversation transcript at
event['transcript_path'], and either:

  - exits 0 with empty stdout  → allow the model to stop, OR
  - exits 0 with `{"decision":"block","reason":"..."}` on stdout
    → block the stop and re-prompt the model.

Unlike the gh-issue-flow guard (which counts sub-skill invocations),
devx:autopilot's inline mode runs no implement sub-skill, so this guard
tracks the ORDERED STEP MARKERS `[step:devx-autopilot/<id>] OK` that the
SKILL.md emits via printf. Because printf output lands in a Bash
tool_result block, the step-marker scan includes tool_result payloads;
the terminal scan does not (report-template.md text must not false-terminate).

These tests assemble synthetic transcript fixtures (one JSONL line per
message) covering the state space and assert the hook's stdout + exit code.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / "claude" / "hooks" / "devx_autopilot_stop_guard.py"


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

    Used to simulate Read/Bash tool output landing in the transcript — e.g.
    the SKILL.md printf step markers (which really land in Bash tool_result)
    or file content that happens to quote command strings.
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


def _step_markers_result(*step_ids: str) -> dict[str, Any]:
    """A tool_result block carrying the printf step markers for the given ids.

    This mirrors the real transcript shape: the SKILL.md emits
    `printf '[step:devx-autopilot/<id>] OK\\n'`, whose stdout lands in a
    Bash tool_result block.
    """
    body = "\n".join(f"[step:devx-autopilot/{sid}] OK" for sid in step_ids)
    return _user_tool_result(body)


# ---------------------------------------------------------------------------
# Safety rails
# ---------------------------------------------------------------------------


def test_hook_script_exists_and_is_executable() -> None:
    assert HOOK_PATH.is_file(), f"Hook script missing: {HOOK_PATH}"


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
            _user_text("/devx-autopilot"),
            _step_markers_result("plan"),
        ],
    )
    payload = _hook_event(transcript, stop_hook_active=True)
    result = _run_hook(payload)
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_malformed_jsonl_lines_skipped(tmp_path: Path) -> None:
    """Garbage lines in the middle of the transcript don't crash the hook."""
    p = tmp_path / "transcript.jsonl"
    with p.open("w", encoding="utf-8") as f:
        f.write(json.dumps(_user_text("/devx-autopilot")) + "\n")
        f.write("not valid json at all {{{\n")
        f.write(json.dumps(_step_markers_result("plan")) + "\n")
        f.write("\n")  # blank line
    result = _run_hook(_hook_event(p))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


# ---------------------------------------------------------------------------
# Boundary detection — four surfaces + Skill tool_use
# ---------------------------------------------------------------------------


def test_boundary_via_raw_slash_command(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_boundary_via_command_name_wrapper(tmp_path: Path) -> None:
    content = (
        "<command-message>devx-autopilot</command-message>\n"
        "<command-name>/devx-autopilot</command-name>\n"
        "<command-args></command-args>\n"
    )
    transcript = _write_transcript(
        tmp_path,
        [
            {"type": "user", "message": {"role": "user", "content": content}},
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_boundary_via_base_dir_line(tmp_path: Path) -> None:
    content = "Base directory for this skill: /home/user/.claude/skills/devx-autopilot\n"
    transcript = _write_transcript(
        tmp_path,
        [
            {"type": "user", "message": {"role": "user", "content": content}},
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_boundary_via_h1_line(tmp_path: Path) -> None:
    content = "# devx:autopilot — Stage-B 자율 실행 (spec → PR)\n"
    transcript = _write_transcript(
        tmp_path,
        [
            {"type": "user", "message": {"role": "user", "content": content}},
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_boundary_via_skill_tool_use(tmp_path: Path) -> None:
    """Boundary can be a Skill(devx-autopilot) tool_use, not just user text."""
    transcript = _write_transcript(
        tmp_path,
        [
            _assistant_skill("devx-autopilot"),
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_boundary_via_colon_skill_tool_use(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _assistant_skill("devx:autopilot"),
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_mid_sentence_mention_not_a_boundary(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text(
                "I was reading the docs about /devx-autopilot and got confused — "
                "could you summarize how the chain works?"
            ),
            _assistant_text("Sure — here's a summary: ..."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Mid-flow blocking with ordered step markers
# ---------------------------------------------------------------------------


def test_mid_flow_only_plan_and_issue_blocks_naming_mode(tmp_path: Path) -> None:
    """plan + issue markers present (via tool_result) → block naming 'mode'."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan", "issue"),
            # The model writes a fake-looking progress note but no terminal report.
            _assistant_text("plan and issue done, continuing..."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "expected a block decision, got nothing"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    reason = decision["reason"]
    assert "mode" in reason
    assert "2/7" in reason


def test_mid_flow_partial_markers_split_across_results(tmp_path: Path) -> None:
    """Markers split across multiple tool_result blocks still accumulate."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan"),
            _step_markers_result("issue"),
            _step_markers_result("mode"),
            _step_markers_result("implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    # First missing after implement is pr.
    assert "gh:pr" in decision["reason"] or "pr" in decision["reason"]
    assert "4/7" in decision["reason"]


def test_partial_marker_without_ok_does_not_count(tmp_path: Path) -> None:
    """A `[step:devx-autopilot/plan]` without ` OK` must not satisfy the step."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _user_tool_result("[step:devx-autopilot/plan]\n(no OK suffix here)"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    # plan should still be reported missing.
    assert "plan" in decision["reason"]
    assert "0/7" in decision["reason"]


def test_all_steps_present_but_no_terminal_blocks_for_report(tmp_path: Path) -> None:
    """All 7 required step markers present (via tool_result) but no terminal
    report in assistant text → block asking for the report."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan", "issue", "mode", "implement", "pr", "simplify", "pr-reply"),
            # No terminal report yet.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    reason = decision["reason"]
    assert "report" in reason
    assert "all 7" in reason.lower() or "7/7" in reason


# ---------------------------------------------------------------------------
# Terminal detection — allow stop
# ---------------------------------------------------------------------------


def test_terminal_ok_marker_in_assistant_text_allows_stop(tmp_path: Path) -> None:
    """A real `[OK] devx:autopilot` in assistant text ends the flow."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan", "issue", "mode", "implement", "pr", "simplify", "pr-reply"),
            _assistant_text("[OK] devx:autopilot 완료 — my-feature-design.md\n  PR: #42"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_terminal_report_step_marker_in_assistant_text_allows_stop(tmp_path: Path) -> None:
    """`[step:devx-autopilot/report] OK` echoed in assistant text is terminal."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan", "issue", "mode", "implement", "pr", "simplify", "pr-reply"),
            _assistant_text("[step:devx-autopilot/report] OK"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_terminal_fail_marker_in_assistant_text_allows_stop(tmp_path: Path) -> None:
    """A `[FAIL] devx:autopilot` hard-stop report also ends the flow."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan", "issue", "mode"),
            _assistant_text("[FAIL] devx:autopilot 정지 — Step 2 (구현)"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_report_template_text_in_tool_result_does_not_terminate(tmp_path: Path) -> None:
    """L1.5 false-positive guard: report-template.md text (which literally
    contains `[OK] devx:autopilot 완료`) read into a tool_result during a
    real flow must NOT count as a terminal marker → still block.
    """
    template_excerpt = (
        "# Report Templates\n\n"
        "## 성공 ([OK])\n"
        "    [OK] devx:autopilot 완료 — <spec 파일명>\n"
        "    - 이슈:   #<N>  <issue-url>\n"
        "## 실패 ([FAIL])\n"
        "    [FAIL] devx:autopilot 정지 — Step <k>\n"
    )
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan", "issue"),
            # Model reads the report template while mid-flow.
            _user_tool_result(template_excerpt),
            _assistant_text("Now selecting the mode..."),  # no real terminal marker
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), (
        "Hook fail-opened — report-template text in tool_result was treated as "
        f"a terminal marker. stdout={result.stdout!r}"
    )
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "mode" in decision["reason"]


def test_step_marker_in_doc_read_as_tool_result_is_fail_open_safe(tmp_path: Path) -> None:
    """Documented behavior: step markers are counted from tool_result on
    purpose (that is where the SKILL.md printf output lands). So if a doc
    that quotes `[step:devx-autopilot/<id>] OK` is read into a tool_result
    during a real flow, those ids count toward the step set — a fail-OPEN
    direction (it can only let a stop through sooner, never trap the user).

    This test pins that chosen behavior: quoting all seven markers in a doc
    read as tool_result advances the step set to complete, so the hook then
    blocks only for the missing terminal report (not for a missing step).
    """
    doc_quoting_markers = (
        "The autopilot skill emits, in order:\n"
        + "\n".join(
            f"[step:devx-autopilot/{sid}] OK"
            for sid in ("plan", "issue", "mode", "implement", "pr", "simplify", "pr-reply")
        )
        + "\n"
    )
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _user_tool_result(doc_quoting_markers),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    # Fail-open-safe: all step ids seen (from the doc), so the only thing
    # missing is the terminal report — block asks for report, not a step.
    assert decision["decision"] == "block"
    assert "report" in decision["reason"]


# ---------------------------------------------------------------------------
# Trace mode
# ---------------------------------------------------------------------------


def test_trace_off_by_default_no_stderr(tmp_path: Path) -> None:
    """Without DEVX_AUTOPILOT_STOP_GUARD_TRACE=1, stderr stays clean."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert result.stderr == ""


def test_trace_on_emits_block_diagnostics(tmp_path: Path) -> None:
    """With trace enabled, stderr describes the boundary + decision."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/devx-autopilot"),
            _step_markers_result("plan"),
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"DEVX_AUTOPILOT_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "[autopilot-stop-guard]" in result.stderr
    assert "steps_seen=1/7" in result.stderr
    assert "block:" in result.stderr


def test_trace_on_emits_allow_reason_for_no_boundary(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [_user_text("just a chat unrelated to autopilot")],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"DEVX_AUTOPILOT_STOP_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert "[autopilot-stop-guard] allow:" in result.stderr
    assert "no devx-autopilot boundary" in result.stderr


# ---------------------------------------------------------------------------
# Callable two ways
# ---------------------------------------------------------------------------


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
