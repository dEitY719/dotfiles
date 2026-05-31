#!/usr/bin/env bats
# tests/bats/functions/gcp.bats
# Tests for issue #697 — gcp_* family unified under the 'gcp <verb>' Type 2A
# dispatcher (docs/.ssot/command-design-pattern.md §4).
#
# Behavior under test:
#   - 'gcp' is a function (dispatcher), not the bash-only integrations version.
#   - Private sub-functions _gcp_scan/_gcp_theirs/_gcp_ours/_gcp_author/_gcp_pick
#     exist and are wired through the dispatcher.
#   - Help is reachable as 'gcp', 'gcp -h', 'gcp --help', 'gcp help',
#     'gcp help <section>', 'gcp help --list', 'gcp help --all'.
#   - The deprecated forms 'gcp_scan', 'gcp-scan', 'gcp_theirs', 'gcp_ours',
#     'gcp_author' still work as aliases routing through 'gcp <verb>'.
#   - 'gcp <unknown-verb>' returns 1 with 'Run: gcp help' hint (Type 2A §6).
#   - 'gcp <committish>' is bridged to 'gcp pick' with a deprecation warning.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Function / alias existence
# ---------------------------------------------------------------------------

@test "bash: gcp dispatcher function exists" {
    run_in_bash 'declare -f gcp >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_scan private function exists" {
    run_in_bash 'declare -f _gcp_scan >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_theirs private function exists" {
    run_in_bash 'declare -f _gcp_theirs >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_ours private function exists" {
    run_in_bash 'declare -f _gcp_ours >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_author private function exists" {
    run_in_bash 'declare -f _gcp_author >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_pick private function exists" {
    run_in_bash 'declare -f _gcp_pick >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gcp_help standalone help exists" {
    run_in_bash 'declare -f gcp_help >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gcp_scan alias maps to 'gcp scan'" {
    run_in_bash 'alias gcp_scan'
    assert_success
    assert_output --partial "gcp scan"
}

@test "bash: gcp-scan alias maps to 'gcp scan'" {
    run_in_bash 'alias gcp-scan'
    assert_success
    assert_output --partial "gcp scan"
}

@test "bash: gcp_theirs alias maps to 'gcp theirs'" {
    run_in_bash 'alias gcp_theirs'
    assert_success
    assert_output --partial "gcp theirs"
}

@test "bash: gcp_ours alias maps to 'gcp ours'" {
    run_in_bash 'alias gcp_ours'
    assert_success
    assert_output --partial "gcp ours"
}

@test "bash: gcp_author alias maps to 'gcp author'" {
    run_in_bash 'alias gcp_author'
    assert_success
    assert_output --partial "gcp author"
}

@test "bash: gcp-help alias maps to gcp_help" {
    run_in_bash 'alias gcp-help'
    assert_success
    assert_output --partial "gcp_help"
}

# ---------------------------------------------------------------------------
# Help entry points
# ---------------------------------------------------------------------------

@test "help: bare 'gcp' invocation shows help (no error)" {
    run_in_bash 'gcp'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp -h' shows help" {
    run_in_bash 'gcp -h'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp --help' shows help" {
    run_in_bash 'gcp --help'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp help' shows help" {
    run_in_bash 'gcp help'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp help scan' shows section detail" {
    run_in_bash 'gcp help scan'
    assert_success
    assert_output --partial "scan"
}

@test "help: 'gcp help --list' lists sections" {
    run_in_bash 'gcp help --list'
    assert_success
    assert_output --partial "scan"
    assert_output --partial "theirs"
    assert_output --partial "ours"
    assert_output --partial "author"
    assert_output --partial "pick"
}

@test "help: summary lists all 5 verbs" {
    run_in_bash 'gcp help'
    assert_output --partial "scan"
    assert_output --partial "theirs"
    assert_output --partial "ours"
    assert_output --partial "author"
    assert_output --partial "pick"
}

# ---------------------------------------------------------------------------
# Dispatcher behavior
# ---------------------------------------------------------------------------

@test "dispatch: unknown sub-command returns error + 'Run: gcp help' hint" {
    run_in_bash 'gcp definitely-not-a-verb'
    assert_failure
    assert_output --partial "Unknown command"
    assert_output --partial "Run: gcp help"
}

@test "dispatch: 'gcp pick' (no args) prints usage and returns 1" {
    run_in_bash 'gcp pick'
    assert_failure
    assert_output --partial "gcp pick"
}

@test "dispatch: 'gcp theirs' (no args) prints usage and returns 1" {
    run_in_bash 'gcp theirs'
    assert_failure
    assert_output --partial "gcp theirs"
}

@test "dispatch: 'gcp author' (no args) prints usage and returns 1" {
    run_in_bash 'gcp author'
    assert_failure
    assert_output --partial "gcp author"
}

