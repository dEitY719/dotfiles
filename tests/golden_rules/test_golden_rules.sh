#!/bin/bash
# tests/golden_rules/test_golden_rules.sh
# Golden rules = the pre-commit checks in whole-file mode over every tracked
# file (#2149). Each rule lives only in git/hooks/checks/*_check.sh; this
# script holds no rule of its own. Known legacy violations: baseline.txt.
# Run: bash tests/golden_rules/test_golden_rules.sh

# Self-locate the repo root so the run is the same from any cwd (PR #1381).
# Never an inherited DOTFILES_ROOT: in a worktree that names the main checkout.
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$DOTFILES_ROOT" || { echo "Could not cd to DOTFILES_ROOT: $DOTFILES_ROOT" >&2; exit 1; }

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════"
echo "GOLDEN RULES VALIDATION (git/hooks/checks/run_all.sh)"
echo "════════════════════════════════════════════════════════════"
# Chunked across CPUs: one serial pass over the tree takes minutes.
if git ls-files -z | xargs -0 -n 40 -P "$(nproc 2>/dev/null || echo 4)" git/hooks/checks/run_all.sh; then
    echo -e "${GREEN}All golden rules validated ✓${NC}"
    exit 0
fi
echo -e "${RED}Golden rule violation(s) above (not in git/hooks/checks/baseline.txt)${NC}"
exit 1
