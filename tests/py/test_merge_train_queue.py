"""dotfiles_tools.merge_train.queue (#2174).

Two layers: explicit expectations per op, and a golden parity check that runs
the legacy jq/shell code (PMT_QUEUE_IMPL=shell) on the same fixtures and
requires byte-identical stdout and the same exit code.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures" / "merge_train"
LEGACY = ROOT / "shell-common/tools/custom/lib/merge_train_queue_shell.sh"
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


def run_shell(op: list[str], fixture: str) -> tuple[int, str]:
    proc = subprocess.run(
        ["bash", "-c", '. "$0" && _pmt_q_shell "$@"', str(LEGACY), *op],
        input=(FIXTURES / fixture).read_bytes(),
        capture_output=True,
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
    # window elapsed: run and double.
    (["backoff-next", "8", FP], "state_window1.txt", 0, "skip 1 0\n"),
    (["backoff-next", "8", FP], "state_capped.txt", 0, "run 8 8\n"),
    (["backoff-next", "4", FP], "state_capped.txt", 0, "run 4 4\n"),
    # a corrupt window reads as 0; surrounding spaces around the stored fingerprint drop.
    (["backoff-next", "8", FP], "state_corrupt.txt", 0, "skip 0 2\n"),
    (["backoff-next", "8"], "state_open.txt", 2, ""),
]


@pytest.mark.parametrize(("op", "fixture", "code", "out"), CASES)
def test_python_queue(op: list[str], fixture: str, code: int, out: str) -> None:
    assert run_python(op, fixture) == (code, out)


@pytest.mark.skipif(shutil.which("jq") is None, reason="legacy filters need jq")
@pytest.mark.parametrize(("op", "fixture", "code", "out"), CASES)
def test_shell_python_parity(op: list[str], fixture: str, code: int, out: str) -> None:
    """Golden: the rollback path answers exactly what the Python path answers."""
    assert run_shell(op, fixture) == run_python(op, fixture)


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
