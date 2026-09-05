#!/usr/bin/env bats
# tests/bats/functions/gh_pr_reply_targeted_review.bats
# Issue #1616 — gh:pr-reply's per-reviewer/per-severity gate and the cheap
# targeted re-review lane that replaces the global
# `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0` rule.
#
# Incident this pins: PR #1609 — codex raised 2 BLOCKERs (both fixed), agy
# separately raised 3 non-blocking FOLLOW-UPs (all validly declined). The old
# global gate saw DECLINED_COUNT=3 and left `review-blocked` stuck, forcing a
# full 5-lane devx:pr-review-all re-run to clear one label.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------
# F-1 — every Step 3 item carries its origin: <reviewer>:<severity>:<verdict>
# ---------------------------------------------------------------------

@test "F-1: origin_line builds the canonical token" {
    run _gh_pr_reply_origin_line codex BLOCKER ACCEPT
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT'
}

@test "F-1: origin_line normalizes case and strips the reviewer's [brackets]" {
    run _gh_pr_reply_origin_line AGY '[Follow-Up]' decline
    assert_success
    assert_output 'agy:FOLLOW-UP:DECLINE'
}

@test "F-1: origin_line accepts ACCEPT-PARTIAL" {
    run _gh_pr_reply_origin_line codex '[BLOCKER]' accept-partial
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT-PARTIAL'
}

@test "F-1: origin_line rejects an unknown reviewer (exit 2)" {
    run _gh_pr_reply_origin_line gemini BLOCKER ACCEPT
    assert_failure 2
}

# ── Bot reviewer logins (PR #1637 review, codex BLOCKER) ─────────────
#
# The skill's Step 3 rubric classifies bot comments (gemini-code-assist,
# sourcery-ai, copilot) exactly like an AI-CLI comment, but the reviewer field
# was a closed `--ai` enum — so a bot-authored BLOCKER exited 2 and could never
# enter ORIGINS at all, leaving it invisible to the gate.

@test "F-1 (PR #1637 review, codex BLOCKER): origin_line accepts every bot login" {
    run _gh_pr_reply_origin_line gemini-code-assist '[BLOCKER]' ACCEPT
    assert_success
    assert_output 'gemini-code-assist:BLOCKER:ACCEPT'
    run _gh_pr_reply_origin_line sourcery-ai '[FOLLOW-UP]' decline
    assert_success
    assert_output 'sourcery-ai:FOLLOW-UP:DECLINE'
    run _gh_pr_reply_origin_line Copilot BLOCKER accept-partial
    assert_success
    assert_output 'copilot:BLOCKER:ACCEPT-PARTIAL'
}

@test "F-1 (PR #1637 review): reviewer_is_bot separates the two sets" {
    for _bot in gemini-code-assist sourcery-ai copilot; do
        run _gh_pr_reply_reviewer_is_bot "$_bot"
        assert_success
    done
    for _cli in codex agy claude opencode hermes; do
        run _gh_pr_reply_reviewer_is_bot "$_cli"
        assert_failure
    done
}

@test "F-1 (PR #1637 review): the --ai enum did not absorb the bots" {
    # The two sets stay separate on purpose: nothing re-invokes a bot, and
    # folding them together would make a typo'd `--ai` value look valid to
    # every caller that validates against one list. The library's `--ai` case
    # arm must therefore still list exactly the five CLIs.
    run grep -qE '^\s*codex \| agy \| claude \| opencode \| hermes\) ;;' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh"
    assert_success
    run grep -qE '^\s*codex \| agy \| claude \| opencode \| hermes \| gemini' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh"
    assert_failure
}

@test "F-1 (PR #1637 review): a bare 'gemini' is still not a reviewer (exit 2)" {
    # Only the full bot LOGIN counts — the guard against a typo'd name is the
    # whole reason both sets are closed enums.
    run _gh_pr_reply_origin_line gemini BLOCKER ACCEPT
    assert_failure 2
    assert_output --partial 'gemini-code-assist'
    assert_output --partial 'codex'
}

@test "F-1 (PR #1637 review): a hyphenated bot login keeps the token delimiter intact" {
    # Bot logins contain `-` but never `:`, so the reviewer:severity:verdict
    # split and the tally's awk `-F:` grouping keep working unchanged.
    run bash -c "printf '%s\n' \
        gemini-code-assist:BLOCKER:ACCEPT \
        gemini-code-assist:FOLLOW-UP:DECLINE \
        codex:BLOCKER:ACCEPT \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origin_tally; }"
    assert_success
    assert_line 'reviewer=codex blocking_total=1 blocking_accepted=1 nonblocking_total=0 nonblocking_declined=0'
    assert_line 'reviewer=gemini-code-assist blocking_total=1 blocking_accepted=1 nonblocking_total=1 nonblocking_declined=1'
}

@test "F-1: origin_line rejects an unknown verdict (exit 2)" {
    run _gh_pr_reply_origin_line codex BLOCKER MAYBE
    assert_failure 2
}

@test "F-1: origin_line rejects an empty severity (exit 2)" {
    run _gh_pr_reply_origin_line codex '' ACCEPT
    assert_failure 2
}

@test "F-1 (PR #1629 review, agy FOLLOW-UP): origin_line accepts the Korean 블로커 tag" {
    run _gh_pr_reply_origin_line codex '블로커' ACCEPT
    assert_success
    assert_output 'codex:블로커:ACCEPT'
}

@test "F-1 (PR #1629 review, agy FOLLOW-UP): severity_is_blocking recognizes the accepted 블로커 token round-trip" {
    run _gh_pr_reply_origin_line codex '블로커' ACCEPT
    assert_success
    run _gh_pr_reply_severity_is_blocking 블로커
    assert_success
}

@test "F-1: origin_line rejects a severity containing ':' (breaks the delimiter)" {
    run _gh_pr_reply_origin_line codex 'BLOCK:ER' ACCEPT
    assert_failure 2
}

@test "F-1: BLOCKER is the blocking severity" {
    run _gh_pr_reply_severity_is_blocking BLOCKER
    assert_success
}

