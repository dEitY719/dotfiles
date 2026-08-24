"""Regression guard for the pytest parallelism config in pyproject.toml (#1413).

The suite mixes fast unit-style checks with slow subprocess/pexpect-driven
tests, so xdist's default `--dist load` (round-robin hand-out) leaves workers
idle behind a straggler. `--dist worksteal` keeps a shared queue and lets idle
workers steal pending tests, which is what keeps the wall clock down. This
pins that choice so a future addopts edit cannot silently revert it.

Deliberately avoids `tomllib` (stdlib only from Python 3.11) so this guard
actually runs on this repo's declared floor, `requires-python = ">=3.10"`
(pyproject.toml) — a full TOML parse isn't needed to pin one known single-line
`addopts` string, and a regex keeps the check dependency-free on 3.10 too
(codex review, PR #1416).
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PYPROJECT = REPO_ROOT / "pyproject.toml"

_ADDOPTS_RE = re.compile(r'^addopts\s*=\s*"([^"]*)"', re.MULTILINE)


def test_pytest_addopts_uses_worksteal_scheduler() -> None:
    text = PYPROJECT.read_text(encoding="utf-8")
    match = _ADDOPTS_RE.search(text)
    assert match, f'could not find an addopts = "..." line in {PYPROJECT}'
    addopts = match.group(1)
    assert "--dist worksteal" in addopts, f"expected --dist worksteal in addopts, got: {addopts!r}"
