#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_dependency_detect.bats
# Locks the Step 2.6 trigger-phrase matrix documented in
#   claude/skills/gh-issue-create/references/dependency-detect.md
# and the --no-auto-deps escape documented in
#   claude/skills/gh-issue-create/SKILL.md.
#
# Source-of-truth fixture: _fixtures/gh_issue_create_dependency_detect.sh.
# It mirrors the detection half (pure text -> issue numbers) and the Step
# 4.5 outcome classification (which id/mutation states raise the NF-1
# warning). The two `gh api graphql` calls are still not mocked — mocking
# `gh` would test the mock — so the fixture-backed tests stay network-free.
#
# The two `addBlockedBy` argument-shape guards at the bottom (#1457) are the
# exception, and they are not mocks either: one asserts the doc's own
# mutation string offline, the other asks the *live* schema what
# `AddBlockedByInput` actually accepts and skips when there is no network or
# no auth. Together they close the gap #1445 exposed — before them this
# suite was byte-for-byte green on both sides of that fix.

bats_require_minimum_version 1.5.0

load '../test_helper'

# gh's own config-dir resolution order, evaluated at file-load time — i.e.
# before setup()'s sandbox replaces $HOME and $XDG_CONFIG_HOME. Under the
# sandbox alone every run looks unauthenticated, so the live-schema check
# below would skip forever instead of ever detecting drift.
#
# Naming the directory directly (rather than restoring the developer's real
# $HOME, PR #1465 codex review) is what keeps the blast radius at "read one
# config file": $HOME and $XDG_CONFIG_HOME stay sandboxed, so nothing this
# suite runs can write to the developer's home no matter how gh behaves.
_REAL_GH_CONFIG_DIR="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}"

_gh_real_config() {
    GH_CONFIG_DIR="$_REAL_GH_CONFIG_DIR" "$@"
}

# Prints only the fenced code blocks of $1, fence lines excluded. The doc's
# prose and its executable snippets have different drift rules — see the
# #1457 offline guard below.
_doc_code_blocks() {
    awk '/^```/ { inblock = !inblock; next } inblock' "$1"
}

# Returns 0 when $2 appears inside a fenced code block of the doc at $1.
_doc_code_contains() {
    _doc_code_blocks "$1" | grep -Fq "$2"
}

setup() {
    setup_isolated_home
    # One definition for every doc-guard below. Two copies is how a skill-dir
    # rename updates one and misses the other — and a stale path is not loud
    # here: `run grep -Fq ... "$DOC"` on a missing file exits non-zero, so the
    # "the drifted spelling appears nowhere" assertion would pass vacuously.
    DOC="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-issue-create/references/dependency-detect.md"
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh"
}

teardown() {
    teardown_isolated_home
}

# ── Korean trailing triggers ─────────────────────────────────────────
@test "deps: '#13 완료 후' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 완료 후에 진행하자" 0
    assert_success
    assert_output '13'
}

@test "deps: '#13 이후에' is a dependency trigger" {
    run gh_issue_create_detect_deps "이 작업은 #13 이후에 하면 된다" 0
    assert_success
    assert_output '13'
}

@test "deps: '선행 이슈: #13' is a dependency trigger" {
    run gh_issue_create_detect_deps "선행 이슈: #13" 0
    assert_success
    assert_output '13'
}

# ── English leading triggers ─────────────────────────────────────────
@test "deps: 'depends on #13' is a dependency trigger (case-insensitive)" {
    run gh_issue_create_detect_deps "This DEPENDS ON #13 landing first" 0
    assert_success
    assert_output '13'
}

@test "deps: 'blocked by #13' is a dependency trigger" {
    run gh_issue_create_detect_deps "blocked by #13" 0
    assert_success
    assert_output '13'
}

# ── Negative: plain mentions must NOT link (F-1 오탐 방지) ───────────
@test "deps: '#13 참고' is a plain mention, not a dependency" {
    run gh_issue_create_detect_deps "#13 참고해서 작업" 0
    assert_success
    assert_output ''
}

@test "deps: '#13 관련' is a plain mention, not a dependency" {
    run gh_issue_create_detect_deps "#13 관련 내용은 아래 참조" 0
    assert_success
    assert_output ''
}

