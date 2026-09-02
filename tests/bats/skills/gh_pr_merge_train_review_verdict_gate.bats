#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_train_review_verdict_gate.bats
# The merge train's review verdict gate (#1564, umbrella #1527).
# Source-of-truth fixture: _fixtures/gh_pr_merge_train_review_verdict_gate.sh
# (the skill docs it used to mirror left this repo with #1680)
#
# Issue #1564 verification checklist:
#   review-blocked / no label / review-passed  -> [SKIPPED] · [SKIPPED] · proceed
#   review-blocked beats a stale review-passed
#   the gate runs AFTER _gh_pr_merge_train_filter_targets, independently of it
#   (gh:label-bootstrap's own provisioning coverage left this repo with the
#    skill in #1680 — it lives in the gh-setup-skills repo now)
#   no code path in the train parses a review comment body

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_merge_train_review_verdict_gate.sh'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------
# The decision table
# ---------------------------------------------------------------------

@test "gate: review-blocked -> [SKIPPED] with the blocking reason" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: no verdict label at all -> [SKIPPED] review not verified" {
    run train_verdict_gate "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# Absence is the third state and it must stay a skip. Merging an unreviewed PR
# is the failure #1527 reproduced (PR #1518 -> #1520 -> PR #1522); a skip is
# one label away from moving.
@test "gate: an unrelated label is still 'not verified'" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"enhancement"},{"name":"ai"}]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "gate: review-passed alone -> stays in the queue" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

@test "gate: review-passed alongside unrelated labels still proceeds" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"fix"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# #1563's invalidation should make this unreachable, but a gate on a merge has
# to be deterministic about a state it does not expect. Blocked wins.
@test "gate: review-blocked beats a stale review-passed" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: label order does not change the verdict" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# A `gh pr list` whose --json projection omitted `labels` must read as "not
# verified", never as a pass — the same fail-closed direction as everywhere
# else in this train.
@test "gate: a PR object with no labels field is 'not verified'" {
    run train_verdict_gate '{"number":11,"isDraft":false}'
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# ---------------------------------------------------------------------
# routing-table.md F-3 — the mid-run re-check
# ---------------------------------------------------------------------
#
# A deferred devx:pr-review-all pass can add or flip a verdict label minutes
# after Step 2 built the queue. F-3's re-query is the only thing that sees it,
# so the verdict rows have to short-circuit the D-1 table the same way
# `reply-pending` does — before `mergeStateStatus` is read at all.

@test "F-3: a mid-run review-blocked short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3: a mid-run label loss short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3: review-passed lets the PR reach the D-1 table" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# Order among the short-circuits: draft and reply-pending are answered first,
# so their (more specific) reasons are what the report shows.
@test "F-3: draft outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]' true)"
    assert_success
    assert_output 'skip:draft'
}

@test "F-3: reply-pending outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit \
        "$(verdict_pr 11 '[{"name":"reply-pending"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:reply-pending — review reply not yet complete'
}

# ---------------------------------------------------------------------
# Independence from the Step 2 array filter (#1564 verification item)
# ---------------------------------------------------------------------
#
# The two filters answer different questions and a PR must pass BOTH. The
# verdict gate deliberately does NOT live inside
# `_gh_pr_merge_train_filter_targets`: that one drops its rejects silently,
# before the queue exists, and report-format.md documents those PRs as never
# listed — which would hide this gate's entire output.

@test "independence: the array filter passes a review-blocked PR through" {
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh'
        printf '%s' '[{\"number\":11,\"updatedAt\":\"2020-01-01T00:00:00Z\",\"isDraft\":false,\"labels\":[{\"name\":\"review-blocked\"}]}]' \
          | _gh_pr_merge_train_filter_targets --now 1800000000 | jq -r '.[].number'"
    assert_success
    assert_output "11"
}

