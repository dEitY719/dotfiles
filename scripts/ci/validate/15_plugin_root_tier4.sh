#!/usr/bin/env bash
# skill-check step: No caller-controlled path defaults (plugin-root tier 4)
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import re, sys, subprocess, pathlib
# The plugin-root convention's gate, hoisted out of the sixteen
# repos that were copying it (harness-skills#59). Built in, with no
# input: a caller that could switch this off is a caller that can
# ship the defect, and #35 is what the copies were worth -- two
# consumers sat on two different, both-incomplete regexes.
#
# https://github.com/dEitY719/harness-skills/blob/main/references/plugin-root.md
#
# An empty default spliced into a path collapses to the filesystem
# root and then gets exported (gh-resolve-skills#8). A default that
# names the cwd is the retired tier 4 (harness-skills#22): $PWD is
# caller-controlled, and these skills run inside the repository
# under review, so a pull request shipping its own
# lib/vendor/shell-common would get it sourced by the reviewer's own
# tooling. Three spellings of that one directory, because a
# $PWD-only alternation passed the other two and `.` is the form
# that actually shipped (claudecode-skills#5).
RX = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*:?-(\$PWD|\$\(pwd\)|\.)?\}/")
# The convention's own page has to show the literals it bans, so it
# is the one exclusion -- hardcoded rather than an input, for the
# same reason the regex is. Inert in every other repo: they link to
# that page rather than copy it, so the path does not exist there.
#
# A consumer's own prose must WORD the ban rather than quote it, or
# that page becomes the file failing its own rule
# (claudecode-skills#10). No exclusion is offered for it: an input
# here is a switch, and one repo's doc is not worth one.
SELF = "references/plugin-root.md"
# TRACKED files only, like every other discovery in this workflow:
# an untracked scratch file must not be able to fail a repo's gate.
# The corollary bites when this is run by hand -- a file you have
# just created is invisible to it until `git add`, so the summary
# line prints the count it actually scanned.
files = subprocess.run(["git", "ls-files"], capture_output=True,
                       text=True, check=True).stdout.split()
if not files:
    # Same rule as every other discovery here: nothing found is a
    # broken checkout, not a clean repo.
    sys.exit("FAIL  plugin-root gate: git ls-files returned no tracked file")
bad = []
for f in files:
    if f == SELF:
        continue
    p = pathlib.Path(f)
    if p.is_symlink() or not p.is_file():
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for i, line in enumerate(text.splitlines(), 1):
        if RX.search(line):
            bad.append(f"{f}:{i}: {line.strip()}")
if bad:
    print("FAIL  caller-controlled or empty path default spliced into a path:")
    print("\n".join(bad))
    print("Guard the variable instead: "
          '[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || <tier 5>; '
          "see references/plugin-root.md.")
    print("Prose that has to describe the banned shape should word "
          "it, not quote it -- a quoted literal fails this gate.")
    sys.exit(1)
print(f"ok    no empty-default or cwd path splices "
      f"({len(files)} tracked file(s); untracked files are not scanned)")
PY
