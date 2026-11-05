#!/usr/bin/env bash
# skill-check step: Skill frontmatter name matches its directory
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import sys, pathlib, re
fail = 0
skills = sorted(p for p in pathlib.Path("skills").iterdir() if p.is_dir())
if not skills:
    print("FAIL  no skills found")
    sys.exit(1)
for d in skills:
    md = d / "SKILL.md"
    if not md.is_file():
        print(f"FAIL  {d}: SKILL.md missing")
        fail = 1
        continue
    text = md.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        print(f"FAIL  {md}: no YAML frontmatter")
        fail = 1
        continue
    fm = m.group(1)
    nm = re.search(r"^name:\s*(.+?)\s*$", fm, re.M)
    if not nm:
        print(f"FAIL  {md}: frontmatter has no name:")
        fail = 1
        continue
    name = nm.group(1).strip().strip("\"'")
    if ":" in name:
        print(f"FAIL  {md}: name must be bare, not namespaced (got {name!r})")
        fail = 1
    elif name != d.name:
        print(f"FAIL  {md}: name {name!r} != directory {d.name!r}")
        fail = 1
    else:
        print(f"ok    {md}")
    if not re.search(r"^description:", fm, re.M):
        print(f"FAIL  {md}: frontmatter has no description:")
        fail = 1
sys.exit(fail)
PY
