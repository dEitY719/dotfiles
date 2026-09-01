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
    [
        # hyphen-form siblings
        "/gh-pr-review --ai agy 123",
        "/gh-pr-reply 123",
        "/gh-pr-resolve-conflict 123",
        # colon-form siblings — `:` is also not a word char, so the lookahead
        # must exclude it too (PR #1169 gemini review).
        "/gh:pr:review --ai agy 123",
        "/gh:pr:reply 123",
        "/gh:pr:resolve-conflict 123",
    ],
)
def test_hyphenated_sibling_command_not_matched_as_gh_pr(tmp_path: Path, sibling: str) -> None:
    """Line-start `/gh-pr-review` etc. must NOT be read as a `gh-pr` boundary (issue #1164).

    Both `-` and `:` are non-word chars, so the old `\\b` after `gh-pr` in
    surface (a) let `/gh-pr-review` (and, after the first fix, the colon
    form `/gh:pr:review`) false-match the `gh-pr` catalog entry, wedging the
    Stop hook into a permanent block. Surface (a) now uses `(?![\\w:-])`.
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


@pytest.mark.parametrize("cmd", ["/gh-pr", "/gh-pr 123", "/gh:pr", "/gh:pr 123"])
def test_bare_gh_pr_command_still_matched(tmp_path: Path, cmd: str) -> None:
    """The real `/gh-pr` (hyphen or colon form, bare or with args) must still
    be detected (issue #1164 / PR #1169). Whitespace or EOL after the name
    passes the `(?![\\w:-])` lookahead."""
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


# ---------------------------------------------------------------------------
# Issue #1550 — the `[flow:async-wait]` grace, per required step.
#
# A step whose work was handed to a background/async Agent cannot honestly
# emit its `[step:<skill>/<id>] OK` marker in the same turn, but the turn
# ending is a legitimate wait, not abandonment. The model says so on the
# record with a `[flow:async-wait]` line; the guard excuses THAT step (and
# only that step) for up to `GH_SKILL_GUARD_ASYNC_WAIT_LIMIT` consecutive
# turns. The grace is catalog-generic — no skill is special-cased.
# ---------------------------------------------------------------------------

_ASYNC_WAIT_LIMIT_ENV = "GH_SKILL_GUARD_ASYNC_WAIT_LIMIT"


def _async_wait_marker(step: str = "gh-issue-implement/implement", agent: str = "a1") -> str:
    """The literal marker line, built the way the SKILL.md docs specify it."""
    return f"[flow:async-wait] step={step} agent={agent} reason=background-worker-delegated"


def _async_wait_text(step: str = "gh-issue-implement/implement", agent: str = "a1") -> dict[str, Any]:
    """One assistant-text turn carrying nothing but the marker."""
    return _assistant_text(_async_wait_marker(step, agent))


def _partially_implemented() -> list[dict[str, Any]]:
    """The exact incident state from #1550.

    `fetch-issue` / `self-assign` / `board-transition` genuinely completed
    and were emitted honestly; `implement` and `report` are the delegated
    work that has not happened yet.
    """
    return [
        _user_text("/gh-issue-implement 42"),
        _emit_marker("gh-issue-implement", "fetch-issue"),
        _emit_marker("gh-issue-implement", "self-assign"),
        _emit_marker("gh-issue-implement", "board-transition"),
    ]


def test_async_wait_reprieves_only_its_own_step(tmp_path: Path) -> None:
    """Grace covers the marked step and nothing else — the easy thing to get wrong.

    `implement` carries an async-wait marker, `report` carries neither a
    marker nor an OK. So the hook must still BLOCK, and the reason must name
    `report` while NOT naming `implement`: a step with zero markers gets no
    free ride just because a sibling step was reprieved.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "`report` is genuinely outstanding — must still block"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "report" in decision["reason"]
    assert "implement" not in decision["reason"].split("emit(s) [")[1].split("]")[0], (
        f"`implement` was reprieved and must not appear in the missing list. reason={decision['reason']!r}"
    )


def test_async_wait_covering_every_outstanding_step_allows_stop(tmp_path: Path) -> None:
    """When every still-missing step is reprieved ON THE LATEST TURN, the turn may end.

    Both markers land in the SAME assistant message — the realistic shape of
    a turn that is deferring two steps at once. Splitting them across two
    separate turns (the pre-fix shape of this test) would mean the FIRST
    step's claim was never renewed on the final turn, which the trailing-
    streak fix correctly treats as unclaimed (PR #1594 review).
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _assistant_text(
                f"{_async_wait_marker('gh-issue-implement/implement')}\n{_async_wait_marker('gh-issue-implement/report')}"
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"all outstanding steps are async-wait-reprieved. stdout={result.stdout!r}"


def test_colon_form_step_prefix_accepted(tmp_path: Path) -> None:
    """`step=gh:issue-implement/implement` normalizes to the catalog key."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _assistant_text(
                f"{_async_wait_marker('gh:issue-implement/implement')}\n{_async_wait_marker('gh:issue-implement/report')}"
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"colon form must be accepted. stdout={result.stdout!r}"


def test_async_wait_marker_for_another_skill_does_not_reprieve(tmp_path: Path) -> None:
    """Grace never crosses skills — a `gh-pr/report` marker cannot excuse
    `gh-issue-implement/report`."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement"),
            _async_wait_text("gh-pr/report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    assert "report" in decision["reason"]


def test_three_async_wait_markers_return_the_step_to_the_blocked_list(tmp_path: Path) -> None:
    """Repeating the marker with no `OK` in between is stagnation, not waiting.

    `implement` is reasserted on all 3 trailing turns (streak 3, past the
    default limit 2) and must return to the blocked list. `report` is
    reasserted only on the LAST of those turns (streak 1, within limit) and
    must stay reprieved — each step's grace is judged by its OWN trailing
    streak, independent of the other's.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement", agent="a1"),
            _async_wait_text("gh-issue-implement/implement", agent="a2"),
            _assistant_text(
                _async_wait_marker("gh-issue-implement/implement", agent="a3")
                + "\n"
                + _async_wait_marker("gh-issue-implement/report")
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "3 markers for one step exceeds the default limit"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    missing_list = decision["reason"].split("emit(s) [")[1].split("]")[0]
    assert "implement" in missing_list, f"stagnating step must return to the list. got {missing_list!r}"
    assert "report" not in missing_list, f"`report` is still within grace. got {missing_list!r}"


def test_marker_in_history_but_absent_from_latest_turn_blocks(tmp_path: Path) -> None:
    """A stale marker must not keep excusing a step on a turn that omits it.

    Marker for `implement` → plain assistant text with no marker at all →
    stop. The original flat-total count let that first marker grant grace
    forever; codex and agy both flagged this as BLOCKING (PR #1594) and agy
    specifically noted this exact scenario had no test coverage. The
    trailing streak must be 0 here, so `implement` returns to `missing`.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement"),
            _assistant_text("Checking on the background worker's status."),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "a stale marker not renewed on the latest turn must not grant grace"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    missing_list = decision["reason"].split("emit(s) [")[1].split("]")[0]
    assert "implement" in missing_list, f"the un-renewed step must return to the list. got {missing_list!r}"


def test_two_markers_for_same_step_in_one_turn_only_counts_once(tmp_path: Path) -> None:
    """A turn with the marker repeated for one step still contributes 1 to that
    step's streak, not 2 (agy review, `findall`-per-step regression).

    `report` is satisfied with a real `OK` marker up front so it drops out
    of `missing` entirely — isolating this test to `implement`'s streak.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _emit_marker("gh-issue-implement", "report"),
            _assistant_text(
                f"{_async_wait_marker('gh-issue-implement/implement')}\n{_async_wait_marker('gh-issue-implement/implement')}"
            ),
            _async_wait_text("gh-issue-implement/implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"two markers in one turn plus one more turn is streak 2, still within the default limit. "
        f"stdout={result.stdout!r}"
    )


def test_async_wait_marker_tolerates_spacing_and_quotes(tmp_path: Path) -> None:
    """A minor formatting variation (extra spaces, quoted values) still matches
    (agy review FOLLOW-UP: the regex was too rigid for LLM-reproduced text)."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _assistant_text(
                '[flow:async-wait] step = "gh-issue-implement/implement" '
                'agent="a1" reason="background-worker-delegated"\n'
                '[flow:async-wait] step = "gh-issue-implement/report" '
                'agent="a1" reason="background-worker-delegated"'
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"quoted/spaced variant must still match. stdout={result.stdout!r}"


def test_real_ok_marker_after_async_wait_satisfies_normally(tmp_path: Path) -> None:
    """The async-wait marker is a stop-gap, never a substitute for the real one.

    Once the delegated work lands and the genuine
    `[step:gh-issue-implement/implement] OK` is emitted, the step is
    satisfied through the ordinary path — proven here by repeating the
    marker far past the grace limit, which would otherwise re-block it.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement", agent="a1"),
            _async_wait_text("gh-issue-implement/implement", agent="a2"),
            _async_wait_text("gh-issue-implement/implement", agent="a3"),
            _emit_marker("gh-issue-implement", "implement"),
            _emit_marker("gh-issue-implement", "report"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", (
        f"a real OK marker satisfies the step regardless of the streak. stdout={result.stdout!r}"
    )


def test_async_wait_marker_inside_tool_result_does_not_reprieve(tmp_path: Path) -> None:
    """The marker is assistant-text-only, unlike the step-OK marker.

    This hook DOES read `tool_result` for `[step:.../...] OK` (Bash printf
    output lands there), so the assistant-text-only scoping of the
    async-wait marker is a real, separately-implemented decision rather than
    an inherited default. A `Read` of this hook's source or of
    `stop-guard.md` puts the literal marker into a `tool_result`; counting it
    would hand every such read two free turns.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _user_tool_result(
                "Excerpt from references/stop-guard.md:\n"
                f"{_async_wait_marker('gh-issue-implement/implement')}\n"
                f"{_async_wait_marker('gh-issue-implement/report')}\n"
            ),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), "a tool_result marker must be ignored"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    missing_list = decision["reason"].split("emit(s) [")[1].split("]")[0]
    assert "implement" in missing_list
    assert "report" in missing_list


def test_async_wait_limit_zero_disables_the_grace(tmp_path: Path) -> None:
    """`GH_SKILL_GUARD_ASYNC_WAIT_LIMIT=0` → the first marker already blocks."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement"),
            _async_wait_text("gh-issue-implement/report"),
        ],
    )
    result = _run_hook(_hook_event(transcript), env={_ASYNC_WAIT_LIMIT_ENV: "0"})
    assert result.returncode == 0
    assert result.stdout.strip(), "limit 0 means zero grace"
    decision = json.loads(result.stdout)
    assert decision["decision"] == "block"
    missing_list = decision["reason"].split("emit(s) [")[1].split("]")[0]
    assert "implement" in missing_list
    assert "report" in missing_list


