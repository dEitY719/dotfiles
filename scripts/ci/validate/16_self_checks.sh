#!/usr/bin/env bash
# skill-check step: Repo self-checks pass (tests/)
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
# Convention, and the rules a check must follow: see README "CI".
# Another shape (a `--self-test` flag, a `lib/*.selfcheck.sh`) is
# wired up by a one-line `tests/` script, never by a third branch here.
#
# `:(glob)` stops `*` from crossing `/`, so only direct children of
# the repo-root `tests/` match. A vendored tree can never be one, so
# this step needs no `shellcheck-exclude-paths` plumbing.
#
# git writes the listing to a file rather than into `mapfile -t x <
# <(git ls-files)`: the process substitution hides git's exit status
# from `set -e`, so a git failure would print "no tests tracked",
# exit 0, and silently disable this gate. `-z` with `-d ''` keeps a
# tracked path containing a newline one path, and discovery is over
# tracked files only, so an untracked `tests/run.sh` left in the
# working tree cannot hijack it.
listing=$(mktemp)
git ls-files -z -- ':(glob)tests/*.sh' >"$listing"
mapfile -t -d '' checks <"$listing"
rm -f "$listing"
if [ "${#checks[@]}" -eq 0 ]; then
    echo "ok    no tests tracked"
    exit 0
fi
for c in "${checks[@]}"; do
    if [ "$c" = tests/run.sh ]; then
        checks=(tests/run.sh)
        break
    fi
done
for c in "${checks[@]}"; do
    echo "note  running $c"
    bash "$c"
done
echo "ok    ${#checks[@]} check(s) passed"
