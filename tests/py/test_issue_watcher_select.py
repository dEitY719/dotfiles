"""dotfiles_tools.issue_watcher.select (#2157).

Explicit expectations per op. The golden parity check against the legacy jq/awk
filters left with the IW_SELECT_IMPL=shell rollback (#2173), so CASES are now the
only pin on the jq semantics -- keep the subtle ones covered: the handled-by-pr
trailing word boundary (#14 vs #145) and the open-blockers exit code.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures" / "issue_watcher"
US = "\x1f"


def run_python(op: list[str], fixture: str, env: dict[str, str] | None = None) -> tuple[int, str]:
    """Invoke the module the way cron_py does: -E -s, cwd = tools/py."""
    proc = subprocess.run(
        [sys.executable, "-E", "-s", "-m", "dotfiles_tools.issue_watcher.select", *op],
        input=(FIXTURES / fixture).read_bytes(),
        capture_output=True,
        cwd=ROOT / "tools/py",
        env=env,
        check=False,
    )
    return proc.returncode, proc.stdout.decode()


CASES = [
    (
        ["search-rows"],
        "search_issues.json",
        0,
        f"acme/api\t14\tbug{US}needs review, soon\nacme/web\t3\t\nacme/api\t145\twontfix\n",
    ),
    (["search-rows"], "truncated.json", 2, ""),
    # Korean label passes through as UTF-8; a tab inside a label is @tsv-escaped.
    (["search-rows"], "search_issues_korean.json", 0, f"acme/api\t9\t보류{US}tab\\there\n"),
    (["pr-count"], "open_prs.json", 0, "4\n"),
    (["pr-count"], "truncated.json", 2, ""),
    # jq `length` semantics: null is 0, a number its absolute value.
    (["pr-count"], "null.json", 0, "0\n"),
    (["pr-count"], "negative_number.json", 0, "3\n"),
    # body keyword, with the trailing \b: #14 must not match "Closes #145".
    (["handled-by-pr", "145"], "open_prs.json", 0, "1\n"),
    (["handled-by-pr", "14"], "open_prs.json", 0, "0\n"),
    # branch name wt/issue-<n>/ — and #77's branch must not handle #7 or vice versa.
    (["handled-by-pr", "7"], "open_prs.json", 0, "1\n"),
    (["handled-by-pr", "77"], "open_prs.json", 0, "1\n"),
    # `fixes: owner/repo#11` spelling.
    (["handled-by-pr", "11"], "open_prs.json", 0, "1\n"),
    # a plain reference is not a closing keyword.
    (["handled-by-pr", "12"], "open_prs.json", 0, "0\n"),
    (["handled-by-pr", "12"], "truncated.json", 2, ""),
    (["open-blockers"], "blocked_by_open.json", 0, "1,3\n"),
    (["open-blockers"], "blocked_by_closed.json", 1, "\n"),
    # fail-open: a server that does not know the field means "not blocked".
    (["open-blockers"], "blocked_by_unknown_field.json", 1, "\n"),
    (["repo-order"], "watch_list.tsv", 0, "acme/api\nacme/web\nacme/cli\n"),
    (["repo-order", "acme/web"], "watch_list.tsv", 0, "acme/cli\nacme/api\nacme/web\n"),
    (["repo-order", "acme/cli"], "watch_list.tsv", 0, "acme/api\nacme/web\nacme/cli\n"),
    (["repo-order", "gone/repo"], "watch_list.tsv", 0, "acme/api\nacme/web\nacme/cli\n"),
]


@pytest.mark.parametrize(("op", "fixture", "code", "out"), CASES)
def test_python_select(op: list[str], fixture: str, code: int, out: str) -> None:
    assert run_python(op, fixture) == (code, out)


def test_repo_order_empty_watch_list() -> None:
    from dotfiles_tools.issue_watcher.select import repo_order

    assert repo_order([], "acme/api") == []


def test_c_locale_keeps_korean_labels() -> None:
    """cron may run under LANG=C; the label must still come out as UTF-8."""
    env = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C", "LANG": "C"}
    assert run_python(["search-rows"], "search_issues_korean.json", env) == (0, f"acme/api\t9\t보류{US}tab\\there\n")
