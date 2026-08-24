"""Regression guard for the pytest parallelism config in pyproject.toml (#1413).

The suite mixes fast unit-style checks with slow subprocess/pexpect-driven
tests, so xdist's default `--dist load` (round-robin hand-out) leaves workers
idle behind a straggler. `--dist worksteal` keeps a shared queue and lets idle
workers steal pending tests, which is what keeps the wall clock down. This
pins that choice so a future addopts edit cannot silently revert it.
"""

from __future__ import annotations

from pathlib import Path

import pytest

tomllib = pytest.importorskip("tomllib", reason="tomllib is stdlib from Python 3.11")

REPO_ROOT = Path(__file__).resolve().parents[2]
PYPROJECT = REPO_ROOT / "pyproject.toml"


def test_pytest_addopts_uses_worksteal_scheduler() -> None:
    config = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    addopts = config["tool"]["pytest"]["ini_options"]["addopts"]
    assert "--dist worksteal" in addopts, f"expected --dist worksteal in addopts, got: {addopts!r}"
