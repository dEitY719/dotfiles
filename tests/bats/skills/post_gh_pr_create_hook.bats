#!/usr/bin/env bats
# tests/bats/skills/post_gh_pr_create_hook.bats
# Verify the PostToolUse hook documented in
#   claude/hooks/post-gh-pr-create.sh
# Source-of-truth fixture: _fixtures/post_gh_pr_create_hook.sh
# (provides a fake gh_project_status.sh that records every call).
#
# Five cases drawn from issue #390's compatibility matrix:
#   1. tool_name != Bash               → exit 0, no sync
#   2. Bash + non-`gh pr create` cmd   → exit 0, no sync
#   3. Bash + `gh pr create` + URL     → 1 call: pr <num> "In review"
#   4. Bash + `gh pr create` + no URL  → exit 0, no sync (graceful)
#   5. Empty stdin                     → exit 0, no sync (graceful)

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/post-gh-pr-create.sh"

setup() {
    setup_isolated_home
    # Stage a fake shell-common with a stub gh_project_status.sh that
    # records every call into $CALL_LOG. The hook sources via
    # $SHELL_COMMON/functions/gh_project_status.sh, so wiring SHELL_COMMON
    # to a tmp tree lets us observe sync calls without a live projectV2.
    FAKE_SHELL_COMMON="$TEST_TEMP_HOME/shell-common"
    mkdir -p "$FAKE_SHELL_COMMON/functions"
    CALL_LOG="$TEST_TEMP_HOME/calls.log"
    : > "$CALL_LOG"
    cat > "$FAKE_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_pr_closing_issue_numbers() { return 0; }  # no linked issues by default
EOF
    export SHELL_COMMON="$FAKE_SHELL_COMMON"
    # Block real gh from running — the hook only calls `gh repo view` for
    # GH_REPO; passing GH_REPO directly avoids the network and the PATH lookup.
    export GH_REPO="owner/repo"
}

teardown() {
    teardown_isolated_home
    unset SHELL_COMMON GH_REPO
}

@test "post-gh-pr-create: tool_name != Bash → no sync" {
    payload='{"tool_name":"Read","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/owner/repo/pull/42"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: Bash + non-pr-create command → no sync" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr list"},"tool_response":{"output":"https://github.com/owner/repo/pull/42"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: Bash + gh pr create + PR URL → sync called" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title foo"},"tool_response":{"output":"https://github.com/owner/repo/pull/123\n"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    # Expect exactly one sync invocation for the PR card itself.
    assert_output --partial 'PR #123 → "In review"'
    grep -q '^sync pr 123 In review$' "$CALL_LOG"
}

@test "post-gh-pr-create: Bash + gh pr create + no URL → no sync" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"error: something went wrong"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: empty stdin → no sync" {
    run bash -c "printf '' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: env-prefixed gh pr create still matches" {
    # Regression for the regex — `FOO=bar gh pr create` and `command gh pr create`
    # should both trigger. Without the (^|space) anchor, prefixes break detection.
    payload='{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=x gh pr create --draft"},"tool_response":{"output":"https://github.com/owner/repo/pull/7"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^sync pr 7 In review$' "$CALL_LOG"
}

# ---------------------------------------------------------------------------
# Issue #703 — GHE host support
# ---------------------------------------------------------------------------

@test "T9 (#703): Bash + gh pr create + GHE URL → pr_num extracted, sync called" {
    # Regression for issue #703 — the original hook had a hard-coded
    # `https://github.com/...` regex, so PR #8 on the `internal` PC
    # (`github.samsungds.net`) silently failed to sync. The fallback
    # regex inside the hook must match the GHE host even when the
    # SSOT helper (gh_host.sh) is absent from this fake shell-common.
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.samsungds.net/byoungwoo-yoon/dotfiles/pull/8"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    assert_output --partial 'PR #8 → "In review"'
    grep -q '^sync pr 8 In review$' "$CALL_LOG"
}

@test "T10 (#703): Bash + gh pr create + github.com URL still works (no regression)" {
    # The github.com case must continue to extract pr_num the same way
    # it did before the host-agnostic refactor. Functionally a duplicate
    # of the earlier `pr/123` test, but explicit here for issue #703's
    # acceptance-criteria checklist.
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/dEitY719/dotfiles/pull/9001"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^sync pr 9001 In review$' "$CALL_LOG"
}

