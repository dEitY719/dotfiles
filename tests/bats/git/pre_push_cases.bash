# shellcheck shell=bash
# tests/bats/git/pre_push_cases.bash
#
# Case library for git/hooks/pre-push (moved from git/tests/test-pre-push.sh,
# #2163). tests/bats/git/test_pre_push_hook.bats calls each case as one @test.
# Covers two layers:
#   1. Protected-branch detection (pure logic — sources pre-push-rules.sh).
#   2. Upstream leak guard (T-1 .. T-10, issue #708) and remote_ref
#      protection (T-11 .. T-13) — invokes the real hook against a throwaway
#      git repo with synthetic stdin / argv.
#
# Fixtures use generic placeholder strings (example.internal, /home/.*/
# private-overlay/) — no real internal identifiers ever appear in this file.
#
# Assertions read captured output via a here-string (`grep -q P <<<"$out"`),
# never `echo "$out" | grep -q P` (SIGPIPE + pipefail under load, #2133).

# shellcheck source=/dev/null
source "${DOTFILES_ROOT}/git/config/pre-push-rules.sh"

HOOK="${DOTFILES_ROOT}/git/hooks/pre-push"
# Layer 0 (`mise run test`, #754) would run inside each throwaway fixture
# repo and fail there; these cases exercise layers 1-2 only.
export SKIP_LOCAL_PYTEST=1
ZERO_SHA="0000000000000000000000000000000000000000"

# ============================================
# LAYER 1 — PROTECTED_BRANCHES (pure logic)
# ============================================

run_test() {
    local branch="$1"
    local expected="$2"

    local is_protected=0
    for protected in "${PROTECTED_BRANCHES[@]}"; do
        if [[ "$protected" == *"*" ]]; then
            pattern="${protected//\*/.*}"
            if [[ "$branch" =~ ^${pattern}$ ]]; then
                is_protected=1
                break
            fi
        else
            if [ "$branch" = "$protected" ]; then
                is_protected=1
                break
            fi
        fi
    done

    if [ $is_protected -eq 1 ]; then
        result="BLOCKED"
    else
        result="ALLOWED"
    fi

    if [ "$result" = "$expected" ]; then
        echo "✓ $branch → $result"
        return 0
    else
        echo "✗ $branch → $result (expected: $expected)"
        return 1
    fi
}

# ============================================
# LAYER 2 — LEAK GUARD (T-1 .. T-10)
# ============================================

# Fixture: tiny git repo with one commit. Caller mutates from there.
_setup_repo() {
    local dir
    dir=$(mktemp -d "${TEST_TEMP_HOME}"/leak-guard-test.XXXXXX)
    git -C "$dir" init -q
    git -C "$dir" config user.email "leak-test@example.com"
    git -C "$dir" config user.name "leak-test"
    git -C "$dir" config commit.gpgsign false
    echo "seed" >"$dir/seed.txt"
    git -C "$dir" add seed.txt
    git -C "$dir" -c core.hooksPath=/dev/null commit -q -m "seed"
    printf '%s' "$dir"
}

# Invoke the real hook against the given repo. Returns the hook's exit
# code and captures stdout+stderr in $LEAK_OUT.
_invoke_hook() {
    local dir="$1" remote_name="$2" remote_url="$3"
    local local_sha remote_sha rc out
    local_sha=$(git -C "$dir" rev-parse HEAD)
    remote_sha="${4:-$ZERO_SHA}"

    # `&& rc=0 || rc=$?` instead of `set +e ... set -e`: re-enabling errexit
    # here would make the non-zero `return` below abort the bats test before
    # the caller reads it. A here-string, not `printf | hook`: a hook that
    # exits without reading stdin (SKIP_PRE_PUSH=1) SIGPIPEs the printf and
    # pipefail turns that into rc=141.
    out=$(cd "$dir" &&
        "$HOOK" "$remote_name" "$remote_url" 2>&1 \
            <<<"refs/heads/test ${local_sha} refs/heads/test ${remote_sha}") && rc=0 || rc=$?
    LEAK_OUT="$out"
    return "$rc"
}

_assert_eq() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        echo "✓ $name"
        return 0
    fi
    echo "✗ $name"
    echo "    want: $want"
    echo "    got:  $got"
    [ -n "${LEAK_OUT:-}" ] && echo "    out:  ${LEAK_OUT}"
    return 1
}

