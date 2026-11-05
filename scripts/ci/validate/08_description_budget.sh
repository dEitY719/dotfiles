#!/usr/bin/env bash
# skill-check step: Skill descriptions fit the Codex context budget
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import os, sys, re, pathlib
budget = int(float(os.environ["DESCRIPTION_BUDGET"]))
total = 0
fail = 0
for md in sorted(pathlib.Path("skills").glob("*/SKILL.md")):
    text = md.read_text(encoding="utf-8")
    fm = re.match(r"^---\n(.*?)\n---\n", text, re.S).group(1)
    m = re.search(r"^description:(.*?)(?=^\S|\Z)", fm, re.M | re.S)
    desc = " ".join(m.group(1).split()) if m else ""
    if not desc:
        print(f"FAIL  {md}: empty description")
        fail = 1
    if len(desc) > 1024:
        print(f"FAIL  {md}: description {len(desc)} chars > 1024 (harness limit)")
        fail = 1
    total += len(desc)
    print(f"{len(desc):>5}  {md}")
pct = total / budget * 100
print(f"TOTAL {total} / {budget} = {pct:.1f}%")
if total > budget:
    print(f"FAIL  description total {total} exceeds the Codex budget {budget}")
    fail = 1
sys.exit(fail)
PY