@test "T11 (#703): Bash + gh pr create + no PR URL on either host → silent exit 0" {
    # When the gh-cli output contains neither host's PR URL, the hook
    # must bow out silently — the alternative is a stray `pr_num=`
    # invocation that errors deep inside _gh_project_status_sync.
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://gitlab.com/owner/repo/-/merge_requests/1"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "T12 (#703): real gh_host.sh in SHELL_COMMON + internal mode → GHE URL extracted" {
    # End-to-end proof that the dynamic regex path works when the SSOT
    # helper is available AND `_dotfiles_setup_mode` returns `internal`
    # (the GHE PC case). Stages a hybrid shell-common with the real
    # gh_host.sh, a stub `_dotfiles_setup_mode` returning `internal`,
    # and the project-status stub from the parent setup().
    HYBRID_SHELL_COMMON="$TEST_TEMP_HOME/hybrid-shell-common"
    mkdir -p "$HYBRID_SHELL_COMMON/functions"
    cp "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_host.sh" \
        "$HYBRID_SHELL_COMMON/functions/gh_host.sh"
    # Stub the integrations-layer helper that gh_host.sh consults.
    # File order matters: gh_host.sh sources nothing at file scope, but
    # `_gh_resolve_host` calls `_dotfiles_setup_mode` at runtime — so as
    # long as the stub is in scope when the hook calls `_gh_resolve_host`
    # it wins. We put it in a "ZZ-prefixed" file in functions/ but the
    # hook only sources gh_host.sh, not the whole functions/ dir, so we
    # instead pre-source the stub via a wrapper.
    cat > "$HYBRID_SHELL_COMMON/functions/_setup_mode_stub.sh" <<'EOF'
_dotfiles_setup_mode() { echo "internal"; }
EOF
    cat > "$HYBRID_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_pr_closing_issue_numbers() { return 0; }
EOF
    # Drive the hook through a wrapper that pre-sources the
    # `_dotfiles_setup_mode` stub into the hook's shell environment.
    # `BASH_ENV` is honoured by `bash` when started non-interactively.
    BASH_ENV="$HYBRID_SHELL_COMMON/functions/_setup_mode_stub.sh" \
    DOTFILES_FORCE_INIT=1 \
    SHELL_COMMON="$HYBRID_SHELL_COMMON" \
        bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr create\"},\"tool_response\":{\"output\":\"https://github.samsungds.net/byoungwoo-yoon/dotfiles/pull/8\"}}' | '$HOOK'"
    grep -q '^sync pr 8 In review$' "$CALL_LOG"
}

@test "T13 (#804): explicit GH_HOST override → regex honors it, PR URL still matched" {
    # PR #805 gemini-code-assist (HIGH): when the caller exports GH_HOST,
    # `gh pr create` emits a URL on THAT host. The regex must be built from
    # the override, not the resolved default — otherwise pr_num is empty and
    # the hook silently exits. We point _dotfiles_setup_mode at `external`
    # (resolves to github.com) but export GH_HOST=github.example.com and feed
    # a URL on github.example.com; the sync must still fire.
    HYBRID_SHELL_COMMON="$TEST_TEMP_HOME/hybrid-override"
    mkdir -p "$HYBRID_SHELL_COMMON/functions"
    cp "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_host.sh" \
        "$HYBRID_SHELL_COMMON/functions/gh_host.sh"
    cat > "$HYBRID_SHELL_COMMON/functions/_setup_mode_stub.sh" <<'EOF'
_dotfiles_setup_mode() { echo "external"; }
EOF
    cat > "$HYBRID_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_pr_closing_issue_numbers() { return 0; }
EOF
    BASH_ENV="$HYBRID_SHELL_COMMON/functions/_setup_mode_stub.sh" \
    DOTFILES_FORCE_INIT=1 \
    GH_HOST="github.example.com" \
    SHELL_COMMON="$HYBRID_SHELL_COMMON" \
        bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr create\"},\"tool_response\":{\"output\":\"https://github.example.com/owner/repo/pull/42\"}}' | '$HOOK'"
    grep -q '^sync pr 42 In review$' "$CALL_LOG"
}

