"""Tests for claude/hooks/bash_wait_loop_guard.py (issue #1521).

The hook is invoked as a Claude Code `PreToolUse` event handler matched on
the `Bash` tool. It reads a JSON event from stdin and either:

  - exits 0 with empty stdout  -> allow (normal permission flow), OR
  - exits 0 with a PreToolUse deny object on stdout:
      {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                              "permissionDecision": "deny",
                              "permissionDecisionReason": "..."}}

Two narrow shapes are denied, and both are gated on **loop context**, not
on how often a token happens to appear in the command string:

  1. a literal `pgrep -f` sitting in an `until`/`while` test where a
     successful match keeps the loop spinning (`until ! pgrep ...` /
     `while pgrep ...`), with a `sleep` in that same loop's body;
  2. an `until`/`while` loop whose test watches a `tasks/*.output` path
     and whose body sleeps.

A one-shot `pgrep -f <literal>` is always allowed -- nothing re-checks
it, so it cannot hang -- and `$$` is not an allow signal anywhere.

The false-positive guard is the load-bearing half of this suite: the
harness's own Monitor documentation recommends the generic
`until <cond>; do sleep <n>; done` shape, so `test_allows_harness_recommended_dev_log_poll`
pins that exact command as ALLOWED and must never be relaxed.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / "claude" / "hooks" / "bash_wait_loop_guard.py"

# The literal command from issue #1521 that spun for 49 minutes.
ISSUE_1521_COMMAND = (
    "until [ -s /home/u/.claude/tasks/a7ab696cc6e841cc7.output ] "
    "&& ! pgrep -f a7ab696cc6e841cc7 >/dev/null 2>&1; do sleep 5; done; echo done"
)

# The harness-recommended one-shot wait from the Monitor tool docs.
HARNESS_RECOMMENDED_POLL = 'until grep -q "Ready in" dev.log; do sleep 0.5; done'


def _run_hook(
    stdin_payload: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Invoke the hook with the given stdin string and optional env overrides."""
    final_env: dict[str, str] | None = None
    if env is not None:
        final_env = os.environ.copy()
        final_env.update(env)
    return subprocess.run(
        ["python3", str(HOOK_PATH)],
        input=stdin_payload,
        capture_output=True,
        text=True,
        timeout=10,
        env=final_env,
    )


def _bash_event(command: str, **extra: Any) -> str:
    """Build a PreToolUse/Bash event payload as the harness sends it."""
    event: dict[str, Any] = {
        "session_id": "test-session",
        "transcript_path": "/tmp/does-not-exist.jsonl",
        "cwd": "/home/u/project",
        "permission_mode": "default",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": command, "description": "test"},
        "tool_use_id": "toolu_test",
    }
    event.update(extra)
    return json.dumps(event)


def _assert_allowed(result: subprocess.CompletedProcess[str]) -> None:
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "", f"expected allow, got: {result.stdout}"


def _assert_denied(result: subprocess.CompletedProcess[str]) -> str:
    """Assert a well-formed PreToolUse deny and return the reason string."""
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip(), "expected a deny object on stdout, got nothing"
    payload = json.loads(result.stdout)
    specific = payload["hookSpecificOutput"]
    assert specific["hookEventName"] == "PreToolUse"
    assert specific["permissionDecision"] == "deny"
    reason = specific["permissionDecisionReason"]
    assert isinstance(reason, str) and reason.strip()
    return reason


# --------------------------------------------------------------------------
# Rule 1: self-matching `pgrep -f`
# --------------------------------------------------------------------------


def test_blocks_issue_1521_command_verbatim() -> None:
    """The exact 49-minute loop from #1521 must be denied."""
    reason = _assert_denied(_run_hook(_bash_event(ISSUE_1521_COMMAND)))
    assert "a7ab696cc6e841cc7" in reason


def test_blocks_self_matching_pgrep_f() -> None:
    """`until ! pgrep -f TOKEN` + sleep: the match is guaranteed, so it never exits."""
    cmd = "until ! pgrep -f UNIQUE_TOKEN_XYZ >/dev/null; do sleep 1; echo UNIQUE_TOKEN_XYZ running; done"
    reason = _assert_denied(_run_hook(_bash_event(cmd)))
    assert "UNIQUE_TOKEN_XYZ" in reason
    # The remedy must be spelled out, and must lead with the character
    # class -- `grep -vx "$$"` alone leaves the outer `zsh -c ... eval`
    # wrapper matching, so it does not actually break the loop.
    assert "[U]NIQUE_TOKEN_XYZ" in reason


