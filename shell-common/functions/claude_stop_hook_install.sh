#!/bin/sh
# shell-common/functions/claude_stop_hook_install.sh
#
# Auto-install the gh-issue-flow Stop hook into claude/settings.json on
# interactive shell startup (issue #505).
#
# Background: claude/setup.sh:_migrate_install_gh_issue_flow_stop_hook
# already performs this migration, but it only runs when the user
# explicitly re-executes setup.sh. Users on a multi-account layout
# whose live settings.json predates issue #383 silently miss the hook —
# the harness backstop documented in gh-issue-flow/SKILL.md never
# fires, and /gh-issue-flow regresses to the early-stop pattern.
#
# This helper closes that gap by re-running the same idempotent
# migration on every interactive shell. Hot-path is silent (no jq
# rewrite when the hook entry is already present); the install path
# emits a single stderr line so the user sees what changed.
#
# Behaviour matrix:
#   - Already installed                 → silent no-op (fast path)
#   - Other Stop hook present (custom)  → silent skip (preserve user config)
#   - jq missing / settings.json absent → silent skip (best effort)
#   - Hook missing, no conflict         → install + 1 stderr line + backup

# The function definition is intentionally NOT gated by the interactive
# guard — defining it has no side effects, and tests source this file
# in non-interactive bash. Only the auto-fire at the bottom is gated.

_claude_install_gh_issue_flow_stop_hook() {
    _csh_dotfiles="${DOTFILES_ROOT:-$HOME/dotfiles}"
    _csh_source_file="${_csh_dotfiles}/claude/settings.json"
    # shellcheck disable=SC2016
    _csh_hook_command='${HOME}/dotfiles/claude/hooks/gh_issue_flow_stop_guard.py'

    [ -f "$_csh_source_file" ] || {
        unset _csh_dotfiles _csh_source_file _csh_hook_command
        return 0
    }
    if ! command -v jq >/dev/null 2>&1; then
        unset _csh_dotfiles _csh_source_file _csh_hook_command
        return 0
    fi

    _csh_count=$(jq --arg cmd "$_csh_hook_command" \
        '[.hooks?.Stop?[]?.hooks?[]? | select(.command == $cmd)] | length' \
        "$_csh_source_file" 2>/dev/null) || _csh_count=0
    if [ "${_csh_count:-0}" -ne 0 ]; then
        unset _csh_dotfiles _csh_source_file _csh_hook_command _csh_count
        return 0
    fi

    _csh_existing=$(jq '[.hooks?.Stop?[]?] | length' "$_csh_source_file" 2>/dev/null) || _csh_existing=0
    if [ "${_csh_existing:-0}" -gt 0 ]; then
        unset _csh_dotfiles _csh_source_file _csh_hook_command _csh_count _csh_existing
        return 0
    fi

    # Bypass shell aliases (e.g. `cp`/`mv`/`rm` aliased to `-i` in
    # interactive bash) so the migration never blocks on a confirmation
    # prompt at shell startup. The auto-fire path runs in interactive
    # bash where alias expansion is enabled.
    # Latest-only backup (issue #919): fixed suffix + legacy sweep so the
    # auto-fire install path does not accumulate one backup per shell start.
    # SSOT policy: shell-common/functions/dotfiles_backup.sh (#806).
    _csh_backup="${_csh_source_file}.pre-stop-hook-fix.bak"
    command rm -f "${_csh_source_file}".pre-stop-hook-fix-*
    if ! command cp "$_csh_source_file" "$_csh_backup"; then
        unset _csh_dotfiles _csh_source_file _csh_hook_command _csh_count _csh_existing _csh_backup
        return 1
    fi

    _csh_tmp=$(mktemp "${_csh_source_file}.XXXXXX") || {
        command rm -f "$_csh_backup"
        unset _csh_dotfiles _csh_source_file _csh_hook_command _csh_count _csh_existing _csh_backup
        return 1
    }

    # shellcheck disable=SC2016
    if jq --arg cmd "$_csh_hook_command" \
        '.hooks = ((.hooks // {}) | .Stop = ((.Stop // []) + [{"hooks":[{"type":"command","command":$cmd}]}]))' \
        "$_csh_source_file" >"$_csh_tmp" && command mv "$_csh_tmp" "$_csh_source_file"; then
        echo "claude/settings.json: gh-issue-flow Stop hook 자동 등록 (issue #505 / #383, backup: $_csh_backup)" >&2
        _csh_rc=0
    else
        command rm -f "$_csh_tmp"
        echo "claude/settings.json: Stop hook 등록 실패 — 백업 보존 ($_csh_backup)" >&2
        _csh_rc=1
    fi

    unset _csh_dotfiles _csh_source_file _csh_hook_command _csh_count _csh_existing _csh_backup _csh_tmp
    return ${_csh_rc:-0}
}

# Auto-fire only on interactive shells. Silent fast-path on no-op; the
# install path emits a single stderr line. Errors are swallowed
# (`|| true`) so a settings.json write failure never aborts shell init.
case $- in
    *i*) _claude_install_gh_issue_flow_stop_hook || true ;;
esac
