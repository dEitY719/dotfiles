"""Stop-guard hooks must behave the same when invoked through a symlink.

Claude Code runs the hooks by the path in settings.json
(`${HOME}/dotfiles/claude/hooks/<hook>.py`), and `~/dotfiles` itself may be a
symlink to the real checkout. A hook that loads a sibling file (the step
catalog, a shared helper module) has to find it next to its *real* location,
not next to the link. These tests run each hook through a file symlink placed
alone in a temp dir and through a symlinked directory, and require the exact
same decision as a direct run.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS_DIR = REPO_ROOT / "claude" / "hooks"


def _user_text(text: str) -> dict[str, Any]:
    return {"type": "user", "message": {"role": "user", "content": text}}


def _tool_result(text: str) -> dict[str, Any]:
    return {
        "type": "user",
        "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_x", "content": text}]},
    }


def _skill_use(skill: str, args: str) -> dict[str, Any]:
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {"type": "tool_use", "id": f"toolu_{skill}", "name": "Skill", "input": {"skill": skill, "args": args}}
            ],
        },
    }


# One mid-flow transcript per hook — each one makes its hook block.
BLOCKING_TRANSCRIPTS: dict[str, list[dict[str, Any]]] = {
    "gh_issue_flow_stop_guard.py": [
        _user_text("/gh-flow:issue 42"),
        _skill_use("gh-issue-implement", "42 direct origin --no-next-hint"),
    ],
    "devx_autopilot_stop_guard.py": [
        _user_text("/gh-flow:autopilot"),
        _tool_result("[step:gh-flow-autopilot/plan] OK\n"),
    ],
    "skill_completion_guard.py": [
        _user_text("/gh-issue-implement 42"),
        _tool_result("[step:gh-issue-implement/fetch-issue] OK\n"),
        _tool_result("[step:gh-issue-implement/self-assign] OK\n"),
        _tool_result("[step:gh-issue-implement/implement] OK\n"),
        _tool_result("[step:gh-issue-implement/report] OK\n"),
    ],
}


def _event(tmp_path: Path, hook: str) -> str:
    transcript = tmp_path / "transcript.jsonl"
    transcript.write_text("".join(json.dumps(m) + "\n" for m in BLOCKING_TRANSCRIPTS[hook]), encoding="utf-8")
    return json.dumps(
        {
            "hook_event_name": "Stop",
            "session_id": "test-session",
            "stop_hook_active": False,
            "transcript_path": str(transcript),
        }
    )


def _run(path: Path, payload: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(path)],
        input=payload,
        capture_output=True,
        text=True,
        timeout=10,
        cwd=cwd,
    )


@pytest.mark.parametrize("hook", sorted(BLOCKING_TRANSCRIPTS))
def test_hook_via_file_symlink_matches_direct_run(tmp_path: Path, hook: str) -> None:
    payload = _event(tmp_path, hook)
    direct = _run(HOOKS_DIR / hook, payload, tmp_path)
    assert direct.returncode == 0
    assert json.loads(direct.stdout)["decision"] == "block"

    link_dir = tmp_path / "account-hooks"
    link_dir.mkdir()
    link = link_dir / hook
    link.symlink_to(HOOKS_DIR / hook)
    via_link = _run(link, payload, tmp_path)
    assert via_link.returncode == 0, via_link.stderr
    assert via_link.stdout == direct.stdout


@pytest.mark.parametrize("hook", sorted(BLOCKING_TRANSCRIPTS))
def test_hook_via_symlinked_checkout_matches_direct_run(tmp_path: Path, hook: str) -> None:
    payload = _event(tmp_path, hook)
    direct = _run(HOOKS_DIR / hook, payload, tmp_path)

    linked_root = tmp_path / "dotfiles"
    linked_root.symlink_to(REPO_ROOT)
    via_link = _run(linked_root / "claude" / "hooks" / hook, payload, tmp_path)
    assert via_link.returncode == 0, via_link.stderr
    assert via_link.stdout == direct.stdout