@test "deps: a bare '#13' with no trigger phrase is not a dependency" {
    run gh_issue_create_detect_deps "see #13 for context" 0
    assert_success
    assert_output ''
}

# ── Multiple + de-dup ────────────────────────────────────────────────
@test "deps: multiple triggers yield ascending, de-duped numbers" {
    run gh_issue_create_detect_deps \
        "#20 완료 후에 진행. blocked by #13. 그리고 #13 이후에 재확인." 0
    assert_success
    assert_line --index 0 '13'
    assert_line --index 1 '20'
    [ "${#lines[@]}" -eq 2 ]
}

# ── NF-2: cross-repo is out of v1 scope ──────────────────────────────
@test "deps: cross-repo 'owner/repo#13' warns and is skipped" {
    run --separate-stderr gh_issue_create_detect_deps \
        "depends on dEitY719/other-repo#13" 0
    assert_success
    assert_output ''
    assert_stderr --partial "cross-repo dependency detected but not supported in v1"
}

@test "deps: cross-repo skip does not drop a same-repo sibling" {
    run --separate-stderr gh_issue_create_detect_deps \
        "depends on dEitY719/other-repo#99 and blocked by #13" 0
    assert_success
    assert_output '13'
    assert_stderr --partial "cross-repo dependency detected but not supported in v1"
}

# ── F-3: --no-auto-deps escape ───────────────────────────────────────
@test "deps: --no-auto-deps skips detection entirely" {
    run gh_issue_create_detect_deps "#13 완료 후에 진행하자" 1
    assert_success
    assert_output ''
}

# ── F-1 (#1424 review): 완료/해결 conjugations beyond "완료 후" ──────
@test "deps: '#13 완료되면' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 완료되면 바로 시작하자" 0
    assert_success
    assert_output '13'
}

@test "deps: '#13 해결 후' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 해결 후에 재측정" 0
    assert_success
    assert_output '13'
}

@test "deps: '#13 완료하고' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 완료하고 넘어가자" 0
    assert_success
    assert_output '13'
}

@test "deps: '선행이슈 #13' matches without a colon" {
    run gh_issue_create_detect_deps "선행이슈 #13" 0
    assert_success
    assert_output '13'
}

@test "deps: a trigger word detached from the reference does not link" {
    # The 완료/해결 branch requires adjacency. Here '검토 후' belongs to a
    # different clause than '#13', so widening the pattern to '#N .* 후'
    # would produce exactly the false positive F-1 forbids.
    run gh_issue_create_detect_deps "#13 참고. 검토 후 진행하자" 0
    assert_success
    assert_output ''
}

# ── Pipefail safety (#1424 review) ───────────────────────────────────
@test "deps: no match under 'set -e -o pipefail' still returns cleanly" {
    # grep exits 1 on no-match; without the pipeline's `|| true` an errexit
    # caller would abort issue creation over "nothing to link".
    run bash -c "
        set -e -o pipefail
        source '${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh'
        gh_issue_create_detect_deps '아무 의존성도 없는 대화' 0
        echo REACHED_END
    "
    assert_success
    assert_output 'REACHED_END'
}

# ── NF-1: Step 4.5 link-outcome classification (#1424 review) ────────
# $5 carries the stderr captured from whichever GraphQL call failed. It is
# what makes a permanent defect (argument-schema mismatch) distinguishable
# from a transient one (replication lag, network) — before #1458 every cause
# collapsed into the same single line.
@test "link: both ids present and mutation ok → no warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 0 13 ""
    assert_success
    assert_output ''
    [ -z "$stderr" ]
}

@test "link: a successful link stays silent even when stderr was captured" {
    # Harmlessness (#1458): gh can chatter on stderr and still succeed. The
    # 원인 line rides on the NF-1 warning, so it must never appear alone.
    run --separate-stderr gh_issue_create_dep_link_outcome \
        "I_new" "I_dep" 0 13 "note: unrelated gh chatter"
    assert_success
    assert_output ''
    [ -z "$stderr" ]
}

@test "link: null new-issue id → NF-1 warning, mutation never reached" {
    run --separate-stderr gh_issue_create_dep_link_outcome "" "I_dep" 0 13 ""
    assert_success
    assert_output ''
    [[ "$stderr" == *"[WARN] Blocked by #13 링크 실패"* ]]
}

