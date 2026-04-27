#!/usr/bin/env python3
"""
Codex Skill Description Budget Checker

Reports the total length of skill description metadata in claude/skills/.
Codex truncates skill descriptions when they exceed roughly 2% of the
context window (about 5440 chars on current builds), which silently degrades
trigger accuracy. Run this to detect when the SSOT is approaching that limit.

Usage:
    python3 check_codex_skills_budget.py [--budget N] [--top N] [--all]
                                          [--quiet] [--skills-dir PATH]

Exit codes:
    0  total description length is within budget
    1  total description length exceeds budget
    2  error (skills directory missing, parse failure)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


class Colors:
    RESET = "\033[0m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"


DEFAULT_BUDGET_CHARS = 5440  # observed Codex skill metadata budget
DEFAULT_TOP_N = 10
LONG_WARN = 400  # per-skill chars that strongly suggest trimming
LONG_HINT = 250  # per-skill chars that hint at being on the long side

NAME_RE = re.compile(r"^name:\s*(.+?)\s*$")
DESC_RE = re.compile(r"^description:\s*(.*)$")
KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*:")
FOLD_INDICATORS = {">", ">-", ">+", "|", "|-", "|+"}


def parse_skill_md(path: Path, fallback_name: str) -> tuple[str, str]:
    """Extract (name, description) from a SKILL.md frontmatter block.

    Supports single-line scalars and folded/literal block scalars
    (``>``, ``>-``, ``|``, ...). Falls back to ``fallback_name`` if no
    ``name:`` is declared in the frontmatter.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return (fallback_name, "")

    if not lines or lines[0].strip() != "---":
        return (fallback_name, "")

    name = fallback_name
    desc_parts: list[str] = []
    in_block = False

    for raw in lines[1:]:
        line = raw.rstrip("\r")
        if line.strip() == "---":
            break

        m = NAME_RE.match(line)
        if m:
            name = m.group(1).strip().strip("\"'")
            in_block = False
            continue

        m = DESC_RE.match(line)
        if m:
            value = m.group(1).strip()
            if value in FOLD_INDICATORS:
                in_block = True
                desc_parts = []
            else:
                desc_parts = [value.strip("\"'")]
                in_block = False
            continue

        if in_block:
            # A new top-level YAML key terminates the block scalar.
            if KEY_RE.match(line):
                in_block = False
                continue
            desc_parts.append(line.strip())

    text = " ".join(p for p in desc_parts if p)

    return (name, re.sub(r"\s+", " ", text).strip())


def collect_rows(skills_dir: Path) -> list[tuple[str, int, Path]]:
    rows: list[tuple[str, int, Path]] = []
    for entry in sorted(skills_dir.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        skill_md = entry / "SKILL.md"
        if not skill_md.is_file():
            continue
        name, desc = parse_skill_md(skill_md, entry.name)
        rows.append((name, len(desc), entry))
    return rows


def format_marker(length: int) -> str:
    if length >= LONG_WARN:
        return f"  {Colors.YELLOW}(>= {LONG_WARN} chars — consider trimming){Colors.RESET}"
    if length >= LONG_HINT:
        return f"  {Colors.DIM}(>= {LONG_HINT}){Colors.RESET}"
    return ""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=("Report Codex skill description length to detect context budget overruns."),
    )
    parser.add_argument(
        "-b",
        "--budget",
        type=int,
        default=DEFAULT_BUDGET_CHARS,
        help=f"budget threshold in chars (default: {DEFAULT_BUDGET_CHARS})",
    )
    parser.add_argument(
        "-n",
        "--top",
        type=int,
        default=DEFAULT_TOP_N,
        help=f"show top N longest descriptions (default: {DEFAULT_TOP_N})",
    )
    parser.add_argument(
        "-a",
        "--all",
        action="store_true",
        help="show all skills, not just the top N longest",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="print only the final budget verdict",
    )
    parser.add_argument(
        "--skills-dir",
        type=Path,
        default=None,
        help="skills directory (default: <dotfiles>/claude/skills)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.skills_dir is not None:
        skills_dir = args.skills_dir
    else:
        script_path = Path(__file__).resolve()
        skills_dir = script_path.parents[2] / "claude" / "skills"

    if not skills_dir.is_dir():
        print(
            f"{Colors.RED}Error: skills source not found: {skills_dir}{Colors.RESET}",
            file=sys.stderr,
        )
        return 2

    rows = collect_rows(skills_dir)
    total_chars = sum(r[1] for r in rows)
    skill_count = len(rows)
    avg = total_chars / skill_count if skill_count else 0
    over_budget = total_chars > args.budget

    if not args.quiet:
        print(f"{Colors.BLUE}=== Codex Skill Description Budget ==={Colors.RESET}")
        print(f"  Source dir: {skills_dir}")
        print(f"  Skills:     {skill_count}")
        print(f"  Total:      {total_chars} chars  (avg {avg:.0f}/skill)")
        print(f"  Budget:     {args.budget} chars")
        print()

        rows_sorted = sorted(rows, key=lambda r: -r[1])
        view = rows_sorted if args.all else rows_sorted[: args.top]
        header = "All skills" if args.all else (f"Top {min(args.top, len(rows_sorted))} longest")
        print(f"{Colors.BLUE}-- {header} --{Colors.RESET}")
        for name, length, _path in view:
            print(f"  {length:5d}  {name}{format_marker(length)}")

    if over_budget:
        print()
        print(f"{Colors.RED}! Total description chars ({total_chars}) exceed budget ({args.budget}).{Colors.RESET}")
        print(
            f"{Colors.YELLOW}  Suggestion: trim long descriptions to "
            f"150-250 chars, or pin Codex to a subset via "
            f"claude/skills/.codex-allowlist.{Colors.RESET}"
        )
        return 1

    if not args.quiet:
        print(f"{Colors.GREEN}OK Within budget ({total_chars}/{args.budget} chars).{Colors.RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
