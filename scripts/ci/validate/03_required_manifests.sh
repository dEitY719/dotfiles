#!/usr/bin/env bash
# skill-check step: Required harness manifests present
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
required="
.claude-plugin/marketplace.json
.claude-plugin/plugin.json
.codex-plugin/plugin.json
.kimi-plugin/plugin.json
.hermes-plugin/plugin.yaml
.hermes-plugin/__init__.py
.opencode/plugins/${PLUGIN_NAME}.js
.opencode/INSTALL.md
.agents/plugins/marketplace.json
gemini-extension.json
GEMINI.md
package.json
CLAUDE.md
AGENTS.md
README.md
LICENSE
"
fail=0
for f in $required; do
    if [ -e "$f" ]; then
        echo "ok    $f"
    else
        echo "FAIL  $f missing"
        fail=1
    fi
done
exit "$fail"