# Common env for leak-guard tests — generic placeholder values only.
# UPSTREAM_REMOTES_ERE picks any github.com URL; LEAK_PATTERNS_ERE picks
# two placeholder patterns that should never appear in real OSS code.
_LEAK_UPSTREAM_ERE='github\.com[:/].+/.+(\.git)?$'
_LEAK_PATTERNS_ERE='example\.internal|/private-overlay/'

_t1_origin_push_with_pattern_passes() {
    local dir
    dir=$(_setup_repo)
    echo "leak: example.internal endpoint" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "add leak content"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" origin "ssh://git@private-mirror.example/foo/bar.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-1 origin push with pattern -> exit 0 (guard inactive)" 0 "$rc"
}

_t2_upstream_push_no_pattern_passes() {
    local dir
    dir=$(_setup_repo)
    echo "plain content, nothing sensitive" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "clean change"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-2 upstream push no pattern -> exit 0" 0 "$rc"
}

_t3_upstream_push_pattern_in_commit_message_blocks() {
    local dir
    dir=$(_setup_repo)
    echo "harmless line" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq \
        -m "wip: probe example.internal zq7canary-msg"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] &&
        grep -q "Upstream push blocked" <<<"$LEAK_OUT" &&
        grep -q "<commit message>" <<<"$LEAK_OUT" &&
        grep -q "lines:  1 " <<<"$LEAK_OUT" &&
        ! grep -q "zq7canary" <<<"$LEAK_OUT" &&
        ! grep -q "example.internal" <<<"$LEAK_OUT"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    _assert_eq "T-3 pattern in commit message -> exit 1 + location only, no matched text" 1 "$rc_ok"
}

_t4_upstream_push_pattern_in_diff_blocks() {
    local dir
    dir=$(_setup_repo)
    echo "OVERLAY_PATH=/home/user/private-overlay/zq7canary-file" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "ordinary subject"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] &&
        grep -q "Upstream push blocked" <<<"$LEAK_OUT" &&
        grep -q "source: seed.txt" <<<"$LEAK_OUT" &&
        grep -q "lines:  [0-9]" <<<"$LEAK_OUT" &&
        ! grep -q "zq7canary" <<<"$LEAK_OUT" &&
        ! grep -q "private-overlay" <<<"$LEAK_OUT"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    _assert_eq "T-4 pattern in file diff -> exit 1 + location only, no matched text" 1 "$rc_ok"
}

_t5_skip_leak_guard_escape_hatch() {
    local dir
    dir=$(_setup_repo)
    echo "leak: example.internal" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "would normally block"

    set +e
    SKIP_LEAK_GUARD=1 \
        UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-5 SKIP_LEAK_GUARD=1 -> exit 0" 0 "$rc"
}

_t6_skip_pre_push_escape_hatch() {
    local dir
    dir=$(_setup_repo)
    echo "leak: example.internal" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "would normally block"

    set +e
    SKIP_PRE_PUSH=1 \
        UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-6 SKIP_PRE_PUSH=1 -> exit 0 (whole hook skipped)" 0 "$rc"
}

_t7_protected_branch_takes_priority() {
    # Protected-branch check runs before the leak guard within the same ref
    # iteration. Pushing `master` with a leak should be blocked by layer 1
    # (exit 1) with the protected-branch message, not the leak message.
    local dir
    dir=$(_setup_repo)
    git -C "$dir" branch -m master 2>/dev/null || git -C "$dir" checkout -qb master
    echo "leak: example.internal" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "master with leak"

    local local_sha rc out
    local_sha=$(git -C "$dir" rev-parse HEAD)

    set +e
    out=$(cd "$dir" &&
        printf 'refs/heads/master %s refs/heads/master %s\n' "$local_sha" "$ZERO_SHA" |
        UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
            "$HOOK" upstream "https://github.com/owner/repo.git" 2>&1)
    rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] &&
        grep -q "protected branch" <<<"$out"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    LEAK_OUT="$out"
    _assert_eq "T-7 protected-branch wins over leak guard" 1 "$rc_ok"
}

# Issue #1997 — a matching file NAME (or pushed ref name) is caught and
# never printed. Fake token only.
_FAKE_PAT='qx9FAKE[A-Z]+[0-9]+'

