#!/usr/bin/env python3
"""
Split-Skill-Repo Contract + Drift Checker (#1671)

Guards the two things the #1410 skill split left unverified.

F-1  Remote contract
    `tests/bats/tools/claude_plugin_scaffold.bats` compares
    `claude/plugin/marketplaces.json` and `plugins.json` against a table
    written by hand in the same file. Nothing compares them against the repos
    they name. `dEitY719/gh-resolve-skills` could rename its plugin from
    `gh-resolve` to anything, or stop existing, and the suite stays green while
    `/plugin install gh-resolve@gh-resolve-skills` fails for everyone.

F-2  Content drift
    #1410 NF-1 keeps the dotfiles originals in `claude/skills/` until Phase 4
    retires them, so every split skill lives in two places for the whole of
    Phase 2-3. A fix or prompt improvement landing on one side only is
    invisible today.

Why drift is not a file diff
    The split is a re-authoring, not a copy: the `gh:pr-resolve-conflict`
    namespace becomes `gh-resolve:conflict`, the directory prefix is dropped,
    the ai-metrics footer is flattened, and a SKILL.md over the 100-line budget
    is broken out into `references/`. `gh-resolve-skills` did all four at once,
    so `diff -r` reports total disagreement on a faithful port. This checker
    compares the *union* of SKILL.md and references/ as a normalized line set —
    the procedure a skill instructs, not the files it is spread across.

Why the pairing has no table (NF-2)
    Split repos are derived from the registration SSOT: an entry in
    `marketplaces.json` owned by --owner whose repo name ends in `-skills`.
    Within a repo, each remote skill is paired to its dotfiles original by
    normalized-content similarity, so a new phase adds nothing to maintain
    here. An unpairable skill is reported, never silently skipped.

Why this is not in the bats/pytest suite (NF-1)
    F-1 and F-2 both need the network; `mise run test` is offline and runs in
    parallel worktrees. The network path lives behind `RemoteSource` and is
    driven by `.github/workflows/split-skill-repo-audit.yml` on a schedule.
    `tests/integration/test_split_skill_repos.py` exercises the pure logic on
    fixtures only.

Usage:
    python3 check_split_skill_repos.py [--check contract|drift|all]
                                       [--repo-root PATH] [--owner NAME]
                                       [--quiet]

Exit codes:
    0  every registered split repo honors its contract and shows no drift
    1  at least one contract violation or content drift
    2  error (registration SSOT missing or unreadable)
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol


class Colors:
    RESET = "\033[0m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"


@dataclass(frozen=True)
class Target:
    """One registered split-out skills repo."""

    marketplace: str
    repo: str
    plugin: str | None


def split_repo_targets(
    marketplaces: dict[str, str],
    plugins: list[str],
    owner: str,
) -> list[Target]:
    """Derive the split-out repo set from the registration SSOT (NF-2).

    A marketplace qualifies when it is owned by `owner` and its repo name ends
    in `-skills`. `kepano/obsidian-skills` matches the suffix but not the
    owner, so it is not one of ours; `dEitY719/dotfiles` is ours but is not a
    split-out repo.

    `plugin` is None when nothing in `plugins.json` installs the marketplace —
    a registration gap worth reporting rather than skipping.
    """
    by_marketplace = {}
    for entry in plugins:
        plugin, _, marketplace = entry.partition("@")
        if marketplace:
            by_marketplace[marketplace] = plugin

    targets = []
    for marketplace, repo in sorted(marketplaces.items()):
        repo_owner, _, repo_name = repo.partition("/")
        if repo_owner != owner or not repo_name.endswith("-skills"):
            continue
        targets.append(Target(marketplace, repo, by_marketplace.get(marketplace)))
    return targets


def check_manifest_contract(target: Target, manifest: dict[str, Any] | None) -> list[str]:
    """F-1: does the remote actually honor `<plugin>@<marketplace>`?

    `manifest` is the remote `.claude-plugin/marketplace.json`, or None when the
    repo or that file could not be fetched — which is itself the loudest kind of
    broken contract, so it is reported rather than skipped.

    Any entry in the manifest's `plugins` array counts: a marketplace is allowed
    to ship several, and which one sits at index 0 is not part of the install id.
    """
    if target.plugin is None:
        return [
            f"{target.marketplace}: registered in marketplaces.json but no "
            f"`<plugin>@{target.marketplace}` entry in plugins.json — nothing installs it"
        ]

    if manifest is None:
        return [
            f"{target.marketplace}: {target.repo} unreachable, or it has no "
            f".claude-plugin/marketplace.json — `{target.plugin}@{target.marketplace}` "
            f"cannot be installed"
        ]

    violations = []

    remote_marketplace = manifest.get("name")
    if remote_marketplace != target.marketplace:
        violations.append(
            f"{target.marketplace}: {target.repo} calls itself "
            f"'{remote_marketplace}' — marketplaces.json registers it as "
            f"'{target.marketplace}'"
        )

    remote_plugins = [p.get("name") for p in manifest.get("plugins", []) if isinstance(p, dict)]
    if target.plugin not in remote_plugins:
        violations.append(
            f"{target.marketplace}: plugins.json installs "
            f"'{target.plugin}@{target.marketplace}' but {target.repo} ships "
            f"{remote_plugins or 'no plugins'}"
        )

    return violations


# --------------------------------------------------------------------------
# F-2 — drift detection
#
# Every regex below cancels one transformation a #1410 split legitimately
# applies. Anything a split does NOT do must survive them, or the checker
# reports nothing and F-2 is theatre.
# --------------------------------------------------------------------------

# `gh:pr-resolve-conflict` -> `gh-resolve:conflict`, and the `/`-prefixed
# forms of both. Requires a hyphen on one side so plain prose colons
# ("Usage:", "Note: see") and URLs are left alone.
_NAMESPACED = re.compile(r"/?\b[a-z][a-z0-9]*(?:-[a-z0-9]+)*:[a-z0-9]+(?:-[a-z0-9]+)*\b(?!//)")
# `/gh-pr-resolve-conflict` — the dash-form alias of the same skill.
_SLASH_DASH = re.compile(r"/[a-z][a-z0-9]*(?:-[a-z0-9]+)+\b")
# `references/rebase-flow.md` — the seam a progressive-disclosure split adds.
# The prefix is deliberately greedy: the same file is `claude/skills/
# gh-issue-implement/references/flow.md` here and `skills/implement/references/
# flow.md` there, and the differing prefix is the rename, not a content change.
_REF_PATH = re.compile(r"`?(?:[\w.@/-]*/)?references/[a-z0-9._-]+\.[a-z0-9]+`?")
# The ai-metrics footer is flattened during a split: HTML wrapper and glyphs go.
# `<summary>` is the disclosure widget's own label — part of the wrapper, not an
# instruction — so the element goes with its text, before bare tags are stripped.
_SUMMARY = re.compile(r"<summary>.*?</summary>", re.DOTALL)
_HTML_TAG = re.compile(r"</?[a-z][a-z0-9]*(?:\s[^>]*)?>")
_EMOJI = re.compile(r"[\U0001F300-\U0001FAFF←-⇿☀-➿️]")
# Markdown scaffolding that a re-layout renumbers or re-levels.
_LEADING_MARKUP = re.compile(r"^\s*(?:#{1,6}\s+|[-*+]\s+|\d+\.\s+|>\s+)+")
# A run of skill placeholders left by listing the same skill's several aliases.
_PLACEHOLDER_RUN = re.compile(r"<skill>(?:[,/·\s]+<skill>)+")
# `/devx-session-close` and `devx:session-close` are the same invocation; only
# the colon-form carries its slash into the placeholder, so level them.
_PLACEHOLDER_SLASH = re.compile(r"/+<skill>")
# dotfiles cross-links a sibling skill as `[[name]]`; a split writes it plain,
# so the wikilink brackets travel with the name they wrap.
_PLACEHOLDER_WIKILINK = re.compile(r"\[\[<skill>\]\]")
# A line that only points at an extracted reference file, with an optional
# short lead-in ("detail", "see", "full procedure"). This is exactly what a
# 100-line-cap extraction leaves behind in SKILL.md, so it is structural.
_PURE_POINTER = re.compile(r"^(?:[a-z ]{0,24}[:\-]?\s*)?<ref>[.:]?$")

# Frontmatter keys that a split re-authors by design: the skill's own name and
# the trigger surface that names it. Everything else in the frontmatter
# (allowed-tools, metadata.model_recommendation) is contract and is compared.
_TRIGGER_KEYS = ("name", "description")


def _strip_frontmatter(text: str) -> str:
    """Drop `name:` / `description:` from a leading YAML block, keep the rest.

    Blanket-ignoring the frontmatter would hide an `allowed-tools` divergence,
    which is a real capability change; keeping the trigger surface would flag
    every split, since re-namespacing the description is the point of one.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    try:
        end = lines.index("---", 1)
    except ValueError:
        return text

    kept, skipping = [], False
    for line in lines[1:end]:
        if re.match(r"^\S", line):
            skipping = line.split(":", 1)[0].strip() in _TRIGGER_KEYS
        if not skipping:
            kept.append(line)
    return "\n".join(kept + lines[end + 1 :])