@test "F-1: FOLLOW-UP / Suggestion / PRAISE are not blocking" {
    run _gh_pr_reply_severity_is_blocking FOLLOW-UP
    assert_failure
    run _gh_pr_reply_severity_is_blocking SUGGESTION
    assert_failure
    run _gh_pr_reply_severity_is_blocking PRAISE
    assert_failure
}

@test "F-1: tally breaks the pass down per reviewer, not as one flat count" {
    run bash -c "printf '%s\n' \
        codex:BLOCKER:ACCEPT \
        codex:BLOCKER:ACCEPT-PARTIAL \
        agy:FOLLOW-UP:DECLINE \
        agy:FOLLOW-UP:DECLINE \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origin_tally; }"
    assert_success
    assert_line 'reviewer=agy blocking_total=0 blocking_accepted=0 nonblocking_total=2 nonblocking_declined=2'
    assert_line 'reviewer=codex blocking_total=2 blocking_accepted=2 nonblocking_total=0 nonblocking_declined=0'
}

@test "F-1: tally ignores blank lines and reports nothing for empty input" {
    run bash -c "printf '\n\n' | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origin_tally; }"
    assert_success
    assert_output ''
}


# ---------------------------------------------------------------------
# F-2 — the `review-passed` gate (#1636)
# ---------------------------------------------------------------------
#
# #1616 asked "may we spend one scoped gh:pr-review re-call?" and needed the
# caller to name the reviewers that had blocked. #1636 removed the re-call, so
# the question collapsed to "did this pass leave an unresolved BLOCKER?" —
# answerable from ORIGINS alone.
#
# The relaxation is deliberate and is pinned here on purpose: these tests
# replace the old "no self-certification path exists" assertions, which
# described a rule the repo has since decided to trade away on this one path
# (cost + a repeatedly jammed gh:pr-merge-train). What is NOT relaxed — one
# unresolved BLOCKER means no label — has its own tests below.

# PR #1637's review added the external-review evidence argument, fail-closed
# by default. These cases all describe a PR an external reviewer DID look at —
# that review is what produced the origin lines — so the helper defaults to
# `yes` and the no-evidence cases pass their own second argument.
_gate() {
    printf '%s\n' "$1" | _gh_pr_reply_review_passed_gate "${2-yes}"
}

@test "F-2 (#1636): every BLOCKER accepted -> pass, with the count" {
    run _gate 'codex:BLOCKER:ACCEPT
codex:BLOCKER:ACCEPT
agy:FOLLOW-UP:DECLINE'
    assert_success
    assert_output 'pass=blockers-resolved:2'
}

@test "F-2 (#1636): no BLOCKER item at all -> pass" {
    # The ordinary clean-PR shape. Under #1616 this read as unresolved,
    # because the caller had already asserted somebody blocked; with no such
    # assertion, holding here would leave every clean PR unlabelled forever.
    run _gate 'agy:FOLLOW-UP:DECLINE
agy:Suggestion:ACCEPT'
    assert_success
    assert_output 'pass=no-blocker'
}

@test "F-2 (#1636): an empty stream is a pass, not an error" {
    run _gate ''
    assert_success
    assert_output 'pass=no-blocker'
}

@test "F-2 (#1636): ACCEPT-PARTIAL counts as resolved" {
    run _gate 'codex:BLOCKER:ACCEPT-PARTIAL'
    assert_success
    assert_output 'pass=blockers-resolved:1'
}

# ---------------------------------------------------------------------
# The fail-closed half — NOT relaxed by #1636
# ---------------------------------------------------------------------

