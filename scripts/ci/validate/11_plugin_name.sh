#!/usr/bin/env bash
# skill-check step: Plugin name is consistent everywhere
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import os, sys, json, re, pathlib
want = os.environ["PLUGIN_NAME"]
fail = 0
def check(label, got):
    global fail
    if got != want:
        print(f"FAIL  {label}: expected {want!r}, got {got!r}")
        fail = 1
    else:
        print(f"ok    {label}")

for f in [".claude-plugin/plugin.json", ".codex-plugin/plugin.json",
          ".kimi-plugin/plugin.json", "gemini-extension.json"]:
    check(f, json.loads(pathlib.Path(f).read_text(encoding="utf-8"))["name"])

mp = json.loads(pathlib.Path(".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
check(".claude-plugin/marketplace.json plugins[0]", mp["plugins"][0]["name"])
ag = json.loads(pathlib.Path(".agents/plugins/marketplace.json").read_text(encoding="utf-8"))
check(".agents/plugins/marketplace.json plugins[0]", ag["plugins"][0]["name"])
y = pathlib.Path(".hermes-plugin/plugin.yaml").read_text(encoding="utf-8")
check(".hermes-plugin/plugin.yaml", re.search(r"^name:\s*(\S+)", y, re.M).group(1))
sys.exit(fail)
PY