# ---------------------------------------------------------------------------
# Bare-form deprecation bridge: 'gcp <committish>' -> '_gcp_pick' + warning
# ---------------------------------------------------------------------------

@test "dispatch: bare committish triggers deprecation bridge" {
    # Stub `git cherry-pick` so the deprecation warning fires inside the
    # dispatcher but the actual cherry-pick is a no-op — keeps the working
    # tree clean across test runs (no leftover CHERRY_PICK_HEAD state).
    # `git rev-parse` (used by _gcp_committish_p) must still pass through to
    # the real git so the heuristic correctly classifies HEAD as commit-ish.
    run_in_bash '
        cd "$DOTFILES_ROOT"
        git() {
            if [ "$1" = "cherry-pick" ]; then
                echo "stubbed: git cherry-pick $*" >&2
                return 1
            fi
            command git "$@"
        }
        gcp "$(command git rev-parse HEAD)"
    '
    assert_output --partial "Deprecated: bare 'gcp <commit>'"
    assert_output --partial "Use: gcp pick"
}

@test "preflight: _gcp_assert_no_cherry_pick aborts when CHERRY_PICK_HEAD exists (PR #698)" {
    # Stub git so rev-parse --verify CHERRY_PICK_HEAD returns 0 (i.e. a
    # cherry-pick is in progress). The helper must emit the recovery hint
    # AND return 1 — used by _gcp_strategy_pick / _gcp_author / _gcp_pick.
    run_in_bash '
        cd "$DOTFILES_ROOT"
        git() {
            case " $* " in
                *" CHERRY_PICK_HEAD "*) return 0 ;;
            esac
            command git "$@"
        }
        _gcp_assert_no_cherry_pick
        echo "rc=$?"
    '
    assert_output --partial "Cherry-pick currently in progress"
    assert_output --partial "git cherry-pick --continue"
    assert_output --partial "git cherry-pick --abort"
    assert_output --partial "rc=1"
}

@test "preflight: _gcp_strategy_pick refuses to start when cherry-pick in progress (PR #698)" {
    run_in_bash '
        cd "$DOTFILES_ROOT"
        git() {
            case " $* " in
                *" CHERRY_PICK_HEAD "*) return 0 ;;
            esac
            command git "$@"
        }
        _gcp_strategy_pick "" abc1234
        echo "rc=$?"
    '
    assert_output --partial "Cherry-pick currently in progress"
    assert_output --partial "rc=1"
}

@test "preflight: _gcp_author refuses to start when cherry-pick in progress (PR #698)" {
    run_in_bash '
        cd "$DOTFILES_ROOT"
        git() {
            case " $* " in
                *" CHERRY_PICK_HEAD "*) return 0 ;;
            esac
            command git "$@"
        }
        _gcp_author "abc..def" someone
        echo "rc=$?"
    '
    assert_output --partial "Cherry-pick currently in progress"
    assert_output --partial "rc=1"
}

@test "preflight: _gcp_strategy_pick emits recovery hint on conflict (PR #698)" {
    # Stub git so cherry-pick returns 1 (conflict). rev-parse must still
    # pass through (the helper uses it for the pre-flight check, which
    # should NOT trip for the stubbed CHERRY_PICK_HEAD case).
    run_in_bash '
        cd "$DOTFILES_ROOT"
        git() {
            case "$1" in
                cherry-pick) return 1 ;;
                rev-parse)
                    case " $* " in
                        *" CHERRY_PICK_HEAD "*) return 1 ;;
                    esac
                    command git "$@" ;;
                *) command git "$@" ;;
            esac
        }
        _gcp_pick abc1234
        echo "rc=$?"
    '
    assert_output --partial "Cherry-pick failed"
    assert_output --partial "Resolve with: git cherry-pick --continue"
    assert_output --partial "rc=1"
}

@test "dispatch: non-committish unknown arg does NOT bridge to pick" {
    run_in_bash 'cd "$DOTFILES_ROOT" && gcp not-a-real-commit-or-verb'
    assert_failure
    assert_output --partial "Unknown command"
    refute_output --partial "Deprecated:"
}

# ---------------------------------------------------------------------------
# Loader sanity: tools/integrations/git.sh no longer defines gcp
# (would shadow the dispatcher since integrations/ loads after functions/)
# ---------------------------------------------------------------------------

@test "loader: 'gcp' resolves to the dispatcher in shell-common/functions/gcp.sh" {
    run_in_bash 'declare -f gcp | head -1'
    assert_success
    assert_output --partial "gcp"
}

@test "loader: tools/integrations/git.sh no longer declares the gcp family" {
    run grep -E '^(gcp|gcp_theirs|gcp_ours|gcp_author|_git_cherry_pick) *\(\)' \
        "${DOTFILES_ROOT}/shell-common/tools/integrations/git.sh"
    assert_failure
}