@test "F-2 (fail-closed): a DECLINEd BLOCKER holds the label" {
    run _gate 'codex:BLOCKER:ACCEPT
codex:BLOCKER:DECLINE
agy:FOLLOW-UP:ACCEPT'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (fail-closed): a QUESTION on a BLOCKER is not a resolution" {
    run _gate 'codex:BLOCKER:ACCEPT
codex:BLOCKER:QUESTION'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (fail-closed): one unresolved BLOCKER outranks every resolved one" {
    run _gate 'codex:BLOCKER:ACCEPT
agy:BLOCKER:DECLINE'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "F-2 (fail-closed): the Korean 블로커 tag blocks too" {
    # `_gh_pr_reply_severity_is_blocking` recognizes it even though the
    # tally's awk only groups the ASCII spellings — counting MORE items as
    # blocking is the safe direction for a gate that authorizes review-passed.
    run _gate 'codex:블로커:DECLINE'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (fail-closed): a BLOCKING-spelled severity blocks too" {
    run _gate 'agy:BLOCKING:QUESTION'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "F-2: a malformed origin line is rejected (exit 2), never silently dropped" {
    run _gate 'codex:BLOCKER'
    assert_failure 2
}

# ---------------------------------------------------------------------
# The origin ledger — cross-pass memory (PR #1637 review)
# ---------------------------------------------------------------------

@test "ledger: origins_block wraps the stream in a sha-suffixed marker pair" {
    run bash -c "printf '%s\n' codex:BLOCKER:DECLINE agy:FOLLOW-UP:ACCEPT \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_origins_block deadbeef; }"
    assert_success
    assert_line --index 0 '<!-- pr-reply-origins:deadbeef -->'
    assert_line --index 1 'codex:BLOCKER:DECLINE'
    assert_line --index 2 'agy:FOLLOW-UP:ACCEPT'
    assert_line --index 3 '<!-- /pr-reply-origins:deadbeef -->'
}

@test "ledger: origins_block falls back to the unsuffixed marker with no sha" {
    # Same fallback `_gh_pr_review_build_comment_body`'s 8th argument makes.
    run bash -c "printf '%s\n' codex:BLOCKER:DECLINE \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_origins_block; }"
    assert_success
    assert_line --index 0 '<!-- pr-reply-origins -->'
    assert_line --index 2 '<!-- /pr-reply-origins -->'
}

@test "ledger: origins_block round-trips through history_origins" {
    run bash -c "{ . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '%s\n' codex:BLOCKER:DECLINE agy:FOLLOW-UP:ACCEPT \
            | _gh_pr_reply_origins_block deadbeef \
            | jq -Rs '[{user: {login: \"pipeline-bot\"}, body: .}]' \
            | _gh_pr_reply_history_origins pipeline-bot; }"
    assert_success
    assert_line --index 0 'codex:BLOCKER:DECLINE'
    assert_line --index 1 'agy:FOLLOW-UP:ACCEPT'
}

@test "ledger: origins_block prints nothing for an empty stream" {
    # Nothing to remember — an empty block would be noise the reader has to
    # skip on every later pass.
    run bash -c "printf '' | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        _gh_pr_reply_origins_block deadbeef; }"
    assert_success
    assert_output ''
}

@test "ledger: origins_block refuses to write a malformed line (exit 2)" {
    run bash -c "printf '%s\n' 'just some prose' | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        _gh_pr_reply_origins_block deadbeef; }"
    assert_failure 2
    assert_output --partial 'malformed origin line'
}

# Since #1639 both history readers take the PR's RAW COMMENTS JSON on stdin
# (what `gh api repos/<repo>/issues/<pr>/comments` returns, `.user.login`
# intact) plus a required <expected-login>, and only trust comments written by
# that login. These helpers keep the fixtures below as plain body text.

# The one login this pipeline authenticates as.
TRUSTED_LOGIN=pipeline-bot

# Body text on stdin -> a one-element raw comments array authored by $1.
_as_comments() {
    jq -Rs --arg login "${1-}" '[{user: {login: $login}, body: .}]'
}

#   _history <body text>              — authored by TRUSTED_LOGIN
#   _history_by <author> <body text>  — authored by anyone
# Both always READ as TRUSTED_LOGIN, so an author other than TRUSTED_LOGIN is
# the forgery path.
_history_by() {
    printf '%s\n' "$2" | _as_comments "$1" | _gh_pr_reply_history_origins "$TRUSTED_LOGIN"
}

_history() {
    _history_by "$TRUSTED_LOGIN" "$1"
}

#   _has_review_by <author> <body text>
_has_review_by() {
    printf '%s\n' "$2" | _as_comments "$1" |
        _gh_pr_reply_history_has_review "$TRUSTED_LOGIN"
}

@test "ledger: history_origins recovers a block from a comment dump" {
    run _history 'some reviewer prose
<!-- pr-reply-origins:deadbeef -->
codex:BLOCKER:DECLINE
<!-- /pr-reply-origins:deadbeef -->
more prose'
    assert_success
    assert_output 'codex:BLOCKER:DECLINE'
}

@test "ledger: history_origins takes the LAST complete block (a later pass supersedes)" {
    run _history '<!-- pr-reply-origins:sha1 -->
codex:BLOCKER:DECLINE
<!-- /pr-reply-origins:sha1 -->
<!-- pr-reply-origins:sha2 -->
codex:BLOCKER:ACCEPT
<!-- /pr-reply-origins:sha2 -->'
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT'
}

@test "ledger: history_origins never harvests an unterminated block" {
    # A truncated comment must not hand back half a history — the same
    # contract devx_pr_review_all_lane_block keeps.
    run _history '<!-- pr-reply-origins:sha1 -->
codex:BLOCKER:DECLINE'
    assert_success
    assert_output ''
}

@test "ledger: history_origins yields nothing when the PR has no ledger yet" {
    run _history 'a perfectly ordinary PR comment'
    assert_success
    assert_output ''
}

@test "ledger: history_origins drops prose a human pasted inside the block" {
    run _history '<!-- pr-reply-origins -->
codex:BLOCKER:DECLINE
this line is a human reply, not an origin
agy:FOLLOW-UP:ACCEPT
<!-- /pr-reply-origins -->'
    assert_success
    assert_line --index 0 'codex:BLOCKER:DECLINE'
    assert_line --index 1 'agy:FOLLOW-UP:ACCEPT'
    refute_output --partial 'human reply'
}

@test "ledger: history_origins ignores ai-review blocks" {
    run _history '<!-- ai-review:codex:deadbeef -->
codex:BLOCKER:DECLINE
<!-- /ai-review:codex:deadbeef -->'
    assert_success
    assert_output ''
}

@test "evidence: history_has_review sees a sha-suffixed ai-review marker" {
    run _has_review_by "$TRUSTED_LOGIN" '<!-- ai-review:codex:deadbeef -->
Verdict: LGTM'
    assert_success
}

@test "evidence: history_has_review sees the unsuffixed ai-review marker" {
    run _has_review_by "$TRUSTED_LOGIN" '<!-- ai-review:agy -->
Verdict: LGTM'
    assert_success
}

@test "evidence: history_has_review is rc 1 when no reviewer ever posted" {
    run _has_review_by "$TRUSTED_LOGIN" 'an ordinary comment
<!-- pr-reply-origins -->'
    assert_failure
}

# ── #1639: marker authorship ────────────────────────────────────────
# Both readers used to be handed body text with the author already stripped,
# so ANY commenter's markers counted. That is two separate unlocks of the same
# gate: a forged `pr-reply-origins` ledger rewrites which BLOCKERs were
# ACCEPTed, and a forged `ai-review` marker manufactures the "an external
# reviewer actually ran" evidence #1636 relaxed NF-2 on. Commenting on a PR is
# a far lower bar than the label-write access `review-passed` needs.
#
# Mirrors the same suite for `_gh_pr_merge_train_review_passed_marker_sha`
# (tests/bats/skills/gh_pr_merge_train_review_verdict_gate.bats, PR #1608).

@test "ledger (#1639): a well-formed ledger from an UNTRUSTED login is ignored" {
    run _history_by attacker '<!-- pr-reply-origins:deadbeef -->
codex:BLOCKER:ACCEPT
<!-- /pr-reply-origins:deadbeef -->'
    assert_success
    assert_output ''
}

@test "ledger (#1639): the identical ledger from the TRUSTED login is read" {
    # Positive control — the ONLY difference is the author.
    run _history_by "$TRUSTED_LOGIN" '<!-- pr-reply-origins:deadbeef -->
codex:BLOCKER:ACCEPT
<!-- /pr-reply-origins:deadbeef -->'
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT'
}

@test "ledger (#1639): a forged ACCEPT cannot supersede the trusted DECLINE" {
    # The attack that matters: last-block-wins means a forged comment posted
    # after the real ledger would otherwise clear a standing DECLINE and let
    # the pass self-apply review-passed.
    local real forged json
    real=$(jq -nc --arg b '<!-- pr-reply-origins:sha1 -->
codex:BLOCKER:DECLINE
<!-- /pr-reply-origins:sha1 -->' '{user: {login: "pipeline-bot"}, body: $b}')
    forged=$(jq -nc --arg b '<!-- pr-reply-origins:sha2 -->
codex:BLOCKER:ACCEPT
<!-- /pr-reply-origins:sha2 -->' '{user: {login: "attacker"}, body: $b}')
    json=$(jq -nc --argjson r "$real" --argjson f "$forged" '[$r, $f]')

    # Through the environment, not spliced into the script text: the fixture
    # is JSON and its quotes would not survive interpolation.
    run env JSON="$json" bash -c "printf '%s' \"\$JSON\" \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_origins pipeline-bot; }"
    assert_success
    assert_output 'codex:BLOCKER:DECLINE'
}

@test "ledger (#1639): an EMPTY expected login reads no history (never 'trust everyone')" {
    run bash -c "printf '%s\n' '<!-- pr-reply-origins -->' 'codex:BLOCKER:ACCEPT' '<!-- /pr-reply-origins -->' \
        | jq -Rs '[{user: {login: \"pipeline-bot\"}, body: .}]' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_origins; }"
    assert_success
    assert_output ''
}

@test "ledger (#1639): an invalid login (jq injection attempt) reads no history" {
    run bash -c "printf '%s\n' '<!-- pr-reply-origins -->' 'codex:BLOCKER:ACCEPT' '<!-- /pr-reply-origins -->' \
        | jq -Rs '[{user: {login: \"pipeline-bot\"}, body: .}]' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_origins 'bot\" | .'; }"
    assert_success
    assert_output ''
}

@test "ledger (#1639): a bot login (name[bot]) is accepted" {
    run bash -c "printf '%s\n' '<!-- pr-reply-origins -->' 'codex:BLOCKER:ACCEPT' '<!-- /pr-reply-origins -->' \
        | jq -Rs '[{user: {login: \"github-actions[bot]\"}, body: .}]' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_origins 'github-actions[bot]'; }"
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT'
}

@test "ledger (#1639): non-JSON on stdin reads no history (fail-closed)" {
    # The pre-#1639 contract — raw body text — must not silently keep working,
    # or an un-migrated call site would keep trusting every author.
    run bash -c "printf '%s\n' '<!-- pr-reply-origins -->' 'codex:BLOCKER:ACCEPT' '<!-- /pr-reply-origins -->' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_origins pipeline-bot; }"
    assert_success
    assert_output ''
}

@test "evidence (#1639): an ai-review marker from an UNTRUSTED login is not evidence" {
    # Forging the evidence probe is the cheapest unlock of all: one comment
    # containing the literal marker string used to satisfy it.
    run _has_review_by attacker '<!-- ai-review:codex:deadbeef -->
Verdict: LGTM'
    assert_failure
}

@test "evidence (#1639): an EMPTY expected login finds no evidence" {
    run bash -c "printf '%s\n' '<!-- ai-review:agy -->' \
        | jq -Rs '[{user: {login: \"pipeline-bot\"}, body: .}]' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_has_review; }"
    assert_failure
}

@test "evidence (#1639): a bot login (name[bot]) is accepted" {
    run bash -c "printf '%s\n' '<!-- ai-review:agy -->' \
        | jq -Rs '[{user: {login: \"github-actions[bot]\"}, body: .}]' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_has_review 'github-actions[bot]'; }"
    assert_success
}

@test "evidence (#1639): non-JSON on stdin is not evidence (fail-closed)" {
    run bash -c "printf '%s\n' '<!-- ai-review:agy -->' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
            _gh_pr_reply_history_has_review pipeline-bot; }"
    assert_failure
}

_merge() {
    printf '%s\n' "$2" | _gh_pr_reply_origins_merge "$1"
}

@test "ledger: merge keeps a history reviewer this pass never mentions" {
    # Silence must never clear a blocker: codex said nothing this round, so
    # its DECLINEd BLOCKER survives.
    run _merge 'codex:BLOCKER:DECLINE' 'agy:FOLLOW-UP:ACCEPT'
    assert_success
    assert_line --index 0 'codex:BLOCKER:DECLINE'
    assert_line --index 1 'agy:FOLLOW-UP:ACCEPT'
}

@test "ledger: merge supersedes a reviewer this pass re-classified" {
    # The escape hatch: the reviewer re-raises the item, gh:pr-reply
    # re-classifies it, and the fresh verdict replaces the stale one. Without
    # this, a DECLINEd BLOCKER would pin review-passed off the PR forever.
    run _merge 'codex:BLOCKER:DECLINE
agy:FOLLOW-UP:DECLINE' 'codex:BLOCKER:ACCEPT'
    assert_success
    assert_line --index 0 'agy:FOLLOW-UP:DECLINE'
    assert_line --index 1 'codex:BLOCKER:ACCEPT'
    refute_output --partial 'codex:BLOCKER:DECLINE'
}

@test "ledger: merge with an empty history is a no-op" {
    run _merge '' 'agy:FOLLOW-UP:ACCEPT'
    assert_success
    assert_output 'agy:FOLLOW-UP:ACCEPT'
}

@test "ledger: merge rejects a malformed line in either input (exit 2)" {
    run _merge 'not an origin line' 'agy:FOLLOW-UP:ACCEPT'
    assert_failure 2
    run _merge 'codex:BLOCKER:DECLINE' 'not an origin line'
    assert_failure 2
}

# ---------------------------------------------------------------------
# The gate's external-review evidence argument (PR #1637 review, agy BLOCKER)
# ---------------------------------------------------------------------

@test "F-2 (PR #1637 review, agy BLOCKER): no evidence argument -> hold, never a pass" {
    # Fail-closed by default: a caller that forgot to probe the PR must not be
    # handed a certification it did not earn.
    run _gate 'agy:FOLLOW-UP:DECLINE' ''
    assert_success
    assert_output 'hold=no-external-review'
}

@test "F-2 (PR #1637 review): an empty ORIGINS with no evidence is a hold" {
    # The exact shape agy named: no external review ever ran, so the "external
    # AI FINDS / gh:pr-reply CONFIRMS" division of labour has no finder half.
    run _gate '' ''
    assert_success
    assert_output 'hold=no-external-review'
}

@test "F-2 (PR #1637 review): anything but a literal yes reads as no evidence" {
    run _gate 'agy:FOLLOW-UP:DECLINE' maybe
    assert_success
    assert_output 'hold=no-external-review'
}

@test "F-2 (PR #1637 review): an unresolved blocker outranks the evidence token" {
    # Both are holds, so the label outcome is identical — but the blocker
    # token names a reviewer and an actionable item, which is more useful than
    # "run a review".
    run _gate 'codex:BLOCKER:DECLINE' ''
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (PR #1637 review, codex BLOCKER): a bot-authored BLOCKER reaches the gate" {
    # The actual consequence of the closed reviewer enum: a DECLINEd
    # gemini-code-assist BLOCKER could not be represented, so the gate never
    # saw it and certified the PR anyway.
    run bash -c "{ . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        _gh_pr_reply_origin_line gemini-code-assist '[BLOCKER]' DECLINE \
            | _gh_pr_reply_review_passed_gate yes; }"
    assert_success
    assert_output 'hold=unresolved-blocker:gemini-code-assist'
}

# THE cross-pass regression (PR #1637 review, codex BLOCKER). Step 2's
# "already replied" dedup hides the codex thread from pass 2 entirely, so
# without the ledger pass 2's ORIGINS carry no BLOCKER and the gate reads
# `pass=no-blocker` — certifying a PR whose blocker was never fixed.
@test "F-2 (PR #1637 review, codex BLOCKER): a DECLINEd BLOCKER from an earlier pass still holds" {
    run bash -c "{ . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '%s\n' agy:FOLLOW-UP:ACCEPT \
            | _gh_pr_reply_origins_merge 'codex:BLOCKER:DECLINE' \
            | _gh_pr_reply_review_passed_gate yes; }"
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

# ---------------------------------------------------------------------
# Reporting the outcome (Step 7)
# ---------------------------------------------------------------------

@test "report (#1636): a resolved-BLOCKER pass names the count and the label flip" {
    run _gh_pr_reply_review_passed_report pass=blockers-resolved:2
    assert_success
    assert_output --partial 'BLOCKER 2건 전부 해소'
    assert_output --partial 'review-blocked 해제'
    assert_output --partial 'review-passed'
}

@test "report (#1636): the pass line says no external re-review was involved" {
    # The relaxation must be visible in the run's own output, not only in the
    # docs — a reader of the summary should see how the label was earned.
    run _gh_pr_reply_review_passed_report pass=no-blocker
    assert_success
    assert_output --partial '외부 재검토 없음'
    assert_output --partial '#1636'
}

@test "report: the hold line names the reviewer and never claims a pass" {
    run _gh_pr_reply_review_passed_report hold=unresolved-blocker:codex
    assert_success
    assert_output --partial 'codex'
    assert_output --partial 'review-blocked 유지'
    assert_output --partial 'review-passed 미부여'
}

@test "report (PR #1637 review, agy BLOCKER): the no-evidence hold names the missing premise" {
    run _gh_pr_reply_review_passed_report hold=no-external-review
    assert_success
    assert_output --partial '외부 리뷰 근거'
    assert_output --partial 'ai-review'
    assert_output --partial 'review-passed 미부여'
    assert_output --partial '#1636'
}

@test "report rejects a token it does not understand (exit 2)" {
    run _gh_pr_reply_review_passed_report lane=codex
    assert_failure 2
}

# ---------------------------------------------------------------------
# _gh_pr_reply_apply_review_passed — the gate wired to the shared writer
# ---------------------------------------------------------------------

_apply_stub() {
    APPLY_LOG="${BATS_TEST_TMPDIR}/apply.log"
    : >"$APPLY_LOG"
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh"
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$APPLY_LOG"
        return "${STUB_GH_RC:-0}"
    }
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    _gh_pr_edit_safe_label() {
        printf 'add %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$APPLY_LOG"
        return "${STUB_ADD_RC:-0}"
    }
}

@test "apply (#1636): a clean pass applies review-passed with no CLI re-call" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget ghe.example.com newsha yes \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output --partial 'add 1609 review-passed --repo acme/widget'
    # Not one reviewer CLI, and not gh:pr-review, is invoked anywhere.
    refute_output --partial '--ai '
    refute_output --partial '--paths'
    refute_output --partial 'pr-review'
}

@test "apply (#1636): applying review-passed deletes review-blocked first" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes >/dev/null
    run cat "$APPLY_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
}

@test "apply (#1636, NF-1): the label carries the post-push head sha as its marker" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes >/dev/null
    run cat "$APPLY_LOG"
    assert_output --partial 'review-verdict:review-passed:newsha'
}

