"""Tests for claude/hooks/_hook_common.py stdin helpers (issue #2148).

read_hook_input() must fail open ({}) on anything that is not a JSON object;
tool_input_command() must return "" unless tool_input.command is a string.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "claude" / "hooks"))
import _hook_common  # noqa: E402


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("", {}),
        ("not json", {}),
        ("[1, 2]", {}),
        ("null", {}),
        ('"text"', {}),
        ('{"tool_name": "Bash"}', {"tool_name": "Bash"}),
    ],
)
def test_read_hook_input(monkeypatch: pytest.MonkeyPatch, raw: str, expected: dict[str, object]) -> None:
    monkeypatch.setattr(sys, "stdin", io.StringIO(raw))
    assert _hook_common.read_hook_input() == expected


@pytest.mark.parametrize(
    ("payload", "expected"),
    [
        ({}, ""),
        ({"tool_input": None}, ""),
        ({"tool_input": "ls"}, ""),
        ({"tool_input": {}}, ""),
        ({"tool_input": {"command": 42}}, ""),
        ({"tool_input": {"command": "ls -la"}}, "ls -la"),
    ],
)
def test_tool_input_command(payload: dict[str, object], expected: str) -> None:
    assert _hook_common.tool_input_command(payload) == expected