# ---------------------------------------------------------------------------
# Issue #813 — projectV2 "Auto-add to project" race (poll-until-In-review)
#
# The hook now probes for a board up front (_post_gh_pr_create_repo_has_board
# via `gh api graphql`) and, when a board exists, re-syncs in a bounded loop
# until _gh_project_status_query_current reports "In review" — absorbing the
# window where GitHub's builtin auto-add lands the PR card *after* our first
# look. Boardless repos keep the single-call silent no-op contract.
#
# These three cases stage a fake `gh` on PATH (board count) plus a
# query_current stub (when the card flips to "In review").
# ---------------------------------------------------------------------------

@test "T14 (#813): no projectV2 board → single sync, retry loop skipped" {
    # has-board probe returns 0 → the hook must take the else branch: exactly
    # one sync and zero query_current calls (the loop is never entered, so a
    # boardless repo does not burn the retry budget spinning on a no-op).
    mkdir -p "$TEST_TEMP_HOME/bin"
    cat > "$TEST_TEMP_HOME/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: report ZERO projectV2 boards for the has-board probe.
[ "$1 $2" = "api graphql" ] && { echo 0; exit 0; }
exit 0
EOF
    chmod +x "$TEST_TEMP_HOME/bin/gh"
    # query_current logs every call so its ABSENCE proves the loop was skipped.
    cat > "$FAKE_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_project_status_query_current() { printf 'query %s\n' "\$*" >> "$CALL_LOG"; echo "Backlog"; }
_gh_pr_closing_issue_numbers() { return 0; }
EOF
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/owner/repo/pull/55"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ "$(grep -c '^sync pr 55 In review$' "$CALL_LOG")" -eq 1 ]
    ! grep -q '^query ' "$CALL_LOG"
}

@test "T15 (#813): board present, card lands late → poll until In review, no warning" {
    # has-board probe returns 1; query_current reports Backlog on the 1st probe
    # and In review on the 2nd — emulating auto-add landing the card between
    # attempts. The loop must re-sync once, then break (exactly 2 sync calls)
    # without emitting the budget-exhausted warning.
    mkdir -p "$TEST_TEMP_HOME/bin"
    cat > "$TEST_TEMP_HOME/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "api graphql" ] && { echo 1; exit 0; }
exit 0
EOF
    chmod +x "$TEST_TEMP_HOME/bin/gh"
    QC_COUNT="$TEST_TEMP_HOME/qc.count"; : > "$QC_COUNT"
    cat > "$FAKE_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_project_status_query_current() {
    n=\$(cat "$QC_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$QC_COUNT"
    if [ "\$n" -ge 2 ]; then echo "In review"; else echo "Backlog"; fi
}
_gh_pr_closing_issue_numbers() { return 0; }
EOF
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
    export POST_GH_PR_CREATE_SYNC_SLEEP=0
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/owner/repo/pull/77"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ "$(grep -c '^sync pr 77 In review$' "$CALL_LOG")" -eq 2 ]
    ! echo "$output" | grep -q 'still not'
}

@test "T16 (#813): board present, never reaches In review → warning + exit 0" {
    # query_current is stuck on Backlog. With attempts=2 the loop must sync
    # twice, then warn (best-effort: still exit 0 so the user flow is never
    # blocked).
    mkdir -p "$TEST_TEMP_HOME/bin"
    cat > "$TEST_TEMP_HOME/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "api graphql" ] && { echo 1; exit 0; }
exit 0
EOF
    chmod +x "$TEST_TEMP_HOME/bin/gh"
    cat > "$FAKE_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_project_status_query_current() { echo "Backlog"; }
_gh_pr_closing_issue_numbers() { return 0; }
EOF
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
    export POST_GH_PR_CREATE_SYNC_SLEEP=0 POST_GH_PR_CREATE_SYNC_ATTEMPTS=2
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/owner/repo/pull/88"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ "$(grep -c '^sync pr 88 In review$' "$CALL_LOG")" -eq 2 ]
    assert_output --partial 'still not "In review" after 2 attempts'
}
