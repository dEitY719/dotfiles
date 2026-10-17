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
        grep -q 'case \$- in \*i\*) \[ -n "\${_DOTFILES_LOADING_FUNCTIONS-}" \] && return 0' "$stub" ||
            fail "$name: no reverse guard"
        n=$((n + 1))
    done
    [ "$n" -eq 20 ] || fail "expected 20 stubs, found $n"
}

@test "bash -i: library functions are not loaded, bootstrap keeps dotfiles_root" {
    run bash --noprofile --norc -i -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}' SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_ROOT_NO_CANONICALIZE=1 HOME='${HOME}' TERM=dumb
        source '${DOTFILES_ROOT}/bash/main.bash' >/dev/null 2>'${TEST_TEMP_HOME}/load.err'
        echo LIBFNS=\$(declare -F | grep -c '_gh_pr_merge_train\|devx_pr_review_all')
        type _dotfiles_root_guard_self >/dev/null 2>&1 && echo GUARD=yes
        _codex_load_skill_sources 2>>'${TEST_TEMP_HOME}/load.err' && echo LAZY=yes
        # Outside the loader pass a stub still forwards, interactive or not.
        . '${SHELL_COMMON}/lib/devx_pr_review_all.sh' 2>>'${TEST_TEMP_HOME}/load.err'
        type _gh_pr_edit_safe_label >/dev/null 2>&1 || . '${SHELL_COMMON}/functions/gh_pr_edit_safe.sh'
        type _gh_pr_edit_safe_label >/dev/null 2>&1 && echo DIRECT=yes
    " 2>/dev/null
    assert_output --partial "LIBFNS=0"
    assert_output --partial "GUARD=yes"
    assert_output --partial "LAZY=yes"
    assert_output --partial "DIRECT=yes"
    # A lib sourced directly in an interactive shell must not reach a sibling
    # through a functions/ stub (which returns there) and warn (PR #2224 review).
    run grep -E 'guard skipped|did not define' "${TEST_TEMP_HOME}/load.err"
    assert_failure
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

# Caller audit (PR #2224 review): a file the interactive loader sources may
# name a lib-only function only if it loads that lib itself, or is a helper
# library whose callers run as non-interactive PATH executables (#2195).
@test "interactive-loaded files reach lib functions only through a direct lib source" {
    local sc="${SHELL_COMMON}" stub lib fns f hits bad=""
    fns=$(for stub in "$sc"/functions/*.sh; do
        grep -q '^# moved to lib/' "$stub" || continue
        grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$sc/lib/$(basename "$stub")" | tr -d '()'
    done | sort -u | paste -sd'|' -)
    [ -n "$fns" ]
    for f in "$sc"/env/*.sh "$sc"/aliases/*.sh "$sc"/functions/*.sh "$sc"/tools/integrations/*.sh; do
        grep -q '^# moved to lib/' "$f" && continue
        hits=$(grep -v '^[[:space:]]*#' "$f" | grep -owE "$fns" | sort -u | tr '\n' ' ')
        [ -n "$hits" ] || continue
        grep -q '/lib/[a-z_]*\.sh' "$f" && continue   # loads the lib itself
        case "$(basename "$f")" in
        # helper libraries run only via tools/custom/<name>.sh executables
        gh_flow.sh | gh_pr_review.sh | git_branch.sh) continue ;;
        gh_project_pat_help.sh) continue ;; # names _gh_resolve_host in help text only
        esac
        bad="$bad
$f: $hits"
    done
    [ -z "$bad" ] || fail "lib functions referenced without a lib source:$bad"
}
