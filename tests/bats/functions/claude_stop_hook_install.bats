#!/usr/bin/env bats
# tests/bats/functions/claude_stop_hook_install.bats
# Verify shell-common/functions/claude_stop_hook_install.sh installs the
# gh-issue-flow Stop hook on interactive shell startup (issue #505).
#
# The helper is the runtime counterpart to
# claude/setup.sh:_migrate_install_gh_issue_flow_stop_hook — same
# idempotent migration, but fires once per interactive shell so users
# who never re-run setup.sh still get the harness backstop documented
# in claude/skills/gh-issue-flow/SKILL.md.

load '../test_helper'

HELPER_REL="shell-common/functions/claude_stop_hook_install.sh"

setup() {
    setup_isolated_home
    setup_isolated_dotfiles_root

    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — helper is a no-op without it"
    fi

    SETTINGS="${DOTFILES_ROOT}/claude/settings.json"
    HELPER="${DOTFILES_ROOT}/${HELPER_REL}"
}

teardown() {
    teardown_isolated_home
}

# shellcheck disable=SC2154
_count_hook_entries() {
    jq '[.hooks?.Stop?[]?.hooks?[]? | select(.command == $cmd)] | length' \
        --arg cmd '${HOME}/dotfiles/claude/hooks/gh_issue_flow_stop_guard.py' \
        "$1"
}

@test "installs hook when settings.json has no Stop block" {
    # Strip the .hooks.Stop entry that the template ships with so we
    # exercise the install path. Other fields stay intact.
    tmp="$(mktemp)"
    jq 'del(.hooks.Stop)' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    [ "$(_count_hook_entries "$SETTINGS")" = "0" ]

    run bash -c "
        set -e
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        source '${HELPER}'
        _claude_install_gh_issue_flow_stop_hook
    "
    assert_success
    assert_output --partial "자동 등록"
    [ "$(_count_hook_entries "$SETTINGS")" = "1" ]

    # Backup file with the documented prefix must exist.
    ls "${SETTINGS}".pre-stop-hook-fix-* >/dev/null 2>&1
}

@test "no-op when hook is already present (silent fast path)" {
    # Template ships with the hook entry → first call should be silent.
    [ "$(_count_hook_entries "$SETTINGS")" = "1" ]

    run bash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        source '${HELPER}'
        _claude_install_gh_issue_flow_stop_hook
    "
    assert_success
    [ -z "$output" ]
    [ "$(_count_hook_entries "$SETTINGS")" = "1" ]

    # No backup created on no-op path.
    ! ls "${SETTINGS}".pre-stop-hook-fix-* >/dev/null 2>&1
}

@test "preserves user-installed Stop hook (no clobber)" {
    # Replace the stop hook with a different command — represents user
    # customisation that the helper must NOT overwrite.
    tmp="$(mktemp)"
    jq '.hooks.Stop = [{"hooks":[{"type":"command","command":"/usr/local/bin/my-custom-hook"}]}]' \
        "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    [ "$(_count_hook_entries "$SETTINGS")" = "0" ]

    run bash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        source '${HELPER}'
        _claude_install_gh_issue_flow_stop_hook
    "
    assert_success
    [ "$(_count_hook_entries "$SETTINGS")" = "0" ]

    # Custom hook must still be there, untouched.
    custom=$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")
    [ "$custom" = "/usr/local/bin/my-custom-hook" ]
}

@test "second invocation after install is a no-op" {
    tmp="$(mktemp)"
    jq 'del(.hooks.Stop)' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"

    bash -c "export DOTFILES_ROOT='${DOTFILES_ROOT}'; source '${HELPER}'; _claude_install_gh_issue_flow_stop_hook" >/dev/null 2>&1
    [ "$(_count_hook_entries "$SETTINGS")" = "1" ]
    backup_count_before=$(ls "${SETTINGS}".pre-stop-hook-fix-* 2>/dev/null | wc -l)

    run bash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        source '${HELPER}'
        _claude_install_gh_issue_flow_stop_hook
    "
    assert_success
    [ -z "$output" ]
    [ "$(_count_hook_entries "$SETTINGS")" = "1" ]
    backup_count_after=$(ls "${SETTINGS}".pre-stop-hook-fix-* 2>/dev/null | wc -l)
    [ "$backup_count_before" = "$backup_count_after" ]
}

@test "function is callable and silent in non-interactive shell" {
    # The auto-fire at the bottom of the file is gated by `case \$-`,
    # so non-interactive sourcing must NOT modify settings.json or emit
    # output, but the function must still be defined.
    md5_before=$(md5sum "$SETTINGS" | awk '{print $1}')

    run bash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        source '${HELPER}'
        type _claude_install_gh_issue_flow_stop_hook >/dev/null && echo defined
    "
    assert_success
    assert_output --partial "defined"

    md5_after=$(md5sum "$SETTINGS" | awk '{print $1}')
    [ "$md5_before" = "$md5_after" ]
}