@test "link: null dep-issue id → NF-1 warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "" 0 13 ""
    assert_success
    assert_output ''
    [[ "$stderr" == *"[WARN] Blocked by #13 링크 실패"* ]]
}

@test "link: rejected mutation → NF-1 warning naming that issue" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 20 ""
    assert_success
    assert_output ''
    [[ "$stderr" == *"[WARN] Blocked by #20 링크 실패 — GH UI에서 수동 추가 필요"* ]]
}

@test "link: no captured cause → the warning carries no 원인 line" {
    # NF-1 is unchanged when there is nothing to add: a bare failure still
    # produces exactly the one line it always did.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 20 ""
    assert_success
    [[ "$stderr" != *"원인:"* ]]
}

@test "link: a non-existent dep number surfaces its GraphQL cause" {
    # The id lookup, not the mutation, is what fails here — the cause has to
    # survive that call too, or this verification case is unreachable.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "" 0 999 \
        "gh: Could not resolve to an Issue with the number of 999. (repository.depIssue)"
    assert_success
    [[ "$stderr" == *"[WARN] Blocked by #999 링크 실패"* ]]
    [[ "$stderr" == *"원인: gh: Could not resolve to an Issue with the number of 999."* ]]
}

@test "link: an argument-schema mismatch surfaces verbatim (#1445 regression)" {
    # This exact sentence was on the wire during #1445 and was thrown away.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 13 \
        "gh: Argument 'blockingIssueId' on InputObject 'AddBlockedByInput' is required. Expected type ID!"
    assert_success
    [[ "$stderr" == *"원인: "* ]]
    [[ "$stderr" == *"AddBlockedByInput"* ]]
}

@test "link: a multi-line cause is truncated to its first line" {
    # 확정 3: the full GraphQL error would swamp \$DEP_WARNINGS in the Step 5
    # report, and the first line already separates schema/permission/network.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 13 \
        "$(printf 'first line matters\nsecond line must not appear\nthird')"
    assert_success
    [[ "$stderr" == *"원인: first line matters"* ]]
    [[ "$stderr" != *"second line must not appear"* ]]
}

@test "link: the 원인 line is indented directly under its warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 13 "boom"
    assert_success
    [[ "$stderr" == *"수동 추가 필요"$'\n'"    원인: boom"* ]]
}

@test "link: one failing sibling does not disturb the other's success" {
    # Per-N isolation (#1458 verification): #13 fails with a cause, #20 links.
    run --separate-stderr bash -c "
        source '${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh'
        gh_issue_create_dep_link_outcome 'I_new' '' 0 13 'gh: Could not resolve to an Issue with the number of 13.'
        gh_issue_create_dep_link_outcome 'I_new' 'I_dep' 0 20 ''
    "
    assert_success
    [[ "$stderr" == *"Blocked by #13 링크 실패"* ]]
    [[ "$stderr" == *"원인: gh: Could not resolve"* ]]
    [[ "$stderr" != *"#20"* ]]
}

# ── Drift guard: doc and fixture must share one reference regex ──────
@test "drift: the doc's reference regex is byte-identical to the fixture's" {
    # The SKILL prose is what actually runs; the fixture is what the tests
    # exercise. Without this guard, editing one and not the other leaves the
    # suite green while shipped behaviour diverges. Same pattern as
    # post_gh_pr_create_hook.bats T20.
    run grep -Fq "$_GH_DEPS_REF" "$DOC"
    assert_success
}

# ── Drift guard: the doc must not discard the GraphQL cause (#1458) ──
@test "drift: the doc's Step 4.5 keeps GraphQL stderr instead of discarding it" {
    # Same reasoning as the regex guard, one level up: the fixture mirroring
    # the cause line proves nothing if the prose that actually runs still
    # writes the discard over it — that discard is precisely what hid #1445.
    # Scoped to the fenced block, because the surrounding prose quotes the
    # removed idiom on purpose when explaining why it went away.
    BLOCK=$(awk '/^```bash$/ {f=1; next} /^```$/ {f=0} f' "$DOC")
    [ -n "$BLOCK" ]
    [[ "$BLOCK" != *'>/dev/null 2>&1'* ]]
    [[ "$BLOCK" == *'2>"$_errf"'* ]]
    [[ "$BLOCK" == *"원인: "* ]]
}

