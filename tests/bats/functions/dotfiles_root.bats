#!/usr/bin/env bats
# tests/bats/functions/dotfiles_root.bats
#
# Unit tests for shell-common/functions/dotfiles_root.sh — the worktree
# canonicalization helper that prevents ~/.claude-*/ symlinks from getting
# baked with a linked-worktree path that goes dangling on worktree removal
# (issue #589).
#
# A scratch git repo + worktree is built in $TEST_TEMP_HOME per test so we
# never depend on the dotfiles repo's own worktrees.

load '../test_helper'

setup() {
    setup_isolated_home
    SCRATCH="$TEST_TEMP_HOME/scratch"
    MAIN="$SCRATCH/main"
    WT="$SCRATCH/wt"
    mkdir -p "$MAIN"
    (cd "$MAIN" && git init -q -b main && \
        git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init && \
        git worktree add -q -b feat "$WT" >/dev/null 2>&1)

    HELPER="$_BATS_REAL_DOTFILES_ROOT/shell-common/functions/dotfiles_root.sh"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# _resolve_dotfiles_root_canonical
# ---------------------------------------------------------------------------

@test "_resolve_dotfiles_root_canonical: main worktree path is returned unchanged" {
    run bash -c ". '$HELPER' && _resolve_dotfiles_root_canonical '$MAIN'"
    assert_success
    assert_output "$MAIN"
}

@test "_resolve_dotfiles_root_canonical: linked worktree resolves to main" {
    run bash -c ". '$HELPER' && _resolve_dotfiles_root_canonical '$WT'"
    assert_success
    assert_output "$MAIN"
}

@test "_resolve_dotfiles_root_canonical: non-git path is returned unchanged" {
    run bash -c ". '$HELPER' && _resolve_dotfiles_root_canonical '$TEST_TEMP_HOME'"
    assert_success
    assert_output "$TEST_TEMP_HOME"
}

@test "_resolve_dotfiles_root_canonical: missing path is returned unchanged" {
    run bash -c ". '$HELPER' && _resolve_dotfiles_root_canonical '/no/such/dir'"
    assert_success
    assert_output "/no/such/dir"
}

@test "_resolve_dotfiles_root_canonical: empty candidate yields empty output" {
    run bash -c ". '$HELPER' && _resolve_dotfiles_root_canonical ''"
    assert_success
    assert_output ""
}

# Regression: a submodule checkout has --git-dir == --git-common-dir
# (both point at <parent>/.git/modules/<sub>), so walking `dirname` would
# falsely land on .git/modules — not a worktree. Helper must return the
# submodule path unchanged. Caught by gemini-code-assist on PR #593.
@test "_resolve_dotfiles_root_canonical: submodule checkout returns candidate (not .git/modules)" {
    PARENT="$SCRATCH/parent"
    mkdir -p "$PARENT"
    (cd "$PARENT" && git init -q -b main && \
        git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init && \
        git -c protocol.file.allow=always submodule add -q "$MAIN" sub)
    SUB="$PARENT/sub"

    run bash -c ". '$HELPER' && _resolve_dotfiles_root_canonical '$SUB'"
    assert_success
    assert_output "$SUB"
}

@test "_resolve_dotfiles_root_canonical: DOTFILES_ROOT_NO_CANONICALIZE=1 disables resolution" {
    run env DOTFILES_ROOT_NO_CANONICALIZE=1 bash -c \
        ". '$HELPER' && _resolve_dotfiles_root_canonical '$WT'"
    assert_success
    assert_output "$WT"
}

# ---------------------------------------------------------------------------
# _dotfiles_root_canonicalize (in-place re-export)
# ---------------------------------------------------------------------------

@test "_dotfiles_root_canonicalize: worktree path is rewritten to main" {
    run bash -c "
        export DOTFILES_ROOT='$WT'
        export SHELL_COMMON='$WT/shell-common'
        . '$HELPER'
        _dotfiles_root_canonicalize
        echo \"\$DOTFILES_ROOT|\$SHELL_COMMON\"
    "
    assert_success
    assert_output "$MAIN|$MAIN/shell-common"
}

@test "_dotfiles_root_canonicalize: main path is left untouched" {
    run bash -c "
        export DOTFILES_ROOT='$MAIN'
        export SHELL_COMMON='$MAIN/shell-common'
        . '$HELPER'
        _dotfiles_root_canonicalize
        echo \"\$DOTFILES_ROOT|\$SHELL_COMMON\"
    "
    assert_success
    assert_output "$MAIN|$MAIN/shell-common"
}

@test "_dotfiles_root_canonicalize: unset DOTFILES_ROOT is a no-op" {
    run bash -c "
        unset DOTFILES_ROOT SHELL_COMMON
        . '$HELPER'
        _dotfiles_root_canonicalize
        echo \"rc=\$?\"
    "
    assert_success
    assert_output "rc=0"
}
