"""Tests for scripts/maintenance/check_split_skill_repos.py.

Issue #1671: the #1410 split left two blind spots. `claude/plugin/*.json` was
only ever compared against itself (`tests/bats/tools/claude_plugin_scaffold.bats`
matches strings against a hand-written table), so a remote repo could rename its
plugin or vanish outright and the suite stayed green. And #1410 NF-1 keeps the
dotfiles originals alive until Phase 4, so every split skill exists twice with
nothing watching the two copies for drift.

NF-1 of this issue forbids putting either check in the offline suite. These
tests therefore exercise the checker's *pure* logic on fixtures only — the
network path lives behind `RemoteSource` and is never touched here.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from scripts.maintenance.check_split_skill_repos import (
    Target,
    check_manifest_contract,
    compare_skills,
    load_registration,
    name_vocabulary,
    pair_skills,
    read_skill_tree,
    run_audit,
    split_repo_targets,
)

REPO_ROOT = Path(__file__).parent.parent.parent

# The one skill body the pairing and audit fixtures are built from. Written
# once so the deliberate one-line variant below reads as the only difference.
CONFLICT_BODY = "Rebase onto base.\nResolve hunks by intent.\nPush with lease.\n"


@pytest.fixture(scope="module")
def registration() -> tuple[dict[str, str], list[str]]:
    """The shipped registration SSOT, read through the checker's own reader."""
    return load_registration(REPO_ROOT)


class TestTargetDerivation:
    """NF-2: adding a repo must not add a hand-maintained row anywhere."""

    def test_derives_targets_from_the_registration_ssot(self) -> None:
        marketplaces = {
            "gh-resolve-skills": "dEitY719/gh-resolve-skills",
            "obsidian-skills": "kepano/obsidian-skills",
            "claude-plugins-official": "anthropics/claude-plugins-official",
        }
        plugins = ["gh-resolve@gh-resolve-skills", "obsidian@obsidian-skills"]

        targets = split_repo_targets(marketplaces, plugins, owner="dEitY719")

        assert [(t.marketplace, t.repo, t.plugins) for t in targets] == [
            ("gh-resolve-skills", "dEitY719/gh-resolve-skills", ("gh-resolve",)),
        ]

    def test_third_party_skills_repo_is_not_a_split_target(self) -> None:
        """`kepano/obsidian-skills` ends in -skills but is nobody's split-out copy."""
        targets = split_repo_targets(
            {"obsidian-skills": "kepano/obsidian-skills"},
            ["obsidian@obsidian-skills"],
            owner="dEitY719",
        )
        assert targets == []

    def test_registered_marketplace_with_no_plugin_entry_is_reported(self) -> None:
        """A marketplace nobody installs is a registration gap, not a silent skip."""
        targets = split_repo_targets(
            {"gh-resolve-skills": "dEitY719/gh-resolve-skills"},
            [],
            owner="dEitY719",
        )
        assert [(t.marketplace, t.plugins) for t in targets] == [("gh-resolve-skills", ())]