def name_vocabulary(*trees: dict[str, dict[str, str]]) -> frozenset[str]:
    """The bare skill names worth treating as renames, taken from the trees.

    A split rewrites skill names in prose as well as in slash commands:
    `[[gh-discussion-create]]` becomes `[[gh-issue:discussion-create]]`, and a
    `## gh-pr-resolve-ci-fail: Constraints` heading becomes
    `## gh-resolve:ci-fail: Constraints`. Only the colon-forms are structural
    enough for a regex; the bare forms need to be recognized by name.

    Single-word names are excluded on purpose. `read`, `create`, `implement`
    and `conflict` are all shipped skill names in the split repos and all
    ordinary English besides — normalizing them away would erase most of the
    prose being compared. They still normalize in their namespaced form
    (`gh-issue:read`), which is how a split actually writes them.
    """
    return frozenset(name for tree in trees for name in tree if "-" in name)


def normalize_line(line: str, vocabulary: frozenset[str] = frozenset()) -> str:
    """Reduce one line to the instruction it carries, or "" if it carries none."""
    line = _SUMMARY.sub(" ", line)
    line = _HTML_TAG.sub(" ", line)
    line = _EMOJI.sub(" ", line)
    line = _LEADING_MARKUP.sub("", line)
    line = _REF_PATH.sub("<ref>", line)
    line = _NAMESPACED.sub("<skill>", line)
    for name in sorted(vocabulary, key=len, reverse=True):
        line = re.sub(rf"(?<![\w-]){re.escape(name)}(?![\w-])", "<skill>", line)
    line = _SLASH_DASH.sub("<skill>", line)
    line = _PLACEHOLDER_SLASH.sub("<skill>", line)
    line = _PLACEHOLDER_WIKILINK.sub("<skill>", line)
    line = _PLACEHOLDER_RUN.sub("<skill>", line)
    return re.sub(r"\s+", " ", line).strip().lower()


