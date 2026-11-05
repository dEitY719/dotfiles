#!/usr/bin/env bash
# skill-check step: Validate JSON manifests parse
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
# Discovery through a file, never a process substitution: that hides
# git's exit status from `set -e`, and this gate failed even quieter
# than the shellcheck one -- an empty log and a green exit.
# tests/self-checks-step.sh now asserts no step in this file
# discovers that way, so the class is closed, not just the site.
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
git ls-files -z -- '*.json' >"$listing"
mapfile -t -d '' files <"$listing"
fail=0
for f in "${files[@]}"; do
    if jq empty "$f" 2>/dev/null; then
        echo "ok    $f"
    else
        echo "FAIL  $f (invalid JSON)"
        fail=1
    fi
done
exit "$fail"
