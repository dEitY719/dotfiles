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
    # ~/dotfiles existing is not enough: on a host where it is an unrelated
    # clone (a fork developed elsewhere, a leftover from an old setup) the
    # guard is *right* to warn, so asserting silence would false-fail. Reuse
    # the production repo-identity helper so this check can never drift from
    # the one under test.
    . "$HELPER"
    _this_common=$(_dotfiles_root_git_common_dir "$(dirname "$HELPER")")
    _canon_common=$(_dotfiles_root_git_common_dir "$_REAL_HOME_1454/dotfiles")
    if [ "$_this_common" != "$_canon_common" ]; then
        skip "~/dotfiles on this host is a different repository than this checkout"
    fi

    run env HOME="$_REAL_HOME_1454" bash -c \
        ". '$HELPER' && _dotfiles_root_warn_if_foreign_source '$HELPER'"
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# _dotfiles_root_guard_self (issue #1505)
#
# The shared caller-side entry point every guarded helper file calls right
# after sourcing this helper. It owns the `command -v` probe, the call, and
# the #724 diagnostic — logic that used to be copy-pasted per caller.
# ---------------------------------------------------------------------------

@test "_dotfiles_root_guard_self: forwards a foreign checkout to the WARN block" {
    _setup_fake_home_dotfiles
    _setup_foreign_repo guardself

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_guard_self '$FOREIGN' 'probe_label'"
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "$FOREIGN"
}

@test "_dotfiles_root_guard_self: canonical checkout stays silent" {
    _setup_fake_home_dotfiles

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' && _dotfiles_root_guard_self '$CANON/shell-common/functions/probe.sh' 'probe_label'"
    assert_success
    assert_output ""
}

# #724: the helper file parsed far enough to define _dotfiles_root_guard_self
# but a regression left _dotfiles_root_warn_if_foreign_source undefined. That
# must say so once on stderr instead of disabling the guard in silence.
@test "_dotfiles_root_guard_self: #724 diagnostic when the warn function is undefined" {
    _setup_fake_home_dotfiles
    _setup_foreign_repo guardself724

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' \
            && unset -f _dotfiles_root_warn_if_foreign_source \
            && _dotfiles_root_guard_self '$FOREIGN' 'probe_label'"
    assert_success
    assert_output --partial "[probe_label]"
    assert_output --partial "did not define _dotfiles_root_warn_if_foreign_source"
    assert_output --partial "#1454 guard skipped (#724)"
    assert_output --partial "functions/dotfiles_root.sh"
}

@test "_dotfiles_root_guard_self: #724 diagnostic falls back to the 'dotfiles' label" {
    _setup_fake_home_dotfiles

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' \
            && unset -f _dotfiles_root_warn_if_foreign_source \
            && _dotfiles_root_guard_self '/no/such/file.sh'"
    assert_success
    assert_output --partial "[dotfiles]"
    assert_output --partial "#1454 guard skipped (#724)"
}