_t8_matching_path_redacted() {
    local dir
    dir=$(_setup_repo)
    mkdir "$dir/d"
    echo "endpoint qx9FAKETOKEN88" >"$dir/d/qx9FAKETOKEN77.conf"
    echo "endpoint example.internal" >>"$dir/seed.txt"
    git -C "$dir" add -A
    git -C "$dir" -c core.hooksPath=/dev/null commit -q -m "ordinary subject"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE|$_FAKE_PAT" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] &&
        [ "$(printf '%s\n' "$LEAK_OUT" | grep -c "source: <redacted path: 21 chars, matches LEAK_PATTERNS_ERE>")" -eq 2 ] &&
        grep -q "lines:  (file name)" <<<"$LEAK_OUT" &&
        grep -q "path:    git diff-tree" <<<"$LEAK_OUT" &&
        grep -q "source: seed.txt" <<<"$LEAK_OUT" &&
        ! grep -q "qx9FAKE" <<<"$LEAK_OUT"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    _assert_eq "T-8 matching path -> exit 1 + redacted path, ordinary path kept" 1 "$rc_ok"
}

_t9_matching_path_clean_content_blocks() {
    local dir
    dir=$(_setup_repo)
    mkdir "$dir/d"
    echo clean >"$dir/d/qx9FAKETOKEN77.conf"
    git -C "$dir" add -A
    git -C "$dir" -c core.hooksPath=/dev/null commit -q -m "ordinary subject"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" LEAK_PATTERNS_ERE="$_FAKE_PAT" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] &&
        grep -q "source: <redacted path:" <<<"$LEAK_OUT" &&
        ! grep -q "qx9FAKE" <<<"$LEAK_OUT"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    _assert_eq "T-9 matching path, clean content -> exit 1, no token" 1 "$rc_ok"
}

_t10_matching_ref_name_redacted() {
    local dir local_sha rc out
    dir=$(_setup_repo)
    local_sha=$(git -C "$dir" rev-parse HEAD)

    set +e
    out=$(cd "$dir" &&
        printf 'refs/heads/f %s refs/heads/feat/qx9FAKETOKEN77 %s\n' "$local_sha" "$ZERO_SHA" |
        UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" LEAK_PATTERNS_ERE="$_FAKE_PAT" \
            "$HOOK" upstream "https://github.com/owner/repo.git" 2>&1)
    rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] &&
        grep -q "source: <redacted ref name:" <<<"$out" &&
        ! grep -q "qx9FAKE" <<<"$out"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    LEAK_OUT="$out"
    _assert_eq "T-10 matching pushed ref name -> exit 1, no token" 1 "$rc_ok"
}

# Issue #2032 — Layer 1 judges the push destination (remote_ref), not just
# the local branch name. Feeds one pre-push stdin line, returns the hook rc.
_push_line_rc() {
    local local_ref="$1" remote_ref="$2" dir
    dir=$(_setup_repo)
    set +e
    LEAK_OUT=$(cd "$dir" &&
        printf '%s %s %s %s\n' "$local_ref" "$ZERO_SHA" "$remote_ref" "$ZERO_SHA" |
        "$HOOK" origin "git@example.com:owner/repo.git" 2>&1)
    PUSH_RC=$?
    set -e
    rm -rf "$dir"
}

_t11_renamed_local_to_remote_master_blocks() {
    _push_line_rc refs/heads/sync/foo refs/heads/master
    local ok=0
    [ "$PUSH_RC" -eq 1 ] && grep -q "protected branch" <<<"$LEAK_OUT" && ok=1
    _assert_eq "T-11 sync/foo -> remote master is BLOCKED" 1 "$ok"
}

_t12_same_name_feature_push_passes() {
    _push_line_rc refs/heads/feature/x refs/heads/feature/x
    _assert_eq "T-12 feature/x -> feature/x is ALLOWED" 0 "$PUSH_RC"
}

_t13_delete_remote_master_blocks() {
    _push_line_rc "(delete)" refs/heads/master
    local ok=0
    [ "$PUSH_RC" -eq 1 ] && grep -q "protected branch" <<<"$LEAK_OUT" && ok=1
    _assert_eq "T-13 delete remote master is BLOCKED" 1 "$ok"
}

# ============================================
# GLOBAL WRAPPER — scripts/hooks/ candidate (G-1 .. G-6, issue #2305)
# ============================================
# git/global-hooks/pre-push (via lib/delegate.sh) searches .githooks/ ->
# git/hooks/ -> scripts/hooks/ -> <git-common-dir>/hooks/. These cases drive
# the wrapper directly, like the cases above drive the project hook.

GLOBAL_PRE_PUSH="${DOTFILES_ROOT}/git/global-hooks/pre-push"

