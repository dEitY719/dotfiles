#!/usr/bin/env bats
# tests/bats/functions/gh_pr_edit_safe.bats
# Unit tests for _gh_pr_edit_safe_label / _gh_pr_edit_safe_body — the
# REST fallback wrappers that recover from `gh pr edit` GraphQL deprecation
# warnings on classic-Projects repos (issue #326).
#
# Network is never touched. A fake `gh` shim on PATH selects per-test
# behavior via FAKE_GH_MODE, mirroring the gh_project_status.bats pattern.

load '../test_helper'

setup() {
    setup_isolated_home
    _setup_fake_gh
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fake `gh` shim
#
# FAKE_GH_MODE controls behaviour of `gh pr edit` and `gh api`:
#   ok          — `gh pr edit` succeeds (no warning, no fallback needed)
#   deprecated  — `gh pr edit` prints deprecation warning + exit 1, then
#                 `gh api POST .../labels` succeeds
#   deprecated_body — same but for body PATCH path
#   missing_label — `gh pr edit` prints deprecation, then `gh label list`
#                   omits the label so REST fallback must be refused
#   other_error — `gh pr edit` exits 1 with an unrelated error (no
#                 deprecation marker → no fallback, error passed through)
#   rest_fail   — deprecation warning, then REST POST also fails
#   delete_ok      — `gh api -X DELETE .../labels/<name>` succeeds (#1563)
#   delete_missing — same DELETE returns `gh: Not Found (HTTP 404)` + exit 1,
#                    and the verification GET succeeds WITHOUT the label
#                    (label genuinely absent → idempotent success)
#   delete_fail    — same DELETE fails for a real reason (5xx), and the
#                    verification GET still lists the label (real failure)
#   delete_notfound_repo — DELETE returns the SAME generic 404, but the
#                    verification GET also fails: bad repo / PR / GH_HOST, so
#                    the state is unknown and the 404 must NOT be swallowed
#                    (PR #1583 codex BLOCKER regression guard)
# A scratch log records every call for assertion: $TEST_TEMP_HOME/gh.log.
# Each line is prefixed `GH_HOST=<value>` so tests can prove the host pinning
# actually reaches `gh`'s environment, not just its argv (PR #1583 codex).
# ---------------------------------------------------------------------------
_setup_fake_gh() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB_BIN"
    GH_LOG="$TEST_TEMP_HOME/gh.log"
    : >"$GH_LOG"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Record the invocation for inspection, prefixed with the GH_HOST this
# process actually inherited (empty when the caller pinned nothing).
{ printf 'GH_HOST=%s gh' "${GH_HOST-}"; for a in "$@"; do printf ' %q' "$a"; done
  printf '\n'; } >>"$GH_LOG"

mode="${FAKE_GH_MODE:-ok}"

# `gh repo view --json nameWithOwner --jq .nameWithOwner` — used by repo
# resolution. Keep it boring.
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
    echo "fake/repo"
    exit 0
fi

# `gh label list ...` — return the labels the test expects to exist.
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    case "$mode" in
        missing_label) printf 'bug\nchore\n' ;;
        *)             printf 'bug\nchore\nfeat\nskill\n' ;;
    esac
    exit 0
fi

# `gh pr edit <N> --repo R --add-label L` or `--body-file F`
if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
    case "$mode" in
        ok)
            exit 0
            ;;
        deprecated|missing_label|rest_fail)
            echo "GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience" >&2
            exit 1
            ;;
        deprecated_body)
            # Body path uses a different mode marker so we can
            # assert different REST fallback (PATCH vs POST).
            echo "GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience" >&2
            exit 1
            ;;
        other_error)
            echo "Some other unrelated error" >&2
            exit 1
            ;;
    esac
fi

# `gh api -X POST .../labels` — REST fallback for labels
if [ "$1" = "api" ] && [ "$3" = "POST" ]; then
    case "$mode" in
        rest_fail) echo "REST POST failed" >&2; exit 1 ;;
        *)         exit 0 ;;
    esac
fi

# `gh api -X DELETE .../issues/N/labels/<name>` — label drop (#1563)
if [ "$1" = "api" ] && [ "$3" = "DELETE" ]; then
    case "$mode" in
        delete_missing)       echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        delete_fail)          echo "gh: Internal Server Error (HTTP 500)" >&2; exit 1 ;;
        delete_notfound_repo) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        *)                    exit 0 ;;
    esac