def is_structural(line: str) -> bool:
    """True for a normalized line that only points at an extracted reference."""
    return bool(_PURE_POINTER.match(line))


def skill_fingerprint(files: dict[str, str], vocabulary: frozenset[str] = frozenset()) -> set[str]:
    """The set of instruction lines a skill carries, across all its files.

    The union is what makes a `references/` extraction invisible: a block moved
    out of SKILL.md is still in the set, just sourced from a different file.
    """
    lines = set()
    for text in files.values():
        for raw in _strip_frontmatter(text).splitlines():
            normalized = normalize_line(raw, vocabulary)
            if normalized and not is_structural(normalized):
                lines.add(normalized)
    return lines


@dataclass
class DriftReport:
    only_local: list[str] = field(default_factory=list)
    only_remote: list[str] = field(default_factory=list)
    similarity: float = 1.0

    @property
    def content_drift(self) -> list[str]:
        return self.only_local + self.only_remote


def compare_skills(
    local_files: dict[str, str],
    remote_files: dict[str, str],
    vocabulary: frozenset[str] = frozenset(),
) -> DriftReport:
    """Compare two copies of one skill as procedures, not as file trees."""
    local = skill_fingerprint(local_files, vocabulary)
    remote = skill_fingerprint(remote_files, vocabulary)

    union = local | remote
    similarity = len(local & remote) / len(union) if union else 1.0
    return DriftReport(
        only_local=sorted(local - remote),
        only_remote=sorted(remote - local),
        similarity=similarity,
    )


# A pairing needs both a floor and a lead over the runner-up. The floor keeps a
# brand-new skill from being force-matched to the least-unlike original; the
# lead keeps two sibling skills (`gh-pr-resolve-conflict` / `-outdated` share
# their preflight and push steps almost verbatim) from being coin-flipped.
PAIR_MIN_SIMILARITY = 0.35
PAIR_MIN_MARGIN = 0.05


@dataclass
class Pairing:
    remote_name: str
    local_name: str | None
    similarity: float = 0.0
    note: str = ""
    report: DriftReport | None = None


