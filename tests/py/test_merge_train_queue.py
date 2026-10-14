"""dotfiles_tools.merge_train.queue (#2174).

Explicit expectations per op. The golden parity check against the legacy
jq/shell code went away with that rollback path (#2210).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures" / "merge_train"
FP = "github.com/acme/api|1:aaa:CLEAN:MERGEABLE:review-passed"


def run_python(op: list[str], fixture: str) -> tuple[int, str]:
    """Invoke the module the way cron_py does: -E -s, cwd = tools/py."""
    proc = subprocess.run(
        [sys.executable, "-E", "-s", "-m", "dotfiles_tools.merge_train.queue", *op],
        input=(FIXTURES / fixture).read_bytes(),
        capture_output=True,
        cwd=ROOT / "tools/py",
        check=False,
    )
    return proc.returncode, proc.stdout.decode()


CASES = [
    (["count"], "queue.json", 0, "5\n"),
    (["count"], "empty.json", 0, "0\n"),
    (["count"], "null.json", 0, "0\n"),
    (["count"], "truncated.json", 2, ""),
    # sorted tuples; only verdict labels count, sorted; null/false fields are empty,
    # a missing number is `?`, a null PR is a tuple of its own.
    (
        ["fingerprint"],
        "queue.json",
        0,
        "100::DIRTY::review-blocked;12:bbb:CLEAN:MERGEABLE:reply-pending,review-passed;"
        "3:aaa:BEHIND:UNKNOWN:;?::::;?:ccc:::\n",
    ),
    (["fingerprint"], "empty.json", 0, "\n"),
    (["fingerprint"], "null.json", 0, "\n"),
    (["fingerprint"], "truncated.json", 2, ""),
    (["fingerprint"], "scalar_pr.json", 2, ""),
    # no fingerprint: run, record nothing.
    (["backoff-next", "8", ""], "state_open.txt", 0, "run\n"),
    # no previous state, or a different fingerprint: reset to window 1.
    (["backoff-next", "8", FP], "state_missing.txt", 0, "run 1 1\n"),
    (["backoff-next", "8", FP + ";2:b:::"], "state_open.txt", 0, "run 1 1\n"),
    # window open: skip and count down.
    (["backoff-next", "8", FP], "state_open.txt", 0, "skip 4 1\n"),
    # last tick of an open window: still a skip, counted down to 0.
    (["backoff-next", "8", FP], "state_window1.txt", 0, "skip 1 0\n"),
    # window elapsed: run and double, capped at <max>.
    (["backoff-next", "8", FP], "state_elapsed.txt", 0, "run 4 4\n"),
    (["backoff-next", "8", FP], "state_capped.txt", 0, "run 8 8\n"),
    (["backoff-next", "4", FP], "state_capped.txt", 0, "run 4 4\n"),
    # a corrupt window reads as 0; surrounding spaces around the stored fingerprint drop.
    (["backoff-next", "8", FP], "state_corrupt.txt", 0, "skip 0 2\n"),
    (["backoff-next", "8"], "state_open.txt", 2, ""),
]


@pytest.mark.parametrize(("op", "fixture", "code", "out"), CASES)
def test_python_queue(op: list[str], fixture: str, code: int, out: str) -> None:
    assert run_python(op, fixture) == (code, out)


def test_backoff_window_sequence() -> None:
    """Unchanged queue: 1 -> 2 -> 4 -> 8 -> 8, each window skipped before it doubles."""
    from dotfiles_tools.merge_train.queue import backoff_next

    line, seen = "", []
    for _ in range(12):
        verdict = backoff_next(line, 8, FP).split()
        seen.append(" ".join(verdict))
        line = f"{verdict[1]} {verdict[2]} {FP}"
    assert seen[:8] == ["run 1 1", "skip 1 0", "run 2 2", "skip 2 1", "skip 2 0", "run 4 4", "skip 4 3", "skip 4 2"]
    assert "run 8 8" in seen
