#!/usr/bin/env bash
# skill-check step: Validate YAML manifests parse
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import sys, pathlib, yaml
fail = 0
for p in sorted(pathlib.Path(".").rglob("*.yaml")) + sorted(pathlib.Path(".").rglob("*.yml")):
    if ".git/" in str(p):
        continue
    try:
        yaml.safe_load(p.read_text(encoding="utf-8"))
        print(f"ok    {p}")
    except Exception as e:
        print(f"FAIL  {p}: {e}")
        fail = 1
sys.exit(fail)
PY