@test "independence: the gate then rejects that same PR" {
    run train_verdict_gate '{"number":11,"labels":[{"name":"review-blocked"}]}'
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# ---------------------------------------------------------------------
# Doc guards — only the shell SSOT ones survive (#1680)
# ---------------------------------------------------------------------
#
# gh-pr-merge-train's SKILL.md and references/ (review-verdict-gate.md,
# routing-table.md, report-format.md), and devx-pr-review-all's producer SSOT,
# moved out to their own marketplace repos, so the guards that pinned the
# fixture above to that prose belong there. The fixture mirror stays as real,
# runnable behaviour — it is simply no longer pinned to any doc in this repo.

@test "doc-guard: no staleness window function exists for the verdict labels" {
    run grep -qE '_gh_pr_merge_train_review_(blocked|passed)_stale_minutes' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    assert_failure
}

# ---------------------------------------------------------------------
# Sha-freshness check for `review-passed` (#1601)
# ---------------------------------------------------------------------
#
# The label alone only proves "some head was reviewed" — its only
# invalidation path is a handful of hand-wired call sites, and a manual
# `git push --force-with-lease` or a GitHub web-UI commit advances the head
# with no hook any of them can see. `_gh_pr_merge_train_review_passed_stale`
# closes that gap by verifying a `<!-- review-verdict:review-passed:<sha> -->`
# marker (posted by `devx_pr_review_all_write_label`, since #1636 on
# gh:pr-reply's write path) against the PR's actual current head, instead of
# trusting label presence alone.
#
# Since #1615 the lookup is bounded to AT MOST TWO `gh api` calls no matter
# how long the PR's comment history is: call 1 fetches page 1 with `-i` (so
# the response headers arrive on stdout ahead of the body) and reads the
# `Link: ...; rel="last"` header; if that says there is more than one page it
# jumps STRAIGHT to the last one (call 2), never walking the pages between.
# The stub below therefore has to answer BOTH call shapes.

_freshness_stub() {
    STUB_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$STUB_LOG"
    # STUB_COMMENTS_JSON: a JSON array of `{"user":{"login":...},"body":...}`
    # objects — the real shape `gh api .../comments` answers. Tests set this
    # instead of a flat text blob so author filtering can be exercised
    # faithfully: the stub replays the REAL `--jq` expression the function
    # under test built (with its `select(.user.login == "...")` clause)
    # against this JSON via a real `jq`, rather than re-deriving the filter
    # logic in bash by hand. It is the body of PAGE 1.
    : "${STUB_COMMENTS_JSON:=[]}"
    # STUB_LAST_PAGE: unset or 1 = single-page PR, so the page-1 response
    # carries NO `Link` header at all (the default, which is what every
    # pre-#1615 test here exercises). Set it to N>1 to simulate an N-page PR:
    # the page-1 response then grows a `rel="last"` Link header pointing at
    # page N, and STUB_PAGE_N_COMMENTS_JSON becomes the body served for the
    # page=N call.
    : "${STUB_PAGE_N_COMMENTS_JSON:=[]}"
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$STUB_LOG"
        case "$*" in
        *"/comments"*"--jq"*)
            # Scan positionally — never a fixed index. The real call's flag
            # order has already shifted twice (per_page=100, then `-i -X GET`
            # plus an explicit page), so hardcoding "the 5th arg" silently
            # reads the wrong token the next time flags move.
            _fs_jq_expr=""
            _fs_want_next=0
            _fs_page=1
            _fs_include_headers=0
            for _fs_arg in "$@"; do
                if [ "$_fs_want_next" -eq 1 ]; then
                    _fs_jq_expr="$_fs_arg"
                    _fs_want_next=0
                    continue
                fi
                case "$_fs_arg" in
                --jq) _fs_want_next=1 ;;
                -i) _fs_include_headers=1 ;;
                # `page=N`, not `per_page=N` — the latter starts with `per_`.
                page=*) _fs_page="${_fs_arg#page=}" ;;
                esac
            done

            # STUB_COMMENTS_RC fails EVERY /comments call (page 1 included) —
            # use it to test call-1 failure. STUB_PAGE_N_RC fails ONLY a
            # non-page-1 call, so page 1 can succeed and the last-page call
            # can fail on its own — the two must stay independent, or a test
            # named "last-page call fails" would actually fail at call 1 and
            # never reach the code path it claims to cover (PR #1630 review,
            # codex BLOCKER).
            if [ "$_fs_page" = "1" ]; then
                [ "${STUB_COMMENTS_RC:-0}" -eq 0 ] || return "$STUB_COMMENTS_RC"
            else
                [ "${STUB_PAGE_N_RC:-0}" -eq 0 ] || return "$STUB_PAGE_N_RC"
            fi

            if [ "$_fs_include_headers" -eq 1 ]; then
                # Mirror what real `gh api -i` emits (verified against gh
                # 2.45.0): an LF-terminated status line, CRLF-terminated
                # headers, then a lone-CR blank line before the body.
                printf 'HTTP/1.1 200 OK\n'
                printf 'Content-Type: application/json; charset=utf-8\r\n'
                # Decoy: this header's VALUE contains the word "Link", so a
                # parser that greps for `Link` unanchored reads garbage.
                printf 'Access-Control-Expose-Headers: ETag, Link, Location\r\n'
                if [ "${STUB_LAST_PAGE:-1}" -gt 1 ]; then
                    printf 'Link: <https://api.github.com/repositories/1/issues/11/comments?page=2&per_page=100>; rel="next", '
                    printf '<https://api.github.com/repositories/1/issues/11/comments?page=%s&per_page=100>; rel="last"\r\n' \
                        "$STUB_LAST_PAGE"
                fi
                printf '\r\n'
            fi

            if [ "$_fs_page" = "1" ]; then
                printf '%s' "$STUB_COMMENTS_JSON" | jq -r "$_fs_jq_expr"
            else
                printf '%s' "$STUB_PAGE_N_COMMENTS_JSON" | jq -r "$_fs_jq_expr"
            fi
            return 0
            ;;
        *)
            return "${STUB_GH_RC:-0}"
            ;;
        esac
    }
}

