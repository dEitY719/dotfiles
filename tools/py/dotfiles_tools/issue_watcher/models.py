"""Shapes of the gh JSON the issue watcher feeds to select.py.

Only the fields select.py reads; everything is optional because the input is
whatever gh printed, and select.py must tolerate a missing key the way the jq
filters it replaced did (a missing field reads as null, never as an error).
"""

from __future__ import annotations

from typing import TypedDict


class Label(TypedDict, total=False):
    name: str


class Repository(TypedDict, total=False):
    nameWithOwner: str


class SearchIssue(TypedDict, total=False):
    """One element of `gh search issues --json number,repository,labels`."""

    number: int
    repository: Repository
    labels: list[Label]


class OpenPr(TypedDict, total=False):
    """One element of `gh pr list --json number,headRefName,body`."""

    number: int
    headRefName: str | None
    body: str | None


class BlockerNode(TypedDict, total=False):
    number: int
    state: str