fi

# `gh api repos/O/R/issues/N/labels --jq .[].name` — verification GET after a
# failed DELETE (#1583). No `-X`, so $2 is the path. Emits post-`--jq` output
# (newline-separated names), matching the `gh label list` shim above.
if [ "$1" = "api" ] && [ "$2" != "-X" ]; then
    case "$2" in
        repos/*/issues/*/labels)
            case "$mode" in
                delete_missing)
                    # Label genuinely gone → idempotent success.
                    printf 'bug\nskill\n'; exit 0 ;;
                delete_fail)
                    # Label still there → the 500 was a real failure.
                    printf 'bug\nreview-passed\n'; exit 0 ;;
                delete_notfound_repo)
                    # Bad repo / PR / host: verification cannot answer either.
                    echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
                *)
                    # delete_ok never reaches here; keep it harmless.
                    exit 0 ;;
            esac
            ;;
    esac
fi

# `gh api -X PATCH .../pulls/N --input -` — REST fallback for body
if [ "$1" = "api" ] && [ "$3" = "PATCH" ]; then
    # Drain stdin to keep the pipe quiet
    cat >/dev/null
    case "$mode" in
        rest_fail) echo "REST PATCH failed" >&2; exit 1 ;;
        *)         exit 0 ;;
    esac
fi

# Catch-all: success
exit 0
GH
    chmod +x "$STUB_BIN/gh"
}

# Run a snippet in bash with the shim on PATH and the helper sourced.
_run_helper() {
    local mode="$1" snippet="$2"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_GH_MODE='${mode}'
        export GH_LOG='${GH_LOG}'
        # The shim logs the GH_HOST it inherited; an ambient one from the
        # developer's shell would make those assertions non-deterministic.
        unset GH_HOST
        . '${DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh'
        ${snippet}
        echo \"rc=\$?\"
    "
}

# ---------------------------------------------------------------------------
# Loading: helpers exist after sourcing
# ---------------------------------------------------------------------------

@test "bash: _gh_pr_edit_safe_label exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                 declare -f _gh_pr_edit_safe_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_pr_edit_safe_body exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                 declare -f _gh_pr_edit_safe_body >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_pr_edit_safe_label exists" {
    run_in_zsh '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                typeset -f _gh_pr_edit_safe_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "label: missing args returns 2" {
    _run_helper ok '_gh_pr_edit_safe_label 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage:"
}

@test "label: unknown option returns 2" {
    _run_helper ok '_gh_pr_edit_safe_label 99 feat --bogus 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "unknown option: --bogus"
}

@test "label: --repo without arg returns 2" {
    _run_helper ok '_gh_pr_edit_safe_label 99 feat --repo 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "--repo requires an argument"
}

@test "body: missing body-file returns 2" {
    _run_helper ok '_gh_pr_edit_safe_body 99 /nonexistent/path/abc.txt 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "body-file not found"
}

# ---------------------------------------------------------------------------
# Happy path: gh pr edit succeeds, no fallback
# ---------------------------------------------------------------------------

@test "label: ok mode — single gh pr edit call, no REST" {
    _run_helper ok '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=0"
    # Exactly one `pr edit`, zero `api ... POST`
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "1"
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "0"
}