@pytest.mark.parametrize("flags", ["-f", "-af", "-fa", "--full"])
def test_blocks_every_full_match_flag_spelling(flags: str) -> None:
    """`f` anywhere in the flag bundle, and `--full`, all mean full-cmdline match."""
    cmd = f"cat tok123abc.log; until ! pgrep {flags} tok123abc; do sleep 1; done"
    _assert_denied(_run_hook(_bash_event(cmd)))


def test_blocks_self_matching_pgrep_inside_until_loop() -> None:
    """The negated-pgrep exit condition is the shape that never terminates."""
    cmd = "until ! pgrep -f agentid9999 >/dev/null; do sleep 2; echo agentid9999; done"
    _assert_denied(_run_hook(_bash_event(cmd)))


def test_blocks_single_occurrence_pattern_in_until_loop() -> None:
    """A pattern occurring ONCE is still fatal inside a loop (PR #1547 review).

    The first cut of this hook allowed anything whose literal pattern
    appeared fewer than two times in the command text. That was the
    dangerous false negative: the Claude Code Bash tool runs commands as
    `zsh -c <snapshot> && eval '<command>'`, so the wrapper's own
    cmdline *is* this command -- which contains `gunicorn` as pgrep's
    argument. `! pgrep` is therefore permanently false and the loop
    spins forever, one occurrence or ten.
    """
    reason = _assert_denied(_run_hook(_bash_event("until ! pgrep -f gunicorn; do sleep 1; done")))
    assert "[g]unicorn" in reason


def test_blocks_while_pgrep_wait_for_exit_loop() -> None:
    """`while pgrep ...` (un-negated) is the other never-false spelling."""
    _assert_denied(_run_hook(_bash_event("while pgrep -f mybuildjob; do sleep 5; done")))


def test_blocks_pgrep_loop_despite_unrelated_dollar_dollar() -> None:
    """An unrelated `$$` must not disarm the check (PR #1547 codex BLOCKER).

    The first cut skipped the entire pgrep rule whenever `$$` occurred
    anywhere, so a stray `echo $$` bought a free pass for a loop that
    still hangs. `$$` is no longer an allow signal at all.
    """
    cmd = "echo $$; until ! pgrep -f token; do sleep 1; done"
    _assert_denied(_run_hook(_bash_event(cmd)))


def test_blocks_pgrep_loop_using_the_dollar_dollar_exclusion_idiom() -> None:
    """`| grep -vx "$$"` inside the loop does NOT make it safe, so it is denied.

    This hook's own docstring measures two self-matches under the Bash
    tool -- the inner shell (`$$`) and the outer `zsh -c ... eval`
    wrapper (#1521's pids 179954 + 1226029). Excluding `$$` deletes one
    of the two, so the loop still never exits. Treating the idiom as an
    opt-out contradicted that measurement; the character class is the
    only remedy the hook endorses, and the reason text says so.
    """
    cmd = 'until ! pgrep -f a7ab696cc6e841cc7 | grep -vx "$$"; do sleep 5; done'
    reason = _assert_denied(_run_hook(_bash_event(cmd)))
    assert "[a]7ab696cc6e841cc7" in reason


def test_allows_pgrep_f_self_exclusion_idiom() -> None:
    """One-shot `pgrep -f "$PAT" | grep -vx "$$"`: no loop, and no literal pattern.

    Allowed for two independent reasons -- nothing re-checks it, and
    `"$PAT"` has no statically knowable value -- NOT because of the
    `$$`, which this hook no longer reads as a safety signal.
    """
    cmd = 'PAT=a7ab696cc6e841cc7; pgrep -f "$PAT" | grep -vx "$$" && echo "$PAT alive"'
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_pgrep_f_with_literal_and_self_pid_exclusion() -> None:
    """A one-shot literal pgrep is allowed however often the token recurs.

    Without an enclosing loop there is nothing to re-evaluate the
    condition, so a spurious self-match costs one wrong answer, never a
    hang. The `grep -vx "$$"` here is incidental.
    """
    cmd = 'pgrep -f a7ab696cc6e841cc7 | grep -vx "$$" > a7ab696cc6e841cc7.pids'
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_short_pattern_that_is_a_substring_of_pgrep() -> None:
    """`pgrep -f ep` must not self-deny (PR #1547 agy BLOCKER).

    The old occurrence-count gate used a raw substring count, so `ep`
    scored two hits -- one inside the literal word `pgrep`, one as the
    operand -- and a plain one-shot lookup was denied. Pinned here so
    the count-based logic can never come back.
    """
    _assert_allowed(_run_hook(_bash_event("pgrep -f ep >/dev/null 2>&1")))