# One comment object for STUB_COMMENTS_JSON. $1=login, $2=body.
_comment() {
    jq -nc --arg login "$1" --arg body "$2" '{user:{login:$login},body:$body}'
}

@test "freshness: marker_sha reads the sha out of a matching marker from the expected login" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot 'some review text
<!-- review-verdict:review-passed:abc1234 -->
more text')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output 'abc1234'
}

@test "freshness: marker_sha with no marker at all yields nothing" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot 'just a plain review comment, no marker here')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output ''
}

@test "freshness: marker_sha takes the LAST marker when re-reviewed" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson c1 "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" \
        --argjson c2 "$(_comment bot '<!-- review-verdict:review-passed:2222222 -->')" \
        '[$c1, $c2]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output '2222222'
}

# ── #1706: the revocation marker ──
# `<!-- review-verdict:revoked:<sha> -->` cancels an earlier `review-passed`
# marker. The rule is "the LAST marker of EITHER type from the trusted login
# wins, by comment order" — the sha a revocation names is audit metadata and
# is never compared against anything.

@test "freshness (#1706): a revoked marker after a review-passed one yields nothing, rc 0" {
    # rc 0, not rc 1: a revocation is a CONFIRMED absence (the lookup ran and
    # answered "no standing verdict"), which is a different thing from the
    # lookup itself having failed.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson c1 "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" \
        --argjson c2 "$(_comment bot '<!-- review-verdict:revoked:1111111 -->')" \
        '[$c1, $c2]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output ''
}

@test "freshness (#1706): a revocation naming a DIFFERENT sha still cancels — order decides, not sha" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson c1 "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" \
        --argjson c2 "$(_comment bot '<!-- review-verdict:revoked:9999999 -->')" \
        '[$c1, $c2]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output ''
}