def pair_skills(
    remote_skills: dict[str, dict[str, str]],
    local_skills: dict[str, dict[str, str]],
    min_similarity: float = PAIR_MIN_SIMILARITY,
    min_margin: float = PAIR_MIN_MARGIN,
) -> list[Pairing]:
    """Match each remote skill to its dotfiles original by content (NF-2).

    A split renames the skill (`gh-pr-resolve-conflict` -> `conflict`) and its
    namespace, so nothing in the name survives to key on. What does survive is
    the procedure, which is what `skill_fingerprint` measures.

    Pairing is greedy by descending confidence and each original is claimed at
    most once: two remote skills matching the same original means one of them
    is a copy nobody meant to keep, and reporting it as unpaired surfaces that
    rather than double-counting the drift.
    """
    vocabulary = name_vocabulary(local_skills, remote_skills)
    local_prints = {name: skill_fingerprint(files, vocabulary) for name, files in local_skills.items()}

    scored = []
    for remote_name, remote_files in remote_skills.items():
        remote_print = skill_fingerprint(remote_files, vocabulary)
        ranked = sorted(
            (
                (
                    len(remote_print & lp) / len(remote_print | lp) if (remote_print | lp) else 0.0,
                    local_name,
                )
                for local_name, lp in local_prints.items()
            ),
            reverse=True,
        )
        scored.append((remote_name, remote_files, ranked))

    scored.sort(key=lambda item: item[2][0][0] if item[2] else 0.0, reverse=True)

    claimed: set[str] = set()
    pairings = []
    for remote_name, remote_files, ranked in scored:
        best_score, best_name = ranked[0] if ranked else (0.0, None)
        runner_up = next((s for s, n in ranked[1:] if n not in claimed), 0.0)

        if best_name is None or best_score < min_similarity:
            note = f"no dotfiles original above {min_similarity:.0%} similarity"
        elif best_name in claimed:
            note = f"'{best_name}' is already paired with another skill in this repo"
        elif best_score - runner_up < min_margin:
            note = f"ambiguous — '{best_name}' and the runner-up score within {min_margin:.0%}"
        else:
            claimed.add(best_name)
            pairings.append(
                Pairing(
                    remote_name=remote_name,
                    local_name=best_name,
                    similarity=best_score,
                    report=compare_skills(local_skills[best_name], remote_files, vocabulary),
                )
            )
            continue

        pairings.append(Pairing(remote_name=remote_name, local_name=None, similarity=best_score, note=note))

    return sorted(pairings, key=lambda p: p.remote_name)


def read_skill_tree(skills_dir: Path) -> dict[str, dict[str, str]]:
    """Load `<skills_dir>/<skill>/{SKILL.md,references/*.md}` keyed by relative path.

    Used for both sides of the comparison: the dotfiles originals, and a split
    repo's `skills/` after it has been cloned. `evals/` and everything else is
    left out — a trigger-eval fixture is not part of the procedure, and its
    absence on one side is not drift.
    """
    if not skills_dir.is_dir():
        return {}

    tree: dict[str, dict[str, str]] = {}
    for skill_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue
        files = {"SKILL.md": skill_md.read_text(encoding="utf-8", errors="replace")}
        for ref in sorted((skill_dir / "references").glob("*.md")):
            files[f"references/{ref.name}"] = ref.read_text(encoding="utf-8", errors="replace")
        tree[skill_dir.name] = files
    return tree


