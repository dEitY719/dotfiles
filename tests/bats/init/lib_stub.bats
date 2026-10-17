#!/usr/bin/env bats
# tests/bats/init/lib_stub.bats
# #2154: pure libraries live in shell-common/lib/; functions/<X>.sh is a
# re-source stub with a REVERSE interactive guard. Interactive shells never
# load them, non-interactive callers (skills, hooks, crons) still reach them.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "every lib/ library with a functions/ stub: stub is <=5 lines and names it" {
    local stub name n=0
    for stub in "${SHELL_COMMON}"/functions/*.sh; do
        grep -q '^# moved to lib/' "$stub" || continue
        name=$(basename "$stub")
        [ -f "${SHELL_COMMON}/lib/$name" ] || fail "$name: stub without lib/$name"
        [ "$(wc -l <"$stub")" -le 5 ] || fail "$name: stub longer than 5 lines"
        grep -q "/lib/$name\"\$" "$stub" || fail "$name: stub does not source lib/$name"
        grep -q 'case \$- in \*i\*) return 0' "$stub" || fail "$name: no reverse guard"
        n=$((n + 1))
    done
    [ "$n" -eq 20 ] || fail "expected 20 stubs, found $n"
}

@test "bash -i: library functions are not loaded, bootstrap keeps dotfiles_root" {
    run bash --noprofile --norc -i -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}' SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_ROOT_NO_CANONICALIZE=1 HOME='${HOME}' TERM=dumb
        source '${DOTFILES_ROOT}/bash/main.bash' >/dev/null 2>&1
        echo LIBFNS=\$(declare -F | grep -c '_gh_pr_merge_train\|devx_pr_review_all')
        type _dotfiles_root_guard_self >/dev/null 2>&1 && echo GUARD=yes
    " 2>/dev/null
    assert_output --partial "LIBFNS=0"
    assert_output --partial "GUARD=yes"
}

@test "zsh -i: library functions are not loaded" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -f -i -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}' SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_ROOT_NO_CANONICALIZE=1 HOME='${HOME}' ZDOTDIR='${HOME}' TERM=dumb
        source '${DOTFILES_ROOT}/zsh/main.zsh' >/dev/null 2>&1
        echo LIBFNS=\$(print -l \${(k)functions} | grep -c '_gh_pr_merge_train\|devx_pr_review_all')
    " 2>/dev/null
    assert_output --partial "LIBFNS=0"
}

@test "sh: a skill-style source of the functions/ stub still defines the library" {
    run sh -c "SHELL_COMMON='${SHELL_COMMON}'; . '${SHELL_COMMON}/functions/gh_host.sh'; type _gh_host_from_url"
    assert_success
    assert_output --partial "function"
}

@test "codex integration lazy-loads lib/skill_sources.sh" {
    run bash --noprofile --norc -c "
        export SHELL_COMMON='${SHELL_COMMON}' DOTFILES_FORCE_INIT=1
        . '${SHELL_COMMON}/tools/integrations/codex.sh' >/dev/null 2>&1
        _codex_load_skill_sources && type _skill_workspace_dirs >/dev/null && echo LAZY=ok
    "
    assert_output --partial "LAZY=ok"
}
