"""Regression guard: `pytest tests/integration/` must collect cleanly (#1432).

The repo's default entry points (`mise run test`, `./tests/test`) inherit
`addopts = "-n auto"` from pyproject.toml, and xdist workers collect in separate
processes — so an import-time `sys.path` / `sys.modules` mutation made by one
test module never reaches the others, and a top-level module name collision
stays invisible on that path. The command `tests/AGENTS.md` documents
(`pytest tests/integration/`) collects everything in one process, where the same
collision aborts collection for the *whole* suite: in #1432 a single
`ModuleNotFoundError` cost all 1350 tests, silently, while the default path
stayed green.

The collision was `scripts`: `claude/skills/skill-create/scripts/` carried an
(empty) `__init__.py`, making it a *regular* package, while the repo-root
`scripts/` has none and is a *namespace* package. A regular package always wins
the name, so once `test_skill_create_run_eval.py` put the skill dir on
`sys.path`, `scripts.maintenance` became unimportable for every later module.
Deleting that empty `__init__.py` turns both into namespace portions, which
*merge* — `scripts.run_eval` and `scripts.maintenance` now resolve side by side.

The first guard below is behavioural (any future collision fails it, whatever
the mechanism); the second pins the specific mechanism so the failure names its
own cause.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_SCRIPTS_INIT = REPO_ROOT / "claude" / "skills" / "skill-create" / "scripts" / "__init__.py"


def test_serial_collection_of_the_integration_suite_reports_no_errors() -> None:
    """`-n 0` forces single-process collection — the mode that exposes #1432.

    Run in a subprocess: collecting the suite from inside itself is only safe
    with `--collect-only`, and a fresh interpreter is also what keeps the parent
    session's already-mutated `sys.modules` from masking the very failure this
    asserts against.
    """
    env = {k: v for k, v in os.environ.items() if k not in {"PYTEST_ADDOPTS", "PYTEST_CURRENT_TEST"}}
    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "tests/integration",
            "--collect-only",
            "-q",
            "-n",
            "0",
            "-p",
            "no:cacheprovider",
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert proc.returncode == 0, (
        "serial collection of tests/integration/ failed — the whole suite is "
        f"unrunnable via the command tests/AGENTS.md documents (exit {proc.returncode}).\n"
        f"--- stdout ---\n{proc.stdout[-4000:]}\n--- stderr ---\n{proc.stderr[-2000:]}"
    )
    assert "errors during collection" not in proc.stdout
    assert "Interrupted:" not in proc.stdout


def test_skill_create_scripts_stays_a_namespace_package_portion() -> None:
    """An `__init__.py` here re-shadows the repo-root `scripts/` namespace package.

    `test_skill_create_run_eval.py` has to put this directory on `sys.path` (see
    its module docstring — `run_eval`'s ProcessPoolExecutor pickles by qualified
    name, so the binding must persist). That is only harmless while this
    directory stays a namespace *portion*, merging with the repo-root `scripts/`
    instead of replacing it.
    """
    assert not SKILL_SCRIPTS_INIT.exists(), (
        f"{SKILL_SCRIPTS_INIT.relative_to(REPO_ROOT)} must not exist (#1432): a regular "
        "package here shadows the repo-root `scripts/` namespace package, and every "
        "`scripts.maintenance.*` import in the suite dies at collection time."
    )
