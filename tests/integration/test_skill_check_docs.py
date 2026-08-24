"""Drift guards for the documented `skill:check` audit contract."""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SKILL_CHECK_DIR = REPO_ROOT / "claude" / "skills" / "skill-check"


def test_sixteen_check_contract_is_consistent_across_docs() -> None:
    skill = (SKILL_CHECK_DIR / "SKILL.md").read_text(encoding="utf-8")
    help_md = (SKILL_CHECK_DIR / "references" / "help.md").read_text(encoding="utf-8")
    checks = (SKILL_CHECK_DIR / "references" / "checks.md").read_text(encoding="utf-8")
    report = (SKILL_CHECK_DIR / "references" / "report-template.md").read_text(encoding="utf-8")

    assert "Run Sixteen Checks" in skill
    assert "all 16 check definitions" in skill
    assert "Checks run (16 total):" in help_md
    assert "Sixteen checks" in checks
    assert "### Check 12: Executable Procedure Extraction" in checks
    assert "### Check 15: Capability Declaration Consistency" in checks
    assert "### Check 16: Description Length" in checks
    assert "| 12 | Executable Procedure Extraction |" in report
    assert "| 15 | Capability Declaration Consistency |" in report
    assert "| 16 | Description Length " in report
    assert "16 checks total" in report


def test_capability_check_still_covers_legacy_scripts_layout() -> None:
    checks = (SKILL_CHECK_DIR / "references" / "checks.md").read_text(encoding="utf-8")
    skill = (SKILL_CHECK_DIR / "SKILL.md").read_text(encoding="utf-8")

    assert "legacy `scripts/` layouts" in checks
    assert "`lib/`, legacy `scripts/`, and adjacent executables" in skill


def test_check16_thresholds_match_the_executable_mirror() -> None:
    """Check 16's thresholds live in two places by design (prose + fixture).

    checks.md tells the reader to keep them byte-identical; without this guard
    that instruction is only a hope. The fixture is the executable form used by
    scripts/measure-skill-descriptions.sh, so a silent drift would make the
    reported verdict disagree with the documented contract.
    """
    fixture = (REPO_ROOT / "tests" / "bats" / "skills" / "_fixtures" / "skill_description_length.sh").read_text(
        encoding="utf-8"
    )

    pass_max = re.search(r"^SKILL_DESC_PASS_MAX=(\d+)$", fixture, re.MULTILINE)
    warn_max = re.search(r"^SKILL_DESC_WARN_MAX=(\d+)$", fixture, re.MULTILINE)
    assert pass_max is not None, "fixture must define SKILL_DESC_PASS_MAX"
    assert warn_max is not None, "fixture must define SKILL_DESC_WARN_MAX"

    checks = (SKILL_CHECK_DIR / "references" / "checks.md").read_text(encoding="utf-8")
    help_md = (SKILL_CHECK_DIR / "references" / "help.md").read_text(encoding="utf-8")
    skill = (SKILL_CHECK_DIR / "SKILL.md").read_text(encoding="utf-8")
    guide = (REPO_ROOT / "claude" / "skills" / "skill-create" / "references" / "skill-writing-guide.md").read_text(
        encoding="utf-8"
    )

    for doc in (checks, help_md, skill, guide):
        assert pass_max.group(1) in doc
        assert warn_max.group(1) in doc


def test_check16_mirror_is_pinned_by_bats() -> None:
    """The executable mirror must stay under test, not drift as dead code."""
    bats = (REPO_ROOT / "tests" / "bats" / "skills" / "skill_check_description_length.bats").read_text(encoding="utf-8")

    assert "_fixtures/skill_description_length.sh" in bats
    for fn in ("skill_desc_extract", "skill_desc_length", "skill_desc_verdict"):
        assert fn in bats
