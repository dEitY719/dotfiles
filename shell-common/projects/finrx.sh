#!/bin/sh
# shell-common/projects/finrx.sh
# FinRx project utilities
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Repository URL (for documentation & reference)
# ═══════════════════════════════════════════════════════════════

REPO_FINRX_URL="https://github.com/dEitY719/FinRx.git"

# ═══════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════

# Check if command exists
_have() {
    command -v "$1" > /dev/null 2>&1
}

# Require a command or exit with error
_need() {
    if ! _have "$1"; then
        echo "[ERR] Cannot find command '$1'. Please install it and try again." >&2
        return 127
    fi
}

# ═══════════════════════════════════════════════════════════════
# FinRx Project Functions
# ═══════════════════════════════════════════════════════════════

run_fr_cli() {
    _need python
    python ./src/ticker_library/cli/cli.py "$@"
}