@pytest.mark.parametrize("cmd", ["pgrep -f grep", "pgrep -f p", "pgrep -f full", "pgrep -f f"])
def test_allows_one_shot_pgrep_with_pgrep_substring_patterns(cmd: str) -> None:
    """Same class of false positive for any pattern inside `pgrep`/`-f`/`--full`."""
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_pgrep_loop_that_exits_on_first_match() -> None:
    """`until pgrep ...` terminates immediately -- wrong, but not a hang.

    A guaranteed self-match makes an un-negated `until` test true on
    iteration one. This hook's mandate is loops that can never end, so
    the shape stays out of scope rather than getting a deny reason that
    would be factually false about it.
    """
    _assert_allowed(_run_hook(_bash_event("until pgrep -f gunicorn; do sleep 1; done")))


def test_allows_pgrep_in_loop_body_rather_than_condition() -> None:
    """A pgrep that is not the exit test does not decide whether the loop ends."""
    cmd = "until [ -f build/done ]; do pgrep -f gunicorn; sleep 1; done"
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_pgrep_f_with_character_class_escape() -> None:
    """A `[a]bc` character class deliberately breaks the literal self-match."""
    cmd = "until ! pgrep -f '[a]7ab696cc6e841cc7'; do sleep 5; done; echo a7ab696cc6e841cc7"
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_pgrep_f_with_variable_pattern() -> None:
    """A non-literal pattern cannot be proven to self-match statically."""
    _assert_allowed(_run_hook(_bash_event('pgrep -f "$SERVICE_NAME" >/dev/null')))


def test_allows_plain_non_recurring_pgrep_f() -> None:
    """The common, safe case: a one-shot lookup with no loop around it."""
    _assert_allowed(_run_hook(_bash_event("pgrep -f gunicorn >/dev/null 2>&1")))


def test_allows_one_shot_pgrep_f_with_recurring_literal() -> None:
    """Even a token repeated all over a one-shot command cannot hang."""
    cmd = "pgrep -f UNIQUE_TOKEN_XYZ >/dev/null && echo UNIQUE_TOKEN_XYZ running"
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_pgrep_without_full_flag() -> None:
    """Without `-f`, pgrep matches the process name only -- no self-match."""
    _assert_allowed(_run_hook(_bash_event("pgrep nginx && echo nginx is up")))


def test_allows_pgrep_with_value_taking_option_before_pattern() -> None:
    """`-u root` consumes its value; `sshd` is still the sole operand."""
    _assert_allowed(_run_hook(_bash_event("pgrep -f -u root sshd")))


# --------------------------------------------------------------------------
# Rule 2: infinite polling of a subagent's tasks/*.output
# --------------------------------------------------------------------------


def test_blocks_tasks_output_until_poll() -> None:
    cmd = "until [ -s tasks/abc123.output ]; do sleep 5; done"
    reason = _assert_denied(_run_hook(_bash_event(cmd)))
    assert "tasks/abc123.output" in reason


@pytest.mark.parametrize(
    "cmd",
    [
        "while [ ! -s /home/u/.claude/tasks/deadbeef.output ]; do sleep 3; done; echo ok",
        "until ls tasks/*.output >/dev/null 2>&1; do sleep 1; done",
    ],
)
def test_blocks_tasks_output_poll_variants(cmd: str) -> None:
    _assert_denied(_run_hook(_bash_event(cmd)))


def test_allows_one_shot_tasks_output_read() -> None:
    """Reading the file without looping is not polling."""
    _assert_allowed(_run_hook(_bash_event("cat tasks/abc123.output")))


