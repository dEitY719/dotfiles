#!/usr/bin/env bash
# skill-check step: Version agrees across all manifests
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import sys, json, re, pathlib
versions = {}
for f in [
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    ".kimi-plugin/plugin.json",
    "gemini-extension.json",
    "package.json",
]:
    versions[f] = json.loads(pathlib.Path(f).read_text(encoding="utf-8"))["version"]
mp = json.loads(pathlib.Path(".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
versions[".claude-plugin/marketplace.json"] = mp["plugins"][0]["version"]
y = pathlib.Path(".hermes-plugin/plugin.yaml").read_text(encoding="utf-8")
versions[".hermes-plugin/plugin.yaml"] = re.search(r"^version:\s*(\S+)", y, re.M).group(1)

for f, v in versions.items():
    print(f"{v}\t{f}")
distinct = set(versions.values())
if len(distinct) != 1:
    print(f"FAIL  manifests disagree on version: {sorted(distinct)}")
    sys.exit(1)
print("ok    all manifests agree")
PY