@test "_dotfiles_root_guard_self: #724 diagnostic goes to stderr, not stdout" {
    _setup_fake_home_dotfiles

    run env HOME="$FAKE_HOME" bash -c \
        ". '$HELPER' \
            && unset -f _dotfiles_root_warn_if_foreign_source \
            && _dotfiles_root_guard_self '/no/such/file.sh' 'probe_label' 2>/dev/null"
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Canonical-side cache (issue #1505)
#
# The $HOME/dotfiles --git-common-dir lookup is memoized per process so seven
# guarded helper files in one shell startup don't re-fork it seven times. The
# cache is keyed on the VALUE of $HOME: bats flips $HOME per test and real
# callers do it too, so a cache that only remembered "already computed" would
# hand back the previous HOME's canonical repo and invert the verdict.
# ---------------------------------------------------------------------------

# Every call is redirected with `2>FILE`, never piped: a pipeline would run
# the function in a subshell, the cache write would be thrown away, and the
# test would pass against a broken cache by accident.
@test "#1505 cache: canonical side is re-resolved after \$HOME changes in-process" {
    _setup_fake_home_dotfiles
    _setup_foreign_repo alt

    # $FOREIGN lives in $SCRATCH/alt/dotfiles, so it is foreign under
    # HOME=$FAKE_HOME and canonical under HOME=$SCRATCH/alt. Three calls in
    # ONE process, flipping $HOME between them: a cache that is not keyed on
    # $HOME makes B warn (verified against a deliberately unkeyed build).
    local script="$BATS_TEST_TMPDIR/cache_home_flip.sh"
    local outdir="$BATS_TEST_TMPDIR/cache_home_flip_out"
    mkdir -p "$outdir"
    cat >"$script" <<'SH'
. "$HELPER"
export HOME="$HOME_A"
_dotfiles_root_warn_if_foreign_source "$SELF" 2>"$OUT/a"
export HOME="$HOME_B"
_dotfiles_root_warn_if_foreign_source "$SELF" 2>"$OUT/b"
export HOME="$HOME_A"
_dotfiles_root_warn_if_foreign_source "$SELF" 2>"$OUT/c"
printf 'A=[%s]\n' "$(head -1 "$OUT/a")"
printf 'B=[%s]\n' "$(head -1 "$OUT/b")"
printf 'C=[%s]\n' "$(head -1 "$OUT/c")"
SH

    run env HELPER="$HELPER" HOME_A="$FAKE_HOME" HOME_B="$SCRATCH/alt" \
        SELF="$FOREIGN" OUT="$outdir" bash "$script"
    assert_success
    assert_line --partial "A=[[WARN] dotfiles: loaded from a foreign checkout"
    assert_line "B=[]"
    assert_line --partial "C=[[WARN] dotfiles: loaded from a foreign checkout"
}

@test "#1505 cache: repeated calls under one \$HOME keep the same verdict" {
    _setup_fake_home_dotfiles
    _setup_foreign_repo repeat

    local script="$BATS_TEST_TMPDIR/cache_repeat.sh"
    local outdir="$BATS_TEST_TMPDIR/cache_repeat_out"
    mkdir -p "$outdir"
    cat >"$script" <<'SH'
. "$HELPER"
export HOME="$HOME_A"
i=1
while [ "$i" -le 3 ]; do
    _dotfiles_root_warn_if_foreign_source "$SELF" 2>"$OUT/r$i"
    printf 'R%s=[%s]\n' "$i" "$(head -1 "$OUT/r$i")"
    i=$((i + 1))
done
SH

    run env HELPER="$HELPER" HOME_A="$FAKE_HOME" SELF="$FOREIGN" \
        OUT="$outdir" bash "$script"
    assert_success
    assert_line --partial "R1=[[WARN] dotfiles: loaded from a foreign checkout"
    assert_line --partial "R2=[[WARN] dotfiles: loaded from a foreign checkout"
    assert_line --partial "R3=[[WARN] dotfiles: loaded from a foreign checkout"
}

@test "_dotfiles_root_canonical_common_dir: agrees with the uncached resolver" {
    _setup_fake_home_dotfiles

    run env HOME="$FAKE_HOME" bash -c "
        . '$HELPER'
        a=\$(_dotfiles_root_git_common_dir '$CANON')
        _dotfiles_root_canonical_common_dir '$CANON'
        b=\"\$_DOTFILES_ROOT_CANON_COMMON\"
        _dotfiles_root_canonical_common_dir '$CANON'
        c=\"\$_DOTFILES_ROOT_CANON_COMMON\"
        [ -n \"\$a\" ] && [ \"\$a\" = \"\$b\" ] && [ \"\$b\" = \"\$c\" ] && echo \"same:\$a\"
    "
    assert_success
    assert_output --partial "same:"
}

# The memoization writes a global, so it only works when the function is
# called in the CURRENT shell. A \$(...) capture would silently make every
# call a cache miss — pin the global-setting contract so a future refactor
# back to stdout is caught here rather than showing up as lost perf.
@test "_dotfiles_root_canonical_common_dir: second call is served from the cache" {
    _setup_fake_home_dotfiles

    run env HOME="$FAKE_HOME" bash -c "
        . '$HELPER'
        _dotfiles_root_canonical_common_dir '$CANON'
        # Point the cached value at a sentinel: a genuine cache hit returns it
        # untouched, a cache miss would overwrite it with the real path.
        _DOTFILES_ROOT_CANON_COMMON='SENTINEL'
        _dotfiles_root_canonical_common_dir '$CANON'
        echo \"cached=\$_DOTFILES_ROOT_CANON_COMMON\"
    "
    assert_success
    assert_output "cached=SENTINEL"
}

@test "_dotfiles_root_canonical_common_dir: non-git dir fails and is not cached" {
    _setup_fake_home_dotfiles
    mkdir -p "$SCRATCH/notgit"

    run env HOME="$FAKE_HOME" bash -c "
        . '$HELPER'
        _dotfiles_root_canonical_common_dir '$SCRATCH/notgit' && echo unexpected-success
        echo \"rc=\$?\"
        echo \"empty=[\$_DOTFILES_ROOT_CANON_COMMON]\"
        # A failed lookup must leave the cache empty so a later, valid
        # canonical dir under the same \$HOME is still resolved.
        _dotfiles_root_canonical_common_dir '$CANON' && echo second-ok
    "
    assert_success
    assert_output --partial "rc=1"
    assert_output --partial "empty=[]"
    assert_output --partial "second-ok"
    refute_output --partial "unexpected-success"
}