@test "apply: every gh call pins the target host (#1403 / #1407)" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget ghe.example.com newsha yes >/dev/null
    run grep -c 'GH_HOST=ghe.example.com' "$APPLY_LOG"
    assert_success
    refute_output '0'
}

@test "apply (#1636): a PR with no BLOCKER at all still earns the label" {
    _apply_stub
    printf '%s\n' agy:FOLLOW-UP:DECLINE |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output --partial 'add 1609 review-passed'
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'BLOCKER 항목 자체가 없음'
}

@test "apply (fail-closed): an unresolved BLOCKER writes nothing at all" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:DECLINE |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output ''
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'review-passed 미부여'
    assert_output --partial 'review-blocked 유지'
}

@test "apply (fail-closed): an unresolved BLOCKER never touches review-blocked" {
    # The hold path must not delete the opposite label either — that delete
    # only happens on the write path, which this input never reaches.
    _apply_stub
    printf '%s\n' codex:BLOCKER:QUESTION |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes >/dev/null
    run cat "$APPLY_LOG"
    refute_output --partial 'labels/review-blocked'
}

@test "apply: a label the repo lacks warns and leaves the PR unlabelled (soft-fail)" {
    _apply_stub
    STUB_ADD_RC=3
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 3; }
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609 acme/widget '' '' yes
    "
    unset STUB_ADD_RC
    assert_success
    assert_output --partial 'gh:label-bootstrap'
    refute_output --partial '[OK]'
}