def test_allows_tasks_output_loop_without_sleep() -> None:
    """A bounded `for`-style read over outputs is not an infinite poll."""
    cmd = 'for f in tasks/*.output; do wc -l "$f"; done'
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_unrelated_tasks_output_mention_next_to_a_loop() -> None:
    """The three ingredients must be structurally connected (PR #1547 agy FOLLOW-UP).

    The first cut looked for a `tasks/*.output` path, a loop keyword and
    a `sleep` independently anywhere in the string, so a one-shot `ls`
    of an output file poisoned a completely unrelated readiness poll.
    """
    cmd = "ls tasks/test.output && while ! pg_isready; do sleep 1; done"
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_tasks_output_read_inside_an_unrelated_polling_loop() -> None:
    """A loop whose *test* is unrelated is not a tasks/*.output poll."""
    cmd = "until [ -f build/ready ]; do cat tasks/abc123.output; sleep 1; done"
    _assert_allowed(_run_hook(_bash_event(cmd)))


# --------------------------------------------------------------------------
# False-positive guard -- the half that must never regress
# --------------------------------------------------------------------------


def test_allows_harness_recommended_dev_log_poll() -> None:
    """Monitor's documented one-shot wait shape must pass through untouched.

    #1521 explicitly decided NOT to ban polling loops in general, because
    the harness itself recommends this exact command. If this test ever
    starts failing, the rule was widened past its mandate -- fix the rule,
    not the test.
    """
    _assert_allowed(_run_hook(_bash_event(HARNESS_RECOMMENDED_POLL)))


@pytest.mark.parametrize(
    "cmd",
    [
        'until grep -q "Ready in" dev.log; do sleep 0.5; done',
        "until [ -f build/done ]; do sleep 1; done",
        "while ! curl -sf http://localhost:3000 >/dev/null; do sleep 2; done",
        "until nc -z localhost 5432; do sleep 0.5; done",
    ],
)
def test_allows_generic_polling_loops(cmd: str) -> None:
    """Generic waits that touch neither pgrep -f nor tasks/*.output."""
    _assert_allowed(_run_hook(_bash_event(cmd)))


def test_allows_plain_unrelated_command() -> None:
    _assert_allowed(_run_hook(_bash_event("ls -la")))


@pytest.mark.parametrize(
    "cmd",
    [
        "git status --short",
        "pytest tests/integration -v",
        "echo 'sleep until done'",
        "rg -n 'pgrep' claude/hooks",
    ],
)
def test_allows_everyday_commands(cmd: str) -> None:
    _assert_allowed(_run_hook(_bash_event(cmd)))


# --------------------------------------------------------------------------
# Safety rails -- the hook must never trap the user
# --------------------------------------------------------------------------


def test_allows_non_bash_tool() -> None:
    payload = json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "Write",
            "tool_input": {"file_path": "/tmp/x", "content": "pgrep -f x x"},
        }
    )
    _assert_allowed(_run_hook(payload))


@pytest.mark.parametrize("payload", ["", "   ", "not json at all", "[]", "null", "{}"])
def test_fails_open_on_bad_stdin(payload: str) -> None:
    _assert_allowed(_run_hook(payload))


def test_allows_missing_command_field() -> None:
    payload = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {}})
    _assert_allowed(_run_hook(payload))


def test_bypass_env_var_disables_the_guard() -> None:
    result = _run_hook(
        _bash_event(ISSUE_1521_COMMAND),
        env={"BASH_WAIT_LOOP_GUARD_BYPASS": "1"},
    )
    _assert_allowed(result)


def test_hook_is_executable_with_python3_shebang() -> None:
    assert os.access(HOOK_PATH, os.X_OK), f"{HOOK_PATH} must be chmod +x"
    assert HOOK_PATH.read_text(encoding="utf-8").startswith("#!/usr/bin/env python3\n")


def test_hook_is_wired_into_settings_json() -> None:
    """claude/settings.json is the hook-wiring SSOT (issue #1521 adds PreToolUse)."""
    settings = json.loads((REPO_ROOT / "claude" / "settings.json").read_text(encoding="utf-8"))
    entries = settings["hooks"]["PreToolUse"]
    commands = [
        hook["command"] for entry in entries if entry.get("matcher") == "Bash" for hook in entry.get("hooks", [])
    ]
    assert any(c.endswith("claude/hooks/bash_wait_loop_guard.py") for c in commands), commands
