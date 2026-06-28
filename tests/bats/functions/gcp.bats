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

@test "scan #811/#913: no-dup path applies every commit (individual iteration)" {
    # The contiguous range shortcut was removed in #913 — commits are always
    # iterated individually so the no-op pre-flight can never be bypassed.
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
    assert_output --partial "2 applied, 0 skipped (dup), 0 conflicts"
    assert_output --partial "HAS_F1"
    assert_output --partial "HAS_F2"
    refute_output --partial "no-op pre-flight"
}

# ---------------------------------------------------------------------------
# Issue #913 — merge-probe no-op pre-flight (supersedes #903/#907/#908/#910).
# `_gcp_scan_preflight_is_noop` runs `git cherry-pick -n` on a candidate and
# decides, from git's own merge result, whether the commit would add anything
# to HEAD. A clean apply with empty staged diff, or a conflict that resolves
# to HEAD with empty staged diff, is a no-op (skip). Anything leaving a
# non-empty staged diff is real work (keep). It absorbs the cases the earlier
# subject-based / file-compare / reverse-patch heuristics each missed, because
# it reuses the very engine the real cherry-pick would use. Reuses the #903
# bare-repo emitter `_gcp903_make_repo` for the shared git-init preamble.
# ---------------------------------------------------------------------------

_gcp903_make_repo() {
    # Emits shell that builds a fresh temp repo (main @ a.txt=v1) and cds in,
    # with EXIT cleanup. Mirrors _gcp811_make_repo; shared by the #903 unit
    # tests below so the mktemp/trap/git-init boilerplate lives in one place.
    cat <<'FIXTURE'
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo v1 > a.txt && git add a.txt && git commit -qm "init"
FIXTURE
}

@test "bash: _gcp_scan_preflight_is_noop private function exists" {
    run_in_bash 'declare -f _gcp_scan_preflight_is_noop >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "preflight #913: empty commit (no file changes) -> no-op (0)" {
    run_in_bash "
        $(_gcp903_make_repo)
        git checkout -q -b side
        git commit -q --allow-empty -m empty
        empty_sha=\$(git rev-parse HEAD)
        git checkout -q main
        _gcp_scan_preflight_is_noop \"\$empty_sha\"
        echo \"rc=\$?\"
    "
    assert_success
    assert_output --partial "rc=0"
}

@test "preflight #913: content already in HEAD via another path -> no-op (0)" {
    run_in_bash "
        $(_gcp903_make_repo)
        git checkout -q -b side
        echo v2 > a.txt && git add a.txt && git commit -qm 'side: bump to v2'
        side_sha=\$(git rev-parse HEAD)
        git checkout -q main
        # HEAD reaches the SAME content for a.txt via a different commit.
        echo v2 > a.txt && git add a.txt && git commit -qm 'main: bump to v2 (other path)'
        _gcp_scan_preflight_is_noop \"\$side_sha\"
        echo \"rc=\$?\"
    "
    assert_success
    assert_output --partial "rc=0"
}

@test "preflight #913: commit bringing a genuinely new file -> real work (1)" {
    run_in_bash "
        $(_gcp903_make_repo)
        git checkout -q -b side
        echo only-on-side > b.txt && echo shared > c.txt && git add b.txt c.txt && git commit -qm 'side: add b and c'
        side_sha=\$(git rev-parse HEAD)
        git checkout -q main
        # HEAD matches c.txt but never gets b.txt -> real work remains.
        echo shared > c.txt && git add c.txt && git commit -qm 'main: add c only'
        _gcp_scan_preflight_is_noop \"\$side_sha\"
        echo \"rc=\$?\"
    "
    assert_success
    assert_output --partial "rc=1"
}