@test "apply: any other write failure warns instead of claiming the label" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 1; }
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609 acme/widget '' '' yes
    "
    assert_success
    assert_output --partial '미검증으로 취급'
}

@test "apply: a marker-post failure adds a second WARN, not silence (#1608 rule)" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        gh() { return 1; }
        _gh_pr_edit_safe_label() { return 0; }
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes
    "
    assert_success
    assert_line --index 1 --partial 'freshness marker failed to post'
}

@test "apply (PR #1637 review, agy BLOCKER): with no evidence argument nothing is written" {
    _apply_stub
    printf '%s\n' agy:FOLLOW-UP:DECLINE |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output ''
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '외부 리뷰 근거'
}

@test "apply (PR #1637 review, codex BLOCKER): a merged history blocker writes nothing" {
    _apply_stub
    printf '%s\n' agy:FOLLOW-UP:ACCEPT |
        _gh_pr_reply_origins_merge 'codex:BLOCKER:DECLINE' |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output ''
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'codex'
    assert_output --partial 'review-passed 미부여'
}

# ---------------------------------------------------------------------
# _gh_pr_reply_post_origins_ledger — writing the cross-pass memory back
# ---------------------------------------------------------------------

@test "ledger: post writes the block as a PR comment" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:DECLINE |
        _gh_pr_reply_post_origins_ledger 1609 acme/widget '' newsha \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output --partial 'api -X POST repos/acme/widget/issues/1609/comments'
    assert_output --partial '<!-- pr-reply-origins:newsha -->'
    assert_output --partial 'codex:BLOCKER:DECLINE'
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '원장 기록됨'
}

