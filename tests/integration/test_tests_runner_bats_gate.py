"""Tests for tests/test's run_bats() fail-closed gate (issue #1397).

run_bats() (tests/test) is expected to fail the suite (non-zero return) when
shell unit tests could not actually run — either because the bats-core
submodule binary is missing, or because zero *.bats files were discovered —
unless the explicit SKIP_BATS=1 opt-out is set, in which case it preserves
the legacy warn-and-succeed behavior (mirrors SKIP_LOCAL_PYTEST=1 in
git/hooks/pre-push).

tests/test unconditionally calls main() at the bottom, guarded by
`if [ "${BASH_SOURCE[0]}" = "${0}" ]` so it only runs when executed
directly. That guard lets us `source` the real script here to reuse its
actual run_bats() implementation, then override SCRIPT_DIR to point at a
disposable fixture directory before invoking run_bats() in isolation —
without ever running check_requirements()/run_golden_rules()/run_pytest(),
so this test never recursively re-invokes `pytest tests/integration/`.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = REPO_ROOT / "tests" / "test"

BATS_STUB = "#!/bin/sh\nexit 0\n"


def _run_bats_in(fake_script_dir: Path, skip_bats: str | None) -> subprocess.CompletedProcess[str]:
    """Source the real tests/test with SCRIPT_DIR overridden, then call run_bats()."""
    script = (
        f'source "{RUNNER_PATH}"\n'
        f'SCRIPT_DIR="{fake_script_dir}"\n'
        "run_bats\n"
    )
    env = {}
    if skip_bats is not None:
        env["SKIP_BATS"] = skip_bats
    return subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        timeout=30,
        env=env or None,
        cwd=REPO_ROOT,
    )


@pytest.fixture
def missing_binary_dir(tmp_path: Path) -> Path:
    """A SCRIPT_DIR with no bats-core binary at all (uninitialized submodule)."""
    (tmp_path / "bats").mkdir()
    return tmp_path


@pytest.fixture
def zero_files_dir(tmp_path: Path) -> Path:
    """A SCRIPT_DIR with an executable bats-core stub but zero *.bats files."""
    bin_dir = tmp_path / "bats" / "lib" / "bats-core" / "bin"
    bin_dir.mkdir(parents=True)
    bats_bin = bin_dir / "bats"
    bats_bin.write_text(BATS_STUB)
    bats_bin.chmod(0o755)
    return tmp_path


def test_missing_binary_fails_closed_by_default(missing_binary_dir: Path) -> None:
    result = _run_bats_in(missing_binary_dir, skip_bats=None)
    assert result.returncode != 0
    assert "bats-core not found" in result.stdout


def test_missing_binary_skip_bats_opt_out_succeeds(missing_binary_dir: Path) -> None:
    result = _run_bats_in(missing_binary_dir, skip_bats="1")
    assert result.returncode == 0
    assert "bats-core not found" in result.stdout


def test_zero_bats_files_fails_closed_by_default(zero_files_dir: Path) -> None:
    result = _run_bats_in(zero_files_dir, skip_bats=None)
    assert result.returncode != 0
    assert "No bats test files found" in result.stdout


def test_zero_bats_files_skip_bats_opt_out_succeeds(zero_files_dir: Path) -> None:
    result = _run_bats_in(zero_files_dir, skip_bats="1")
    assert result.returncode == 0
    assert "No bats test files found" in result.stdout