@test "freshness (#1706): a revocation that is NOT last does not poison a later re-review" {
    # Revocation only wins while it is the last marker. A genuine re-review
    # afterwards stamps a new `review-passed` and that one is now last.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson c1 "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" \
        --argjson c2 "$(_comment bot '<!-- review-verdict:revoked:1111111 -->')" \
        --argjson c3 "$(_comment bot '<!-- review-verdict:review-passed:3333333 -->')" \
        '[$c1, $c2, $c3]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output '3333333'
}

@test "freshness (#1706): a revocation from ANY OTHER commenter is ignored" {
    # Same trust boundary as every other marker in this file: an untrusted
    # login can neither grant nor revoke. The trusted marker still wins.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson real "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" \
        --argjson forged "$(_comment some-random-contributor '<!-- review-verdict:revoked:1111111 -->')" \
        '[$real, $forged]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output '1111111'
}

@test "freshness: marker_sha pins GH_HOST on the lookup" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:abc1234 -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget ghe.example.com bot
    assert_success
    run cat "$STUB_LOG"
    assert_output --partial '[GH_HOST=ghe.example.com]'
}

@test "freshness: a lookup failure yields nothing AND a nonzero rc (undetermined, not confirmed)" {
    _freshness_stub
    STUB_COMMENTS_RC=1
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_failure
    assert_output ''
}

# ── #1601 / PR #1608 review (agy + codex BLOCKER): marker authorship ──
# A marker string alone proves nothing — anyone who can comment on the PR
# could type it by hand. Only a marker from the expected (pipeline) login
# may be trusted.

@test "freshness (BLOCKER fix): a marker from ANY OTHER commenter is ignored" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment some-random-contributor '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output ''
}

@test "freshness (BLOCKER fix): the expected login's marker still wins over a forged one" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson forged "$(_comment attacker '<!-- review-verdict:review-passed:deadbeef -->')" \
        --argjson real "$(_comment bot '<!-- review-verdict:review-passed:0000000 -->')" \
        '[$forged, $real]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output '0000000'
}

@test "freshness (BLOCKER fix): an empty expected login is fail-closed (rc 1, no marker)" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget ''
    assert_failure
    assert_output ''
}

@test "freshness (BLOCKER fix): an empty expected login never calls gh at all" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' >/dev/null || true
    run cat "$STUB_LOG"
    assert_output ''
}

@test "freshness (BLOCKER fix): an invalid login (injection attempt) is fail-closed, no gh call" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' 'bot" | .'
    assert_failure
    assert_output ''
    run cat "$STUB_LOG"
    assert_output ''
}

# ── PR #1608 round-2 review (agy BLOCKER): bot logins ──
# GitHub App identities carry a literal `[bot]` suffix in `.user.login`
# (`github-actions[bot]`, `dependabot[bot]`). The first cut of the validator
# rejected every bracket, so a pipeline authenticating as any bot account
# could never validate a single marker.

@test "freshness (BLOCKER fix): a bot login (name[bot]) is accepted" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment 'github-actions[bot]' '<!-- review-verdict:review-passed:abc1234 -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' 'github-actions[bot]'
    assert_success
    assert_output 'abc1234'
}

@test "freshness (BLOCKER fix): a bot login only matches its own marker, not another login's" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment attacker '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' 'dependabot[bot]'
    assert_success
    assert_output ''
}

@test "freshness (BLOCKER fix): a login that merely CONTAINS brackets (not a bot suffix) is still rejected" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment 'bot[x]y' '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' 'bot[x]y'
    assert_failure
    assert_output ''
    run cat "$STUB_LOG"
    assert_output ''
}

# ── #1615: the lookup must cost a BOUNDED number of gh calls ──
# The first cut used `gh api --paginate`, which walks every comment page on
# every merge-train tick — one HTTP round trip per 100 comments, forever.
# These two tests are the regression bound: 1 call for a single-page PR
# (no cost regression on the common case), 2 calls for ANY multi-page PR.

