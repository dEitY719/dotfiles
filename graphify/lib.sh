#!/bin/bash
# graphify/lib.sh: shared bootstrap for graphify/setup.sh and graphify/uninstall.sh
#
# Sourced, never executed. Loads ux_lib + the multi-account helpers
# (_claude_resolve_account, _dotfiles_setup_mode) the same way claude/setup.sh
# does, and defines the one path both scripts agree on.

_GRAPHIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_GRAPHIFY_DIR%/graphify}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
# Both files carry the interactive guard; DOTFILES_FORCE_INIT lets a script load them.
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/env/claude.sh"
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/tools/integrations/claude.sh"

# Single source: `graphify install --platform claude` with CLAUDE_CONFIG_DIR
# unset lands here; every account links to it (issue #1844).
GRAPHIFY_SKILL_SRC="${HOME}/.claude/skills/graphify"
