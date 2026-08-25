"""Regression guard: `pytest tests/integration/` must collect cleanly (#1432).

The repo's default entry points (`mise run test`, `./tests/test`) inherit
`addopts = "-n auto"` from pyproject.toml, and xdist workers collect in separate
processes — so an import-time `sys.path` / `sys.modules` mutation made by one
test module never reaches the others, and the tests themselves still run. That
does *not* make a top-level module name collision invisible on that path: the
controller's own collection still errors, so pytest exits non-zero there too
(measured at #1432's pre-fix commit: `1350 passed, 1 error`, `EXIT=1`). What the
parallel path hides is the *scale* — the run reads as one broken module. Run
serially (`-n 0`), the same collision aborts collection for the *whole* suite:
in #1432 a single `ModuleNotFoundError` cost all 1350 tests. That is why this
guard shells out with `-n 0` — it is the only configuration where the assertion
sees the defect at its true size (#1448).

The collision was `scripts`: `claude/skills/skill-create/scripts/` carried an
(empty) `__init__.py`, making it a *regular* package, while the repo-root
`scripts/` has none and is a *namespace* package. A regular package always wins
the name, so once `test_skill_create_run_eval.py` put the skill dir on
`sys.path`, `scripts.maintenance` became unimportable for every later module.
Deleting that empty `__init__.py` turns both into namespace portions, which
*merge* — `scripts.run_eval` and `scripts.maintenance` now resolve side by side.

Four guards below. The first is behavioural (any future collision fails it,
whatever the mechanism) and also pins how *much* got collected, so a regression
that silently drops modules instead of erroring cannot pass. The rest pin the
three ways the merge can quietly come undone: the `__init__.py` returning, a
same-named module appearing in both portions, and the documented `python -m
scripts.*` entry point breaking.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_SCRIPTS = REPO_ROOT / "claude" / "skills" / "skill-create" / "scripts"
SKILL_SCRIPTS_INIT = SKILL_SCRIPTS / "__init__.py"
ROOT_SCRIPTS = REPO_ROOT / "scripts"

# A floor, deliberately not the exact count: the suite grows every week and an
# exact number would be a chore to bump, but a collapse from four figures to a
# handful is exactly the silent-drop regression this pins (PR #1435, codex).
MIN_COLLECTED = 1200

# Modules that must appear in the collected set. `test_trigger_eval_sets` is the
# one #1432 actually lost; `test_skill_create_run_eval` is the module whose
# `sys.path` insert makes the collision possible in the first place. Matched as
# bare filenames: pyproject's `addopts = "-v ..."` cancels the `-q` below, so
# collection prints the `<Module test_x.py>` tree rather than full node ids, and
# a filename is the one token both renderings share.
REQUIRED_MODULES = (
    "test_trigger_eval_sets.py",
    "test_skill_create_run_eval.py",
)

# pytest's `--collect-only -q` summary line, e.g. "==== 1512 tests collected in 0.3s ====".
# Deliberately unanchored: the count is wrapped in the `=` padding of a section header.
_COLLECTED_RE = re.compile(r"(\d+) tests? collected in ")


def test_serial_collection_of_the_integration_suite_reports_no_errors() -> None:
    """`-n 0` forces single-process collection — the mode that exposes #1432.

    Run in a subprocess: collecting the suite from inside itself is only safe
    with `--collect-only`, and a fresh interpreter is also what keeps the parent
    session's already-mutated `sys.modules` from masking the very failure this
    asserts against.
    """
    # Drop `PYTEST_ADDOPTS` so flags a CI or dev shell injects into the parent run
    # cannot reach the child and reshape what it collects.
    env = {k: v for k, v in os.environ.items() if k != "PYTEST_ADDOPTS"}
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
    # pytest reports a collection error as exit 2 (`Interrupted: N error(s) during
    # collection`), so a zero exit already means every module imported.
    assert proc.returncode == 0, (
        "serial collection of tests/integration/ failed — the whole suite is "
        f"unrunnable via the command tests/AGENTS.md documents (exit {proc.returncode}).\n"
        f"--- stdout ---\n{proc.stdout[-4000:]}\n--- stderr ---\n{proc.stderr[-2000:]}"
    )

    # Exit 0 alone would still pass if a module vanished from the collected set
    # without erroring — a deselect leaking in, a renamed path, a conftest that
    # skips a directory. Pin the size and the two modules that matter here.
    match = _COLLECTED_RE.search(proc.stdout)
    assert match, f"could not parse a 'N tests collected' line from:\n{proc.stdout[-2000:]}"
    collected = int(match.group(1))
    assert collected >= MIN_COLLECTED, (
        f"only {collected} tests collected, expected at least {MIN_COLLECTED} — "
        "the suite is being silently truncated rather than erroring."
    )
    for module in REQUIRED_MODULES:
        assert module in proc.stdout, f"{module} contributed no collected tests (#1432 regression)."


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


def _top_level_module_names(portion: Path) -> set[str]:
    """Names a namespace portion contributes to `scripts.*`: modules and subpackages."""
    if not portion.is_dir():
        return set()
    names = {p.stem for p in portion.glob("*.py") if p.stem != "__init__"}
    names |= {p.name for p in portion.iterdir() if p.is_dir() and any(p.glob("*.py"))}
    return names


def test_the_two_scripts_portions_contribute_disjoint_module_names() -> None:
    """Merging portions coexist only while no name appears in both (PR #1435, agy).

    Namespace portions merge, they do not overlay: when the same `scripts.<name>`
    exists on both sides, `sys.path` order alone decides the winner and the loser
    becomes unimportable — the #1432 failure again, one level down and just as
    silent. Today the skill dir holds the eval harness (`run_eval`, `utils`, …)
    and the repo root holds `maintenance`, so the sets are disjoint; this fails
    the moment someone adds, say, a repo-root `scripts/utils.py`.
    """
    overlap = _top_level_module_names(SKILL_SCRIPTS) & _top_level_module_names(ROOT_SCRIPTS)
    assert not overlap, (
        f"`scripts.{{{', '.join(sorted(overlap))}}}` exists in both "
        f"{SKILL_SCRIPTS.relative_to(REPO_ROOT)} and {ROOT_SCRIPTS.relative_to(REPO_ROOT)} — "
        "sys.path order decides which one wins and the other silently disappears. "
        "Rename one side."
    )


def test_the_skill_module_entry_point_still_runs() -> None:
    """`python -m scripts.run_loop` is the documented entry point — prove it, don't assume.

    `references/description-optimization.md` documents running the eval harness
    this way from the skill directory. Deleting `__init__.py` turned that package
    into a namespace portion, and the changelog claims the entry point is
    unaffected; this is the claim's proof rather than an assertion (PR #1435,
    codex). `--help` exercises the full import chain (`run_loop` imports
    `scripts.run_eval`, `scripts.utils`, …) and exits before doing any work.
    """
    proc = subprocess.run(
        [sys.executable, "-m", "scripts.run_loop", "--help"],
        cwd=SKILL_SCRIPTS.parent,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, (
        "`python -m scripts.run_loop --help` failed from the skill directory — the "
        f"documented entry point is broken (exit {proc.returncode}).\n"
        f"--- stdout ---\n{proc.stdout[-2000:]}\n--- stderr ---\n{proc.stderr[-2000:]}"
    )
    assert "usage: run_loop.py" in proc.stdout