# ── #1457: addBlockedBy argument shape, pinned two ways ──────────────
#
# #1445 fixed a drift from the non-existent `blockedByIds: [ID!]` to the
# real `blockingIssueId: ID!`, and this suite was green before *and* after
# that fix — it proved nothing. NF-1 is why the drift was quiet in the
# first place: a rejected mutation is downgraded to one warning line and
# the issue is still created, so nobody notices until a `Blocked by` link
# silently stops appearing.
#
# The two checks below fail differently on purpose: the offline one catches
# an accidental edit to the doc, the live one catches an upstream schema
# change. Scope is `addBlockedBy` only — the `Issue.blockedBy` read path was
# verified working in #1445 and pinning the whole schema would cost more
# than it is worth.

@test "shape: the doc's addBlockedBy mutation uses blockingIssueId, not blockedByIds" {
    # Offline half. `references/dependency-detect.md` is the SSOT that the
    # skill actually executes, so a revert to the rejected array form must
    # turn this suite red with no network at all — the live check below
    # skips in that situation and would leave the tree undefended.

    # The prose that records the verified input shape.
    run grep -Fq '{issueId: ID!, blockingIssueId: ID!}' "$DOC"
    assert_success

    # The executable mutation itself.
    run grep -Fq 'addBlockedBy(input:{issueId:$issueId, blockingIssueId:$blockingIssueId})' "$DOC"
    assert_success

    # And the drifted spelling survives in none of the doc's executable
    # snippets. Scoped to fenced code, not the whole file (PR #1465, agy +
    # codex both): a whole-file ban would also forbid the prose from ever
    # naming the old spelling to explain the #1445 history, which is exactly
    # the kind of context the next reader needs. Coverage is unchanged —
    # the two positive assertions above already pin the prose line and the
    # mutation string, so a revert in either place still turns this red.
    run _doc_code_contains "$DOC" 'blockedByIds'
    assert_failure
}

@test "shape: AddBlockedByInput's live input fields match the documented shape" {
    # Live half — introspection, not a mock: it asks the real server what the
    # mutation accepts. Skips rather than fails without network or auth
    # (#1457 확정 2): a red here in an offline shell would get the check
    # switched off, and detection is not lost — one networked run catches the
    # drift. github.com is queried explicitly because that is the host whose
    # shape the doc records.
    #
    # Where that networked run happens (PR #1465, codex): `git/hooks/pre-push`
    # runs `mise run test` on every push, and this repo deliberately has no CI
    # test lane to wire into — #754 moved the whole suite to that hook, SSOT
    # in `docs/.ssot/local-test-policy.md`. The pushing machine is the same one
    # that just authenticated `gh`, so the guard runs for real on the path that
    # matters. It is a developer-machine guarantee, not a server-side one: a
    # push with `SKIP_LOCAL_PYTEST=1`, or from a shell with no gh auth, skips
    # it — which is what the offline guard above is there to cover.
    command -v gh >/dev/null 2>&1 || skip "gh not installed"
    # `auth token`, not `auth status`: it answers the same question from the
    # local config instead of verifying the token against the API, so the
    # precondition costs no round-trip. Only the introspection below is
    # allowed to touch the network.
    _gh_real_config gh auth token --hostname github.com >/dev/null 2>&1 ||
        skip "not authenticated to github.com — live schema check needs a real API"

    # `mise run test` runs this suite from the pre-push hook, so the one
    # network call is bounded: a half-open link must skip, not hang a push.
    # A timeout leaves $fields empty and lands on the same skip as no network.
    fields=$(_gh_real_config timeout 10 env GH_HOST=github.com gh api graphql \
        -f query='{__type(name:"AddBlockedByInput"){inputFields{name}}}' \
        --jq '[.data.__type.inputFields[].name] | sort | join(",")' 2>/dev/null) || fields=""
    [ -n "$fields" ] || skip "GraphQL introspection unavailable"

    # Exact equality is deliberate. An added field is also drift worth
    # seeing: the doc records this shape as verified, and the red is the
    # prompt to re-verify it rather than a spurious failure.
    assert_equal "$fields" 'blockingIssueId,clientMutationId,issueId'
}