@test "preflight #913: probe is non-destructive — dirty working tree survives" {
    run_in_bash "
        $(_gcp903_make_repo)
        git checkout -q -b side
        echo v2 > a.txt && git add a.txt && git commit -qm 'side: bump to v2'
        side_sha=\$(git rev-parse HEAD)
        git checkout -q main
        echo v2 > a.txt && git add a.txt && git commit -qm 'main: bump to v2 (other path)'
        orig=\$(git rev-parse HEAD)
        # Uncommitted edits (tracked + untracked) MUST survive the probe.
        echo localedit >> a.txt
        echo scratch > untracked.txt
        _gcp_scan_preflight_is_noop \"\$side_sha\"; echo \"rc=\$?\"
        grep -q localedit a.txt && echo EDIT_KEPT || echo EDIT_LOST
        [ -f untracked.txt ] && echo UNTRACKED_KEPT || echo UNTRACKED_LOST
        [ \"\$(git rev-parse HEAD)\" = \"\$orig\" ] && echo HEAD_SAME || echo HEAD_MOVED
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "EDIT_KEPT"
    assert_output --partial "UNTRACKED_KEPT"
    assert_output --partial "HEAD_SAME"
    assert_output --partial "PICK_CLEAR"
}

@test "preflight #913/#916: fatal cherry-pick error (bad SHA) is NOT a no-op (1)" {
    # PR #916 review: a fatal `cherry-pick -n` error (invalid object, lock)
    # leaves an empty conflict list on a clean index — it must NOT be mistaken
    # for an absorbed commit and silently skipped.
    run_in_bash "
        $(_gcp903_make_repo)
        _gcp_scan_preflight_is_noop deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
        echo \"rc=\$?\"
    "
    assert_success
    assert_output --partial "rc=1"
}

@test "preflight #913/#916: untracked-only dirty tree does not break the no-op verdict" {
    # PR #916 review: `git add -A` used to stage untracked files (which the
    # initial `git diff` dirty-check never stashed), wrongly flipping a real
    # no-op to rc=1. The untracked file must survive AND the verdict stay 0.
    run_in_bash "
        $(_gcp903_make_repo)
        git checkout -q -b side
        echo v2 > a.txt && git add a.txt && git commit -qm 'side: bump to v2'
        side_sha=\$(git rev-parse HEAD)
        git checkout -q main
        echo v2 > a.txt && git add a.txt && git commit -qm 'main: bump to v2 (other path)'
        # Only an untracked file is dirty — git diff does not see it, so it is
        # never stashed; the probe must still report the commit as a no-op.
        echo scratch > untracked.txt
        _gcp_scan_preflight_is_noop \"\$side_sha\"; echo \"rc=\$?\"
        [ -f untracked.txt ] && echo UNTRACKED_KEPT || echo UNTRACKED_LOST
    "
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "UNTRACKED_KEPT"
}

@test "scan #913: content-dup commit (unique subject, different patch-id) skipped via no-op pre-flight, no conflict" {
    # The content-dup commit must reach the individual loop, so its patch-id
    # has to DIFFER from how HEAD acquired the same final content (else
    # `git cherry` filters it out up front). HEAD reaches shared.txt=TARGET via
    # MIDDLE (two-step), source reaches it in one step from a different parent
    # -> distinct patch-ids, unique subject. A separate subject-dup commit
    # creates the gap that forces the non-contiguous (individual) path.
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
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
    # Content-dup caught by Stage-2 pre-flight; shown in Analysis Result, not execution loop.
    assert_output --partial "Already in HEAD (no-op):"
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

# ---------------------------------------------------------------------------
# Issue #913 (context-drift case, formerly #907) — a commit whose file content
# differs textually from HEAD so it cherry-picks to a CONFLICT, yet the
# conflict is pure context drift (e.g. a comment block an unrelated upstream
# commit expanded later) and resolves to HEAD with nothing added. The merge
# probe `_gcp_scan_preflight_is_noop` catches this BEFORE any real cherry-pick:
# the conflicted file is reset to HEAD and the empty staged diff marks it a
# no-op. A commit carrying genuinely new content (a non-conflicting added file)
# leaves a non-empty staged diff and is always kept.
#
# The two scan tests share the full partial-apply fixture via
# `_gcp907_make_partial_repo` (mirrors the `_gcp811`/`_gcp903` emitter
# convention) instead of re-inlining it.
# ---------------------------------------------------------------------------

_gcp907_make_partial_repo() {
    # Emits shell that builds the #907 partial-apply fixture in a fresh temp
    # repo (EXIT-trap cleaned) and cds in. The "feat: set CONFIG=new" commit
    # changes ONLY the CONFIG line; main reaches the same CONFIG=new value via
    # a different commit that ALSO expanded the adjacent comment, so cherry-
    # picking conflicts (adjacent-line coupling) yet the commit's patch is
    # already applied. A "shared dup subject" pair forces the non-contiguous
    # individual path.
    cat <<'FIXTURE'
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        printf '# comment v1\nCONFIG=old\n' > conf.txt && git add conf.txt && git commit -qm "add conf"
        git checkout -q -b source
        echo one > f1.txt && git add f1.txt && git commit -qm "feat one"
        echo dupsrc > f2.txt && git add f2.txt && git commit -qm "shared dup subject"
        # Partial-apply: changes ONLY the CONFIG line (comment stays v1).
        printf '# comment v1\nCONFIG=new\n' > conf.txt && git add conf.txt && git commit -qm "feat: set CONFIG=new"
        echo four > f4.txt && git add f4.txt && git commit -qm "feat four"
        git checkout -q main
        echo dupbase > onbase.txt && git add onbase.txt && git commit -qm "shared dup subject"
        # HEAD already has CONFIG=new AND an unrelated comment expansion -> conf
        # differs textually (bypasses pre-flight) but the commit's patch is
        # already applied; the cherry-pick conflict is context-only.
        printf '# comment v2 expanded much longer\nCONFIG=new\n' > conf.txt && git add conf.txt && git commit -qm "main: config + comment drift"
FIXTURE
}

@test "preflight #913: context-drift conflict that resolves to HEAD -> no-op (0), non-destructive" {
    run_in_bash "
        $(_gcp903_make_repo)
        printf '# comment v1\nCONFIG=old\n' > conf.txt && git add conf.txt && git commit -qm 'add conf'
        git checkout -q -b side
        # commit changes ONLY the CONFIG line (comment stays v1).
        printf '# comment v1\nCONFIG=new\n' > conf.txt && git add conf.txt && git commit -qm 'feat: set CONFIG=new'
        src=\$(git rev-parse HEAD)
        git checkout -q main
        # HEAD already has CONFIG=new plus an unrelated comment expansion -> the
        # cherry-pick conflicts on adjacent lines, but resolves to HEAD empty.
        printf '# comment v2 expanded much longer\nCONFIG=new\n' > conf.txt && git add conf.txt && git commit -qm 'main: config + comment drift'
        orig=\$(git rev-parse HEAD)
        # An unrelated uncommitted edit MUST survive the non-destructive probe.
        echo localedit >> a.txt
        _gcp_scan_preflight_is_noop \"\$src\"; echo \"rc=\$?\"
        grep -q localedit a.txt && echo EDIT_KEPT || echo EDIT_LOST
        [ \"\$(git rev-parse HEAD)\" = \"\$orig\" ] && echo HEAD_SAME || echo HEAD_MOVED
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "EDIT_KEPT"
    assert_output --partial "HEAD_SAME"
    assert_output --partial "PICK_CLEAR"
}

@test "preflight #913: conflicting commit that ALSO adds new content -> real work (1)" {
    run_in_bash "
        $(_gcp903_make_repo)
        printf '# comment v1\nCONFIG=old\n' > conf.txt && git add conf.txt && git commit -qm 'add conf'
        git checkout -q -b side
        # Conflicts on conf.txt (context drift) AND brings a genuinely new file.
        printf '# comment v1\nCONFIG=new\n' > conf.txt && echo brandnew > g.txt
        git add conf.txt g.txt && git commit -qm 'feat: config + new file'
        src=\$(git rev-parse HEAD)
        git checkout -q main
        printf '# comment v2 expanded much longer\nCONFIG=new\n' > conf.txt && git add conf.txt && git commit -qm 'main: config + comment drift'
        _gcp_scan_preflight_is_noop \"\$src\"; echo \"rc=\$?\"
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    # g.txt is genuinely new -> non-empty staged diff -> never auto-skipped.
    assert_output --partial "rc=1"
    assert_output --partial "PICK_CLEAR"
}

@test "scan #913: context-drift commit auto-skipped by pre-flight (no conflict surfaced)" {
    run_in_bash "
        $(_gcp907_make_partial_repo)
        printf 'y\n' | _gcp_scan main source --author=all
    "
    assert_success
    # Stage-2 pre-flight catches the context-drift commit in Analysis phase;
    # shown as "Already in HEAD (no-op)" there, no conflict ever surfaced.
    assert_output --partial "Already in HEAD (no-op):"
    assert_output --partial "0 conflicts"
    refute_output --partial "CONFLICT"
    refute_output --partial "Resolve and run"
}

@test "scan #961: noop commit absent from Commit List display (phantom removed in Analysis phase)" {
    # Source has a real commit AND a context-drift noop (unique subject, content
    # already in main via a different two-step path). Stage-2 pre-flight must
    # remove the noop from the Commit List BEFORE the user sees it.
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        echo shared > b.txt && git add b.txt && git commit -qm "base: add b.txt"
        git checkout -q -b source
        echo real > real.txt && git add real.txt && git commit -qm "feat: real work"
        # Unique subject; patches b.txt from shared to target in one step.
        echo target > b.txt && git add b.txt && git commit -qm "feat: phantom noop"
        git checkout -q main
        # Main reaches b.txt=target via two-step path -> different patch-id,
        # so git cherry lists the source commit as "+" even though the final
        # state is identical. The context-drift conflict resolves to HEAD empty.
        echo middle > b.txt && git add b.txt && git commit -qm "main: b.txt middle"
        echo target > b.txt && git add b.txt && git commit -qm "main: b.txt target"
        printf "n\n" | _gcp_scan main source --author=all
    '
    assert_success
    # Noop commit must NOT appear in Commit List (phantom removed in Stage-2).
    refute_output --partial "feat: phantom noop"
    # Analysis Result must show the noop count.
    assert_output --partial "Already in HEAD (no-op):"
    # Real commit must still appear.
    assert_output --partial "feat: real work"
}

@test "scan #961: all-noop scan exits cleanly without prompt (nothing to do)" {
    # Source has only a context-drift noop; Stage-2 eliminates it so count=0
    # triggers the early-return path with "Nothing to do" — no cherry-pick prompt.
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        echo shared > b.txt && git add b.txt && git commit -qm "base: add b.txt"
        git checkout -q -b source
        echo target > b.txt && git add b.txt && git commit -qm "feat: all noop"
        git checkout -q main
        echo middle > b.txt && git add b.txt && git commit -qm "main: b.txt middle"
        echo target > b.txt && git add b.txt && git commit -qm "main: b.txt target"
        _gcp_scan main source --author=all
    '
    assert_success
    assert_output --partial "Already in HEAD (no-op):"
    assert_output --partial "Nothing to do"
    refute_output --partial "Do you want to cherry-pick"
}

@test "scan #907: partial-apply skipped while real commits still applied; HEAD drift intact" {
    run_in_bash "
        $(_gcp907_make_partial_repo)
        printf 'y\n' | _gcp_scan main source --author=all >/dev/null 2>&1
        git cat-file -e HEAD:f1.txt && echo HAS_F1
        git cat-file -e HEAD:f4.txt && echo HAS_F4
        # conf.txt retains HEAD's drifted version (partial-apply did not touch it).
        git show HEAD:conf.txt
        # No stray cherry-pick left behind.
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    assert_output --partial "HAS_F1"
    assert_output --partial "HAS_F4"
    assert_output --partial "comment v2 expanded much longer"
    assert_output --partial "PICK_CLEAR"
}

# ---------------------------------------------------------------------------
# Issue #1033 — Stage-1.5 file-dependency pre-check. When the author filter
# drops the upstream commit that CREATES a file, a later author commit that
# MODIFIES (or DELETES) that file would hit a modify/delete conflict because
# the file is absent from base. Stage-1.5 detects this before any cherry-pick,
# skips the dependent commit with a warning, and reports it as
# "Dep-missing (skipped): N". Under --author=all the creating commit is in the
# pick set, so the check must NOT false-positive.
#
# Fixture authors: a NON-author "Upstream Bot" creates dep.txt; the author
# "Me" modifies dep.txt (the dependent candidate) and independently adds
# other.txt (a clean, dependency-free candidate).
# ---------------------------------------------------------------------------

_gcp1033_make_repo() {
    cat <<'FIXTURE'
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Me" GIT_AUTHOR_EMAIL="me@me" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm "init"
        git checkout -q -b source
        # Non-author creates dep.txt (this is the commit the author filter drops).
        echo created > dep.txt && git add dep.txt \
            && git commit -q --author="Upstream Bot <bot@up>" -m "create dep.txt"
        # Author modifies dep.txt -> depends on the create above.
        echo modified > dep.txt && git add dep.txt && git commit -qm "modify dep.txt"
        # Author adds an independent file -> no dependency.
        echo standalone > other.txt && git add other.txt && git commit -qm "add other.txt"
        git checkout -q main
FIXTURE
}

@test "bash: _gcp_scan_check_file_deps private function exists" {
    run_in_bash 'declare -f _gcp_scan_check_file_deps >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "scan #1033: create-then-modify dependency detected, dependent commit skipped (no conflict)" {
    run_in_bash "
        $(_gcp1033_make_repo)
        printf 'y\n' | _gcp_scan main source --author=Me
    "
    assert_success
    # Warning naming the dependent file + the absent precedent.
    assert_output --partial "Skipping"
    assert_output --partial "dep.txt"
    assert_output --partial "--author=all"
    # Analysis Result counter.
    assert_output --partial "Dep-missing (skipped): 1"
    # The independent commit still applied; no conflict ever surfaced.
    assert_output --partial "0 conflicts"
    refute_output --partial "CONFLICT"
    refute_output --partial "Resolve and run"
}

@test "scan #1033: dependent commit's file is absent, independent commit applied" {
    run_in_bash "
        $(_gcp1033_make_repo)
        printf 'y\n' | _gcp_scan main source --author=Me >/dev/null 2>&1
        git cat-file -e HEAD:other.txt && echo HAS_OTHER
        git cat-file -e HEAD:dep.txt 2>/dev/null && echo HAS_DEP || echo NO_DEP
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    assert_output --partial "HAS_OTHER"
    assert_output --partial "NO_DEP"
    assert_output --partial "PICK_CLEAR"
}

@test "scan #1033: --author=all includes the creator -> no false-positive, dep applied cleanly" {
    run_in_bash "
        $(_gcp1033_make_repo)
        printf 'y\n' | _gcp_scan main source --author=all
        git show HEAD:dep.txt 2>/dev/null
    "
    assert_success
    # Creator is in the pick set, so the modify is NOT flagged as dep-missing.
    refute_output --partial "Dep-missing (skipped)"
    refute_output --partial "CONFLICT"
    # dep.txt ends at the modified content (create + modify both applied).
    assert_output --partial "modified"
}

@test "scan #1033: delete of a file whose creator was filtered out is detected" {
    run_in_bash "
        repo=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/gcp_test.XXXXXX\")\"
        trap \"rm -rf \$repo\" EXIT
        cd \"\$repo\" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME=\"Me\" GIT_AUTHOR_EMAIL=\"me@me\" \
               GIT_COMMITTER_NAME=\"Test\" GIT_COMMITTER_EMAIL=\"t@t\"
        git init -q -b main
        echo init > a.txt && git add a.txt && git commit -qm 'init'
        git checkout -q -b source
        # Non-author creates del.txt; author later deletes it -> delete depends
        # on a create absent from main.
        echo gone > del.txt && git add del.txt \
            && git commit -q --author='Upstream Bot <bot@up>' -m 'create del.txt'
        git rm -q del.txt && git commit -qm 'delete del.txt'
        git checkout -q main
        printf 'y\n' | _gcp_scan main source --author=Me
    "
    assert_success
    assert_output --partial "Dep-missing (skipped): 1"
    assert_output --partial "del.txt"
    refute_output --partial "CONFLICT"
}

# ---------------------------------------------------------------------------
# Issue #1037 — Stage-1.6 content-conflict pre-check. Extends Stage-1.5: when a
# candidate and HEAD both change the same region of a file present on BOTH
# sides, a real cherry-pick hits a 3-way *content* conflict (Stage-1.5 only
# covers modify/delete of a file absent from base). Stage-1.6 probes each
# survivor with `git merge-tree` (non-destructive dry-run, cherry-pick merge
# base = candidate's parent), skips the ones predicted to conflict, and reports
# "Content-conflict (skipped): N". Under --author=all an earlier pick_list
# commit touching the same file means the conflict is an unapplied-precedent
# artifact, so the check must NOT false-positive.
#
# Fixture: author "Me" edits foo.txt (same line main later edits -> conflict)
# and independently adds bar.txt (clean, different file). main diverges on the
# same foo.txt line.
# ---------------------------------------------------------------------------

_gcp1037_make_repo() {
    cat <<'FIXTURE'
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Me" GIT_AUTHOR_EMAIL="me@me" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        printf 'orig\n' > foo.txt && echo init > a.txt \
            && git add foo.txt a.txt && git commit -qm "init"
        git checkout -q -b source
        # Author edits foo.txt -> will collide with main's edit to the same line.
        printf 'upstream\n' > foo.txt && git add foo.txt && git commit -qm "edit foo"
        # Author adds an independent file -> clean, conflict-free candidate.
        echo standalone > bar.txt && git add bar.txt && git commit -qm "add bar.txt"
        git checkout -q main
        # main diverges on the SAME line of foo.txt.
        printf 'mainline\n' > foo.txt && git add foo.txt && git commit -qm "main edits foo"
FIXTURE
}

@test "bash: _gcp_scan_predict_content_conflict private function exists" {
    run_in_bash 'declare -f _gcp_scan_predict_content_conflict >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "scan #1037: same-line edit on both sides predicted, candidate skipped (no conflict surfaced)" {
    run_in_bash "
        $(_gcp1037_make_repo)
        printf 'y\n' | _gcp_scan main source --author=Me
    "
    assert_success
    # Warning naming the conflicting file.
    assert_output --partial "Skipping"
    assert_output --partial "foo.txt"
    assert_output --partial "content conflict"
    # Analysis Result counter.
    assert_output --partial "Content-conflict (skipped): 1"
    # The independent commit still applied; no real conflict ever surfaced.
    assert_output --partial "0 conflicts"
    refute_output --partial "CONFLICT"
    refute_output --partial "Resolve and run"
}

@test "scan #1037: conflicting commit skipped, independent commit applied, foo untouched" {
    run_in_bash "
        $(_gcp1037_make_repo)
        printf 'y\n' | _gcp_scan main source --author=Me >/dev/null 2>&1
        git cat-file -e HEAD:bar.txt && echo HAS_BAR
        git show HEAD:foo.txt
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    assert_output --partial "HAS_BAR"
    # foo.txt keeps main's content — the conflicting edit was never applied.
    assert_output --partial "mainline"
    refute_output --partial "upstream"
    assert_output --partial "PICK_CLEAR"
}

@test "scan #1037: non-conflicting candidate (different file) is NOT flagged" {
    run_in_bash "
        $(_gcp1037_make_repo)
        printf 'y\n' | _gcp_scan main source --author=Me
    "
    assert_success
    # Only foo.txt's edit conflicts; bar.txt is applied, never counted.
    assert_output --partial "Content-conflict (skipped): 1"
    refute_output --partial "Content-conflict (skipped): 2"
}

@test "scan #1037: --author=all defers to precedent, no false-positive" {
    # When the precedent that the dependent edit builds on is itself in the pick
    # set (--author=all), Stage-1.6 must NOT flag the dependent as a content
    # conflict — the real loop applies the precedent first. (The dependent is
    # then absorbed by the pre-existing Stage-2 no-op pre-flight, which probes
    # against bare main; that is out of Stage-1.6's scope. The point under test
    # is solely the absence of a false content-conflict skip / surfaced conflict.)
    run_in_bash "
        repo=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/gcp_test.XXXXXX\")\"
        trap \"rm -rf \$repo\" EXIT
        cd \"\$repo\" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME=\"Me\" GIT_AUTHOR_EMAIL=\"me@me\" \
               GIT_COMMITTER_NAME=\"Test\" GIT_COMMITTER_EMAIL=\"t@t\"
        git init -q -b main
        printf 'orig\n' > foo.txt && git add foo.txt && git commit -qm 'init'
        git checkout -q -b source
        # Non-author appends a line; author then modifies that same appended line
        # -> a static probe of the author commit alone (vs main, which lacks the
        # appended line) predicts a conflict, but the precedent is in the pick set.
        printf 'orig\nlineC1\n' > foo.txt && git add foo.txt \
            && git commit -q --author='Upstream Bot <bot@up>' -m 'append lineC1'
        printf 'orig\nlineC1-modified\n' > foo.txt && git add foo.txt \
            && git commit -qm 'modify lineC1'
        git checkout -q main
        printf 'y\n' | _gcp_scan main source --author=all
    "
    assert_success
    # Precedent is in the pick set -> conflict prediction deferred, not skipped.
    refute_output --partial "Content-conflict (skipped)"
    refute_output --partial "CONFLICT"
    refute_output --partial "Resolve and run"
}

@test "scan #1037: guard flips verdict on pick_list membership (unit)" {
    # Directly exercise _gcp_scan_predict_content_conflict: the SAME commit that
    # is flagged a conflict with an empty pick_list must be DEFERRED once a
    # precedent touching the conflicting file is present in the pick_list.
    run_in_bash "
        repo=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/gcp_test.XXXXXX\")\"
        trap \"rm -rf \$repo\" EXIT
        cd \"\$repo\" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME=\"Me\" GIT_AUTHOR_EMAIL=\"me@me\" \
               GIT_COMMITTER_NAME=\"Test\" GIT_COMMITTER_EMAIL=\"t@t\"
        git init -q -b main
        printf 'A\nB\nC\n' > foo.txt && git add foo.txt && git commit -qm 'init'
        git checkout -q -b source
        printf 'A\nB1\nC\n' > foo.txt && git add foo.txt \
            && git commit -q --author='Upstream Bot <bot@up>' -m 'B->B1'
        c1=\$(git rev-parse HEAD)
        printf 'A\nB2\nC\n' > foo.txt && git add foo.txt && git commit -qm 'B1->B2'
        c2=\$(git rev-parse HEAD)
        git checkout -q main
        # No precedent in pick_list -> conflict predicted (return 1, prints file).
        if _gcp_scan_predict_content_conflict \"\$c2\" \"\$c2\"; then echo NO_FLAG; else echo FLAGGED; fi
        # Precedent c1 present in pick_list -> deferred (return 0, prints nothing).
        if _gcp_scan_predict_content_conflict \"\$c2\" \"\$c1
\$c2\"; then echo DEFERRED; else echo STILL_FLAGGED; fi
    "
    assert_success
    assert_output --partial "FLAGGED"
    assert_output --partial "DEFERRED"
    refute_output --partial "STILL_FLAGGED"
}

@test "scan #1037: one uncovered conflicting file flags the commit despite a covered one (unit)" {
    # gemini PR #1038 review: the guard is per-file. A commit that conflicts in
    # TWO files — one also touched by a precedent (covered), one touched by no
    # other pick commit (uncovered) — is still GUARANTEED to conflict on the
    # uncovered file, so it must be FLAGGED (return 1) naming that file, NOT
    # deferred just because the other file is covered.
    run_in_bash "
        repo=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/gcp_test.XXXXXX\")\"
        trap \"rm -rf \$repo\" EXIT
        cd \"\$repo\" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME=\"Me\" GIT_AUTHOR_EMAIL=\"me@me\" \
               GIT_COMMITTER_NAME=\"Test\" GIT_COMMITTER_EMAIL=\"t@t\"
        git init -q -b main
        printf 'Foo0\n' > foo.txt && printf 'Bar0\n' > bar.txt \
            && git add foo.txt bar.txt && git commit -qm 'init'
        git checkout -q -b source
        # Precedent touches bar.txt only.
        printf 'Bar1\n' > bar.txt && git add bar.txt \
            && git commit -q --author='Upstream Bot <bot@up>' -m 'bar->Bar1'
        c1=\$(git rev-parse HEAD)
        # Candidate touches BOTH foo.txt (uncovered) and bar.txt (covered by c1).
        printf 'Foo2\n' > foo.txt && printf 'Bar2\n' > bar.txt \
            && git add foo.txt bar.txt && git commit -qm 'foo+bar'
        c2=\$(git rev-parse HEAD)
        git checkout -q main
        # main diverges on BOTH files so each conflicts in the 3-way merge.
        printf 'FooMain\n' > foo.txt && printf 'BarMain\n' > bar.txt \
            && git add foo.txt bar.txt && git commit -qm 'main diverges'
        out=\$(_gcp_scan_predict_content_conflict \"\$c2\" \"\$c1
\$c2\"); rc=\$?
        echo \"rc=\$rc out=\$out\"
    "
    assert_success
    # Flagged (rc=1) despite bar.txt being covered, naming the uncovered foo.txt.
    assert_output --partial "rc=1"
    assert_output --partial "foo.txt"
    refute_output --partial "rc=0"
}

# ---------------------------------------------------------------------------
# Issue #1039 — Stage-1.4 known-resolved skip list. A commit a human has
# already reconciled into HEAD (manual conflict resolution) or that depends on
# an unmergeable precedent is detected correctly by Stage-1.5/1.6 every run,
# producing repeated warning noise. Registering its SHA in the skip-list file
# (git/config/gcp-scan-skip.conf, override GCP_SCAN_SKIP_FILE) drops it
# SILENTLY before Stage-1.5/1.6, counted under "Known-resolved (skipped)". The
# list is IGNORED under --author=all (full detection stays as a safety net).
# Reuses _gcp1037_make_repo (foo.txt content-conflict fixture); the conflicting
# "edit foo" commit is source~1.
# ---------------------------------------------------------------------------

@test "bash: _gcp_scan_load_skip_list private function exists" {
    run_in_bash 'declare -f _gcp_scan_load_skip_list >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_scan_in_skip_list private function exists" {
    run_in_bash 'declare -f _gcp_scan_in_skip_list >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "scan #1039: --show-skip-list prints registered SHAs, strips comments/blanks" {
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        export GIT_EDITOR=true GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="t@t" \
               GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="t@t"
        git init -q -b main
        skipf="$repo/skip.conf"
        printf "deadbeef  # inline reason\n# whole-line comment\n\ncafebabe\n" > "$skipf"
        export GCP_SCAN_SKIP_FILE="$skipf"
        _gcp_scan main upstream/main --show-skip-list
    '
    assert_success
    assert_output --partial "Known-resolved skip list"
    assert_output --partial "deadbeef"
    assert_output --partial "cafebabe"
    # Reasons / full-comment lines must not be emitted as SHA tokens.
    refute_output --partial "whole-line comment"
    refute_output --partial "inline reason"
}

@test "scan #1039: --show-skip-list reports empty when no file registered" {
    run_in_bash '
        repo="$(mktemp -d "${TMPDIR:-/tmp}/gcp_test.XXXXXX")"
        trap "rm -rf $repo" EXIT
        cd "$repo" || exit 1
        git init -q -b main
        export GCP_SCAN_SKIP_FILE="$repo/does-not-exist.conf"
        _gcp_scan main upstream/main --show-skip-list
    '
    assert_success
    assert_output --partial "Known-resolved skip list"
    assert_output --partial "no skip-list file"
}

@test "scan #1039: registered SHA skipped silently as known-resolved (no conflict warning)" {
    run_in_bash "
        $(_gcp1037_make_repo)
        conflict_sha=\$(git rev-parse source~1)
        skipf=\"\$repo/skip.conf\"
        printf '%s  # manually resolved, already in HEAD\n' \"\$conflict_sha\" > \"\$skipf\"
        export GCP_SCAN_SKIP_FILE=\"\$skipf\"
        printf 'y\n' | _gcp_scan main source --author=Me
    "
    assert_success
    # Counted as known-resolved in the Analysis Result.
    assert_output --partial "Known-resolved (skipped): 1"
    # The Stage-1.6 content-conflict warning must NOT fire for the listed SHA.
    refute_output --partial "predicted content conflict"
    refute_output --partial "Content-conflict (skipped)"
    # Final report carries the known-resolved skip line; no real conflict.
    assert_output --partial "known-resolved"
    refute_output --partial "CONFLICT"
    refute_output --partial "Resolve and run"
}

@test "scan #1039: known-resolved commit not applied; independent commit still applied" {
    run_in_bash "
        $(_gcp1037_make_repo)
        conflict_sha=\$(git rev-parse source~1)
        skipf=\"\$repo/skip.conf\"
        printf '%s\n' \"\$conflict_sha\" > \"\$skipf\"
        export GCP_SCAN_SKIP_FILE=\"\$skipf\"
        printf 'y\n' | _gcp_scan main source --author=Me >/dev/null 2>&1
        git cat-file -e HEAD:bar.txt && echo HAS_BAR
        git show HEAD:foo.txt
        git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 && echo PICK_ACTIVE || echo PICK_CLEAR
    "
    assert_success
    assert_output --partial "HAS_BAR"
    # foo.txt keeps main's content — the known-resolved edit was never applied.
    assert_output --partial "mainline"
    refute_output --partial "upstream"
    assert_output --partial "PICK_CLEAR"
}

@test "scan #1039: --author=all ignores the skip list (safety net)" {
    run_in_bash "
        $(_gcp1037_make_repo)
        conflict_sha=\$(git rev-parse source~1)
        skipf=\"\$repo/skip.conf\"
        printf '%s\n' \"\$conflict_sha\" > \"\$skipf\"
        export GCP_SCAN_SKIP_FILE=\"\$skipf\"
        printf 'y\n' | _gcp_scan main source --author=all
    "
    assert_success
    # Under --author=all the list is bypassed -> Stage-1.6 still detects it.
    assert_output --partial "Content-conflict (skipped): 1"
    refute_output --partial "Known-resolved (skipped)"
}

@test "scan #1039: abbreviated SHA token matches by prefix" {
    run_in_bash "
        $(_gcp1037_make_repo)
        conflict_short=\$(git rev-parse --short=8 source~1)
        skipf=\"\$repo/skip.conf\"
        printf '%s  # short form\n' \"\$conflict_short\" > \"\$skipf\"
        export GCP_SCAN_SKIP_FILE=\"\$skipf\"
        printf 'y\n' | _gcp_scan main source --author=Me
    "
    assert_success
    assert_output --partial "Known-resolved (skipped): 1"
    refute_output --partial "Content-conflict (skipped)"
}