@test "ledger: the post pins the target host (#1403 / #1407)" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:DECLINE |
        _gh_pr_reply_post_origins_ledger 1609 acme/widget ghe.example.com newsha >/dev/null
    run cat "$APPLY_LOG"
    assert_output --partial 'GH_HOST=ghe.example.com'
}

@test "ledger: an empty stream posts nothing at all" {
    _apply_stub
    printf '' | _gh_pr_reply_post_origins_ledger 1609 acme/widget '' newsha \
        >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output ''
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '원장 생략'
}

@test "ledger: a failing post WARNs about the lost memory and still returns 0" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        gh() { return 1; }
        printf 'codex:BLOCKER:DECLINE\n' | _gh_pr_reply_post_origins_ledger 1609 acme/widget '' newsha
    "
    assert_success
    assert_output --partial '[WARN]'
    assert_output --partial '원장 기록 실패'
    assert_output --partial 'BLOCKER 재분류'
}

@test "ledger: a missing repo arg is a usage error (rc 2)" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf 'codex:BLOCKER:DECLINE\n' | _gh_pr_reply_post_origins_ledger 1609
    "
    assert_failure 2
    assert_output --partial 'usage: _gh_pr_reply_post_origins_ledger'
}

@test "apply: a missing repo arg is a usage error (rc 2)" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609
    "
    assert_failure 2
    assert_output --partial 'usage: _gh_pr_reply_apply_review_passed'
}

# ---------------------------------------------------------------------
# #1762 — the optional 4th field: a DECLINE escalated to a tracking issue
# ---------------------------------------------------------------------
#
# Upstream half of dEitY719/gh-pr-skills#21. Five rollout PRs on 2026-09-05
# each declined the same BLOCKER with a pointer to dEitY719/harness-skills#22
# and all five correctly kept `review-blocked` — the item IS unresolved in
# those PRs. What the ledger could not say is WHERE the item went: a
# declined-and-escalated BLOCKER wrote the same `<r>:BLOCKER:DECLINE` line as
# a declined-and-ignored one.
#
# The fix keeps `DECLINE` and appends an OPTIONAL 4th field carrying the ref.
# Two properties are load-bearing and each has its own tests below:
#   - every existing 3-field line keeps parsing, in every consumer (the ledger
#     is durable state already posted on live PRs), and
#   - the gate still HOLDS on a tracked decline. Escalation is not resolution;
#     only the report line changes.

@test "#1762: origin_line appends the tracking ref as a 4th field" {
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE dEitY719/harness-skills#22
    assert_success
    assert_output 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'
}

@test "#1762: origin_line omits the 4th field when no ref is given" {
    # The strict-superset guarantee: the 3-argument call is byte-identical to
    # what it produced before this issue.
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE
    assert_success
    assert_output 'agy:BLOCKER:DECLINE'
}

@test "#1762: an empty 4th argument is the same as omitting it" {
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE ''
    assert_success
    assert_output 'agy:BLOCKER:DECLINE'
}

@test "#1762: origin_line rejects a malformed tracking ref (exit 2)" {
    # A typo must be a NAMED failure at the write boundary, not a garbage
    # ledger line a later pass silently drops.
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE 'harness-skills#22'
    assert_failure 2
    assert_output --partial 'tracking ref'
}

@test "#1762: origin_line rejects a ref with no issue number (exit 2)" {
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE 'dEitY719/harness-skills'
    assert_failure 2
}

@test "#1762: origin_line rejects a non-numeric issue number (exit 2)" {
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE 'dEitY719/harness-skills#abc'
    assert_failure 2
}

@test "#1762: origin_line rejects a ref containing ':' (breaks the delimiter)" {
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE 'dEitY719/harn:ess#22'
    assert_failure 2
}

@test "#1762: the ref is preserved verbatim, case included" {
    # `owner/repo` is case-sensitive on GitHub, so the reviewer/verdict
    # lowercase-then-uppercase normalization must not reach this field.
    run _gh_pr_reply_origin_line AGY '[Blocker]' decline dEitY719/Harness-Skills#7
    assert_success
    assert_output 'agy:BLOCKER:DECLINE:dEitY719/Harness-Skills#7'
}

