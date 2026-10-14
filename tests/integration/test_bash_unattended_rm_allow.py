"""Tests for claude/hooks/bash_unattended_rm_allow.py (issue #2119).

Allow = exit 0 + `permissionDecision: "allow"` on stdout. Anything else is
exit 0 with empty stdout (no opinion).
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

HOOK_PATH = Path(__file__).resolve().parents[2] / "claude" / "hooks" / "bash_unattended_rm_allow.py"

# Shape of the incident: nested sh -c plus a mktemp'd clone dir removed at the end.
INCIDENT = (
    "C=$(mktemp -d /tmp/claude-1000/pr-verify-XXXXXX); git clone -q . $C; "
    "for d in $C $C/.before; do cd $d; sh -c 'x'; done; cd /; rm -rf \"$C\""
)

ALLOWED = [
    INCIDENT,
    "rm -rf /tmp/claude-1000/scratch/a.txt",
    "sh -c 'rm -f /tmp/claude-1000/x/y'",
    "D=/tmp/claude-1000/w; rm -rf ${D}/sub",
    'for sh in bash zsh; do $sh -c "echo hi"; done',  # opaque -c, no rm word
    'env -i PATH="$PATH" zsh -f -c "echo hi"',
]

NO_OPINION = [
    "rm -rf /",
    "rm -rf ~/",
    "rm -rf $HOME/x",
    "rm -rf /tmp/claude-1000/../etc",
    "rm -rf /tmp/other/x",
    'rm -rf "$C"',  # C never assigned from a safe path
    "C=/home/u/x; rm -rf $C",
    "rm /tmp/claude-1000/ok; rm /etc/passwd",
    "ls /tmp/claude-1000",  # no rm at all
    "rm -rf",  # no target
]


def _run(command: str, mode: str = "bypassPermissions", env: dict | None = None) -> str:
    event = {"tool_name": "Bash", "permission_mode": mode, "tool_input": {"command": command}}
    return subprocess.run(
        ["python3", str(HOOK_PATH)],
        input=json.dumps(event),
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    ).stdout


@pytest.mark.parametrize("command", ALLOWED)
def test_allows_scratch_rm(command: str) -> None:
    out = json.loads(_run(command))
    assert out["hookSpecificOutput"]["permissionDecision"] == "allow"


@pytest.mark.parametrize("command", NO_OPINION)
def test_no_opinion_otherwise(command: str) -> None:
    assert _run(command) == ""


@pytest.mark.parametrize("mode", ["default", "acceptEdits", "plan", ""])
def test_only_in_bypass_mode(mode: str) -> None:
    assert _run(ALLOWED[1], mode=mode) == ""


def test_bypass_env_and_bad_input(monkeypatch: pytest.MonkeyPatch) -> None:
    import os

    env = {**os.environ, "BASH_UNATTENDED_RM_ALLOW_BYPASS": "1"}
    assert _run(ALLOWED[1], env=env) == ""
    r = subprocess.run(["python3", str(HOOK_PATH)], input="not json", capture_output=True, text=True)
    assert (r.returncode, r.stdout) == (0, "")