class GitCloneRemoteSource:
    """The network half of the audit — the only part `mise run test` never runs.

    A shallow clone beats walking the contents API: one request instead of one
    per file, and the clone is then read back through the same `read_skill_tree`
    the local side uses, so neither side can drift in how it is parsed.
    """

    def __init__(self, workdir: Path, host: str = "https://github.com") -> None:
        self._workdir = workdir
        self._host = host.rstrip("/")
        self._clones: dict[str, Path | None] = {}

    def _clone(self, repo: str) -> Path | None:
        if repo not in self._clones:
            dest = self._workdir / repo.replace("/", "__")
            completed = subprocess.run(
                ["git", "clone", "--depth", "1", "--quiet", f"{self._host}/{repo}.git", str(dest)],
                capture_output=True,
                text=True,
                timeout=180,
            )
            self._clones[repo] = dest if completed.returncode == 0 else None
        return self._clones[repo]

    def marketplace_manifest(self, repo: str) -> dict[str, Any] | None:
        clone = self._clone(repo)
        if clone is None:
            return None
        manifest = clone / ".claude-plugin" / "marketplace.json"
        if not manifest.is_file():
            return None
        try:
            parsed: dict[str, Any] = json.loads(manifest.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return None
        return parsed

    def skill_tree(self, repo: str) -> dict[str, dict[str, str]]:
        clone = self._clone(repo)
        return read_skill_tree(clone / "skills") if clone is not None else {}


class RemoteSource(Protocol):
    """The one seam the offline suite substitutes (NF-1)."""

    def marketplace_manifest(self, repo: str) -> dict[str, Any] | None: ...

    def skill_tree(self, repo: str) -> dict[str, dict[str, str]]: ...


@dataclass
class AuditResult:
    findings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    @property
    def exit_code(self) -> int:
        return 1 if self.findings else 0


def run_audit(
    targets: list[Target],
    local_skills: dict[str, dict[str, str]],
    source: RemoteSource,
    checks: str = "all",
) -> AuditResult:
    """Run F-1 and/or F-2 over every derived target.

    `source` is anything with `marketplace_manifest(repo)` and `skill_tree(repo)`
    — the seam that keeps the network out of the offline suite (NF-1).
    """
    result = AuditResult()

    for target in targets:
        manifest = source.marketplace_manifest(target.repo)

        if checks in ("all", "contract"):
            result.findings.extend(check_manifest_contract(target, manifest))

        if checks not in ("all", "drift"):
            continue

        remote_skills = source.skill_tree(target.repo)
        if not remote_skills:
            # Silent when the contract half already said the repo is
            # unreachable; a reachable repo with no skills/ is worth a note.
            if manifest is not None:
                result.notes.append(f"{target.marketplace}: no skills/ directory in {target.repo}")
            continue

        for pairing in pair_skills(remote_skills, local_skills):
            if pairing.local_name is None:
                # Not a finding: #1410 Phase 4 deletes the originals, after
                # which every skill is legitimately unpaired.
                result.notes.append(f"{target.marketplace}: '{pairing.remote_name}' unpaired — {pairing.note}")
                continue

            report = pairing.report
            if report is None or not report.content_drift:
                continue

            result.findings.append(
                f"{target.marketplace}: '{pairing.remote_name}' has drifted from "
                f"claude/skills/{pairing.local_name} "
                f"({report.similarity:.0%} similar, "
                f"{len(report.only_local)} line(s) only in dotfiles, "
                f"{len(report.only_remote)} only in the split repo)"
            )
            for line in report.only_local[:5]:
                result.findings.append(f"    only in dotfiles: {line}")
            for line in report.only_remote[:5]:
                result.findings.append(f"    only in {target.repo}: {line}")

    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify #1410 split-out skill repos against their registration (#1671).",
    )
    parser.add_argument("--check", choices=("all", "contract", "drift"), default="all")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--owner", default="dEitY719")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    plugin_dir = args.repo_root / "claude" / "plugin"
    try:
        marketplaces = json.loads((plugin_dir / "marketplaces.json").read_text(encoding="utf-8"))
        plugins = json.loads((plugin_dir / "plugins.json").read_text(encoding="utf-8"))["plugins"]
    except (OSError, json.JSONDecodeError, KeyError) as exc:
        print(f"{Colors.RED}[FAIL]{Colors.RESET} cannot read the registration SSOT in {plugin_dir}: {exc}")
        return 2

    targets = split_repo_targets(marketplaces, plugins, owner=args.owner)
    if not args.quiet:
        print(f"Auditing {len(targets)} split-out repo(s) owned by {args.owner} (--check {args.check})")

    local_skills = read_skill_tree(args.repo_root / "claude" / "skills")

    with tempfile.TemporaryDirectory(prefix="split-skill-audit-") as workdir:
        result = run_audit(targets, local_skills, GitCloneRemoteSource(Path(workdir)), checks=args.check)

    if not args.quiet:
        for note in result.notes:
            print(f"{Colors.YELLOW}[NOTE]{Colors.RESET} {note}")

    for finding in result.findings:
        print(f"{Colors.RED}[FAIL]{Colors.RESET} {finding}" if not finding.startswith("    ") else finding)

    if not result.findings and not args.quiet:
        print(f"{Colors.GREEN}[OK]{Colors.RESET} every registered split repo matches its manifest and shows no drift")

    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
