#!/bin/sh
# shell-common/tools/ccusage.sh
# Claude Code Usage (ccusage) - aliases, functions, and help
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Installation Instructions
# ═══════════════════════════════════════════════════════════════

# Global prefix installation (recommended):
# 1) Install to user home directory:
#    npm install -g ccusage --prefix=$HOME/.npm-global
# 2) Add to PATH if needed:
#    export PATH="$HOME/.npm-global/bin:$PATH"
#
# Verify installation:
#    which ccusage && ccusage --version

# ═══════════════════════════════════════════════════════════════
# PATH Helper Function
# ═══════════════════════════════════════════════════════════════

ccusage_path_hint() {
    case ":$PATH:" in
    *":$HOME/.npm-global/bin:"*) ;;
    *)
        echo "Note: If $HOME/.npm-global/bin is not in PATH, run:"
        echo "  export PATH='$HOME/.npm-global/bin:\$PATH'"
        ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Essential Command Aliases (3 aliases)
# ═══════════════════════════════════════════════════════════════

alias ccd='ccusage daily --breakdown'   # Show daily usage by model
alias ccs='ccusage session --sort tokens' # Analyze session usage by token count
alias ccb='ccusage blocks --live'       # Display cache ratio (live)
