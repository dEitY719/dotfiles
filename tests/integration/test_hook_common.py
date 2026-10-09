"""Tests for claude/hooks/_hook_common.py — helpers shared by the Stop guards.

Unit tests for the helpers themselves, plus the import contract each hook
relies on: a hook copied somewhere without its sibling module must fail open
(exit 0, empty stdout = allow the stop), never crash the session.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS_DIR = REPO_ROOT / "claude" / "hooks"
HOOKS = ["gh_issue_flow_stop_guard.py", "devx_autopilot_stop_guard.py", "skill_completion_guard.py"]

sys.path.insert(0, str(HOOKS_DIR))
import _hook_common as common  # noqa: E402


def test_load_transcript_skips_blank_malformed_and_non_dict_lines(tmp_path: Path) -> None:
    p = tmp_path / "t.jsonl"
    p.write_text('{"a": 1}\n\nnot json {{\n[1, 2]\n  {"b": 2}  \n', encoding="utf-8")
    assert common.load_transcript(p) == [{"a": 1}, {"b": 2}]


def test_load_transcript_missing_file_is_empty(tmp_path: Path) -> None:
    assert common.load_transcript(tmp_path / "absent.jsonl") == []


def test_load_transcript_tolerates_invalid_utf8(tmp_path: Path) -> None:
    p = tmp_path / "t.jsonl"
    p.write_bytes(b'{"a": "\xff"}\n')
    assert len(common.load_transcript(p)) == 1


def test_message_payload_prefers_inner_message_dict() -> None:
    assert common.message_payload({"message": {"role": "user"}}) == {"role": "user"}
    entry = {"message": "not a dict", "role": "assistant"}
    assert common.message_payload(entry) is entry


def test_line_anchored_alternation_matches_only_at_line_start() -> None:
    pattern = common.line_anchored_alternation(("<marker>", "[x]"), (r"Base directory for this skill:",))
    assert pattern.search("text\n<marker> here")
    assert pattern.search("[x] at start")
    assert pattern.search("Base directory for this skill: /p")
    assert not pattern.search("quoted <marker> mid-sentence")
    assert not pattern.search("x")


@pytest.mark.parametrize("hook", HOOKS)
def test_hook_without_common_module_fails_open(tmp_path: Path, hook: str) -> None:
    lone = tmp_path / hook
    shutil.copy(HOOKS_DIR / hook, lone)
    transcript = tmp_path / "t.jsonl"
    transcript.write_text(json.dumps({"type": "user", "message": {"role": "user", "content": "/gh-flow:issue 42"}}))
    payload = json.dumps({"hook_event_name": "Stop", "stop_hook_active": False, "transcript_path": str(transcript)})
    result = subprocess.run(
        [sys.executable, "-I", str(lone)], input=payload, capture_output=True, text=True, timeout=10, cwd=tmp_path
    )
    assert result.returncode == 0
    assert result.stdout == ""


@pytest.mark.parametrize("hook", HOOKS)
def test_hook_finds_common_module_from_real_location_in_isolated_mode(tmp_path: Path, hook: str) -> None:
    """`-I` keeps the script dir off sys.path, so only the hook's own realpath insert can find the module."""
    link = tmp_path / hook
    link.symlink_to(HOOKS_DIR / hook)
    result = subprocess.run(
        [
            sys.executable,
            "-I",
            "-c",
            f"import runpy; print(runpy.run_path({str(link)!r}, run_name='probe')['_load_transcript'].__module__)",
        ],
        capture_output=True,
        text=True,
        timeout=10,
        cwd=tmp_path,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "_hook_common"
