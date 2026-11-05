#!/usr/bin/env bash
# skill-check step: AGENTS.md is a symlink to CLAUDE.md
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
target=$(readlink AGENTS.md || true)
if [ "$target" != "CLAUDE.md" ]; then
    echo "FAIL  AGENTS.md must be a symlink to CLAUDE.md (got: '${target:-not a symlink}')"
    exit 1
fi
echo "ok    AGENTS.md -> CLAUDE.md"
