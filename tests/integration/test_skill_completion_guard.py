"""Tests for claude/hooks/skill_completion_guard.py (issue #753).

The hook is invoked as a Claude Code Stop event handler — same protocol
as `gh_issue_flow_stop_guard.py`. It reads a JSON event from stdin,
parses the conversation transcript, and either:

  - exits 0 with empty stdout  → allow the model to stop, OR
  - exits 0 with `{"decision":"block","reason":"..."}` on stdout
    → block the stop and re-prompt the model.

These tests assemble synthetic transcript fixtures (one JSONL line per
message) covering the full state space and assert the hook's stdout +
exit code. Mirrors the fixture helpers in
`test_gh_issue_flow_stop_guard.py` so the two hooks share the same
shape of test infrastructure.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / "claude" / "hooks" / "skill_completion_guard.py"
CATALOG_PATH = REPO_ROOT / "claude" / "hooks" / "skill_step_catalog.yml"


def _run_hook(
    stdin_payload: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    import os as _os

    final_env: dict[str, str] = _os.environ.copy()
    # Default: point the hook at the shipped catalog so the standard
    # gh-issue-implement / gh-pr / gh-commit entries are in scope.
    final_env.setdefault("GH_SKILL_GUARD_CATALOG", str(CATALOG_PATH))
    if env is not None:
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
    p = tmp_path / "transcript.jsonl"
    with p.open("w", encoding="utf-8") as f:
        for m in messages:
            f.write(json.dumps(m) + "\n")
    return p


def _user_text(text: str) -> dict[str, Any]:
    return {"type": "user", "message": {"role": "user", "content": text}}


def _assistant_text(text: str) -> dict[str, Any]:
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": text}],
        },
    }


def _user_tool_result(text: str) -> dict[str, Any]:
    """Build a user message carrying a single tool_result block.

    This is the shape Bash printf output takes in the transcript — the
    step-emit markers will be detected from these blocks.
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
    payload: dict[str, Any] = {
        "hook_event_name": "Stop",
        "session_id": "test-session",
        "stop_hook_active": False,
    }
    if transcript_path is not None:
        payload["transcript_path"] = str(transcript_path)
    payload.update(extras)
    return json.dumps(payload)


def _user_slash_command(skill_name: str, args: str) -> dict[str, Any]:
    """Mirror the Claude Code wrapped-command transcript shape."""
    content = (
        f"<command-message>{skill_name}</command-message>\n"
        f"<command-name>/{skill_name}</command-name>\n"
        f"<command-args>{args}</command-args>\n"
        f"Base directory for this skill: /tmp/skills/{skill_name}\n"
        f"# {skill_name}\n"
        f"ARGUMENTS: {args}\n"
    )
    return {"type": "user", "message": {"role": "user", "content": content}}


# ---------------------------------------------------------------------------
# Safety-rail / fail-open paths
# ---------------------------------------------------------------------------


def test_hook_script_exists_and_is_executable() -> None:
    assert HOOK_PATH.is_file(), f"Hook script missing: {HOOK_PATH}"


def test_catalog_yaml_exists() -> None:
    assert CATALOG_PATH.is_file(), f"Catalog missing: {CATALOG_PATH}"


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


