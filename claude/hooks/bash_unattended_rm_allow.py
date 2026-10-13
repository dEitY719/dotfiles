#!/usr/bin/env python3
"""Claude Code PreToolUse hook: allow scratch-dir `rm` in yolo sessions (issue #2119).

A compound command such as `xargs ... sh -c '...'` or `eval "$(...)"` that
contains `rm` makes the harness ask `This shell -c script runs rm and could
not be checked`. An unattended session auto-denies that prompt after a
timeout, so the command fails and the night's work is lost.

This hook answers `permissionDecision: "allow"` only when ALL hold:
    - `permission_mode` is `bypassPermissions` (a yolo session; elsewhere the
      prompt is a feature and this hook has no opinion);
    - the command has at least one `rm`/`rmdir` word;
    - every non-option argument of every `rm`/`rmdir` is under
      `/tmp/claude-<uid>/` (literal, or `$VAR` assigned in the same command
      from such a path / `mktemp -d /tmp/claude-<uid>/...`), without `..`.

Anything else -> exit 0 with no output (no opinion; normal permission flow).
The scan is regex over the raw text, not shlex: the whole point is to see
through nested `sh -c '...'` quoting. It over-matches (`echo "no rm here"`
yields args `here`), which only costs a missed allow, never a wrong one.

shortcut: allow covers the whole command, not just the rm -- acceptable
because bypassPermissions already allows everything; upgrade if this hook is
ever widened beyond yolo sessions.

Fail-open: bad JSON or any exception -> no output. Escape hatch
`BASH_UNATTENDED_RM_ALLOW_BYPASS=1`.
"""

from __future__ import annotations

import json
import os
import re
import sys

_SAFE_ROOT = r"/tmp/claude-\d+/"
_RM_RE = re.compile(r"(?<![\w./-])(?:rm|rmdir)\b([^;&|)\n]*)")
_ASSIGN_RE = re.compile(
    r"\b([A-Za-z_]\w*)=(?:\$\(\s*mktemp\s+-d\s+)?[\"']?(" + _SAFE_ROOT + r"[^\s\"')]*|[^\s\"')]*XXXX[^\s\"')]*)"
)
_VAR_RE = re.compile(r"^\$(?:\{(\w+)\}|(\w+))(/.*)?$")


def _safe_vars(command: str) -> set[str]:
    return {m.group(1) for m in _ASSIGN_RE.finditer(command) if m.group(2).startswith("/tmp/claude-")}


def _arg_ok(arg: str, safe_vars: set[str]) -> bool:
    if ".." in arg:
        return False
    if re.match(_SAFE_ROOT + r"\S", arg):
        return True
    m = _VAR_RE.match(arg)
    return bool(m and (m.group(1) or m.group(2)) in safe_vars)


def all_rm_targets_safe(command: str) -> bool:
    safe_vars = _safe_vars(command)
    seen = False
    for m in _RM_RE.finditer(command):
        seen = True
        args = [a for a in m.group(1).replace("'", " ").replace('"', " ").split() if not a.startswith("-")]
        if not args or not all(_arg_ok(a, safe_vars) for a in args):
            return False
    return seen


def main() -> int:
    if os.environ.get("BASH_UNATTENDED_RM_ALLOW_BYPASS") == "1":
        return 0
    try:
        event = json.loads(sys.stdin.read())
    except (ValueError, TypeError):
        return 0
    if not isinstance(event, dict) or event.get("tool_name") != "Bash":
        return 0
    if event.get("permission_mode") != "bypassPermissions":
        return 0
    tool_input = event.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not all_rm_targets_safe(command):
        return 0
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "yolo 세션: rm 대상이 모두 /tmp/claude-<uid>/ 하위 (#2119)",
            }
        },
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # fail open, always
        sys.exit(0)
