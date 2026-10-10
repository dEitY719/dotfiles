#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all_fanout.bats
# devx_pr_review_all_fanout (#2069): every `<ai>:<preset>` lane runs
# gh_pr_review in parallel, and each lane reports one `ok` / `skip<TAB>why`
# line. The real gh_pr_review is replaced by a stub module under a throwaway
# $SHELL_COMMON — the fanout sources gh_pr_review.sh from there in each lane.
load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_SHELL_COMMON:?}/functions/gh_pr_review.sh"
    # shellcheck disable=SC1090
    source "${_BATS_REAL_SHELL_COMMON:?}/functions/devx_pr_review_all.sh"
    export SHELL_COMMON="$TEST_TEMP_HOME/sc"
    mkdir -p "$SHELL_COMMON/functions"
    # Stub: sleeps 1s per lane, then behaves by --ai value. `--ai X --review
    # Y <pr> <remote>` is the exact argv the fanout must pass.
    cat >"$SHELL_COMMON/functions/gh_pr_review.sh" <<'EOF'
gh_pr_review() {
    [ "$1" = "--ai" ] && [ "$3" = "--review" ] || { echo "bad argv: $*" >&2; return 9; }
    sleep 1
    case "$2" in
    codex) printf '\n  boom:   it\tbroke  \nsecond line\n' >&2; return 1 ;;
    agy) return 3 ;;
    hang) sleep 5; return 0 ;;
    *) echo "review posted $2 $4 $5 $6"; return 0 ;;
    esac
}
EOF
}

teardown() {
    teardown_isolated_home
}

@test "fanout: one failing lane of three -> exactly 3 lines, skip reason, others ok, in parallel" {
    local start end
    start=$(date +%s)
    run devx_pr_review_all_fanout 42 origin "claude:default,codex:thorough,opencode:default"
    end=$(date +%s)
    assert_success
    [ "${#lines[@]}" -eq 3 ]
    assert_line --index 0 "claude:default:ok"
    assert_line --index 1 "$(printf 'codex:thorough:skip\tboom: it broke')"
    assert_line --index 2 "opencode:default:ok"
    # Three 1s lanes run serially take >= 3s, which whole-second `date +%s`
    # can never report as under 3; in parallel they take ~1s (<= 2 reported).
    [ $((end - start)) -lt 3 ]
}

@test "fanout: non-zero rc with empty stderr -> exit <rc>" {
    run devx_pr_review_all_fanout 42 origin "agy:default"
    assert_success
    assert_output "$(printf 'agy:default:skip\texit 3')"
}

@test "fanout: a hung lane is cut by the timeout and reported as such" {
    GH_PR_REVIEW_SLOW_CLI_TIMEOUT_SEC=2 run devx_pr_review_all_fanout 42 origin "hang:default,claude:default"
    assert_success
    assert_line --index 0 "$(printf 'hang:default:skip\ttimeout 2s')"
    assert_line --index 1 "claude:default:ok"
}

@test "fanout: lane stdout does not leak into the result lines" {
    run devx_pr_review_all_fanout 42 origin "claude:default"
    assert_success
    assert_output "claude:default:ok"
}

@test "fanout: empty lanes -> rc 2 with usage" {
    run devx_pr_review_all_fanout 42 origin ""
    assert_failure 2
    assert_output --partial "usage: <pr> <remote>"
}

@test "fanout: malformed lane -> rc 2 with usage" {
    run devx_pr_review_all_fanout 42 origin "claude"
    assert_failure 2
    assert_output --partial "usage: <pr> <remote>"
}

@test "fanout: missing remote -> rc 2 with usage" {
    run devx_pr_review_all_fanout 42
    assert_failure 2
    assert_output --partial "usage: <pr> <remote>"
}
