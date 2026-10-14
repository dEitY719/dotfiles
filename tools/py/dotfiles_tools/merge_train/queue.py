"""Queue fingerprint/backoff logic of pr_merge_train_cron.sh, ported from jq/shell (#2174).

The shell keeps every gh/herdr call, the lock, the state-file I/O and the logging;
it pipes what it holds into one of the ops below and reads the answer back. Each
op mirrors the jq/shell code it replaced -- the legacy code lives in
shell-common/tools/custom/lib/merge_train_queue_shell.sh (PMT_QUEUE_IMPL=shell)
and tests/py/test_merge_train_queue.py proves both agree on every fixture.

Usage: python3 -s -E -m dotfiles_tools.merge_train.queue <op> [arg...] < input

  count                          filtered PR array -> its length
  fingerprint                    filtered PR array -> sorted `;`-joined
                                 `number:headRefOid:mergeStateStatus:mergeable:labels`
                                 tuples (labels: the verdict labels, sorted, `,`-joined)
  backoff-next <max> <fp>        backoff state line `<window> <remaining> <fp>` ->
                                 `run` (record nothing), `run <w> <r>` (record, wake)
                                 or `skip <w> <r>` (record, do not wake)

Exit codes: 0 answered, 2 unreadable input or bad usage, with empty stdout. The
shell decides from stdout: an empty or unknown verdict means "run, record nothing".
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

from dotfiles_tools.issue_watcher.select import _iterate, jq_length

VERDICT_LABELS = ("review-passed", "review-blocked", "reply-pending")
_DIGITS = re.compile(r"[0-9]+")


def _jq_str(value: Any) -> str:
    """jq `tostring` (and jq 1.6+ `join` coercion) for the scalars gh emits."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return value
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def _field(pr: dict[str, Any], key: str) -> str:
    """jq `(.key // "")`: null and false fall back to the empty string."""
    value = pr.get(key)
    if isinstance(value, dict | list):  # jq `join` rejects them
        raise ValueError(f"{key} is not a scalar")
    return "" if value is None or value is False else _jq_str(value)


def fingerprint(prs: Any) -> str:
    """The #1709 queue fingerprint, minus the `<host>/<repo>|` prefix the shell adds."""
    tuples = []
    for item in _iterate(prs):
        if item is None:  # jq: `null | .number` is null, not an error
            item = {}
        if not isinstance(item, dict):
            raise ValueError("PR is not an object")
        number = item.get("number")
        labels = sorted(
            label["name"]
            for label in _iterate(item.get("labels"))
            if isinstance(label, dict) and label.get("name") in VERDICT_LABELS
        )
        tuples.append(
            ":".join(
                [
                    "?" if number is None or number is False else _jq_str(number),
                    _field(item, "headRefOid"),
                    _field(item, "mergeStateStatus"),
                    _field(item, "mergeable"),
                    ",".join(labels),
                ]
            )
        )
    return ";".join(sorted(tuples))


def _counter(text: str) -> int:
    # shortcut: a leading-zero counter ("08") is decimal here, an arithmetic error in
    # the shell path; only a hand-edited state file has one, so parity there is moot.
    return int(text) if _DIGITS.fullmatch(text) else 0


def backoff_next(state_line: str, maximum: int, fp: str) -> str:
    """Decide this tick's backoff verdict from the previous state line.

    Fingerprint changed -> reset to window 1 and run. Window still open -> skip and
    count it down. Window elapsed -> run and arm the next, doubled (capped) one.
    """
    if not fp:
        return "run"
    # bash `IFS=' ' read -r window remaining prev`: space-separated, the last
    # field keeps inner spaces, surrounding spaces dropped.
    fields = re.split(r" +", state_line.strip(" "), maxsplit=2) + ["", ""]
    window, remaining, prev = _counter(fields[0]), _counter(fields[1]), fields[2]
    if fp != prev:
        return "run 1 1"
    if remaining > 0:
        return f"skip {window} {remaining - 1}"
    window = min(max(window * 2, 1), maximum)
    return f"run {window} {window}"


def main(argv: list[str]) -> int:
    # An unexpected JSON shape must read as "unreadable" (2) with empty stdout,
    # never as an uncaught-traceback exit 1.
    try:
        code, out = _main(argv)
    except Exception as exc:
        print(f"queue: unreadable input: {exc!r}", file=sys.stderr)
        return 2
    sys.stdout.buffer.write(out.encode("utf-8"))
    return code


def _main(argv: list[str]) -> tuple[int, str]:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2, ""
    op, args = argv[0], argv[1:]
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")

    if op == "backoff-next" and len(args) == 2 and _DIGITS.fullmatch(args[0]):
        return 0, backoff_next(raw.split("\n", 1)[0], int(args[0]), args[1]) + "\n"

    if op in ("count", "fingerprint") and not args:
        try:
            data = json.loads(raw)
        except ValueError:
            return 2, ""
        if op == "count":
            return 0, f"{jq_length(data)}\n"
        return 0, fingerprint(data) + "\n"

    print(f"queue: unknown op or bad arguments: {' '.join(argv)}", file=sys.stderr)
    return 2, ""


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
