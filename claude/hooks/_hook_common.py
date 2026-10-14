"""Helpers shared by the Python hooks (refactor F7, #2148).

Imported by the Stop guards (gh_issue_flow_stop_guard.py,
devx_autopilot_stop_guard.py, skill_completion_guard.py) for transcript
helpers, and by the PreToolUse Bash hooks (bash_*.py) for stdin parsing --
each used to carry its own copy. Each hook
puts its own *real* directory on sys.path before importing this module —
settings.json runs hooks by a path that may go through a symlinked checkout,
and the module must be found next to the real file, not next to the link.

Stdlib only, no side effects at import: a hook that cannot import this module
fails open (allows the stop) rather than trapping the session.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


def read_hook_input() -> dict[str, Any]:
    """Parse the hook event JSON on stdin; {} when empty, malformed or not an object.

    Callers treat {} as "nothing to judge" and exit 0, so a bad payload
    always fails open.
    """
    try:
        event = json.load(sys.stdin)
    except (ValueError, TypeError, OSError):
        return {}
    return event if isinstance(event, dict) else {}


def tool_input_command(payload: dict[str, Any]) -> str:
    """Return `tool_input.command` when it is a string, else ""."""
    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    return command if isinstance(command, str) else ""


def line_anchored_alternation(markers: tuple[str, ...], shapes: tuple[str, ...] = ()) -> re.Pattern[str]:
    """Compile markers into one `(?m)^`-anchored alternation (#1281).

    An unanchored `marker in text` test fired on any occurrence, so a human
    asking "what does 'Stop hook feedback:' mean?" had that whole turn
    discarded from the fresh-prompt count. Real harness injections always
    open a line with their marker (same reasoning as `_USER_BOUNDARY_RE`),
    so line-start anchoring keeps every genuine injection matched while
    letting a quoted marker mid-sentence stay a human turn.

    `markers` are literals (escaped — they carry `<`, `>`, `[`, `]`).
    `shapes` are already-regex fragments, for injections whose literal
    prefix is variable and so cannot be expressed as a fixed marker.
    """
    return re.compile(r"(?m)^(?:" + "|".join([re.escape(m) for m in markers] + list(shapes)) + r")")


def load_transcript(path: Path) -> list[dict[str, Any]]:
    """Best-effort JSONL load. Skips malformed lines, never raises."""
    out: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    out.append(obj)
    except OSError:
        return []
    return out


def message_payload(entry: dict[str, Any]) -> dict[str, Any]:
    """Return the inner `message` dict if present, else the entry itself."""
    inner = entry.get("message")
    return inner if isinstance(inner, dict) else entry
