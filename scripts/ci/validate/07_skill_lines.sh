#!/usr/bin/env bash
# skill-check step: SKILL.md respects progressive disclosure
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import os, sys, pathlib
limit = int(float(os.environ["MAX_SKILL_LINES"]))
fail = 0
for md in sorted(pathlib.Path("skills").glob("*/SKILL.md")):
    n = len(md.read_text(encoding="utf-8").splitlines())
    if n > limit:
        print(f"FAIL  {md}: {n} lines > {limit} — extract detail into references/")
        fail = 1
    else:
        print(f"ok    {md} ({n} lines)")
sys.exit(fail)
PY
