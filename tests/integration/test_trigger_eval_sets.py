"""Structural guards for the SKILL.md trigger-eval query sets (issue #1417).

These sets are the only instrument that can catch a description which is short
enough for Check 16 and yet no longer triggers. The measurement itself costs API
budget and lives in the manual harness `claude/tools/run-trigger-eval.sh`; what
runs in CI is everything about the sets that can be checked for free.

The invariants below are the ones that make a *comparison* valid rather than
merely well-formed:

- a fixed 10/10 split, so a score is directly a percentage and the 5%p contract
  in `claude/skills/skill-check/references/trigger-eval-procedure.md` is
  meaningful;
- bidirectional cross-pair coverage, so a competing pair's misfire is measured
  in both directions instead of assumed;
- the `#1410` note on every slash-command literal, so the rename that issue
  performs knows exactly which queries it invalidates.
"""

import json
import re
from functools import cache
from pathlib import Path
from typing import Any

import pytest

from scripts.maintenance.check_codex_skills_budget import parse_skill_md

REPO_ROOT = Path(__file__).parent.parent.parent
SKILLS_DIR = REPO_ROOT / "claude" / "skills"

ALLOWED_KEYS = {"query", "should_trigger", "note"}
QUERIES_PER_SET = 20
EXPECTED_PER_CLASS = QUERIES_PER_SET // 2
RENAME_NOTE = "slash-literal: update if the skill is renamed (#1410)"

# The #1417 sample. The issue calls it "표본 13종" by counting group C as three
# *pairs*; a pair needs a file on each side for the bidirectional cross-check
# below, so the sample is 13 units and 16 files.
SAMPLE_A_LONGEST_SHRINK = [
    "claude-plugin-structure-refactor",
    "devx-mise-migrate",
    "devx-md-to-scrolldeck",
    "devx-restart",
    "gh-issue-relay-flow",
]
SAMPLE_B_HIGH_FREQUENCY = [
    "gh-issue-create",
    "gh-commit",
    "gh-pr",
    "gh-pr-reply",
    "gh-issue-flow",
]
SAMPLE_C_COMPETING_PAIRS = [
    ("skill-check", "sh-check"),
    ("gh-pr-resolve-conflict", "gh-pr-resolve-outdated"),
    ("devx-pr-verify-live", "devx-pr-verify-merged"),
]
SAMPLE_SKILLS = [
    *SAMPLE_A_LONGEST_SHRINK,
    *SAMPLE_B_HIGH_FREQUENCY,
    *[s for pair in SAMPLE_C_COMPETING_PAIRS for s in pair],
]

# Every set actually on disk. The invariants below are properties of the
# artifact, not of #1417's roster, so they are parametrized over what exists.
# Keying them to SAMPLE_SKILLS instead would leave the 17th set — added by the
# #1410 rename, or by the next description shrink — guarded by nothing while CI
# stayed green. SAMPLE_SKILLS still guards the other direction: a sample skill
# whose set went missing.
ALL_EVAL_SETS = sorted(p.parent.parent.name for p in SKILLS_DIR.glob("*/evals/trigger-eval.json"))

# Minimum queries each side of a competing pair must borrow from the other side's
# should-trigger list. Four of ten keeps the cross-check the dominant signal in
# the reject class without crowding out the third-competitor cases.
MIN_CROSS_PAIR = 4

# Ceiling on slash-literal queries per set, so #1410's rename cannot invalidate
# more than a fraction of any set. See test_majority_of_queries_survive_a_rename.
MAX_SLASH_LITERALS = 3

EMOJI = re.compile("[\U0001f000-\U0001faff☀-➿]")


def eval_path(skill: str) -> Path:
    return SKILLS_DIR / skill / "evals" / "trigger-eval.json"


# Every set is read by six parametrized tests and never mutated, so both the
# bytes and the parsed form are cached per worker instead of per assertion.
@cache
def raw(skill: str) -> str:
    return eval_path(skill).read_text(encoding="utf-8")


@cache
def load(skill: str) -> list[dict[str, Any]]:
    data: list[dict[str, Any]] = json.loads(raw(skill))
    return data


def queries(skill: str, *, trigger: bool) -> set[str]:
    return {q["query"] for q in load(skill) if q["should_trigger"] is trigger}


def skill_command_literals() -> set[str]:
    """Every form a skill can be named by in a slash command.

    Both the directory name (`sh-check`) and the frontmatter `name:`
    (`sh:check`) are in use in user-facing text, and #1410 rewrites both. The
    `name:` half comes from the repo's existing frontmatter parser rather than
    a local scan, so it stays bounded to the frontmatter block and handles the
    quoted and folded forms the same way Check 16's own tooling does.
    """
    literals: set[str] = set()
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        literals.add(skill_md.parent.name)
        literals.add(parse_skill_md(skill_md, skill_md.parent.name)[0])
    return literals


COMMAND_LITERALS = skill_command_literals()

# One alternation over all ~142 literals rather than one search per literal per
# query. Longest-first so a shorter name cannot shadow a longer one that starts
# with it. The leading-boundary anchor is load-bearing: a bare
# `f"/{name}" in query` also matches file paths like
# `claude/skills/gh-commit/SKILL.md`, which the #1410 rename does not
# invalidate the way a `/gh:commit` literal does.
SLASH_LITERAL_RE = re.compile(
    r"(?:^|\s)/(?:" + "|".join(re.escape(n) for n in sorted(COMMAND_LITERALS, key=len, reverse=True)) + r")\b"
)


