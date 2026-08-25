"""Tests for scripts/maintenance/check_gh_skill_host_pinning.py.

Issue #1407: PR #1404 introduced the `GH_HOST` pinning contract but applied
it to 6 of 19 `gh:*` skills by hand-copying a binding block. The remaining 13
kept 66 `gh` calls with no host (the issue counted 65 with a narrower ad-hoc
regex), several of them writes (`gh pr merge --admin`, `gh pr review
--approve`, `gh api -X DELETE`). Nothing detected the gap.

These tests pin the checker's rules, and the last one is the regression gate:
every executable `gh` call in the shipped `claude/skills/gh-*` tree must carry
both halves of the contract.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
SCRIPT = REPO_ROOT / "scripts" / "maintenance" / "check_gh_skill_host_pinning.py"
SKILLS_DIR = REPO_ROOT / "claude" / "skills"


def _make_skill(skills_dir: Path, name: str, body: str, filename: str = "SKILL.md") -> None:
    skill_dir = skills_dir / name
    (skill_dir / filename).parent.mkdir(parents=True, exist_ok=True)
    (skill_dir / filename).write_text(body, encoding="utf-8")


def _run(skills_dir: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--skills-dir", str(skills_dir), *extra],
        capture_output=True,
        text=True,
        timeout=60,
    )


@pytest.fixture
def skills_root(tmp_path: Path) -> Path:
    root = tmp_path / "skills"
    root.mkdir()
    return root


class TestHostPinning:
    def test_bare_gh_call_is_a_violation(self, skills_root: Path) -> None:
        _make_skill(skills_root, "gh-demo", '```bash\ngh pr merge 5 --repo "$TARGET_REPO" --admin\n```\n')
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing GH_HOST= prefix" in result.stdout

    def test_host_pinned_call_passes(self, skills_root: Path) -> None:
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh pr merge 5 --repo "$TARGET_REPO" --admin\n```\n',
        )
        assert _run(skills_root).returncode == 0

    def test_hostname_flag_counts_as_pinned(self, skills_root: Path) -> None:
        """`gh api --hostname "$HOST" -i user` pins the host without the env prefix."""
        _make_skill(skills_root, "gh-demo", '```bash\ngh api --hostname "$HOST" -i user\n```\n')
        assert _run(skills_root).returncode == 0

    def test_command_substitution_is_scanned(self, skills_root: Path) -> None:
        _make_skill(skills_root, "gh-demo", "```bash\nME=$(gh api user -q .login)\n```\n")
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing GH_HOST= prefix" in result.stdout


class TestRepoScoping:
    def test_missing_repo_flag_is_a_violation(self, skills_root: Path) -> None:
        _make_skill(skills_root, "gh-demo", '```bash\nGH_HOST="$TARGET_HOST" gh pr view 5 --json labels\n```\n')
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing --repo" in result.stdout

    def test_repo_flag_on_a_continuation_line_counts(self, skills_root: Path) -> None:
        """A wrapped command is judged whole, not one physical line at a time."""
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh run list \\\n    --repo "$TARGET_REPO" --limit 50\n```\n',
        )
        assert _run(skills_root).returncode == 0

    def test_repo_less_subcommand_is_exempt(self, skills_root: Path) -> None:
        """`gh gist create` has no --repo flag; the host still has to be pinned."""
        _make_skill(skills_root, "gh-demo", '```bash\nGH_HOST="$TARGET_HOST" gh gist create "$patch" --desc x\n```\n')
        assert _run(skills_root).returncode == 0

    def test_gh_api_literal_placeholder_is_a_violation(self, skills_root: Path) -> None:
        """`{owner}/{repo}` makes gh resolve the repo implicitly — the #1403 bug."""
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh api -X DELETE "repos/{owner}/{repo}/issues/5/labels/conflict"\n```\n',
        )
        result = _run(skills_root)
        assert result.returncode == 1
        assert "placeholder" in result.stdout

    def test_gh_api_repo_variable_passes(self, skills_root: Path) -> None:
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh api -X DELETE "repos/$TARGET_REPO/issues/5/labels/conflict"\n```\n',
        )
        assert _run(skills_root).returncode == 0

    def test_gh_api_non_repo_path_is_exempt(self, skills_root: Path) -> None:
        _make_skill(
            skills_root, "gh-demo", '```bash\nGH_HOST="$TARGET_HOST" gh api "gists/$GIST_ID" --jq .files\n```\n'
        )
        assert _run(skills_root).returncode == 0


class TestPrVerbWithoutPositional:
    """`gh pr <verb>` with no PR argument reads the PR off the current branch,
    and gh REFUSES `--repo` in that mode:

        $ gh pr view --repo owner/repo --json number
        argument required when using the --repo flag

    The first cut of #1407 required `--repo` unconditionally, which broke four
    skills' branch auto-detect paths (PR #1425 review, agy). The contract
    inverts here: host pinned, repo flag forbidden.
    """

    def test_repo_flag_without_a_pr_argument_is_a_violation(self, skills_root: Path) -> None:
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh pr view --repo "$TARGET_REPO" --json number\n```\n',
        )
        result = _run(skills_root)
        assert result.returncode == 1
        assert "must NOT pass --repo" in result.stdout

    def test_host_only_branch_autodetect_passes(self, skills_root: Path) -> None:
        _make_skill(skills_root, "gh-demo", '```bash\nGH_HOST="$TARGET_HOST" gh pr view --json number\n```\n')
        assert _run(skills_root).returncode == 0

    def test_a_pr_argument_still_requires_repo(self, skills_root: Path) -> None:
        """The exemption is narrow — with a positional, --repo is mandatory again."""
        _make_skill(skills_root, "gh-demo", '```bash\nGH_HOST="$TARGET_HOST" gh pr view 5 --json state\n```\n')
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing --repo" in result.stdout

    def test_quoted_and_placeholder_positionals_count_as_arguments(self, skills_root: Path) -> None:
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh pr view "$PR_NUMBER" --repo "$TARGET_REPO"\n'
            'GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO"\n```\n',
        )
        assert _run(skills_root).returncode == 0

    def test_verbs_that_take_no_positional_still_require_repo(self, skills_root: Path) -> None:
        """`gh pr create` / `gh pr list` accept no PR argument at all, so the
        inversion must not reach them — an earlier cut of this rule flagged
        every `gh pr create --repo` in the repo as a violation.
        """
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh pr create --repo "$GH_REPO" --title x --body y\n'
            'GH_HOST="$TARGET_HOST" gh pr list --repo "$GH_REPO" --state open\n```\n',
        )
        assert _run(skills_root).returncode == 0