@test "freshness (#1615): a single-page PR still costs exactly ONE gh call" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:abc1234 -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output 'abc1234'
    # No `Link` header came back, so page 1 WAS the whole PR — the body from
    # call 1 must be reused, never re-fetched.
    run wc -l <"$STUB_LOG"
    assert_output '1'
}

@test "freshness (#1615): a 37-page PR costs exactly TWO gh calls and jumps straight to page 37" {
    _freshness_stub
    STUB_LAST_PAGE=37
    # An OLD marker sits on page 1; the CURRENT one is on the last page.
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" '[$c]')
    STUB_PAGE_N_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:9999999 -->')" '[$c]')

    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    assert_success
    assert_output '9999999'

    # (b) two calls — NOT 37. This is the whole point of #1615.
    run wc -l <"$STUB_LOG"
    assert_output '2'

    # (c) the second call asks for page 37 directly, not page 2 or any
    # intermediate page.
    run sed -n '2p' "$STUB_LOG"
    assert_output --partial 'page=37'
    run cat "$STUB_LOG"
    refute_output --partial 'page=2 '
}

@test "freshness (#1615): a failure on the LAST-page call is UNDETERMINED (rc 1), not a confirmed absence" {
    # Page 1 SUCCEEDS (with an old marker) and reports a 4-page PR; only the
    # page=4 call fails. STUB_COMMENTS_RC would fail page 1 too, which never
    # reaches the page-N call this test exists to cover (PR #1630 review,
    # codex BLOCKER: the prior version used STUB_COMMENTS_RC and so always
    # failed at call 1, never actually exercising this path).
    _freshness_stub
    STUB_LAST_PAGE=4
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:1111111 -->')" '[$c]')
    STUB_PAGE_N_RC=1
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget '' bot
    # The function must not fall back to page 1's stale marker (1111111),
    # and must not report "no marker" either — it must fail closed.
    assert_failure
    assert_output ''

    # Prove call 1 (page 1) actually ran and succeeded before call 2 failed —
    # otherwise this test would pass vacuously even if the function bailed
    # out at call 1 for an unrelated reason.
    run wc -l <"$STUB_LOG"
    assert_output '2'
    run sed -n '2p' "$STUB_LOG"
    assert_output --partial 'page=4'
}

# ── _gh_pr_merge_train_review_passed_stale: 3-way exit code ──
# 0 = fresh, 1 = stale CONFIRMED (lookup succeeded, no matching-head marker),
# 2 = stale UNDETERMINED (the lookup itself failed). The two "stale" codes
# are deliberately different rc values — see routing-table.md / #1601 for why
# the caller must not delete the label on a rc-2 (PR #1608 review, agy
# round-2 BLOCKER: a transient lookup failure must never destroy a valid
# review-passed).

@test "freshness: ABSENT (rc 2) when the trusted login posted no marker at all" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot 'no marker in sight')" '[$c]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef bot
    [ "$status" -eq 2 ]
}

@test "freshness: MISMATCH (rc 1) when a marker exists but its sha does not match head" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:0000000 -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef bot
    [ "$status" -eq 1 ]
}

@test "freshness: FRESH (rc 0) when the marker sha matches head" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef bot
    assert_success
}

@test "freshness (#1706): a revoked latest marker is ABSENT (rc 2), not MISMATCH or UNDETERMINED" {
    # The revocation names the CURRENT head, so a sha-comparing implementation
    # would answer rc 0 (fresh) — the whole point is that a revocation is not
    # compared at all, it just erases the standing verdict. rc 2 also means
    # the caller leaves the label alone rather than self-healing it away.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc \
        --argjson c1 "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" \
        --argjson c2 "$(_comment bot '<!-- review-verdict:revoked:deadbeef -->')" \
        '[$c1, $c2]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef bot
    [ "$status" -eq 2 ]
}

@test "freshness (BLOCKER fix): a lookup failure is UNDETERMINED (rc 3), not MISMATCH or ABSENT" {
    _freshness_stub
    STUB_COMMENTS_RC=1
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef bot
    [ "$status" -eq 3 ]
}