class TestManifestContract:
    """F-1: the registered id must be installable against the real remote."""

    MANIFEST = {
        "name": "gh-resolve-skills",
        "plugins": [{"name": "gh-resolve", "source": "./"}],
    }

    def _target(self, plugin: tuple[str, ...] = ("gh-resolve",)) -> Target:
        return Target("gh-resolve-skills", "dEitY719/gh-resolve-skills", plugin)

    def test_matching_manifest_reports_no_violation(self) -> None:
        assert check_manifest_contract(self._target(), self.MANIFEST) == []

    def test_renamed_remote_plugin_is_a_violation(self) -> None:
        manifest = {"name": "gh-resolve-skills", "plugins": [{"name": "gh-fix"}]}
        violations = check_manifest_contract(self._target(), manifest)
        assert len(violations) == 1
        assert "gh-resolve" in violations[0] and "gh-fix" in violations[0]

    def test_renamed_remote_marketplace_is_a_violation(self) -> None:
        manifest = {"name": "gh-resolve-plugins", "plugins": [{"name": "gh-resolve"}]}
        violations = check_manifest_contract(self._target(), manifest)
        assert len(violations) == 1
        assert "gh-resolve-plugins" in violations[0]

    def test_plugin_beyond_the_first_entry_still_matches(self) -> None:
        """A multi-plugin marketplace is legal; only presence of the id matters."""
        manifest = {
            "name": "gh-resolve-skills",
            "plugins": [{"name": "other"}, {"name": "gh-resolve"}],
        }
        assert check_manifest_contract(self._target(), manifest) == []

    def test_unreachable_remote_is_a_violation(self) -> None:
        violations = check_manifest_contract(self._target(), None)
        assert len(violations) == 1
        assert "unreachable" in violations[0].lower() or "no .claude-plugin" in violations[0].lower()

    def test_marketplace_with_no_plugins_json_entry_is_a_violation(self) -> None:
        violations = check_manifest_contract(self._target(plugin=()), self.MANIFEST)
        assert len(violations) == 1
        assert "plugins.json" in violations[0]


class TestDriftNormalization:
    """F-2: the four transformations a #1410 split applies are not drift.

    Each is a real thing `gh-resolve-skills` did to `gh-pr-resolve-conflict`.
    """

    def test_namespace_rewrite_is_not_drift(self) -> None:
        local = {"SKILL.md": "Not a clean base sync (gh:pr-resolve-outdated).\n"}
        remote = {"SKILL.md": "Not a clean base sync (gh-resolve:outdated).\n"}
        assert compare_skills(local, remote).content_drift == []

    def test_slash_command_rewrite_is_not_drift(self) -> None:
        local = {"SKILL.md": "Use for /gh:pr-resolve-conflict, /gh-pr-resolve-conflict.\n"}
        remote = {"SKILL.md": "Use for /gh-resolve:conflict.\n"}
        assert compare_skills(local, remote).content_drift == []

    def test_heading_level_change_is_not_drift(self) -> None:
        local = {"SKILL.md": "## Step 2: Fetch + Rebase\n"}
        remote = {"SKILL.md": "### Step 2: Fetch + Rebase\n"}
        assert compare_skills(local, remote).content_drift == []

    def test_ai_metrics_footer_flattening_is_not_drift(self) -> None:
        local = {"SKILL.md": "<details><summary>AI Metrics</summary>\nElapsed time recorded.\n</details>\n"}
        remote = {"SKILL.md": "Elapsed time recorded.\n"}
        assert compare_skills(local, remote).content_drift == []

    def test_progressive_disclosure_split_is_not_drift(self) -> None:
        """The #1671 headline false positive: a 100-line-cap extraction."""
        local = {
            "SKILL.md": (
                "## Step 3: Conflict Resolution Loop\n"
                "Resolve each conflicted hunk by intent, never by `--ours`.\n"
                "Re-run the failing test after every hunk.\n"
            )
        }
        remote = {
            "SKILL.md": ("## Step 3: Conflict Resolution Loop\nDetail: `references/step5-helpers.md`.\n"),
            "references/step5-helpers.md": (
                "Resolve each conflicted hunk by intent, never by `--ours`.\n"
                "Re-run the failing test after every hunk.\n"
            ),
        }
        assert compare_skills(local, remote).content_drift == []

    def test_frontmatter_trigger_surface_is_excluded(self) -> None:
        local = {
            "SKILL.md": (
                "---\nname: gh:pr-resolve-conflict\n"
                "description: Rebase-resolve a PR.\nallowed-tools: Bash\n---\nBody.\n"
            )
        }
        remote = {
            "SKILL.md": (
                "---\nname: conflict\ndescription: Totally re-authored trigger text.\nallowed-tools: Bash\n---\nBody.\n"
            )
        }
        assert compare_skills(local, remote).content_drift == []

    def test_allowed_tools_change_is_drift(self) -> None:
        """Frontmatter is not blanket-ignored — only the trigger surface is."""
        local = {"SKILL.md": "---\nname: a\nallowed-tools: Bash, Read\n---\nBody.\n"}
        remote = {"SKILL.md": "---\nname: b\nallowed-tools: Bash\n---\nBody.\n"}
        assert compare_skills(local, remote).content_drift != []


