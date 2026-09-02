#!/bin/sh
# shell-common/env/claude.sh
# Claude Code environment variables

# Skills/docs are exposed to each Claude Code account as a single
# directory symlink (issue #575) — no bind-mount, no per-skill sync,
# no auto-mount env vars. See claude/AGENTS.md for the layout.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# AI tool for documentation generation
# Options: claude (default), agy, codex, or any CLI tool accepting -p/--prompt
# Can be overridden per-command or per-session
export CLAUDE_DOC_GENERATOR=claude

# Skills directory path (used by skill_loader and other tools).
# Points at the composed harness directory, not a dotfiles source: #1680
# moved every skill into its own marketplace repo, and the composition of
# those clones into "<config dir>/skills/<name>" is what a shell actually
# has on hand (scripts/setup-skills-ssot.sh / _claude_compose_workspace_skills).
export CLAUDE_SKILLS_PATH="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"

# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# Auto-detect setup mode (internal vs external) for account defaults.
# Internal-PC (사내): work account only. External-PC: personal + work + work1.
#
# Unconditional assignment: setup-mode is the single source of truth, so
# we overwrite any stale value inherited from a prior shell-init cycle.
# Per-PC overrides happen below via claude.local.sh, which is sourced
# AFTER this block and can freely reassign these vars.
_claude_setup_mode="$(cat "$HOME/.dotfiles-setup-mode" 2>/dev/null)"
case "$_claude_setup_mode" in
    internal|2)
        export CLAUDE_DEFAULT_ACCOUNT="work"
        export CLAUDE_ENABLED_ACCOUNTS="work"
        ;;
    *)
        export CLAUDE_DEFAULT_ACCOUNT="personal"
        export CLAUDE_ENABLED_ACCOUNTS="personal work work1"
        ;;
esac
unset _claude_setup_mode

# Load PC-local overrides (gitignored, see claude.local.example).
_claude_env_root="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
if [ -f "$_claude_env_root/env/claude.local.sh" ]; then
    . "$_claude_env_root/env/claude.local.sh"
fi
unset _claude_env_root
