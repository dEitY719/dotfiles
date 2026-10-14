#!/usr/bin/env bats
# tests/bats/functions/help_native_format.bats
# #2136 deleted zz_help_standard_adapter.sh, which wrapped 57 topics at every
# shell start and registered their dash-form alias. Each topic now carries the
# native format itself (docs/.ssot/command-guidelines.md "Native 형식
# 체크리스트"). Pin, in bash and zsh, for every former adapter topic: the
# dispatcher, the _<topic>_help_summary helper, and the <topic-dash>-help alias.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# The adapter's hard-coded list, verbatim.
FORMER_ADAPTER_TOPICS='git gwt gbr uv py nvm npm bun pp cli ux du psql mytool
docker dproxy sys proxy ssl mount mysql redis gpu network claude cc agy codex
litellm ollama claude_plugins claude_skills_marketplace superpowers fzf fd fasd
ripgrep pet bat zsh zsh_autosuggestions gc tmux p10k crt apt pip ghostty dot
show_doc notion work_log work dir opencode category register'

# Prints one "MISSING <what> <topic>" line per gap, then "checked=<n>".
NATIVE_CHECK='
    n=0
    for t in '"$(printf '%s' "$FORMER_ADAPTER_TOPICS" | tr '\n' ' ')"'; do
        n=$((n + 1))
        command -v "${t}_help" >/dev/null 2>&1 || echo "MISSING dispatcher $t"
        command -v "_${t}_help_summary" >/dev/null 2>&1 || echo "MISSING summary $t"
        a="$(printf "%s" "$t" | tr _ -)-help"
        alias "$a" 2>/dev/null | grep -Eq "=.?${t}_help.?\$" || echo "MISSING alias $a"
    done
    echo "checked=$n"
'

@test "bash: every former adapter topic is native (dispatcher, summary, alias)" {
    run_in_bash "$NATIVE_CHECK"
    assert_success
    assert_output "checked=57"
}

@test "zsh: every former adapter topic is native (dispatcher, summary, alias)" {
    run_in_zsh "$NATIVE_CHECK"
    assert_success
    assert_output "checked=57"
}

@test "the help adapter is gone from the tree and the loader" {
    [ ! -e "${DOTFILES_ROOT}/shell-common/functions/zz_help_standard_adapter.sh" ]
    run grep -rn "apply_help_standard_adapter" \
        "${DOTFILES_ROOT}/shell-common" "${DOTFILES_ROOT}/bash" "${DOTFILES_ROOT}/zsh"
    assert_failure
}

# Ratchet for topics added after #2136: no adapter backfills them any more, so
# every registered topic must carry the summary helper and dash alias itself.
# Only these pre-existing exceptions may lack one; shrink the list, never grow it.
LEGACY_NON_NATIVE=' del_file_help devx_help my_help_impl
show_devx_pr_verify_live_backend_identity_help zsh_autosuggestions_install_help
gh_audit_builtin_workflows_help ghes_mirror_help gh_flow_help
gh_pr_approve_help gh_pr_reply_help gh_pr_review_help
mirror_pages_activate_help sync_to_deploy_help '

@test "every registered help topic is native, except the legacy allowlist" {
    run_in_bash '
        legacy=" $(printf "%s" "'"$LEGACY_NON_NATIVE"'" | tr "\n" " ") "
        for k in "${!HELP_DESCRIPTIONS[@]}"; do
            case "$legacy" in *" $k "*) continue ;; esac
            declare -F "_${k}_summary" >/dev/null || echo "MISSING summary $k"
            a="$(printf "%s" "${k%_help}" | tr _ -)-help"
            alias "$a" >/dev/null 2>&1 || echo "MISSING alias $a"
        done
        echo done
    '
    assert_success
    assert_output "done"
}
