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

# Captured at file-load time — setup_isolated_home replaces $HOME with a
# tmpdir, and the #1454 guard reads $HOME directly.
_REAL_HOME_1454="$HOME"

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

# ---------------------------------------------------------------------------
# _dotfiles_root_warn_if_foreign_source (issue #1454)
#
# The function reads $HOME directly, so each case fakes a HOME whose
# `dotfiles` child is the scratch repo under test. $MAIN is renamed-in-place
# by symlink-free layout: HOME is $SCRATCH and the canonical checkout is
# $SCRATCH/dotfiles, built as a sibling of $MAIN.
# ---------------------------------------------------------------------------

# Build $SCRATCH/dotfiles (the fake $HOME/dotfiles) as a main worktree, plus
# $SCRATCH/dotfiles-wt as a linked worktree of that same repo.
_setup_fake_home_dotfiles() {
    FAKE_HOME="$SCRATCH"
    CANON="$FAKE_HOME/dotfiles"
    CANON_WT="$FAKE_HOME/dotfiles-wt"
    mkdir -p "$CANON/shell-common/functions"
    (cd "$CANON" && git init -q -b main && \
        git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init && \
        git worktree add -q -b wtbranch "$CANON_WT" >/dev/null 2>&1)
    mkdir -p "$CANON_WT/shell-common/functions"
    : >"$CANON/shell-common/functions/probe.sh"
    : >"$CANON_WT/shell-common/functions/probe.sh"
}

# Build $SCRATCH/<NAME>/dotfiles as its own standalone repo (a different
# --git-common-dir than $CANON) and sets FOREIGN to its probe.sh path.
# Shared by the "genuinely different repo" and "stderr not stdout" tests.
_setup_foreign_repo() {
    _sfr_name="${1:?_setup_foreign_repo requires a NAME arg}"
    FOREIGN_DIR="$SCRATCH/$_sfr_name/dotfiles"
    mkdir -p "$FOREIGN_DIR/shell-common/functions"
    (cd "$FOREIGN_DIR" && git init -q -b main && \
        git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init)
    FOREIGN="$FOREIGN_DIR/shell-common/functions/probe.sh"
    : >"$FOREIGN"
}

@test "_dotfiles_root_warn_if_foreign_source: canonical \$HOME/dotfiles path is silent" {
    _setup_fake_home_dotfiles
    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$CANON/shell-common/functions/probe.sh'"
    assert_success
    assert_output ""
}

@test "_dotfiles_root_warn_if_foreign_source: linked worktree of the same repo is silent" {
    _setup_fake_home_dotfiles
    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$CANON_WT/shell-common/functions/probe.sh'"
    assert_success
    assert_output ""
}

@test "_dotfiles_root_warn_if_foreign_source: a genuinely different repo warns with both paths" {
    _setup_fake_home_dotfiles
    _setup_foreign_repo foreign

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$FOREIGN'"
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "$FOREIGN"
    assert_output --partial "$CANON"
}

@test "_dotfiles_root_warn_if_foreign_source: submodule checkout named dotfiles warns" {
    _setup_fake_home_dotfiles
    PARENT="$SCRATCH/parent"
    mkdir -p "$PARENT"
    (cd "$PARENT" && git init -q -b main && \
        git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init && \
        git -c protocol.file.allow=always submodule add -q "$MAIN" dotfiles)
    SUB="$PARENT/dotfiles"
    mkdir -p "$SUB/shell-common/functions"
    : >"$SUB/shell-common/functions/probe.sh"

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$SUB/shell-common/functions/probe.sh'"
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "$SUB/shell-common/functions/probe.sh"
}

@test "_dotfiles_root_warn_if_foreign_source: warning goes to stderr, not stdout" {
    _setup_fake_home_dotfiles
    _setup_foreign_repo foreign2

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$FOREIGN' 2>/dev/null"
    assert_success
    assert_output ""
}

@test "_dotfiles_root_warn_if_foreign_source: missing \$HOME/dotfiles is silent" {
    EMPTY_HOME="$SCRATCH/emptyhome"
    mkdir -p "$EMPTY_HOME"
    : >"$MAIN/probe.sh"
    run env HOME="$EMPTY_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$MAIN/probe.sh'"
    assert_success
    assert_output ""
}

@test "_dotfiles_root_warn_if_foreign_source: empty SELF_PATH is a silent no-op" {
    _setup_fake_home_dotfiles
    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source ''"
    assert_success
    assert_output ""
}

@test "_dotfiles_root_warn_if_foreign_source: missing SELF_PATH arg is a silent no-op" {
    _setup_fake_home_dotfiles
    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source"
    assert_success
    assert_output ""
}

@test "_dotfiles_root_warn_if_foreign_source: nonexistent SELF_PATH file is a silent no-op" {
    _setup_fake_home_dotfiles
    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '/no/such/file.sh'"
    assert_success
    assert_output ""
}

# The dotfiles repo's own tree is the real-world regression case: this suite
# runs from a linked worktree, which must never warn when ~/dotfiles is the
# same repository.
@test "_dotfiles_root_warn_if_foreign_source: this checkout against a real ~/dotfiles is silent" {
    if [ ! -e "$_REAL_HOME_1454/dotfiles/.git" ]; then
        skip "no ~/dotfiles checkout on this host"
    fi
    run env HOME="$_REAL_HOME_1454" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$HELPER'"
    assert_success
    assert_output ""
}