# ---------------------------------------------------------------------------
# Issue #700 regression — OMZ alias shadowing (mirrors #692 pattern in
# tests/bats/functions/git_worktree_alias_shadow.bats).
#
# Without `unalias gcp` at the top of gcp.sh, OMZ git plugin's
# `alias gcp='git cherry-pick'` is still active when zsh/main.zsh sources
# gcp.sh — zsh expands aliases at parse time, turning `gcp() {` into
# `git cherry-pick () {` and producing a parse error. The dispatcher is
# never defined and bare `gcp` silently degrades to the OMZ alias.
#
# These tests pre-declare the conflicting alias, source dotfiles' zsh
# loader, then assert (a) `whence -w gcp` reports a function (existence)
# and (b) `eval 'gcp -h'` invokes the dispatcher rather than the
# shadowed `git cherry-pick` (dispatch). `eval` in (b) is load-bearing —
# in `zsh -fc "..."` the whole script string is parsed before runtime
# `alias` commands take effect, so a plain `gcp -h` is never
# alias-expanded (false positive). `eval` forces a runtime re-parse at
# the point where the alias *is* registered, exactly mirroring #692
# (PR #693 review).
# ---------------------------------------------------------------------------

@test "alias-shadow: pre-existing 'alias gcp=git cherry-pick' removed when dotfiles loads (zsh) (#700)" {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        alias gcp='git cherry-pick'
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        whence -w gcp
    "
    assert_success
    assert_output --partial "gcp: function"
    refute_output --partial "gcp: alias"
}

# ---------------------------------------------------------------------------
# Issue #811 — individual (non-contiguous) cherry-pick auto-skips Stage-1
# duplicates with a log line, instead of attempting them and conflicting.
#
# Fixture commit tree (author = all, so author filter is a no-op):
#   main:   C0 "init"  ->  M1 "shared dup subject"
#   source: C0 "init"  ->  S1 "feat one" -> S2 "shared dup subject" -> S3 "feat three"
# S2 shares M1's subject (dup) but a different patch, so `git cherry` still
# lists it as missing. final_selected_list = {S1,S3} (count 2) but the range
# S1^..S3 spans 3 commits -> non-contiguous -> individual cherry-pick path.
# ---------------------------------------------------------------------------

_gcp811_make_repo() {
    # Emits shell that builds the dup fixture in a fresh temp repo and cds in.
    cat <<'FIXTURE'
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        git checkout -q -b source
        echo one > f1.txt && git add f1.txt && git commit -qm "feat one"
        echo dupsrc > f2.txt && git add f2.txt && git commit -qm "shared dup subject"
        echo three > f3.txt && git add f3.txt && git commit -qm "feat three"
        git checkout -q main
        echo dupbase > onbase.txt && git add onbase.txt && git commit -qm "shared dup subject"
FIXTURE
}

@test "scan #811: non-contiguous dup is skipped (not cherry-picked) with base SHA logged" {
    run_in_bash "
        $(_gcp811_make_repo)
        base_dup_sha=\$(git rev-parse --short main)
        printf 'y\n' | _gcp_scan main source --author=all
    "
    assert_success
    # F-3: skip log naming the matching base SHA.
    assert_output --partial "Skipping"
    assert_output --partial "already applied as"
    assert_output --partial "(duplicate subject)"
    # F-4: summary reports 1 dup skipped, 0 conflicts.
    assert_output --partial "skipped (dup), 0 conflicts"
    # The dup commit's own file must NOT have been applied to main.
    refute_output --partial "CONFLICT"
}

@test "scan #811: dup commit's payload is absent, non-dup commits are applied" {
    run_in_bash "
        $(_gcp811_make_repo)
        printf 'y\n' | _gcp_scan main source --author=all >/dev/null 2>&1
        # Non-dup commits applied:
        git cat-file -e HEAD:f1.txt && echo HAS_F1
        git cat-file -e HEAD:f3.txt && echo HAS_F3
        # Dup commit (f2.txt) skipped -> absent on main:
        git cat-file -e HEAD:f2.txt 2>/dev/null && echo HAS_F2 || echo NO_F2
    "
    assert_success
    assert_output --partial "HAS_F1"
    assert_output --partial "HAS_F3"
    assert_output --partial "NO_F2"
}

@test "scan #811: contiguous no-dup path is unchanged (NF-1) — clean range pick" {
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        git checkout -q -b source
        echo one > f1.txt && git add f1.txt && git commit -qm "feat one"
        echo two > f2.txt && git add f2.txt && git commit -qm "feat two"
        git checkout -q main
        printf "y\n" | _gcp_scan main source --author=all
        git cat-file -e HEAD:f1.txt && echo HAS_F1
        git cat-file -e HEAD:f2.txt && echo HAS_F2
    '
    assert_success
    assert_output --partial "Range is contiguous"
    assert_output --partial "Cherry-pick complete"
    assert_output --partial "HAS_F1"
    assert_output --partial "HAS_F2"
    refute_output --partial "skipped (dup)"
}

