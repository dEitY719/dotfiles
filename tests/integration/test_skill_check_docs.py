"""Drift guards for the documented `skill:check` audit contract."""

from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SKILL_CHECK_DIR = REPO_ROOT / "claude" / "skills" / "skill-check"


def test_fifteen_check_contract_is_consistent_across_docs() -> None:
    skill = (SKILL_CHECK_DIR / "SKILL.md").read_text(encoding="utf-8")
    help_md = (SKILL_CHECK_DIR / "references" / "help.md").read_text(encoding="utf-8")
    checks = (SKILL_CHECK_DIR / "references" / "checks.md").read_text(encoding="utf-8")
    report = (SKILL_CHECK_DIR / "references" / "report-template.md").read_text(encoding="utf-8")

    assert "Run Fifteen Checks" in skill
    assert "all 15 check definitions" in skill
    assert "Checks run (15 total):" in help_md
    assert "Fifteen checks" in checks
    assert "### Check 12: Executable Procedure Extraction" in checks
    assert "### Check 15: Capability Declaration Consistency" in checks
    assert "| 12 | Executable Procedure Extraction |" in report
    assert "| 15 | Capability Declaration Consistency |" in report
    assert "15 checks total" in report


def test_capability_check_still_covers_legacy_scripts_layout() -> None:
    checks = (SKILL_CHECK_DIR / "references" / "checks.md").read_text(encoding="utf-8")
    skill = (SKILL_CHECK_DIR / "SKILL.md").read_text(encoding="utf-8")

    assert "legacy `scripts/` layouts" in checks
    assert "`lib/`, legacy `scripts/`, and adjacent executables" in skill
