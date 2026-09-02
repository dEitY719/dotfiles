#!/usr/bin/env python3
"""
gh Skill Host-Pinning Checker

Enforces the `GH_HOST` pinning contract introduced by issue #1403 / PR #1404
across every `gh:*` skill, so a dual-host login (github.com + GHES) cannot
silently route a read - or worse, a write - to the wrong server.

The contract has two halves and both are required:

    GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"

`--repo <owner>/<repo>` carries no host, so `gh` resolves that slug against
its own default host (`gh repo set-default`) rather than git's remote. The
`GH_HOST=` prefix is what pins the server; `--repo` is what pins the repo.
Neither substitutes for the other.

PR #1404 applied the contract by copying a binding block into each SKILL.md
by hand, which left 13 of 19 `gh:*` skills outside it (#1407). This checker
is the mechanical gate that keeps the next skill from leaking the same way.

Scope and its deliberate boundary
    A call counts as executable when it starts a line or a `$(...)`
    substitution - the same shape issue #1407's reproduction script measured.
    A `gh` fragment quoted mid-sentence is NOT flagged, because skill docs
    legitimately name commands in prose ("`gh pr view --json rebaseable` fails
    with Unknown JSON field") and flagging those would train people to ignore
    the checker. Reviewers still have to read prose; this gate covers the
    copy-pasteable calls, which is where #1403 actually bit.

Usage:
    python3 check_gh_skill_host_pinning.py [--skills-dir PATH] [--quiet]
                                           [--prefix gh-]

Exit codes:
    0  every executable `gh` call is host-pinned and repo-scoped
    1  at least one violation
    2  error (skills directory missing)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


class Colors:
    RESET = "\033[0m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"


# An executable `gh` call: one that starts a line or a `$(...)`, optionally
# behind `VAR=val` assignments and/or a shell keyword (`if`, `if !`, `while`,
# `elif`, a bare `!`). Not prose that merely names `gh`.
#
# The keyword branch was added after PR #1425 review (codex): `if ! gh ... ;
# then` is a copy-pasteable executable shape this file's own comment already
# claimed to cover, and without it an unpinned call in that form passed both
# the checker and its test.
GH_CALL_RE = re.compile(
    r"""
    (?:^|\$\()                 # start of line, or command substitution
    [ \t]*
    (?:(?:if|elif|while|until)[ \t]+)?                   # shell keyword
    (?:![ \t]*)?                                         # negation
    (?P<prefix>(?:[A-Za-z_][A-Za-z0-9_]*=\S*[ \t]+)*)   # VAR=val ... prefixes
    gh[ \t]+(?P<sub>[a-z][a-z-]*)                       # gh <sub-command>
    """,
    re.VERBOSE,
)

# `gh` sub-commands that are not repo-scoped: `--repo` is not a valid flag.
# `search` is deliberately NOT here - `gh search issues|prs` does take
# `-R, --repo` (PR #1425 review, agy), so exempting it would hide real calls.
REPO_LESS_SUBCOMMANDS = frozenset({"gist", "auth", "config", "extension", "version", "alias", "status"})

# Verbs whose synopsis is `gh pr <verb> [<number> | <url> | <branch>]` - the
# positional is OPTIONAL, so omitting it means "read the PR off the current
# branch", and in exactly that mode `gh` REFUSES `--repo`:
#
#     $ gh pr view --repo owner/repo --json number
#     argument required when using the --repo flag
#
# So the contract inverts for these: host pinned, repo flag forbidden.
# Deliberately excluded: `create` / `list` / `status` take no positional at all
# and are correctly repo-scoped, and `close` / `reopen` / `checkout` require
# theirs (`{...}`), so neither group can reach the branch-autodetect mode.
# Taken from `gh pr <verb> --help` synopses, not guessed.
PR_AUTODETECT_VERBS = frozenset({"view", "diff", "checks", "edit", "merge", "review", "comment", "ready"})
# The leading `VAR=val ` / keyword prefix is skipped here because check_command
# receives the command starting at the regex match, i.e. including that prefix.
PR_VERB_RE = re.compile(
    r"""
    ^
    (?:(?:if|elif|while|until)[ \t]+)?
    (?:![ \t]*)?
    (?:[A-Za-z_][A-Za-z0-9_]*=\S*[ \t]+)*
    gh[ \t]+pr[ \t]+(?P<verb>[a-z-]+)[ \t]*(?P<rest>.*)$
    """,
    re.VERBOSE | re.DOTALL,
)

# Names the skills bind their resolved repo slug to (#1404 used two: gh-pr
# says GH_REPO, the gh-issue-* family says TARGET_REPO; gh:relay-merge adds
# DEST_REPO for the destination remote).
REPO_VAR_RE = re.compile(r"\$\{?(?:TARGET_REPO|GH_REPO|DEST_REPO|SOURCE_REPO)\b|\$OWNER/\$REPO")

# Literal placeholders that make `gh api` fall back to implicit resolution -
# exactly the silent misroute #1403 hit.
PLACEHOLDER_RE = re.compile(r"\{owner\}/\{repo\}|<owner>/<repo>")

HOST_PIN_RE = re.compile(r"\bGH_HOST=")
HOSTNAME_FLAG_RE = re.compile(r"--hostname\b")


def join_continuations(lines: list[str]) -> list[tuple[int, str]]:
    """Fold backslash-continued shell lines into one logical line.

    Returns (1-indexed line number of the first physical line, joined text).
    A `--repo` on the second line of a wrapped command still counts.
    """
    joined: list[tuple[int, str]] = []
    buf = ""
    start = 0
    for idx, raw in enumerate(lines, start=1):
        line = raw.rstrip("\n")
        if not buf:
            start = idx
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            continue
        buf += line
        joined.append((start, buf))
        buf = ""
    if buf:
        joined.append((start, buf))
    return joined


def api_path_is_repo_scoped(command: str) -> bool | None:
    """For `gh api`, decide whether the call targets a repo path.

    Returns True  - repo path carrying a repo variable (compliant),
            False - repo path carrying a literal placeholder (violation),
            None  - not a repo path at all (`user`, `gists/...`, `graphql`).
    """
    if PLACEHOLDER_RE.search(command):
        return False
    if re.search(r"repos/", command):
        return bool(REPO_VAR_RE.search(command))
    return None


def first_command(command: str) -> str:
    """Truncate at the first shell separator so a later piped `gh` call's
    `--repo` cannot satisfy an earlier one (PR #1425 review, agy).

    Separators are matched outside quotes only in the crude sense that a `|`
    inside a `--jq` expression is normally quoted; a stray split there costs a
    false positive at worst, never a false negative.
    """
    return re.split(r"[|;]|&&|\|\|", command, maxsplit=1)[0]


def pr_verb_without_positional(command: str) -> bool:
    """True for `gh pr <verb>` called with no PR argument (branch auto-detect).

    The token after the verb decides it: a flag (`--json`) means no positional,
    anything else (`5`, `"$PR_NUMBER"`, `<N>`) means one was supplied.
    """
    match = PR_VERB_RE.match(command.strip())
    if not match:
        return False
    if match.group("verb") not in PR_AUTODETECT_VERBS:
        return False
    rest = match.group("rest").strip()
    if not rest:
        return True
    return rest.startswith("-")


def check_command(sub: str, prefix: str, command: str) -> list[str]:
    """Return the list of contract violations for one `gh` command."""
    problems: list[str] = []
    command = first_command(command)

    if not HOST_PIN_RE.search(prefix) and not HOSTNAME_FLAG_RE.search(command):
        problems.append("missing GH_HOST= prefix (or --hostname)")

    if sub == "api":
        scoped = api_path_is_repo_scoped(command)
        if scoped is False:
            problems.append("gh api uses a literal {owner}/{repo} placeholder instead of $TARGET_REPO")
    elif sub == "pr" and pr_verb_without_positional(command):
        # Inverted contract: gh rejects --repo when it has to read the PR off
        # the current branch. Requiring it here is what broke four skills in
        # the first cut of #1407 (PR #1425 review, agy).
        if "--repo" in command:
            problems.append(
                "gh pr <verb> with no PR argument must NOT pass --repo "
                "(gh: 'argument required when using the --repo flag'); host prefix only"
            )
    elif sub not in REPO_LESS_SUBCOMMANDS:
        if "--repo" not in command and not REPO_VAR_RE.search(command):
            problems.append("missing --repo")

    return problems


def scan_file(path: Path) -> list[tuple[int, str, list[str]]]:
    """Scan one markdown file; return (line, command, problems) per violation."""
    findings: list[tuple[int, str, list[str]]] = []
    text = path.read_text(encoding="utf-8", errors="replace")
    for lineno, command in join_continuations(text.splitlines()):
        for match in GH_CALL_RE.finditer(command):
            sub = match.group("sub")
            prefix = match.group("prefix")
            problems = check_command(sub, prefix, command[match.start() :])
            if problems:
                findings.append((lineno, command.strip(), problems))
    return findings


def scan_skill(skill_dir: Path) -> list[tuple[Path, int, str, list[str]]]:
    findings: list[tuple[Path, int, str, list[str]]] = []
    for md in sorted(skill_dir.rglob("*.md")):
        for lineno, command, problems in scan_file(md):
            findings.append((md, lineno, command, problems))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Check the gh:* skills' GH_HOST pinning contract (#1407).")
    parser.add_argument(
        "--skills-dir",
        required=True,
        help="Directory holding the skill folders. No default (#1680) — the "
        "gh-* skills this checks now live in their own marketplace repos, "
        "e.g. <workspace>/gh-pr-skills/skills.",
    )
    parser.add_argument(
        "--prefix", default="gh-", help="Only scan skills whose directory starts with this (default: gh-)."
    )
    parser.add_argument("--quiet", action="store_true", help="Print nothing on success.")
    args = parser.parse_args()

    skills_dir = Path(args.skills_dir)
    if not skills_dir.is_dir():
        print(f"{Colors.RED}Error: skills directory not found: {skills_dir}{Colors.RESET}", file=sys.stderr)
        return 2

    all_findings: list[tuple[str, Path, int, str, list[str]]] = []
    scanned = 0
    for skill_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir() and p.name.startswith(args.prefix)):
        scanned += 1
        for md, lineno, command, problems in scan_skill(skill_dir):
            all_findings.append((skill_dir.name, md, lineno, command, problems))

    if all_findings:
        print(f"{Colors.RED}! {len(all_findings)} unpinned gh call(s) across {scanned} skill(s).{Colors.RESET}")
        print()
        current = None
        for skill, md, lineno, command, problems in all_findings:
            if skill != current:
                print(f"{Colors.YELLOW}-- {skill} --{Colors.RESET}")
                current = skill
            rel = md.relative_to(skills_dir)
            print(f"  {rel}:{lineno}")
            print(f"      {command[:120]}")
            for problem in problems:
                print(f"      {Colors.RED}->{Colors.RESET} {problem}")
        print()
        print(
            f'{Colors.YELLOW}  Contract (#1403/#1407): GH_HOST="$TARGET_HOST" gh <sub> ... '
            f'--repo "$TARGET_REPO", both bound in the skill\'s Step 1 from one remote URL.{Colors.RESET}'
        )
        return 1

    if not args.quiet:
        print(f"{Colors.GREEN}OK All gh calls in {scanned} skill(s) are host-pinned and repo-scoped.{Colors.RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