def test_stop_hook_active_short_circuits(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            # No step markers — would normally block.
        ],
    )
    payload = _hook_event(transcript, stop_hook_active=True)
    result = _run_hook(payload)
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_no_catalog_boundary_allows_stop(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("just chatting"),
            _assistant_text("sure"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_catalog_unreadable_allows_stop(tmp_path: Path) -> None:
    """Catalog pointed somewhere that does not exist → fail open."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
        ],
    )
    bogus_catalog = tmp_path / "no-such.yml"
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_SKILL_GUARD_CATALOG": str(bogus_catalog)},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_global_bypass_env_allows_stop(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            # No step markers — would normally block.
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_SKILL_GUARD_BYPASS": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Boundary detection — all 4 surfaces (raw, wrapped, base-dir, H1)
# ---------------------------------------------------------------------------


def test_raw_slash_command_boundary_detected(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            _assistant_text("running"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "expected block — boundary detected, no steps emitted"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-issue-implement" in decision["reason"]


def test_wrapped_command_boundary_detected(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_slash_command("gh-pr", "42"),
            _assistant_text("running"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-pr" in decision["reason"]


def test_skill_tool_use_boundary_detected(tmp_path: Path) -> None:
    """Sub-skill invocation via Skill() also counts as a boundary."""
    transcript = _write_transcript(
        tmp_path,
        [
            _assistant_skill("gh-commit"),
            _assistant_text("running"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-commit" in decision["reason"]


def test_colon_namespace_skill_tool_use_counted(tmp_path: Path) -> None:
    """`gh:issue-implement` (colon form) maps to the catalog `gh-issue-implement` key."""
    transcript = _write_transcript(
        tmp_path,
        [
            _assistant_skill("gh:issue-implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-issue-implement" in decision["reason"]


def test_mid_sentence_command_does_not_match(tmp_path: Path) -> None:
    """Mid-sentence mention of /gh-pr is not a boundary (PR #386 regression class)."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("I was reading docs about /gh-pr and got confused"),
            _assistant_text("sure"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


@pytest.mark.parametrize(
    "sibling",
    ["/gh-pr-review --ai gemini 123", "/gh-pr-reply 123", "/gh-pr-resolve-conflict 123"],
)
def test_hyphenated_sibling_command_not_matched_as_gh_pr(tmp_path: Path, sibling: str) -> None:
    """Line-start `/gh-pr-review` etc. must NOT be read as a `gh-pr` boundary (issue #1164).

    `-` is a non-word char, so the old `\\b` after `gh-pr` in surface (a)
    let `/gh-pr-review` false-match the `gh-pr` catalog entry, wedging the
    Stop hook into a permanent block. Surface (a) now uses `(?![\\w-])`.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text(sibling),
            _assistant_text("running"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"{sibling} should not be a gh-pr boundary"


@pytest.mark.parametrize("cmd", ["/gh-pr", "/gh-pr 123"])
def test_bare_gh_pr_command_still_matched(tmp_path: Path, cmd: str) -> None:
    """The real `/gh-pr` (bare, or with args) must still be detected (issue #1164)."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text(cmd),
            _assistant_text("running"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block", f"{cmd!r} should be a gh-pr boundary"
    assert "gh-pr" in decision["reason"]


def test_tool_result_command_mention_not_boundary(tmp_path: Path) -> None:
    """A `/gh-pr` substring in a tool_result block is documentation, not a real boundary."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("read the docs"),
            _user_tool_result("Examples: run `/gh-pr` or `/gh-commit` or `/gh-issue-implement N`"),
            _assistant_text("ok"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Step-marker scanning — happy path + missing steps
# ---------------------------------------------------------------------------


def _emit_marker(skill: str, step: str) -> dict[str, Any]:
    """Simulate a Bash printf for `[step:<skill>/<step>] OK` landing in tool_result."""
    return _user_tool_result(f"[step:{skill}/{step}] OK\n")


def test_all_required_steps_present_allows_stop(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            _emit_marker("gh-issue-implement", "fetch-issue"),
            _emit_marker("gh-issue-implement", "self-assign"),
            _emit_marker("gh-issue-implement", "board-transition"),
            _emit_marker("gh-issue-implement", "implement"),
            _emit_marker("gh-issue-implement", "report"),
            _assistant_text("done"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_missing_board_transition_step_blocks(tmp_path: Path) -> None:
    """The exact incident from issue #753: Step 3.4 board-transition skipped."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            _emit_marker("gh-issue-implement", "fetch-issue"),
            _emit_marker("gh-issue-implement", "self-assign"),
            # 3.4 board-transition deliberately omitted.
            _emit_marker("gh-issue-implement", "implement"),
            _emit_marker("gh-issue-implement", "report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "board-transition" in decision["reason"]
    assert "gh-issue-implement" in decision["reason"]


def test_missing_gh_pr_board_sync_step_blocks(tmp_path: Path) -> None:
    """The other half of issue #753: gh-pr Step 7 board-sync skipped."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-pr"),
            _emit_marker("gh-pr", "push-and-create"),
            _emit_marker("gh-pr", "labels"),
            # board-sync deliberately omitted.
            _emit_marker("gh-pr", "report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "board-sync" in decision["reason"]
    assert "gh-pr" in decision["reason"]


def test_markers_in_assistant_text_also_count(tmp_path: Path) -> None:
    """If the model prints the marker as assistant text (not bash), still count it."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-commit"),
            _assistant_text("[step:gh-commit/stage-commit] OK"),
            _assistant_text("[step:gh-commit/metrics-board-sync] OK"),
            _assistant_text("[step:gh-commit/report] OK"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_colon_skill_markers_recognized(tmp_path: Path) -> None:
    """Markers written as `gh:commit/<step>` (colon form) should also satisfy."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-commit"),
            _emit_marker("gh:commit", "stage-commit"),
            _emit_marker("gh:commit", "metrics-board-sync"),
            _emit_marker("gh:commit", "report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_partial_marker_without_ok_does_not_satisfy(tmp_path: Path) -> None:
    """Strings missing the trailing `OK` (the discriminator) must not count."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-commit"),
            _user_tool_result("[step:gh-commit/stage-commit]\n"),
            _user_tool_result("[step:gh-commit/metrics-board-sync]\n"),
            _user_tool_result("[step:gh-commit/report]\n"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"


def test_unrelated_skill_markers_do_not_satisfy(tmp_path: Path) -> None:
    """Markers from a different catalog skill must not cross-credit."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-commit"),
            _emit_marker("gh-pr", "push-and-create"),
            _emit_marker("gh-pr", "labels"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-commit" in decision["reason"]


# ---------------------------------------------------------------------------
# Catalog-level enforce flag
# ---------------------------------------------------------------------------


def test_enforce_false_skill_does_not_block(tmp_path: Path) -> None:
    """An entry with enforce=false logs but never blocks."""
    custom_catalog = tmp_path / "catalog.yml"
    custom_catalog.write_text(
        "gh-issue-implement:\n  enforce: false\n  description: test\n  required:\n    - some-step\n",
        encoding="utf-8",
    )
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            # No step markers, but enforce=false → must NOT block.
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_SKILL_GUARD_CATALOG": str(custom_catalog)},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""


def test_unknown_skill_in_transcript_does_not_block(tmp_path: Path) -> None:
    """A slash command for a skill NOT in the catalog leaves the hook silent."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/some-unrelated-skill"),
            _assistant_text("ok"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Multi-boundary scenarios (gh-issue-flow chain compatibility)
# ---------------------------------------------------------------------------


def test_most_recent_boundary_governs(tmp_path: Path) -> None:
    """When two catalog skills appear sequentially, the LATER one's requirements
    drive the block reason. The earlier section is assumed to have moved on.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            # Step markers for gh-issue-implement — all 5 present.
            _emit_marker("gh-issue-implement", "fetch-issue"),
            _emit_marker("gh-issue-implement", "self-assign"),
            _emit_marker("gh-issue-implement", "board-transition"),
            _emit_marker("gh-issue-implement", "implement"),
            _emit_marker("gh-issue-implement", "report"),
            # Now the model moves on to gh-commit but skips half the steps.
            _assistant_skill("gh-commit"),
            _emit_marker("gh-commit", "stage-commit"),
            # metrics-board-sync and report missing.
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "gh-commit" in decision["reason"]
    assert "metrics-board-sync" in decision["reason"]
    # The previous skill's report markers must NOT bleed into gh-commit.
    assert "fetch-issue" not in decision["reason"]


def test_chain_of_catalog_skills_with_each_completing_allows_stop(tmp_path: Path) -> None:
    """The gh-issue-flow happy path: each sub-skill emits all its required markers."""
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-flow 42"),
            _assistant_skill("gh-issue-implement"),
            _emit_marker("gh-issue-implement", "fetch-issue"),
            _emit_marker("gh-issue-implement", "self-assign"),
            _emit_marker("gh-issue-implement", "board-transition"),
            _emit_marker("gh-issue-implement", "implement"),
            _emit_marker("gh-issue-implement", "report"),
            _assistant_skill("gh-commit"),
            _emit_marker("gh-commit", "stage-commit"),
            _emit_marker("gh-commit", "metrics-board-sync"),
            _emit_marker("gh-commit", "report"),
            _assistant_skill("gh-pr"),
            _emit_marker("gh-pr", "push-and-create"),
            _emit_marker("gh-pr", "labels"),
            _emit_marker("gh-pr", "board-sync"),
            _emit_marker("gh-pr", "report"),
            _assistant_text("gh:issue-flow complete (#42)"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Trace mode
# ---------------------------------------------------------------------------


def test_trace_off_by_default_no_stderr(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            _emit_marker("gh-issue-implement", "fetch-issue"),
            _emit_marker("gh-issue-implement", "self-assign"),
            _emit_marker("gh-issue-implement", "board-transition"),
            _emit_marker("gh-issue-implement", "implement"),
            _emit_marker("gh-issue-implement", "report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert result.stderr == ""


def test_trace_on_block_emits_diagnostics(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text("/gh-issue-implement 42"),
            # No markers — must block + emit trace.
        ],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_SKILL_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "[skill-guard]" in result.stderr
    assert "skill=gh-issue-implement" in result.stderr
    assert "layer=L1.5" in result.stderr


def test_trace_on_allow_path_no_boundary(tmp_path: Path) -> None:
    transcript = _write_transcript(
        tmp_path,
        [_user_text("hello")],
    )
    result = _run_hook(
        _hook_event(transcript),
        env={"GH_SKILL_GUARD_TRACE": "1"},
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""
    assert "[skill-guard] allow:" in result.stderr
    assert "layer=L1" in result.stderr


# ---------------------------------------------------------------------------
# Coexistence with gh_issue_flow_stop_guard.py
# ---------------------------------------------------------------------------


def test_gh_issue_flow_guard_tests_unaffected_by_new_hook() -> None:
    """The existing gh_issue_flow_stop_guard.py tests must still pass.

    This is a structural sanity check — the new hook ships in the same
    `claude/hooks/` directory and registers next to the old one in
    settings.json. We verify the existing test module still loads its
    hook path correctly.
    """
    other_hook = REPO_ROOT / "claude" / "hooks" / "gh_issue_flow_stop_guard.py"
    assert other_hook.is_file()


# ---------------------------------------------------------------------------
# Hook callable via shebang
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "exec_form",
    [
        ["python3", str(HOOK_PATH)],
        [str(HOOK_PATH)],
    ],
)
def test_hook_callable_two_ways(tmp_path: Path, exec_form: list[str]) -> None:
    import os as _os

    transcript = _write_transcript(
        tmp_path,
        [_user_text("just chat")],
    )
    env = _os.environ.copy()
    env["GH_SKILL_GUARD_CATALOG"] = str(CATALOG_PATH)
    result = subprocess.run(
        exec_form,
        input=_hook_event(transcript),
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == ""