class TestDriftDetection:
    """F-2: a real one-sided edit must survive all of that normalization."""

    def test_changed_instruction_is_drift(self) -> None:
        local = {"SKILL.md": "Push with `--force-with-lease`.\n"}
        remote = {"SKILL.md": "Push with `--force`.\n"}
        report = compare_skills(local, remote)
        assert report.content_drift
        assert any("force-with-lease" in line for line in report.only_local)
        assert any("`--force`" in line for line in report.only_remote)

    def test_step_dropped_from_one_side_is_drift(self) -> None:
        local = {
            "SKILL.md": "Run the preflight.\nVerify mergeable.\n",
            "references/safety.md": "Never push to a protected branch.\n",
        }
        remote = {"SKILL.md": "Run the preflight.\nVerify mergeable.\n"}
        report = compare_skills(local, remote)
        assert any("protected branch" in line for line in report.only_local)

    def test_identical_skills_score_full_similarity(self) -> None:
        files = {"SKILL.md": "Run the preflight.\nVerify mergeable.\n"}
        assert compare_skills(files, dict(files)).similarity == 1.0


class TestPairing:
    """NF-2: `gh-resolve:conflict` -> `gh-pr-resolve-conflict` with no table.

    The remote name is not derivable from the local one (`conflict` vs
    `gh-pr-resolve-conflict`), so the pairing is made on content.
    """

    LOCAL = {
        "gh-pr-resolve-conflict": {"SKILL.md": CONFLICT_BODY},
        "gh-pr-resolve-outdated": {"SKILL.md": "Sync a clean base.\nNo conflicts expected.\nPush with lease.\n"},
        "write-rca": {"SKILL.md": "Write a postmortem.\nName the root cause.\nList the timeline.\n"},
    }

    def test_pairs_a_renamed_skill_to_its_original(self) -> None:
        remote = {"conflict": {"SKILL.md": CONFLICT_BODY}}
        (pairing,) = pair_skills(remote, self.LOCAL)
        assert (pairing.remote_name, pairing.local_name) == ("conflict", "gh-pr-resolve-conflict")

    def test_unpairable_skill_is_reported_not_skipped(self) -> None:
        remote = {"brand-new": {"SKILL.md": "Provision a Kubernetes cluster.\nApply the manifest.\n"}}
        (pairing,) = pair_skills(remote, self.LOCAL)
        assert pairing.local_name is None
        assert "no dotfiles original" in pairing.note

    def test_ambiguous_pairing_is_refused(self) -> None:
        """Two near-identical candidates must not be guessed between."""
        local = {
            "skill-a": {"SKILL.md": "Run the preflight.\nVerify mergeable.\n"},
            "skill-b": {"SKILL.md": "Run the preflight.\nVerify mergeable.\n"},
        }
        remote = {"thing": {"SKILL.md": "Run the preflight.\nVerify mergeable.\n"}}
        (pairing,) = pair_skills(remote, local)
        assert pairing.local_name is None
        assert "ambiguous" in pairing.note

    def test_one_local_original_is_not_claimed_by_two_remotes(self) -> None:
        remote = {
            "conflict": {"SKILL.md": CONFLICT_BODY},
            "conflict-copy": {"SKILL.md": "Rebase onto base.\nResolve hunks by intent.\n"},
        }
        pairs = {p.remote_name: p.local_name for p in pair_skills(remote, self.LOCAL)}
        assert pairs["conflict"] == "gh-pr-resolve-conflict"
        assert pairs["conflict-copy"] is None


