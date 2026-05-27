"""Tests for scripts/maintenance/check_codex_skills_budget.py.

Covers the per-skill hard limit added in issue #785: any single skill
description exceeding 1024 characters must fail the check so the loader
never silently drops a skill again.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
SCRIPT = REPO_ROOT / "scripts" / "maintenance" / "check_codex_skills_budget.py"


def _make_skill(skills_dir: Path, name: str, description: str) -> None:
    skill_dir = skills_dir / name
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {description}\n---\n# {name}\nbody\n",
        encoding="utf-8",
    )


def _run(skills_dir: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--skills-dir", str(skills_dir), "--quiet", *extra],
        capture_output=True,
        text=True,
        timeout=30,
    )


@pytest.fixture
def skills_root(tmp_path: Path) -> Path:
    root = tmp_path / "skills"
    root.mkdir()
    return root


def test_under_per_skill_limit_passes(skills_root: Path) -> None:
    _make_skill(skills_root, "ok", "a" * 500)
    result = _run(skills_root)
    assert result.returncode == 0, result.stderr or result.stdout


def test_per_skill_limit_failure_exits_1(skills_root: Path) -> None:
    _make_skill(skills_root, "tiny", "ok")
    _make_skill(skills_root, "bloated", "x" * 1100)
    result = _run(skills_root)
    assert result.returncode == 1
    assert "bloated" in result.stdout
    assert "per-skill description hard limit" in result.stdout


def test_per_skill_limit_flag_respected(skills_root: Path) -> None:
    _make_skill(skills_root, "modest", "x" * 600)
    result = _run(skills_root, "--per-skill-max", "500")
    assert result.returncode == 1
    assert "modest" in result.stdout


def test_total_budget_still_enforced(skills_root: Path) -> None:
    for i in range(5):
        _make_skill(skills_root, f"s{i}", "y" * 500)
    result = _run(skills_root, "--budget", "100")
    assert result.returncode == 1
    assert "exceed budget" in result.stdout