# Stub project hook at <dir>/<relpath>: records "<tag>:<argv>|<stdin>" in
# <dir>/.ran and exits <rc>. Pass mode 644 to leave the exec bit off.
_stub_hook() {
    local dir="$1" rel="$2" tag="$3" rc="${4:-0}" mode="${5:-755}"
    mkdir -p "$dir/$(dirname "$rel")"
    cat >"$dir/$rel" <<STUB
#!/bin/bash
printf '%s:%s|%s\n' "$tag" "\$*" "\$(cat)" >>"$dir/.ran"
exit $rc
STUB
    chmod "$mode" "$dir/$rel"
}

# Run the global wrapper in <dir> with argv "origin <url>" and one stdin
# line. Sets WRAP_RC and LEAK_OUT (stdout+stderr).
_run_global_pre_push() {
    local dir="$1"
    LEAK_OUT=$(cd "$dir" &&
        "$GLOBAL_PRE_PUSH" origin "git@example.com:owner/repo.git" 2>&1 \
            <<<"refs/heads/x ${ZERO_SHA} refs/heads/x ${ZERO_SHA}") && WRAP_RC=0 || WRAP_RC=$?
}

_ran() { cat "$1/.ran" 2>/dev/null || true; }

_g1_scripts_hooks_only_is_exec_with_passthrough() {
    local dir
    dir=$(_setup_repo)
    _stub_hook "$dir" scripts/hooks/pre-push SCRIPTS 7
    _run_global_pre_push "$dir"
    local want="SCRIPTS:origin git@example.com:owner/repo.git|refs/heads/x ${ZERO_SHA} refs/heads/x ${ZERO_SHA}"
    _assert_eq "G-1 scripts/hooks/pre-push exit code passed through" 7 "$WRAP_RC" &&
        _assert_eq "G-1 argv + stdin passed through" "$want" "$(_ran "$dir")" &&
        _assert_eq "G-1 delegation notice names scripts/hooks/pre-push" 1 \
            "$(grep -c "Delegating to project hook: .*scripts/hooks/pre-push" <<<"$LEAK_OUT" || true)"
    local ok=$?
    rm -rf "$dir"
    return "$ok"
}

_g2_githooks_beats_scripts_hooks() {
    local dir
    dir=$(_setup_repo)
    _stub_hook "$dir" .githooks/pre-push GITHOOKS
    _stub_hook "$dir" scripts/hooks/pre-push SCRIPTS
    _run_global_pre_push "$dir"
    local got
    got=$(_ran "$dir" | cut -d: -f1)
    rm -rf "$dir"
    _assert_eq "G-2 .githooks/ wins over scripts/hooks/" GITHOOKS "$got"
}

_g3_git_hooks_beats_scripts_hooks() {
    local dir
    dir=$(_setup_repo)
    _stub_hook "$dir" git/hooks/pre-push GITHOOKS_DIR
    _stub_hook "$dir" scripts/hooks/pre-push SCRIPTS
    _run_global_pre_push "$dir"
    local got
    got=$(_ran "$dir" | cut -d: -f1)
    rm -rf "$dir"
    _assert_eq "G-3 git/hooks/ wins over scripts/hooks/" GITHOOKS_DIR "$got"
}

_g4_scripts_hooks_without_exec_bit_is_skipped() {
    local dir
    dir=$(_setup_repo)
    _stub_hook "$dir" scripts/hooks/pre-push SCRIPTS 7 644
    _run_global_pre_push "$dir"
    local got
    got="${WRAP_RC}:$(_ran "$dir")"
    rm -rf "$dir"
    _assert_eq "G-4 non-executable scripts/hooks/pre-push is skipped" "0:" "$got"
}

# scripts/hooks/pre-push is a symlink to the wrapper itself (as if a repo
# pointed it at ~/.config/git/hooks). `-ef` must skip it, not recurse.
_g5_scripts_hooks_self_link_is_skipped() {
    local dir
    dir=$(_setup_repo)
    mkdir -p "$dir/scripts/hooks"
    ln -s "$GLOBAL_PRE_PUSH" "$dir/scripts/hooks/pre-push"
    _run_global_pre_push "$dir"
    local got="${WRAP_RC}:${LEAK_OUT}"
    rm -rf "$dir"
    _assert_eq "G-5 self-link under scripts/hooks/ is skipped silently" "0:" "$got"
}

_g6_no_project_hook_is_noop() {
    local dir
    dir=$(_setup_repo)
    mkdir -p "$dir/scripts/hooks"
    _run_global_pre_push "$dir"
    local got="${WRAP_RC}:${LEAK_OUT}"
    rm -rf "$dir"
    _assert_eq "G-6 no project pre-push -> silent no-op" "0:" "$got"
}