class TestSkillTreeLoading:
    def test_reads_skill_md_and_references_keyed_by_relative_path(self, tmp_path: Path) -> None:
        skill = tmp_path / "skills" / "conflict"
        (skill / "references").mkdir(parents=True)
        (skill / "SKILL.md").write_text("Body.\n", encoding="utf-8")
        (skill / "references" / "help.md").write_text("Help.\n", encoding="utf-8")
        (skill / "evals").mkdir()
        (skill / "evals" / "trigger-eval.json").write_text("{}", encoding="utf-8")

        tree = read_skill_tree(tmp_path / "skills")

        assert set(tree) == {"conflict"}
        assert set(tree["conflict"]) == {"SKILL.md", "references/help.md"}

    def test_directory_without_a_skill_md_is_not_a_skill(self, tmp_path: Path) -> None:
        (tmp_path / "skills" / "docs").mkdir(parents=True)
        (tmp_path / "skills" / "docs" / "notes.md").write_text("x", encoding="utf-8")
        assert read_skill_tree(tmp_path / "skills") == {}

    def test_missing_directory_reads_as_empty(self, tmp_path: Path) -> None:
        assert read_skill_tree(tmp_path / "nope") == {}


class _FakeSource:
    """Stands in for the network so NF-1 holds: these tests never reach out."""

    def __init__(self, manifests: dict, skills: dict) -> None:
        self._manifests = manifests
        self._skills = skills

    def marketplace_manifest(self, repo: str) -> dict | None:
        return self._manifests.get(repo)

    def skill_tree(self, repo: str) -> dict[str, dict[str, str]]:
        return self._skills.get(repo, {})


class TestAudit:
    REPO = "dEitY719/gh-resolve-skills"
    MANIFEST = {"name": "gh-resolve-skills", "plugins": [{"name": "gh-resolve"}]}
    LOCAL = {"gh-pr-resolve-conflict": {"SKILL.md": CONFLICT_BODY}}

    def _audit(
        self,
        *,
        manifest: dict | None = None,
        remote_body: str | None = None,
        checks: str = "all",
    ) -> object:
        """Audit one target, stating only what this test varies.

        `manifest=None` is an unreachable repo; `remote_body=None` a repo with
        no skills/ — both are the "absent" case the checker must still report.
        """
        source = _FakeSource(
            {self.REPO: manifest} if manifest is not None else {},
            {self.REPO: {"conflict": {"SKILL.md": remote_body}}} if remote_body is not None else {},
        )
        return run_audit([Target("gh-resolve-skills", self.REPO, ("gh-resolve",))], self.LOCAL, source, checks=checks)

    def test_faithful_port_is_clean(self) -> None:
        result = self._audit(manifest=self.MANIFEST, remote_body=CONFLICT_BODY)
        assert result.findings == []
        assert result.exit_code == 0

    def test_remote_plugin_rename_is_caught(self) -> None:
        result = self._audit(
            manifest={"name": "gh-resolve-skills", "plugins": [{"name": "renamed"}]},
            remote_body=CONFLICT_BODY,
        )
        assert result.exit_code == 1
        assert any("renamed" in f for f in result.findings)

    def test_one_sided_edit_is_caught_as_drift(self) -> None:
        result = self._audit(
            manifest=self.MANIFEST,
            remote_body="Rebase onto base.\nResolve hunks by intent.\nPush with force.\n",
        )
        assert result.exit_code == 1
        assert any("conflict" in f and "gh-pr-resolve-conflict" in f for f in result.findings)

    def test_contract_only_run_ignores_drift(self) -> None:
        result = self._audit(
            manifest=self.MANIFEST,
            remote_body="Completely different procedure.\n",
            checks="contract",
        )
        assert result.exit_code == 0

    def test_unreachable_repo_fails_the_audit(self) -> None:
        result = self._audit()
        assert result.exit_code == 1
        assert any("unreachable" in f for f in result.findings)