@test "freshness (BLOCKER fix): a forged-only marker (wrong login) reads as ABSENT (rc 2), not MISMATCH" {
    # The trusted login posted nothing; "attacker" posting a marker (even a
    # correct-looking one) must never count as evidence either way — it is
    # simply invisible to the check, same as if no comment existed at all.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment attacker '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef bot
    [ "$status" -eq 2 ]
}

@test "freshness (FOLLOW-UP fix): an empty head-oid fails closed to UNDETERMINED (rc 3), never MISMATCH" {
    # agy round-4: a caller that failed to resolve headRefOid upstream must
    # never have that show up as "positive proof of staleness" — an empty
    # head-oid can never equal a real marker sha, so without this guard a
    # genuinely fresh marker would fall through to rc 1 (MISMATCH) and get
    # self-healed away on the strength of the CALLER's own unresolved state.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' '' bot
    [ "$status" -eq 3 ]
    run cat "$STUB_LOG"
    assert_output ''
}

@test "freshness (BLOCKER fix): a literal 'null' head-oid (jq's missing-field answer) also fails closed to rc 3" {
    # agy round-5: jq -r '.headRefOid' on a missing/null field emits the
    # 4-character string "null", not empty — a plain [ -n ] check does not
    # catch it, so a genuinely fresh marker would compare against "null",
    # never match, and fall through to a false MISMATCH self-heal.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' null bot
    [ "$status" -eq 3 ]
    run cat "$STUB_LOG"
    assert_output ''
}

# ---------------------------------------------------------------------
# F-3 integration — the full per-PR form (routing-table.md)
# ---------------------------------------------------------------------

@test "F-3 freshness: review-blocked still wins over everything else" {
    _freshness_stub
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-blocked"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3 freshness: no verdict label at all is still 'not verified'" {
    _freshness_stub
    run train_verdict_gate_f3 "$(verdict_pr 11 '[]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3 freshness: a fresh review-passed marker from the expected login proceeds" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'proceed'
}

@test "F-3 freshness: a stale review-passed (head advanced) is skipped" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:0000000 -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed label stale — head advanced without invalidation'
}

@test "F-3 freshness: a review-passed label with NO marker at all is skipped WITHOUT dropping it" {
    # A pre-#1601 label, a manual push, or a repo that never wired the
    # writer all look like this. Absence alone is not proof the label is
    # wrong for this head (agy, PR #1608 review, both rounds) — route as
    # unverified, but never delete on a guess.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot 'plain comment, no marker')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed not confirmed for this head — no freshness marker found'
    run cat "$STUB_LOG"
    refute_output --partial 'DELETE'
}

@test "F-3 freshness (BLOCKER fix): a review-passed label with only a FORGED marker is skipped WITHOUT dropping it" {
    # The exact PR #1608 review finding: a non-pipeline commenter's marker
    # must never re-arm a label the gate would otherwise (correctly) skip —
    # and it must not count as evidence of staleness either. To the trusted
    # login's check this looks exactly like ABSENT, not MISMATCH, so it must
    # not trigger the self-heal delete.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment attacker '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed not confirmed for this head — no freshness marker found'
    run cat "$STUB_LOG"
    refute_output --partial 'DELETE'
}

@test "F-3 freshness: a MISMATCH PR self-heals by dropping the label" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:0000000 -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    run cat "$STUB_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/11/labels/review-passed'
}

@test "F-3 freshness (BLOCKER fix): an UNDETERMINED lookup failure is skipped WITHOUT dropping the label" {
    # The exact PR #1608 review finding: a transient gh api failure must
    # never destroy an otherwise-valid review-passed label.
    _freshness_stub
    STUB_COMMENTS_RC=1
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed freshness unknown — marker lookup failed, treating as unverified'
    run cat "$STUB_LOG"
    refute_output --partial 'DELETE'
}