@test "body: ok mode — single gh pr edit call, no REST" {
    _run_helper ok "
        BF=\$(mktemp); printf 'hi' > \"\$BF\"
        _gh_pr_edit_safe_body 99 \"\$BF\" --repo fake/repo
        rm -f \"\$BF\"
    "
    assert_output --partial "rc=0"
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "1"
    run grep -c 'api .*PATCH' "$GH_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Fallback path: deprecation warning triggers REST
# ---------------------------------------------------------------------------

@test "label: deprecated mode — falls back to REST POST and succeeds" {
    _run_helper deprecated '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=0"
    # gh pr edit attempted, then label list (validation), then api POST
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "1"
    run grep -c 'label list' "$GH_LOG"
    assert_output "1"
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "1"
}

@test "body: deprecated mode — falls back to REST PATCH and succeeds" {
    _run_helper deprecated_body "
        BF=\$(mktemp); printf 'hello world' > \"\$BF\"
        _gh_pr_edit_safe_body 99 \"\$BF\" --repo fake/repo
        rm -f \"\$BF\"
    "
    assert_output --partial "rc=0"
    run grep -c 'api .*PATCH' "$GH_LOG"
    assert_output "1"
}

# ---------------------------------------------------------------------------
# Defensive guard: REST fallback must NOT auto-create labels.
# ---------------------------------------------------------------------------

@test "label: missing-label mode — refuses REST fallback (rc=3)" {
    _run_helper missing_label '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=3"
    assert_output --partial "refusing REST fallback (would auto-create)"
    # No POST should have been issued.
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Non-deprecation errors must NOT trigger fallback.
# ---------------------------------------------------------------------------

@test "label: other_error mode — passes error through (rc=1, no REST)" {
    _run_helper other_error '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "Some other unrelated error"
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# REST fallback failure surfaces as rc=1
# ---------------------------------------------------------------------------

@test "label: rest_fail mode — REST POST failure surfaces as rc=1" {
    _run_helper rest_fail '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "REST POST failed"
}

# ---------------------------------------------------------------------------
# _gh_pr_drop_label (#1563) — shared REST DELETE with idempotent 404.
#
# Used by every skill that advances a PR's head (`gh:pr-reply`,
# `gh:pr-resolve-conflict`, `gh:pr-resolve-outdated`) to invalidate a stale
# `review-passed` verdict label. DELETE never touches the classic-Projects
# GraphQL path, so there is no `gh pr edit` primary attempt to assert here —
# a single REST call is the whole contract.
# ---------------------------------------------------------------------------

@test "bash: _gh_pr_drop_label exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                 declare -f _gh_pr_drop_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_pr_drop_label exists" {
    run_in_zsh '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                typeset -f _gh_pr_drop_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "drop: missing args returns 2" {
    _run_helper delete_ok '_gh_pr_drop_label 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage:"
    run grep -c 'api .*DELETE' "$GH_LOG"
    assert_output "0"
}

@test "drop: missing repo arg returns 2" {
    _run_helper delete_ok '_gh_pr_drop_label 99 review-passed 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage:"
    run grep -c 'api .*DELETE' "$GH_LOG"
    assert_output "0"
}

@test "drop: delete_ok mode — one REST DELETE, rc=0, no gh pr edit" {
    _run_helper delete_ok \
        '_gh_pr_drop_label 99 review-passed fake/repo github.com 2>&1'
    assert_output --partial "rc=0"
    run grep -c 'api .*DELETE' "$GH_LOG"
    assert_output "1"
    # DELETE is GraphQL-free: no primary `gh pr edit` attempt at all.
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "0"
}

@test "drop: delete_ok mode — repo and label land in the REST path" {
    _run_helper delete_ok \
        '_gh_pr_drop_label 99 review-passed fake/repo github.com 2>&1'
    assert_output --partial "rc=0"
    run grep -c 'repos/fake/repo/issues/99/labels/review-passed' "$GH_LOG"
    assert_output "1"
}

@test "drop: delete_missing mode — 404 verified absent is idempotent success, not a warning" {
    _run_helper delete_missing \
        '_gh_pr_drop_label 99 review-passed fake/repo github.com 2>&1'
    assert_output --partial "rc=0"
    # stderr must be swallowed — a missing label is the normal case.
    refute_output --partial "Not Found"
    refute_output --partial "HTTP 404"
    # The 404 alone proved nothing: a verification GET of the real label list
    # is what licensed the rc=0 (#1583).
    run grep -c 'api repos/fake/repo/issues/99/labels ' "$GH_LOG"
    assert_output "1"
}

@test "drop: delete_fail mode — label still listed, rc=1 with stderr passed through" {
    _run_helper delete_fail \
        '_gh_pr_drop_label 99 review-passed fake/repo github.com 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "Internal Server Error"
    # Verification ran and found the label still attached.
    run grep -c 'api repos/fake/repo/issues/99/labels ' "$GH_LOG"
    assert_output "1"
}

@test "drop: delete_notfound_repo mode — unverifiable 404 must NOT be swallowed (rc=1)" {
    # PR #1583 codex BLOCKER: GitHub answers a bad repo slug, a bad PR number
    # and a wrong GH_HOST with the very same generic `Not Found (HTTP 404)` as
    # "label not on this issue". Reading the DELETE's stderr would report
    # success to a caller that never reached the issue at all, leaving a stale
    # `review-passed` alive on unreviewed code. When the verification GET also
    # fails, the state is unknown → surface the original error, rc=1.
    _run_helper delete_notfound_repo \
        '_gh_pr_drop_label 99 review-passed typo/repo github.com 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "Not Found"
    # Both calls were attempted: the DELETE, then the verification GET.
    run grep -c 'api .*DELETE' "$GH_LOG"
    assert_output "1"
    run grep -c 'api repos/typo/repo/issues/99/labels ' "$GH_LOG"
    assert_output "1"
}

@test "drop: host argument reaches gh as the GH_HOST env var, not just argv" {
    # PR #1583 codex FOLLOW-UP: the pinning (#1403 / #1407) is an exported
    # env var inside a subshell, invisible in argv — assert on the value the
    # `gh` process actually inherited.
    _run_helper delete_ok \
        '_gh_pr_drop_label 99 review-passed fake/repo github.example.com 2>&1'
    assert_output --partial "rc=0"
    run grep -c '^GH_HOST=github.example.com gh api .*DELETE' "$GH_LOG"
    assert_output "1"
}

@test "drop: no host argument leaves GH_HOST unset so gh's own default applies" {
    _run_helper delete_ok '_gh_pr_drop_label 99 review-passed fake/repo 2>&1'
    assert_output --partial "rc=0"
    run grep -c '^GH_HOST= gh api .*DELETE' "$GH_LOG"
    assert_output "1"
}

@test "drop: label is percent-encoded into the URL path segment" {
    # PR #1583 agy FOLLOW-UP: the label is a path SEGMENT in the DELETE URL
    # (unlike the POST above, where it rides in a `-f` body field). A raw `/`
    # or space would forge a different path — and, post-#1583, a 404 from a
    # malformed path is indistinguishable from "genuinely absent".
    _run_helper delete_ok \
        "_gh_pr_drop_label 99 'needs review/ci' fake/repo github.com 2>&1"
    assert_output --partial "rc=0"
    run grep -c 'repos/fake/repo/issues/99/labels/needs%20review%2Fci' "$GH_LOG"
    assert_output "1"
    # The raw, unencoded form must never appear in the path.
    run grep -c 'labels/needs review/ci' "$GH_LOG"
    assert_output "0"
}

@test "drop: unreserved characters survive encoding unescaped" {
    # RFC 3986 unreserved set (A-Za-z0-9-._~) must pass through untouched, or
    # every ordinary label name would arrive mangled.
    _run_helper delete_ok \
        '_gh_pr_drop_label 99 review-passed.v2_x~y fake/repo github.com 2>&1'
    assert_output --partial "rc=0"
    run grep -c 'labels/review-passed\.v2_x~y' "$GH_LOG"
    assert_output "1"
}

# ---------------------------------------------------------------------------
# Self-check (#724) — "helper present but wrappers undefined" canary.
# Codex review on PR #725 flagged the gap: gh_pr_edit_safe.sh grew a
# multi-function self-check (verifies BOTH `_gh_pr_edit_safe_label` and
# `_gh_pr_edit_safe_body`) but there were no Bats cases proving (a) the
# warning stays silent on a healthy source and (b) it fires when either
# wrapper is undefined post-source. PR #1583 added a third clause for
# `_gh_pr_drop_label` (#1563); the synthetic stubs below mirror the tail
# verbatim, so they must be updated in lockstep with it.
# ---------------------------------------------------------------------------

@test "self-check (#724): healthy gh_pr_edit_safe source emits no BUG warning" {
    # Sanity: sourcing the real helper defines both wrappers; the tail
    # self-check should see both `command -v` checks succeed and stay
    # silent. Catches a future regression where the warning fires on
    # the happy path (false positive).
    run bash --noprofile --norc -c \
        ". \"${SHELL_COMMON}/functions/gh_pr_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "BUG: _gh_pr_edit_safe_"
}

@test "self-check (#724): regressed gh_pr_edit_safe (no wrappers) prints warning" {
    # Synthesize the failure mode #724 targets: future regression leaves
    # the file sourceable but neither wrapper gets defined. The tail
    # self-check MUST print a stderr warning while keeping rc 0 so
    # caller's `||` chains stay intact.
    cat >"$BATS_TEST_TMPDIR/regressed_edit_safe.sh" <<'STUB'
#!/bin/sh
# Simulate: future regression — both wrappers never get defined.
# Trailing self-check (copied verbatim from gh_pr_edit_safe.sh tail):
if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1 \
    || ! command -v _gh_pr_edit_safe_body >/dev/null 2>&1 \
    || ! command -v _gh_pr_drop_label >/dev/null 2>&1; then
    printf '[gh_pr_edit_safe] BUG: _gh_pr_edit_safe_{label,body} / _gh_pr_drop_label undefined after source — PR edit safe-fallback will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/regressed_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial \
        "BUG: _gh_pr_edit_safe_{label,body} / _gh_pr_drop_label undefined after source"
}

@test "self-check (#724): partial wrappers (label only) still triggers warning" {
    # Multi-function check must catch the case where ONE wrapper is
    # defined but the other isn't (typo / partial sourcing). Defines
    # only `_gh_pr_edit_safe_label`; the `||` between the two
    # `command -v` clauses MUST fire on the missing `_body`.
    cat >"$BATS_TEST_TMPDIR/partial_edit_safe.sh" <<'STUB'
#!/bin/sh
# Define label wrapper only — body wrapper is missing.
_gh_pr_edit_safe_label() { return 0; }
# Trailing self-check (copied verbatim from gh_pr_edit_safe.sh tail):
if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1 \
    || ! command -v _gh_pr_edit_safe_body >/dev/null 2>&1 \
    || ! command -v _gh_pr_drop_label >/dev/null 2>&1; then
    printf '[gh_pr_edit_safe] BUG: _gh_pr_edit_safe_{label,body} / _gh_pr_drop_label undefined after source — PR edit safe-fallback will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/partial_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial \
        "BUG: _gh_pr_edit_safe_{label,body} / _gh_pr_drop_label undefined after source"
}

@test "self-check (#724): both edit wrappers present but _gh_pr_drop_label missing still warns" {
    # PR #1583 agy FOLLOW-UP: the self-check grew a third clause when
    # `_gh_pr_drop_label` (#1563) joined the file. Undefined, every
    # head-advancing skill silently keeps a stale `review-passed` — exactly
    # the class of silent breakage #724 exists to shout about. Defines BOTH
    # edit wrappers so only the new clause can fire.
    cat >"$BATS_TEST_TMPDIR/no_drop_edit_safe.sh" <<'STUB'
#!/bin/sh
# Define both edit wrappers — only the drop helper is missing.
_gh_pr_edit_safe_label() { return 0; }
_gh_pr_edit_safe_body() { return 0; }
# Trailing self-check (copied verbatim from gh_pr_edit_safe.sh tail):
if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1 \
    || ! command -v _gh_pr_edit_safe_body >/dev/null 2>&1 \
    || ! command -v _gh_pr_drop_label >/dev/null 2>&1; then
    printf '[gh_pr_edit_safe] BUG: _gh_pr_edit_safe_{label,body} / _gh_pr_drop_label undefined after source — PR edit safe-fallback will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/no_drop_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial \
        "BUG: _gh_pr_edit_safe_{label,body} / _gh_pr_drop_label undefined after source"
}

# ---------------------------------------------------------------------------
# #1454 foreign-checkout guard, propagated to this file by issue #1505.
#
# Mirrors tests/bats/functions/gh_pr_review.bats — zsh is the case that
# matters: the guard reads ${BASH_SOURCE[0]}, which bash always populated but
# zsh never does, so before #1454 the zsh path self-disabled on its first
# line. The file is re-sourced explicitly rather than read off the loader's
# own pass because both loaders source with `2>/dev/null` (safe_source /
# load_category), which would swallow the very stderr under test.
# ---------------------------------------------------------------------------

@test "zsh: #1505 foreign-checkout guard warns when gh_pr_edit_safe.sh is sourced under zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_zsh '. "$SHELL_COMMON/functions/gh_pr_edit_safe.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/gh_pr_edit_safe.sh"
}

@test "bash: #1505 foreign-checkout guard warns when gh_pr_edit_safe.sh is sourced under bash" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_bash '. "$SHELL_COMMON/functions/gh_pr_edit_safe.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/gh_pr_edit_safe.sh"
}