class TestShippedRegistration:
    """Offline guard on the wiring NF-2 depends on."""

    def test_every_dotfiles_skills_marketplace_is_a_derived_target(
        self, registration: tuple[dict[str, str], list[str]]
    ) -> None:
        marketplaces, plugins = registration

        targets = split_repo_targets(marketplaces, plugins, owner="dEitY719")
        expected = {k for k, v in marketplaces.items() if v.startswith("dEitY719/") and v.endswith("-skills")}

        assert {t.marketplace for t in targets} == expected
        assert expected, "no split-out marketplaces registered — did the SSOT move?"

    def test_every_derived_target_has_an_installing_plugin_entry(
        self, registration: tuple[dict[str, str], list[str]]
    ) -> None:
        """Catches a marketplace registered but never installed, offline."""
        marketplaces, plugins = registration

        orphans = [t.marketplace for t in split_repo_targets(marketplaces, plugins, owner="dEitY719") if not t.plugins]
        assert orphans == []


class TestSkillNameVocabulary:
    """A split rewrites skill names in prose too, not only in slash commands.

    `[[gh-discussion-create]]` becomes `[[gh-issue:discussion-create]]`; a
    `## gh-pr-resolve-ci-fail: Constraints` heading becomes
    `## gh-resolve:ci-fail: Constraints`. The colon-form is already normalized;
    the bare form needs the names of the skills actually under comparison,
    which is data both trees already carry (NF-2 — still no table).
    """

    VOCAB = frozenset({"gh-discussion-create", "discussion-create", "gh-pr-resolve-ci-fail"})

    def test_bare_skill_name_from_the_vocabulary_is_normalized(self) -> None:
        local = {"SKILL.md": "Sister skill [[gh-discussion-create]] creates it.\n"}
        remote = {"SKILL.md": "Sister skill [[discussion-create]] creates it.\n"}
        assert compare_skills(local, remote, vocabulary=self.VOCAB).content_drift == []

    def test_hyphenated_non_skill_token_is_left_alone(self) -> None:
        """`--force-with-lease` must never be mistaken for a skill name."""
        local = {"SKILL.md": "Push with `--force-with-lease`.\n"}
        remote = {"SKILL.md": "Push with `--force-with-leash`.\n"}
        assert compare_skills(local, remote, vocabulary=self.VOCAB).content_drift != []

    def test_single_word_skill_names_are_not_vocabulary(self) -> None:
        """`read` and `create` are English before they are skill names."""
        vocab = name_vocabulary({"gh-issue-read": {}}, {"read": {}, "gh-issue:read": {}})
        assert "read" not in vocab
        assert "gh-issue-read" in vocab

    def test_reference_path_matches_under_any_prefix(self) -> None:
        """`claude/skills/<name>/references/x.md` vs `skills/issue/references/x.md`."""
        local = {"SKILL.md": "See `claude/skills/gh-issue-implement/references/flow.md` for detail.\n"}
        remote = {"SKILL.md": "See `skills/implement/references/flow.md` for detail.\n"}
        assert compare_skills(local, remote).content_drift == []

    def test_vocabulary_is_derived_from_both_trees(self) -> None:
        vocab = name_vocabulary({"gh-pr-resolve-conflict": {}}, {"resolve-conflict": {}})
        assert {"gh-pr-resolve-conflict", "resolve-conflict"} <= vocab