@test "#1762: a tracked decline still HOLDS — escalation is not resolution" {
    run _gate 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'
    assert_success
    assert_output 'hold=unresolved-blocker-tracked:agy:dEitY719/harness-skills#22'
}

@test "#1762: an untracked decline keeps the original token unchanged" {
    run _gate 'agy:BLOCKER:DECLINE'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "#1762: a tracked ACCEPT is still a pass (the ref never blocks)" {
    # The 4th field is provenance, not a verdict. Only the verdict decides.
    run _gate 'codex:BLOCKER:ACCEPT:dEitY719/harness-skills#22'
    assert_success
    assert_output 'pass=blockers-resolved:1'
}

@test "#1762: a 4th field on a NON-blocking line never reaches the gate token" {
    run _gate 'agy:FOLLOW-UP:DECLINE:dEitY719/harness-skills#22'
    assert_success
    assert_output 'pass=no-blocker'
}

@test "#1762: an unresolved untracked BLOCKER still outranks a tracked one" {
    # First-unresolved-wins is unchanged; the tracked line is not privileged.
    run _gate 'codex:BLOCKER:DECLINE
agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "#1762: a malformed ref read back from the ledger degrades, never fails" {
    # `_gh_pr_reply_history_origins` already drops unparseable ledger lines
    # silently so a human editing the PR comment cannot hard-error the next
    # pass. A garbage 4th field follows the same rule: it falls back to the
    # plain hold token rather than reporting a ref nobody can follow.
    run _gate 'agy:BLOCKER:DECLINE:not a ref'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "#1762: a QUESTION carrying a ref is tracked too, not only DECLINE" {
    run _gate 'agy:BLOCKER:QUESTION:dEitY719/harness-skills#22'
    assert_success
    assert_output 'hold=unresolved-blocker-tracked:agy:dEitY719/harness-skills#22'
}

@test "#1762: the report line names both the reviewer and where the item went" {
    run _gh_pr_reply_review_passed_report \
        hold=unresolved-blocker-tracked:agy:dEitY719/harness-skills#22
    assert_success
    assert_output --partial 'agy'
    assert_output --partial 'dEitY719/harness-skills#22'
    assert_output --partial 'review-passed 미부여'
    assert_output --partial 'review-blocked 유지'
}

@test "#1762: the tracked report line is a [BLOCKED] line, never an [OK]" {
    run _gh_pr_reply_review_passed_report \
        hold=unresolved-blocker-tracked:agy:dEitY719/harness-skills#22
    assert_success
    assert_output --partial '[BLOCKED]'
    refute_output --partial '[OK]'
}

@test "#1762: apply writes NO label for a tracked decline" {
    # The whole point: legibility changed, the decision did not.
    _apply_stub
    printf '%s\n' 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output ''
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'dEitY719/harness-skills#22'
    assert_output --partial 'review-passed 미부여'
}

@test "#1762: apply never deletes review-blocked on the tracked hold path" {
    _apply_stub
    printf '%s\n' 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha yes >/dev/null
    run cat "$APPLY_LOG"
    refute_output --partial 'labels/review-blocked'
}

# ── The other four consumers must swallow the 4-field line unchanged ──

@test "#1762: tally reads the verdict from \$3, not the whole tail" {
    run bash -c "printf '%s\n' \
        'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' \
        'agy:BLOCKER:ACCEPT' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origin_tally; }"
    assert_success
    assert_output 'reviewer=agy blocking_total=2 blocking_accepted=1 nonblocking_total=0 nonblocking_declined=0'
}

@test "#1762: origins_block writes a 4-field line without complaint" {
    run bash -c "printf '%s\n' 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origins_block abc123; }"
    assert_success
    assert_output --partial 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'
}

@test "#1762: a 4-field line round-trips through the ledger" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        block=\$(printf '%s\n' 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' \
            | _gh_pr_reply_origins_block abc123)
        printf '%s' \"\$block\" | jq -Rs '[{user:{login:\"tester\"},body:.}]' \
            | _gh_pr_reply_history_origins tester
    "
    assert_success
    assert_output 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'
}

@test "#1762: merge supersedes a tracked line per reviewer, like any other" {
    run bash -c "{ . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '%s\n' agy:BLOCKER:ACCEPT \
            | _gh_pr_reply_origins_merge 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'; }"
    assert_success
    assert_output 'agy:BLOCKER:ACCEPT'
}

@test "#1762: a tracked history line survives to the gate through merge" {
    # The cross-pass hole PR #1637 closed must stay closed for the new shape.
    run bash -c "{ . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '%s\n' codex:FOLLOW-UP:ACCEPT \
            | _gh_pr_reply_origins_merge 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' \
            | _gh_pr_reply_review_passed_gate yes; }"
    assert_success
    assert_output 'hold=unresolved-blocker-tracked:agy:dEitY719/harness-skills#22'
}

# ── PR #1764 review — agy + codex findings on the #1762 shape ─────────

@test "#1762 (PR #1764, codex BLOCKER): #0 is not an issue number" {
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE 'dEitY719/harness-skills#0'
    assert_failure 2
}

@test "#1762 (PR #1764, codex BLOCKER): a zero-padded number is rejected" {
    # `#022` does not resolve on GitHub, so a report naming it would point at
    # a target the reader cannot open.
    run _gh_pr_reply_origin_line agy BLOCKER DECLINE 'dEitY719/harness-skills#022'
    assert_failure 2
}

@test "#1762 (PR #1764, agy FOLLOW-UP): an empty owner or repo segment is rejected" {
    for _ref in 'owner#22' 'owner//repo#22' '/repo#22' 'owner/#22'; do
        run _gh_pr_reply_origin_line agy BLOCKER DECLINE "$_ref"
        assert_failure 2
    done
}

@test "#1762 (PR #1764, agy FOLLOW-UP): a second / or # is rejected, not reinterpreted" {
    for _ref in 'a/b/c#1' 'a/b#1#2'; do
        run _gh_pr_reply_origin_line agy BLOCKER DECLINE "$_ref"
        assert_failure 2
    done
}

@test "#1762 (PR #1764, codex BLOCKER): the ledger write refuses an unvalidated ref" {
    # `_gh_pr_reply_origin_line` is not the only way a line can reach the
    # ledger. This function IS the write, and its contract is that garbage is
    # never persisted — a hand-built line must not get past it either.
    run bash -c "printf '%s\n' 'agy:BLOCKER:DECLINE:not a ref' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origins_block abc123; }"
    assert_failure 2
    assert_output --partial 'tracking ref'
}

@test "#1762 (PR #1764, codex BLOCKER): a valid ref still writes fine" {
    run bash -c "printf '%s\n' 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22' \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origins_block abc123; }"
    assert_success
    assert_output --partial 'agy:BLOCKER:DECLINE:dEitY719/harness-skills#22'
}

@test "#1762 (PR #1764, codex BLOCKER): history STRIPS a bad ref, keeping the blocker" {
    # Dropping the whole line would take the BLOCKER's verdict with it and let
    # the gate certify a PR whose blocker still stands — fail-OPEN, the exact
    # hole this ledger closes. The verdict must survive; only the ref goes.
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '<!-- pr-reply-origins:abc -->\nagy:BLOCKER:DECLINE:not a ref\n<!-- /pr-reply-origins:abc -->\n' \
            | jq -Rs '[{user:{login:\"t\"},body:.}]' \
            | _gh_pr_reply_history_origins t
    "
    assert_success
    assert_output 'agy:BLOCKER:DECLINE'
}

@test "#1762 (PR #1764, codex BLOCKER): the sanitized history still HOLDS the gate" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '<!-- pr-reply-origins:abc -->\nagy:BLOCKER:DECLINE:not a ref\n<!-- /pr-reply-origins:abc -->\n' \
            | jq -Rs '[{user:{login:\"t\"},body:.}]' \
            | _gh_pr_reply_history_origins t \
            | _gh_pr_reply_review_passed_gate yes
    "
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "#1762 (PR #1764, codex BLOCKER): a sanitized history line is re-writable" {
    # The strip is what lets the strict ledger write above coexist with a
    # human typing inside the PR comment: one typo must not break the write
    # for every later pass.
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf '<!-- pr-reply-origins:abc -->\nagy:BLOCKER:DECLINE:not a ref\n<!-- /pr-reply-origins:abc -->\n' \
            | jq -Rs '[{user:{login:\"t\"},body:.}]' \
            | _gh_pr_reply_history_origins t \
            | _gh_pr_reply_origins_block abc123
    "
    assert_success
    assert_output --partial 'agy:BLOCKER:DECLINE'
}

@test "#1762 (PR #1764, agy FOLLOW-UP): extra colons past the ref degrade safely" {
    run _gate 'agy:BLOCKER:DECLINE:a/b#1:junk'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "#1762 (PR #1764): origin_ref returns the verdict for no 4-field line" {
    # The trap the shared extractor exists to close: the same expansion on a
    # 3-field line would hand back DECLINE.
    run bash -c "{ . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        _gh_pr_reply_origin_ref 'agy:BLOCKER:DECLINE'; }"
    assert_success
    assert_output ''
}

# ---------------------------------------------------------------------
# The #1616 re-review lane is gone (#1636 F-3)
# ---------------------------------------------------------------------

@test "#1636: the targeted re-review lane's functions no longer exist" {
    # Leaving them defined would be a maintenance trap: nothing consumes a
    # `lane=` token any more, and a future caller finding one would rebuild
    # the very CLI round-trip this issue removed.
    for _fn in _gh_pr_reply_targeted_lane_decide _gh_pr_reply_lane_available \
        _gh_pr_reply_targeted_lane_report; do
        run command -v "$_fn"
        assert_failure
    done
}

# The library's prose still *describes* the removed lane (that history is why
# the relaxation is legible), so these guards read CODE only — comment lines
# stripped — or they would pin the documentation instead of the behaviour.
_lib_code_file() {
    local _lib="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh"
    LIB_CODE="${BATS_TEST_TMPDIR}/lib_code.sh"
    grep -v '^[[:space:]]*#' "$_lib" >"$LIB_CODE"
}

@test "#1636: the library's code no longer re-invokes any reviewer CLI" {
    _lib_code_file
    run grep -qF -- '_gh_pr_review_require_ai_cli' "$LIB_CODE"
    assert_failure
    run grep -qF -- '--paths' "$LIB_CODE"
    assert_failure
    run grep -qF -- 'gh_pr_review.sh' "$LIB_CODE"
    assert_failure
}

@test "#1636: the library never fabricates a reviewer verdict token" {
    # The one banned shortcut: synthesizing an `lgtm`/`concerns` line and
    # feeding it to devx_pr_review_all_apply_label would record gh:pr-reply's
    # own judgment as a reviewer CLI's opinion. It writes a LABEL directly.
    _lib_code_file
    run grep -qF -- 'devx_pr_review_all_apply_label' "$LIB_CODE"
    assert_failure
    run grep -qE "printf.*'(lgtm|concerns)" "$LIB_CODE"
    assert_failure
    run grep -qF -- 'devx_pr_review_all_write_label' "$LIB_CODE"
    assert_success
}

# ---------------------------------------------------------------------
# Library hygiene
# ---------------------------------------------------------------------

@test "the library defines every function the skill delegates to" {
    for _fn in _gh_pr_reply_origin_line _gh_pr_reply_reviewer_is_bot \
        _gh_pr_reply_severity_is_blocking _gh_pr_reply_origin_tally \
        _gh_pr_reply_origins_block _gh_pr_reply_history_origins \
        _gh_pr_reply_history_has_review _gh_pr_reply_origins_merge \
        _gh_pr_reply_post_origins_ledger _gh_pr_reply_review_passed_gate \
        _gh_pr_reply_review_passed_report _gh_pr_reply_apply_review_passed; do
        run command -v "$_fn"
        assert_success
    done
}

@test "the library loads in a non-interactive shell with no interactive guard" {
    # The skill's Bash tool calls run `bash --noprofile --norc`; an
    # interactive guard here would silently define nothing and the gate
    # would never run (#724's failure shape).
    run bash --noprofile --norc -c \
        ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh' && command -v _gh_pr_reply_review_passed_gate"
    assert_success
}