def has_slash_literal(query: str) -> bool:
    """True when the query invokes a skill by slash command."""
    return SLASH_LITERAL_RE.search(query) is not None


@pytest.mark.parametrize("skill", SAMPLE_SKILLS)
def test_sample_skill_has_an_eval_set(skill: str) -> None:
    assert eval_path(skill).is_file(), f"{skill} is in the #1417 sample but has no evals/trigger-eval.json"


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_set_shape_makes_the_score_a_percentage(skill: str) -> None:
    data = load(skill)
    assert isinstance(data, list), f"{skill}: expected a flat array"
    assert len(data) == QUERIES_PER_SET, f"{skill}: {len(data)} queries, want {QUERIES_PER_SET}"

    triggering = [q for q in data if q["should_trigger"] is True]
    rejecting = [q for q in data if q["should_trigger"] is False]
    assert len(triggering) == EXPECTED_PER_CLASS, f"{skill}: {len(triggering)} should-trigger"
    assert len(rejecting) == EXPECTED_PER_CLASS, f"{skill}: {len(rejecting)} should-not-trigger"


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_entries_carry_only_known_keys(skill: str) -> None:
    for entry in load(skill):
        extra = set(entry) - ALLOWED_KEYS
        assert not extra, f"{skill}: unexpected keys {extra} on {entry['query'][:40]!r}"
        assert isinstance(entry["query"], str) and entry["query"].strip()
        assert isinstance(entry["should_trigger"], bool)


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_no_duplicate_queries(skill: str) -> None:
    """A duplicate would be scored twice and silently double-weight one case."""
    seen = [q["query"] for q in load(skill)]
    assert len(seen) == len(set(seen)), f"{skill}: duplicate query text"


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_slash_literals_are_marked_for_the_rename(skill: str) -> None:
    """#1410 renames every namespace; these are the queries it invalidates."""
    for entry in load(skill):
        if has_slash_literal(entry["query"]):
            assert RENAME_NOTE in entry.get("note", ""), (
                f"{skill}: slash-literal query missing the #1410 note: {entry['query'][:60]!r}"
            )


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_majority_of_queries_survive_a_rename(skill: str) -> None:
    """Natural-language queries are the fixed points #1410 compares across.

    A set built mostly from slash literals would have to be rewritten by the
    rename, and could not show whether the rename changed triggering.
    """
    data = load(skill)
    literal_count = sum(1 for q in data if has_slash_literal(q["query"]))
    assert literal_count <= MAX_SLASH_LITERALS, (
        f"{skill}: {literal_count} slash-literal queries, want <= {MAX_SLASH_LITERALS}"
    )


@pytest.mark.parametrize(("left", "right"), SAMPLE_C_COMPETING_PAIRS)
def test_competing_pairs_cross_check_in_both_directions(left: str, right: str) -> None:
    """Each side must reject the other side's should-trigger queries.

    Testing one direction only would leave the more damaging misfire unmeasured:
    for `gh:pr-resolve-conflict` vs `gh:pr-resolve-outdated`, firing the conflict
    skill on a clean base sync and firing the sync skill on a real conflict are
    different failures with different costs.
    """
    forward = queries(left, trigger=False) & queries(right, trigger=True)
    backward = queries(right, trigger=False) & queries(left, trigger=True)

    assert len(forward) >= MIN_CROSS_PAIR, (
        f"{left} rejects only {len(forward)} of {right}'s trigger queries, want >= {MIN_CROSS_PAIR}"
    )
    assert len(backward) >= MIN_CROSS_PAIR, (
        f"{right} rejects only {len(backward)} of {left}'s trigger queries, want >= {MIN_CROSS_PAIR}"
    )

    for skill, shared in ((left, forward), (right, backward)):
        marked = {q["query"] for q in load(skill) if "cross-pair" in q.get("note", "")}
        assert shared <= marked, f"{skill}: cross-pair queries missing their note"


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_no_emojis_in_query_sets(skill: str) -> None:
    """Repo-wide rule; the ai-metrics footer is the only sanctioned exception."""
    for entry in load(skill):
        assert not EMOJI.search(entry["query"]), f"{skill}: emoji in {entry['query'][:40]!r}"


@pytest.mark.parametrize("skill", ALL_EVAL_SETS)
def test_korean_is_stored_as_literal_utf8(skill: str) -> None:
    """`\\uXXXX` escapes are valid JSON but unreadable in review diffs."""
    assert "\\u" not in raw(skill), f"{skill}: contains \\uXXXX escapes, want literal UTF-8"


def test_harness_and_procedure_are_cross_referenced() -> None:
    """The sets are useless without the harness that knows how to isolate them."""
    harness = REPO_ROOT / "claude" / "tools" / "run-trigger-eval.sh"
    procedure = SKILLS_DIR / "skill-check" / "references" / "trigger-eval-procedure.md"

    assert harness.is_file(), "the trigger-eval harness is missing"
    assert procedure.is_file(), "the trigger-eval procedure doc is missing"

    procedure_text = procedure.read_text(encoding="utf-8")
    assert "claude/tools/run-trigger-eval.sh" in procedure_text
    assert "trigger-eval.json" in procedure_text

    checks = (SKILLS_DIR / "skill-check" / "references" / "checks.md").read_text(encoding="utf-8")
    assert "trigger-eval-procedure.md" in checks, (
        "Check 16 must point at the trigger-accuracy harness it cannot itself measure"
    )

    harness_text = harness.read_text(encoding="utf-8")
    assert "--num-workers 1" in harness_text, (
        "run_eval must stay serial inside a job; concurrent probes shadow each other"
    )