# ---------------------------------------------------------------------------
# Issue #903 — content-based pre-flight skip. Stage-1 (subject-based) dup
# detection misses a commit whose subject is unique but whose payload already
# landed in HEAD via a different path (merge / squash / edit). Cherry-picking
# it conflicts, resolves to empty, and forces an endless conflict -> --skip
# loop. `_gcp_scan_already_in_head` catches it before the cherry-pick attempt.
# ---------------------------------------------------------------------------

@test "bash: _gcp_scan_already_in_head private function exists" {
    run_in_bash 'declare -f _gcp_scan_already_in_head >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "preflight #903: empty commit (no file changes) -> already in HEAD (0)" {
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo v1 > a.txt && git add a.txt && git commit -qm "init"
        git commit -q --allow-empty -m "empty"
        empty_sha=$(git rev-parse HEAD)
        _gcp_scan_already_in_head "$empty_sha"
        echo "rc=$?"
    '
    assert_success
    assert_output --partial "rc=0"
}

@test "preflight #903: all touched files identical to HEAD -> already in HEAD (0)" {
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo v1 > a.txt && git add a.txt && git commit -qm "init"
        git checkout -q -b side
        echo v2 > a.txt && git add a.txt && git commit -qm "side: bump to v2"
        side_sha=$(git rev-parse HEAD)
        git checkout -q main
        # HEAD reaches the SAME content for a.txt via a different commit.
        echo v2 > a.txt && git add a.txt && git commit -qm "main: bump to v2 (other path)"
        _gcp_scan_already_in_head "$side_sha"
        echo "rc=$?"
    '
    assert_success
    assert_output --partial "rc=0"
}

@test "preflight #903: some touched files differ from HEAD -> NOT in HEAD (1)" {
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo v1 > a.txt && git add a.txt && git commit -qm "init"
        git checkout -q -b side
        echo only-on-side > b.txt && echo shared > c.txt && git add b.txt c.txt \
            && git commit -qm "side: add b and c"
        side_sha=$(git rev-parse HEAD)
        git checkout -q main
        # HEAD matches c.txt but never gets b.txt -> real work remains.
        echo shared > c.txt && git add c.txt && git commit -qm "main: add c only"
        _gcp_scan_already_in_head "$side_sha"
        echo "rc=$?"
    '
    assert_success
    assert_output --partial "rc=1"
}

@test "scan #903: content-dup commit (unique subject, different patch-id) skipped via pre-flight, no conflict" {
    # The content-dup commit must reach the individual loop, so its patch-id
    # has to DIFFER from how HEAD acquired the same final content (else
    # `git cherry` filters it out up front). HEAD reaches shared.txt=TARGET via
    # MIDDLE (two-step), source reaches it in one step from a different parent
    # -> distinct patch-ids, unique subject. A separate subject-dup commit
    # creates the gap that forces the non-contiguous (individual) path.
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        git checkout -q -b source
        echo one > f1.txt && git add f1.txt && git commit -qm "feat one"
        echo dupsrc > f2.txt && git add f2.txt && git commit -qm "shared dup subject"
        # Unique subject; creates shared.txt=TARGET in one step.
        echo TARGET > shared.txt && git add shared.txt && git commit -qm "feat: bring shared payload"
        echo four > f4.txt && git add f4.txt && git commit -qm "feat four"
        git checkout -q main
        echo dupbase > onbase.txt && git add onbase.txt && git commit -qm "shared dup subject"
        # HEAD reaches shared.txt=TARGET via a DIFFERENT path (MIDDLE -> TARGET)
        # so the patch-id differs from source -> git cherry still lists it.
        echo MIDDLE > shared.txt && git add shared.txt && git commit -qm "wip shared"
        echo TARGET > shared.txt && git add shared.txt && git commit -qm "finalize shared"
        printf "y\n" | _gcp_scan main source --author=all
    '
    assert_success
    # Subject-dup still handled by Stage-1.
    assert_output --partial "already applied as"
    # Content-dup caught by the new pre-flight.
    assert_output --partial "changes already in HEAD (pre-flight)"
    refute_output --partial "CONFLICT"
    refute_output --partial "Resolve and run"
}

@test "alias-shadow: 'gcp -h' invokes dispatcher (not shadowed git cherry-pick) in zsh (#700)" {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        alias gcp='git cherry-pick'
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        eval 'gcp -h'
    "
    assert_success
    assert_output --partial "Usage: gcp help"
}
