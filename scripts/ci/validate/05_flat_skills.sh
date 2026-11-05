#!/usr/bin/env bash
# skill-check step: Skills are flat under skills/ and never nested under plugins/
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
if [ -d plugins ]; then
    echo "FAIL  plugins/ exists — this repo uses the root layout, not the nested mono layout"
    exit 1
fi
if [ ! -d skills ]; then
    echo "FAIL  skills/ missing"
    exit 1
fi
echo "ok    flat skills/ layout"
