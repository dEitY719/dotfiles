"""Regression tests for issue #707 NF-1 — private company-skills repo must
never enter the dotfiles git history.

The dotfiles tree may host the *mechanism* (the overlay script and
`.gitignore` entry are #707 F-6), but it must never carry actual private
skill content. These tests pin both halves of that contract:

1. `git log --all --diff-filter=A -- "*company-skills*"` returns only
   approved mechanism paths (script, gitignore, tests, docs). No file
   beneath a top-level `company-skills/` directory has ever been added.
2. `.gitignore` declares `/company-skills/`, so a fresh clone-into-root
   is shielded by default.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent


ALLOWED_PATH_PREFIXES = (
    "scripts/setup-company-skills.sh",
    "tests/bats/functions/setup_company_skills.bats",
    "tests/integration/test_company_skills_safety.py",
)


def _git_added_paths_matching(pattern: str) -> list[str]:
    """All paths ever added (filter=A) across all refs that match
    pattern. Uses pathspec, not regex — pattern is a git glob."""
    out = subprocess.check_output(
        [
            "git",
            "log",
            "--all",
            "--diff-filter=A",
            "--name-only",
            "--pretty=format:",
            "--",
            pattern,
        ],
        cwd=REPO_ROOT,
        text=True,
    )
    return sorted({line.strip() for line in out.splitlines() if line.strip()})


def test_no_company_skills_content_in_git_history() -> None:
    """NF-1: the private repo's *content* must never have been committed.

    Approved mechanism paths (the overlay script, the bats test, this
    pytest) carry the literal substring `company-skills` but are not
    skill content — they are the SSOT-separating wrapper. Anything
    else is a leak.
    """
    added = _git_added_paths_matching("*company-skills*")
    leaks = [p for p in added if not p.startswith(ALLOWED_PATH_PREFIXES)]
    assert not leaks, f"Forbidden company-skills paths in git history (NF-1 violation): {leaks}"


def test_gitignore_blocks_company_skills_at_repo_root() -> None:
    """F-7: the dotfiles `.gitignore` must block `/company-skills/` so a
    user who accidentally clones the private repo into the dotfiles root
    is shielded.
    """
    gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert "/company-skills/" in gitignore, ".gitignore must declare `/company-skills/` (issue #707 F-7)"


def test_gitignore_actually_ignores_a_company_skills_path() -> None:
    """Belt-and-braces check on top of the literal grep: ask git itself
    whether a probe path inside `/company-skills/` would be ignored."""
    probe = "company-skills/secret-skill/SKILL.md"
    rc = subprocess.run(
        ["git", "check-ignore", "-q", probe],
        cwd=REPO_ROOT,
        check=False,
    ).returncode
    assert rc == 0, f"git check-ignore did not ignore {probe!r} — .gitignore rule missing or shadowed (issue #707 F-7)"