class TestInvocationFormNormalization:
    """Found by running the checker against the 13 live repos (#1671).

    Both cases produced identical instruction text on each side and were still
    reported — the kind of false positive that trains people to ignore a gate.
    """

    def test_leading_slash_on_an_invocation_is_not_drift(self) -> None:
        """`/devx-session-close` vs `devx:session-close`: same call, one written bare."""
        local = {"SKILL.md": "  /devx-session-close   # alias form (hyphen)\n"}
        remote = {"SKILL.md": "  session:close   # alias form (hyphen)\n"}
        vocab = name_vocabulary({"devx-session-close": {}}, {"close": {}})
        assert compare_skills(local, remote, vocabulary=vocab).content_drift == []

    def test_reference_path_to_a_non_markdown_file_matches_under_any_prefix(self) -> None:
        """`references/compute-fire-time.py` is an extracted file like any other."""
        local = {"SKILL.md": "Run `claude/skills/devx-rate-limit-guard/references/compute-fire-time.py HH MM 5`.\n"}
        remote = {"SKILL.md": "Run `skills/rate-limit-guard/references/compute-fire-time.py HH MM 5`.\n"}
        assert compare_skills(local, remote).content_drift == []

    def test_wikilink_brackets_around_a_skill_name_are_not_drift(self) -> None:
        """dotfiles cross-links skills as `[[name]]`; a split writes them plain."""
        local = {"SKILL.md": "Crosses the [[devx-pr-verify-merged]] boundary; #1417 measured the cost.\n"}
        remote = {"SKILL.md": "Crosses the gh-verify:merged boundary; #1417 measured the cost.\n"}
        vocab = name_vocabulary({"devx-pr-verify-merged": {}}, {"merged": {}})
        assert compare_skills(local, remote, vocabulary=vocab).content_drift == []


class TestMultiPluginMarketplace:
    """PR #1691 review, codex + agy BLOCKER: a marketplace may ship several plugins.

    `check_manifest_contract` already tolerated a multi-plugin remote, but the
    target derivation feeding it kept only the last `plugins.json` entry per
    marketplace — so every earlier plugin went silently unverified.
    """

    def test_all_registered_plugins_for_one_marketplace_survive_derivation(self) -> None:
        targets = split_repo_targets(
            {"gh-resolve-skills": "dEitY719/gh-resolve-skills"},
            ["gh-resolve@gh-resolve-skills", "gh-extra@gh-resolve-skills"],
            owner="dEitY719",
        )
        assert [t.plugins for t in targets] == [("gh-extra", "gh-resolve")]

    def test_a_plugin_missing_from_the_remote_is_a_violation_even_when_a_sibling_matches(self) -> None:
        target = Target("gh-resolve-skills", "dEitY719/gh-resolve-skills", ("gh-resolve", "gh-extra"))
        manifest = {"name": "gh-resolve-skills", "plugins": [{"name": "gh-resolve"}]}
        violations = check_manifest_contract(target, manifest)
        assert len(violations) == 1
        assert "gh-extra" in violations[0]

    def test_every_registered_plugin_present_is_clean(self) -> None:
        target = Target("gh-resolve-skills", "dEitY719/gh-resolve-skills", ("gh-resolve", "gh-extra"))
        manifest = {"name": "gh-resolve-skills", "plugins": [{"name": "gh-extra"}, {"name": "gh-resolve"}]}
        assert check_manifest_contract(target, manifest) == []