@pytest.mark.parametrize(
    ("marker_count", "should_block"),
    [(1, False), (2, True)],
)
def test_async_wait_limit_one_allows_exactly_one(tmp_path: Path, marker_count: int, should_block: bool) -> None:
    """`GH_SKILL_GUARD_ASYNC_WAIT_LIMIT=1` → 1 trailing occurrence allows, the 2nd blocks.

    `report` is satisfied with a real `OK` marker up front so it drops out
    of `missing` entirely — isolating this parametrization to `implement`'s
    own trailing streak, independent of any other step's grace state.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _emit_marker("gh-issue-implement", "report"),
            *[_async_wait_text("gh-issue-implement/implement", agent=f"a{i}") for i in range(marker_count)],
        ],
    )
    result = _run_hook(_hook_event(transcript), env={_ASYNC_WAIT_LIMIT_ENV: "1"})
    assert result.returncode == 0
    if should_block:
        assert result.stdout.strip(), f"streak {marker_count} exceeds limit 1 and must block"
        assert json.loads(result.stdout)["decision"] == "block"
    else:
        assert result.stdout.strip() == "", f"streak {marker_count} is within limit 1. stdout={result.stdout!r}"


def test_trace_reports_async_wait_reprieve(tmp_path: Path) -> None:
    """The L1.5 trace must name which steps were excused and by how many markers."""
    transcript = _write_transcript(
        tmp_path,
        [
            *_partially_implemented(),
            _async_wait_text("gh-issue-implement/implement"),
        ],
    )
    result = _run_hook(_hook_event(transcript), env={"GH_SKILL_GUARD_TRACE": "1"})
    assert result.returncode == 0
    assert json.loads(result.stdout)["decision"] == "block"
    assert "async_wait_reprieved=implement=1" in result.stderr
    assert "async_wait_limit=2" in result.stderr
    assert "outstanding=['report']" in result.stderr


# ---------------------------------------------------------------------------
# Plugin-namespace command forms (#1677 / PR #1689, codex BLOCKER)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "cmd",
    [
        "/gh-pr:create",
        "/gh-pr:create 1677 origin",
        "/gh-pr:commit",
        "/gh-pr:commit 1677 origin",
    ],
)
def test_plugin_namespace_command_is_a_boundary(tmp_path: Path, cmd: str) -> None:
    """`/gh-pr:create` — hyphen inside the namespace, colon before the skill.

    The `gh-pr-skills` migration (#1677) made this the live invocation form of
    the `gh-pr-create` / `gh-pr-commit` catalog keys. The boundary regex used
    to offer only two whole-string spellings per key — fully hyphenated
    (`gh-pr-create`) or fully colonized (`gh:pr:create`) — so this mixture
    matched nothing, no boundary was detected, and the guard failed open for
    every migrated skill. Separators are now independently `-` or `:`.
    """
    transcript = _write_transcript(
        tmp_path,
        [
            _user_text(cmd),
            _assistant_text("running"),
        ],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip(), f"{cmd!r} must be detected as a boundary"
    assert json.loads(result.stdout)["decision"] == "block"


@pytest.mark.parametrize(
    ("cmd", "skill", "steps"),
    [
        ("/gh-pr:create", "gh-pr-create", ["push-and-create", "labels", "board-sync", "report"]),
        ("/gh-pr:commit", "gh-pr-commit", ["stage-commit", "metrics-board-sync", "report"]),
    ],
)
def test_plugin_namespace_required_steps_satisfy(
    tmp_path: Path, cmd: str, skill: str, steps: list[str]
) -> None:
    """The migrated skills' own markers clear their new catalog keys."""
    transcript = _write_transcript(
        tmp_path,
        [_user_text(cmd), *(_emit_marker(skill, s) for s in steps)],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"stdout={result.stdout!r}"


@pytest.mark.parametrize(
    "sibling",
    ["/gh-pr:review 99", "/gh-pr:approve 99", "/gh-pr:merge 51", "/gh-pr:merge-train"],
)
def test_plugin_namespace_sibling_not_matched_as_gh_pr(tmp_path: Path, sibling: str) -> None:
    """Loosening the separator must not resurrect the #1164 false-match class.

    `/gh-pr:review` is a real skill with no catalog entry; it must not be read
    as the `gh-pr` entry. Surface (a)'s `(?![\\w:-])` lookahead is what keeps
    that true, and it has to keep holding for the colon spelling too.
    """
    transcript = _write_transcript(
        tmp_path,
        [_user_text(sibling), _assistant_text("running")],
    )
    result = _run_hook(_hook_event(transcript))
    assert result.returncode == 0
    assert result.stdout.strip() == "", f"{sibling} must not be a boundary"
