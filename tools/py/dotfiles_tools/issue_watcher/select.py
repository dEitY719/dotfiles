"""Candidate selection/filter logic of issue_watcher_cron.sh, ported from jq/awk (#2157).

The shell keeps every gh/herdr call, the lock and the logging; it pipes the JSON
gh printed into one of the ops below and reads the answer back. Each op mirrors
the jq/awk filter it replaced byte for byte -- the legacy filters live in
shell-common/tools/custom/lib/issue_watcher_select_shell.sh (IW_SELECT_IMPL=shell)
and tests/py/test_issue_watcher_select.py proves both agree on every fixture.

Usage: python3 -s -E -m dotfiles_tools.issue_watcher.select <op> [arg] < input

  search-rows          gh search issues JSON -> `<repo>TAB<number>TAB<labels>` lines,
                       labels joined by US (0x1f)
  pr-count             gh pr list JSON -> its length
  handled-by-pr <n>    gh pr list JSON -> exit 0 handled / 1 not / 2 cannot tell
  open-blockers        blockedBy GraphQL JSON -> comma-joined OPEN blockers;
                       exit 0 when there is one, 1 when there is none
  repo-order [<last>]  watch-list TSV lines -> repos, starting after <last>

Exit codes: 0 / 1 are the op's answer, 2 is unreadable input or bad usage.
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Iterable
from typing import Any, cast

from dotfiles_tools.issue_watcher.models import BlockerNode, OpenPr, SearchIssue

US = "\x1f"


def _iterate(value: Any) -> list[Any]:
    """jq `.[]?`: an array's elements, an object's values, nothing otherwise."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return []


def _jq_str(value: Any) -> str:
    """jq `tostring` for the scalars gh emits."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return value
    return json.dumps(value)


def _tsv_field(value: Any) -> str:
    """One `@tsv` field: null is empty, and \\ TAB LF CR are escaped."""
    text = "" if value is None else _jq_str(value)
    return text.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def search_rows(issues: Any) -> list[str]:
    """`<repo>TAB<number>TAB<labels>` per searched issue (labels joined by US)."""
    rows = []
    for item in _iterate(issues):
        issue = cast(SearchIssue, item if isinstance(item, dict) else {})
        repo = (issue.get("repository") or {}).get("nameWithOwner")
        labels = US.join(
            "" if label.get("name") is None else _jq_str(label.get("name"))
            for label in cast(Iterable[Any], _iterate(issue.get("labels")))
            if isinstance(label, dict)
        )
        rows.append("\t".join([_tsv_field(repo), _tsv_field(_jq_str(issue.get("number"))), _tsv_field(labels)]))
    return rows


def handled_by_pr(prs: Any, number: str) -> bool:
    """True when an open PR closes issue <number> by branch name or by keyword.

    The trailing \\b is load-bearing: without it #14 would match a body that
    closes #145. `Closes: #11` and the cross-repo `Closes owner/repo#11` count too.
    """
    branch = re.compile("^wt/issue-" + re.escape(number) + "/")
    keyword = re.compile(
        r"\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?\s+(\S+)?#" + re.escape(number) + r"\b", re.IGNORECASE
    )
    for item in _iterate(prs):
        pr = cast(OpenPr, item)
        head = pr.get("headRefName") or ""
        body = pr.get("body") or ""
        if not isinstance(head, str) or not isinstance(body, str):
            raise ValueError("headRefName/body is not a string")
        if branch.search(head) or keyword.search(body):
            return True
    return False


def open_blockers(response: Any) -> list[int]:
    """Numbers of the OPEN issues in a blockedBy GraphQL answer."""
    node: Any = response
    for key in ("data", "repository", "issue", "blockedBy", "nodes"):
        node = node.get(key) if isinstance(node, dict) else None
    return [
        cast(BlockerNode, blocker)["number"]
        for blocker in _iterate(node)
        if isinstance(blocker, dict) and blocker.get("state") == "OPEN"
    ]


def repo_order(lines: list[str], last: str) -> list[str]:
    """Every watched repo once, starting at the one after <last> (round-robin).

    Without the rotation a repo that always has candidates would starve every
    repo after it, at one dispatch per tick.
    """
    repos = [line.split("\t", 1)[0] for line in lines]
    start = 0
    if last:
        for index, repo in enumerate(repos):
            if repo == last:
                start = index + 1
                break
    return [repos[(start + k) % len(repos)] for k in range(len(repos))]


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    op, args = argv[0], argv[1:]
    raw = sys.stdin.read()

    if op == "repo-order":
        for repo in repo_order(raw.splitlines(), args[0] if args else ""):
            print(repo)
        return 0

    try:
        data = json.loads(raw)
    except ValueError:
        return 2

    if op == "search-rows":
        for row in search_rows(data):
            print(row)
        return 0
    if op == "pr-count":
        if isinstance(data, list | dict | str):
            print(len(data))
            return 0
        return 2
    if op == "handled-by-pr" and len(args) == 1:
        try:
            return 0 if handled_by_pr(data, args[0]) else 1
        except ValueError:
            return 2
    if op == "open-blockers":
        blockers = open_blockers(data)
        print(",".join(str(n) for n in blockers))
        return 0 if blockers else 1

    print(f"select: unknown op or bad arguments: {' '.join(argv)}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