class TestUnpairedIsNotSilent:
    """PR #1691 review, codex BLOCKER: drift bad enough to break pairing exited 0.

    A skill drifts out of similarity range precisely *because* the drift is
    severe, so routing "unpaired" to a note made the worst cases the quiet
    ones. Phase 4 still has to stay quiet, hence the sibling rule: an unpaired
    skill is a finding only while some other skill in the same repo still
    pairs — i.e. the dotfiles originals are still there to drift from.
    """

    LOCAL = {
        "gh-pr-resolve-conflict": {"SKILL.md": CONFLICT_BODY},
        "gh-pr-resolve-outdated": {"SKILL.md": "Sync a clean base.\nNo conflicts expected.\nPush with lease.\n"},
    }
    MANIFEST = {"name": "gh-resolve-skills", "plugins": [{"name": "gh-resolve"}]}

    def _audit(self, remote_skills: dict, local: dict | None = None) -> object:
        source = _FakeSource(
            {"dEitY719/gh-resolve-skills": self.MANIFEST},
            {"dEitY719/gh-resolve-skills": remote_skills},
        )
        target = Target("gh-resolve-skills", "dEitY719/gh-resolve-skills", ("gh-resolve",))
        return run_audit([target], self.LOCAL if local is None else local, source, checks="drift")

    def test_unpaired_skill_beside_a_paired_sibling_fails_the_audit(self) -> None:
        result = self._audit(
            {
                "conflict": {"SKILL.md": CONFLICT_BODY},
                "outdated": {"SKILL.md": "Provision a Kubernetes cluster.\nApply the manifest.\n"},
            }
        )
        assert result.exit_code == 1
        assert any("outdated" in f and "unpaired" in f for f in result.findings)

    def test_a_wholly_unpaired_repo_stays_quiet(self) -> None:
        """Phase 4 deleted the originals — every skill is legitimately unpaired."""
        result = self._audit({"conflict": {"SKILL.md": CONFLICT_BODY}}, local={})
        assert result.exit_code == 0
        assert result.findings == []
        assert result.notes

    def test_runner_up_is_tried_when_the_top_match_is_already_claimed(self) -> None:
        """PR #1691 review, agy FOLLOW-UP: a claimed top match discarded the rest."""
        pairs = {
            p.remote_name: p.local_name
            for p in pair_skills(
                {
                    "conflict": {"SKILL.md": CONFLICT_BODY},
                    "outdated": {"SKILL.md": self.LOCAL["gh-pr-resolve-outdated"]["SKILL.md"]},
                },
                self.LOCAL,
            )
        }
        assert pairs == {"conflict": "gh-pr-resolve-conflict", "outdated": "gh-pr-resolve-outdated"}


class TestFailOnScope:
    """PR #1691 review, agy BLOCKER: the workflow swallowed the audit's exit code.

    The `| tee` pipeline returned tee's status under the runner's default
    `bash -e` (no pipefail), so a failing audit reported success. The fix is
    not just pipefail — that would turn the 23 known Phase 2-3 drift findings
    permanently red. `--fail-on` makes the intent explicit instead: contract
    breakage is always actionable and gates; drift is reported while the
    two-copy window lasts.
    """

    MANIFEST_BAD = {"name": "gh-resolve-skills", "plugins": [{"name": "renamed"}]}
    LOCAL = {"gh-pr-resolve-conflict": {"SKILL.md": CONFLICT_BODY}}

    def _audit(self, manifest: dict, remote: dict, fail_on: str) -> object:
        source = _FakeSource({"dEitY719/gh-resolve-skills": manifest}, {"dEitY719/gh-resolve-skills": remote})
        target = Target("gh-resolve-skills", "dEitY719/gh-resolve-skills", ("gh-resolve",))
        return run_audit([target], self.LOCAL, source, fail_on=fail_on)

    def test_drift_alone_does_not_gate_under_fail_on_contract(self) -> None:
        result = self._audit(
            {"name": "gh-resolve-skills", "plugins": [{"name": "gh-resolve"}]},
            {"conflict": {"SKILL.md": "Rebase onto base.\nResolve hunks by intent.\nPush with force.\n"}},
            fail_on="contract",
        )
        assert result.findings, "drift must still be reported"
        assert result.exit_code == 0

    def test_contract_breakage_gates_under_fail_on_contract(self) -> None:
        result = self._audit(self.MANIFEST_BAD, {"conflict": {"SKILL.md": CONFLICT_BODY}}, fail_on="contract")
        assert result.exit_code == 1

    def test_fail_on_any_is_the_default_and_gates_on_drift(self) -> None:
        result = self._audit(
            {"name": "gh-resolve-skills", "plugins": [{"name": "gh-resolve"}]},
            {"conflict": {"SKILL.md": "Rebase onto base.\nResolve hunks by intent.\nPush with force.\n"}},
            fail_on="any",
        )
        assert result.exit_code == 1
