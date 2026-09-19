"""Tests for claude/hooks/bash_stdin_repl_guard.py (issue #1815).

The hook is a Claude Code `PreToolUse` handler matched on `Bash`. It denies
an interpreter called with no arguments and no stdin redirect: the Bash tool
leaves stdin open, so such a call never sees EOF and waits forever (the
brokerdesk PR #78 incident hung for 64 minutes).

Allow = exit 0 with empty stdout. Deny = exit 0 plus a
`hookSpecificOutput.permissionDecision: "deny"` object on stdout.

The ALLOWED table is the load-bearing half: a false positive is the fastest
way to get a guard switched off, so a new false-positive report goes into
that table and the rule narrows -- it never widens.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / "claude" / "hooks" / "bash_stdin_repl_guard.py"

# The literal command from the incident (brokerdesk PR #78, `/simplify` lane).
INCIDENT_COMMAND = (
    "(.venv/bin/python 2>/dev/null || true; P=.venv/bin/python; "
    "[ -x $P ] || P=python3; $P - <<'EOF'\nimport time\nprint(time.time())\nEOF\n)"
)


def _run_hook(stdin_payload: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(HOOK_PATH)],
        input=stdin_payload,
        capture_output=True,
        text=True,
        timeout=10,
    )


def _bash_event(command: str) -> str:
    return json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command, "description": "test"},
        }
    )


def _assert_allowed(result: subprocess.CompletedProcess[str]) -> None:
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "", f"expected allow, got: {result.stdout}"


def _assert_denied(result: subprocess.CompletedProcess[str]) -> str:
    assert result.returncode == 0, result.stderr
    specific = json.loads(result.stdout)["hookSpecificOutput"]
    assert specific["hookEventName"] == "PreToolUse"
    assert specific["permissionDecision"] == "deny"
    reason = specific["permissionDecisionReason"]
    assert isinstance(reason, str) and reason.strip()
    return reason


def test_denies_incident_command_verbatim_with_remedy() -> None:
    reason = _assert_denied(_run_hook(_bash_event(INCIDENT_COMMAND)))
    assert ".venv/bin/python" in reason
    # The reason must tell the model how to fix its own command.
    assert "<<'EOF'" in reason
    assert "</dev/null" in reason


@pytest.mark.parametrize(
    "command",
    [
        "python3",
        "python",
        "python3.12",
        "/usr/bin/python3",
        "node",
        "ruby",
        "irb",
        "lua",
        "cd x && python",
        "ls; node",
        "false || ruby",
        "{ python3; }",
        "x=$(python3)",
        "echo hi\npython3",
        "python3 2>/dev/null",
        "python3 >out.txt 2>&1",
        # fd-number redirects, glued or spaced (PR #1817 review, agy).
        "python3 2>out.txt",
        "python3 2> out.txt",
        "python3 2>&1 | tee log.txt",
        # a bare call after two heredocs is still found once both bodies close
        "cat <<A; cat <<B\nx\nA\ny\nB\npython3",
        "python3 | cat",
        # bash hands an async job /dev/null, but zsh -- which the Bash tool
        # may run -- keeps the open stdin: measured, it hangs.
        "python3 &",
        "if true; then python3; fi",
        "echo ok # note\npython3",
    ],
)
def test_denies_bare_interpreter(command: str) -> None:
    _assert_denied(_run_hook(_bash_event(command)))


@pytest.mark.parametrize(
    "command",
    [
        "python -c 'print(1)'",
        "python -m pytest",
        "python file.py",
        "python - <<EOF\nprint(1)\nEOF",
        "python3 - <<'EOF'\npython3\nEOF",
        # bodies of several heredocs on one line close in declaration order
        "cat <<A; cat <<B\nx\nA\npython3\nB",
        "echo x | python",
        "echo x |& python3",
        "python < f",
        "python 0<f",
        "python <<< 'print(1)'",
        "python3 </dev/null",
        "python --version",
        "echo python",
        'echo "cd x; python"',
        "git commit -m 'python'",
        "# python",
        "echo ok # python",
        "which python3",
        "bun",
        "deno",
        "pythonista",
        "node_modules/.bin/tsc",
        "ls python3/",
        "",
        "echo 'unbalanced",
    ],
)
def test_allows_non_repl_calls(command: str) -> None:
    _assert_allowed(_run_hook(_bash_event(command)))


@pytest.mark.parametrize(
    "payload",
    [
        "not json",
        "",
        "[]",
        json.dumps({"tool_name": "Read", "tool_input": {"file_path": "python3"}}),
        json.dumps({"tool_name": "Bash", "tool_input": "python3"}),
    ],
)
def test_fails_open_on_malformed_or_foreign_input(payload: str) -> None:
    _assert_allowed(_run_hook(payload))


def test_registered_in_settings_pretooluse_bash() -> None:
    settings = json.loads((REPO_ROOT / "claude" / "settings.json").read_text())
    commands = [
        hook["command"]
        for entry in settings["hooks"]["PreToolUse"]
        if entry.get("matcher") == "Bash"
        for hook in entry["hooks"]
    ]
    assert any(c.endswith("claude/hooks/bash_stdin_repl_guard.py") for c in commands)