class TestShellKeywordPrefixes:
    """`if ! gh ...` is a copy-pasteable executable shape the first cut missed,
    even though the regex comment claimed if-style prefixes were covered
    (PR #1425 review, codex).
    """

    def test_if_bang_prefix_is_scanned(self, skills_root: Path) -> None:
        _make_skill(skills_root, "gh-demo", '```bash\nif ! gh pr merge 5 --repo "$TARGET_REPO"; then\n```\n')
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing GH_HOST= prefix" in result.stdout

    def test_if_prefix_with_pinned_call_passes(self, skills_root: Path) -> None:
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nif ! GH_HOST="$TARGET_HOST" gh pr merge 5 --repo "$TARGET_REPO"; then\n```\n',
        )
        assert _run(skills_root).returncode == 0


class TestPipedCommands:
    def test_a_later_commands_repo_flag_does_not_satisfy_an_earlier_one(self, skills_root: Path) -> None:
        """Judging the whole line let a piped second call's --repo mask the
        first call's missing one (PR #1425 review, agy)."""
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$H" gh pr diff 5 | GH_HOST="$H" gh pr edit 6 --repo "$TARGET_REPO"\n```\n',
        )
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing --repo" in result.stdout


class TestSearchIsRepoScoped:
    def test_gh_search_requires_repo(self, skills_root: Path) -> None:
        """`gh search issues|prs` does take -R/--repo, so exempting `search`
        hid real calls (PR #1425 review, agy)."""
        _make_skill(skills_root, "gh-demo", '```bash\nGH_HOST="$TARGET_HOST" gh search issues "in:body foo"\n```\n')
        result = _run(skills_root)
        assert result.returncode == 1
        assert "missing --repo" in result.stdout

    def test_gh_search_with_repo_passes(self, skills_root: Path) -> None:
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\nGH_HOST="$TARGET_HOST" gh search issues --repo "$TARGET_REPO" "in:body foo"\n```\n',
        )
        assert _run(skills_root).returncode == 0


class TestScanScope:
    def test_reference_files_are_scanned_too(self, skills_root: Path) -> None:
        """Most of #1407's unpinned calls lived in references/, not SKILL.md."""
        _make_skill(
            skills_root,
            "gh-demo",
            '```bash\ngh pr review 5 --repo "$TARGET_REPO" --approve\n```\n',
            filename="references/approval-templates.md",
        )
        assert _run(skills_root).returncode == 1

    def test_non_gh_skills_are_not_scanned(self, skills_root: Path) -> None:
        _make_skill(skills_root, "devx-demo", "```bash\ngh pr merge 5 --admin\n```\n")
        assert _run(skills_root).returncode == 0

    def test_missing_skills_dir_exits_2(self, tmp_path: Path) -> None:
        assert _run(tmp_path / "nope").returncode == 2

    def test_prose_mention_of_a_command_is_not_flagged(self, skills_root: Path) -> None:
        """Documented boundary: skills name commands in prose without running them.

        Flagging `gh pr view --json rebaseable` where the text explains that the
        flag fails would make the checker noise, so mid-sentence fragments are
        out of scope - only line-initial calls and `$(...)` are executable.
        """
        _make_skill(
            skills_root,
            "gh-demo",
            "The `rebaseable` field is REST-only; `gh pr view --json rebaseable` fails.\n",
        )
        assert _run(skills_root).returncode == 0


def test_shipped_gh_skills_are_all_host_pinned() -> None:
    """Regression gate for #1407 — the contract holds across every gh:* skill.

    Verified to fail on the pre-fix tree with 66 unpinned calls in 13 skills,
    and to stay silent on the 6 skills PR #1404 had already fixed.
    """
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--skills-dir", str(SKILLS_DIR), "--quiet"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"unpinned gh calls found:\n{result.stdout}"


def test_gate_actually_scanned_the_gh_skill_tree() -> None:
    """Exit 0 alone is not proof — an empty scan also exits 0.

    Without this, a moved `claude/skills/`, a renamed prefix, or an over-broad
    exemption would leave the gate silently green (PR #1425 review, agy).
    """
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--skills-dir", str(SKILLS_DIR)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stdout
    match = re.search(r"in (\d+) skill\(s\)", result.stdout)
    assert match, f"checker did not report a scanned-skill count:\n{result.stdout}"
    assert int(match.group(1)) >= 15, f"only {match.group(1)} gh-* skills scanned — the tree moved or the prefix broke"

    # And the files inside them are really being read: the shipped tree must
    # contain executable gh calls for the gate to be meaningful at all.
    md_with_gh = [p for p in SKILLS_DIR.glob("gh-*/**/*.md") if "GH_HOST=" in p.read_text(encoding="utf-8")]
    assert len(md_with_gh) >= 20, f"only {len(md_with_gh)} skill docs carry a pinned gh call — scan scope is wrong"
