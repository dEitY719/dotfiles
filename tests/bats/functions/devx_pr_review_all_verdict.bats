#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all_verdict.bats
# Issue #1562 — correctness and portability of the reviewer-verdict parser.
#
# Background: the verdict line ("판정: 블로킹" / "Verdict: BLOCKING") that every
# gh:pr-review preset mandates had no machine-readable consumer, so PR #1518
# merged carrying two independent blocking reviews. #1527's first attempt at a
# parser was abandoned with three defects still in it; this suite pins the
# fixes:
#
#   1. aggregation lost lanes under zsh, because the call site relied on
#      ambient word-splitting of an unquoted "$VERDICTS"
#   2. a stale block from an earlier round was reused as if it were fresh
#   3. `Verdict: BLOCKING | 5 findings` was misread as the unanswered template
#
# Fail-closed is the whole point: "no label" must never be reachable from
# "everything passed", and "a lane ran but said nothing parseable" must never
# be promoted to a pass.
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_review_all.sh"
}

# ── devx_pr_review_all_verdict: Korean verdicts ──────────────────────

@test "verdict: Korean 블로킹 -> blocking" {
    run devx_pr_review_all_verdict <<'EOF'
[BLOCKER] a.sh:1 — breaks on empty input
판정: 블로킹
EOF
    assert_success
    assert_output "blocking"
}

@test "verdict: Korean 우려있음 -> concerns" {
    run devx_pr_review_all_verdict <<<"판정: 우려있음"
    assert_success
    assert_output "concerns"
}

@test "verdict: Korean LGTM -> lgtm" {
    run devx_pr_review_all_verdict <<<"판정: LGTM"
    assert_success
    assert_output "lgtm"
}

# ── devx_pr_review_all_verdict: English verdicts ─────────────────────

@test "verdict: English BLOCKING -> blocking" {
    run devx_pr_review_all_verdict <<<"Verdict: BLOCKING"
    assert_success
    assert_output "blocking"
}

@test "verdict: English CONCERNS -> concerns" {
    run devx_pr_review_all_verdict <<<"Verdict: CONCERNS"
    assert_success
    assert_output "concerns"
}

@test "verdict: English lgtm is case-insensitive" {
    run devx_pr_review_all_verdict <<<"verdict: lgtm"
    assert_success
    assert_output "lgtm"
}

# ── devx_pr_review_all_verdict: real-world noise ─────────────────────

@test "verdict: markdown bold + trailing detail still parses" {
    run devx_pr_review_all_verdict <<<"**판정: 블로킹 (BLOCKER 4건)**"
    assert_success
    assert_output "blocking"
}

@test "verdict: leading list dash still parses" {
    run devx_pr_review_all_verdict <<<"- Verdict: LGTM"
    assert_success
    assert_output "lgtm"
}

@test "verdict: last verdict line wins" {
    run devx_pr_review_all_verdict <<'EOF'
판정: LGTM
판정: 블로킹
EOF
    assert_success
    assert_output "blocking"
}

@test "verdict: a BLOCKER finding alone is not a verdict" {
    # Findings are classified [BLOCKER|FOLLOW-UP|PRAISE]; only the mandatory
    # last verdict line decides the lane. No verdict line -> unknown.
    run devx_pr_review_all_verdict <<<"[BLOCKER] a.sh:1 — breaks on empty input"
    assert_success
    assert_output "unknown"
}

@test "verdict: empty lane output -> unknown" {
    run devx_pr_review_all_verdict </dev/null
    assert_success
    assert_output "unknown"
}

@test "verdict: unrecognized verdict value -> unknown" {
    run devx_pr_review_all_verdict <<<"Verdict: MAYBE"
    assert_success
    assert_output "unknown"
}

# ── BUG 3: template detection is bracket+pipe, not "contains a pipe" ──
# The abandoned parser dropped every candidate line containing `|`
# (`grep -vF '|'`), so a genuine verdict with an explanatory tail after a
# pipe was classified `unknown` — no label, PR silently un-mergeable. The
# template's real signature is the bracketed alternation `[A|B|C]`.

@test "verdict (bug 3): answered verdict with a trailing pipe -> blocking" {
    run devx_pr_review_all_verdict <<<"Verdict: BLOCKING | 5 findings"
    assert_success
    assert_output "blocking"
}

@test "verdict (bug 3): Korean answered verdict with a trailing pipe -> blocking" {
    run devx_pr_review_all_verdict <<<"판정: 블로킹 | BLOCKER 5건"
    assert_success
    assert_output "blocking"
}

@test "verdict (bug 3): answered LGTM with a trailing pipe -> lgtm" {
    run devx_pr_review_all_verdict <<<"Verdict: LGTM | no findings"
    assert_success
    assert_output "lgtm"
}

@test "verdict (bug 3): the English template alternation is still rejected" {
    run devx_pr_review_all_verdict <<<"Verdict: [LGTM|CONCERNS|BLOCKING]"
    assert_success
    assert_output "unknown"
}

@test "verdict (bug 3): the Korean template alternation is still rejected" {
    # The preset prompt itself contains `판정: [LGTM|우려있음|블로킹]`. A lane
    # that echoes its own instructions back must not be read as an LGTM.
    run devx_pr_review_all_verdict <<<"판정: [LGTM|우려있음|블로킹]"
    assert_success
    assert_output "unknown"
}

@test "verdict (bug 3): bracketed single verdict still parses (English)" {
    run devx_pr_review_all_verdict <<<"Verdict: [BLOCKING]"
    assert_success
    assert_output "blocking"
}

@test "verdict (bug 3): bracketed single verdict still parses (Korean)" {
    run devx_pr_review_all_verdict <<<"판정: [블로킹]"
    assert_success
    assert_output "blocking"
}

@test "verdict (bug 3): a bracket in the detail text is not a template echo" {
    # Only a value that *opens* with `[` and carries a `|` inside is the
    # template. A bracketed count after a real verdict must still parse.
    run devx_pr_review_all_verdict <<<"판정: 블로킹 [BLOCKER 4건]"
    assert_success
    assert_output "blocking"
}

@test "verdict (bug 3): bracketed verdict followed by a piped tail parses" {
    run devx_pr_review_all_verdict <<<"Verdict: [BLOCKING] | 5 findings"
    assert_success
    assert_output "blocking"
}

@test "verdict (PR #1573 review, agy FOLLOW-UP): bracketed detail after the pipe is not a template echo" {
    # The template-detection glob used to match `[` and `|` anywhere in the
    # value, so a real verdict with a *second* bracketed group after the pipe
    # (e.g. a bracketed finding count) was misread as the unanswered preset
    # template `[LGTM|우려있음|블로킹]`. Only a pipe INSIDE the first bracket
    # group is the template's signature.
    run devx_pr_review_all_verdict <<<"Verdict: [BLOCKING] | [5 findings]"
    assert_success
    assert_output "blocking"
}

# ── devx_pr_review_all_aggregate (stdin, newline-delimited) ──────────

@test "aggregate: all lanes pass -> review-passed" {
    run devx_pr_review_all_aggregate <<'EOF'
lgtm
concerns
EOF
    assert_success
    assert_line "label=review-passed"
    assert_line "lanes=2"
}

@test "aggregate: a blocking lane outranks a passing one" {
    run devx_pr_review_all_aggregate <<'EOF'
lgtm
blocking
EOF
    assert_success
    assert_line "label=review-blocked"
    assert_line "lanes=2"
}

@test "aggregate: zero lanes ran -> no label" {
    run devx_pr_review_all_aggregate </dev/null
    assert_success
    assert_line "label="
    assert_line "lanes=0"
}

@test "aggregate: an unknown lane is never promoted to a pass" {
    run devx_pr_review_all_aggregate <<'EOF'
lgtm
unknown
EOF
    assert_success
    assert_line "label="
    assert_line "lanes=2"
}

@test "aggregate: blocking outranks unknown" {
    run devx_pr_review_all_aggregate <<'EOF'
unknown
blocking
EOF
    assert_success
    assert_line "label=review-blocked"
}

@test "aggregate: garbage token is treated as unknown, not a pass" {
    run devx_pr_review_all_aggregate <<'EOF'
lgtm
ohai
EOF
    assert_success
    assert_line "label="
}

@test "aggregate: blank lines are not lanes" {
    # A skipped lane must contribute nothing at all; a stray empty line in
    # the stream must not inflate the lane count into a false "verified".
    run devx_pr_review_all_aggregate <<'EOF'

lgtm

EOF
    assert_success
    assert_line "label=review-passed"
    assert_line "lanes=1"
}

@test "aggregate: a final verdict with no trailing newline still counts" {
    run bash -c '
        . "'"${DOTFILES_ROOT}"'/shell-common/functions/devx_pr_review_all.sh"
        printf "lgtm\nblocking" | devx_pr_review_all_aggregate'
    assert_success
    assert_line "label=review-blocked"
    assert_line "lanes=2"
}

@test "aggregate: reports the lane count it decided on" {
    run devx_pr_review_all_aggregate <<'EOF'
lgtm
concerns
blocking
EOF
    assert_success
    assert_line "lanes=3"
}

# ── Lane block extraction ────────────────────────────────────────────
# Step 3 dispatches each reviewer lane as a subagent, and `gh:pr-review`
# guarantees only a one-line `[OK] PR #N reviewed by <ai> — comment: <URL>`
# as its return value. Nothing carries the verdict back, so the verdict is
# read from the artifact the lane already wrote: the raw output `gh:pr-review`
# Step 6 posts inside `<!-- ai-review:<ai> -->` markers.

@test "lane block: extracts the marked block for the named lane" {
    run devx_pr_review_all_lane_block codex <<'EOF'
<!-- ai-review:codex -->
[BLOCKER] a.sh:1 — nope
판정: 블로킹
<!-- /ai-review:codex -->
EOF
    assert_success
    assert_line "판정: 블로킹"
}

@test "lane block: picks the right lane when several are present" {
    run devx_pr_review_all_lane_block agy <<'EOF'
<!-- ai-review:codex -->
판정: 블로킹
<!-- /ai-review:codex -->
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->
EOF
    assert_success
    assert_line "Verdict: LGTM"
    refute_output --partial "블로킹"
}

@test "lane block: the LAST block wins when a lane was re-reviewed" {
    # A re-review posts a second comment; the newest verdict is the live one.
    run devx_pr_review_all_lane_block agy <<'EOF'
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->
<!-- ai-review:agy -->
Verdict: BLOCKING
<!-- /ai-review:agy -->
EOF
    assert_success
    assert_line "Verdict: BLOCKING"
    refute_output --partial "LGTM"
}

@test "lane block: absent lane yields nothing (-> unknown downstream)" {
    run devx_pr_review_all_lane_block hermes <<'EOF'
<!-- ai-review:codex -->
판정: LGTM
<!-- /ai-review:codex -->
EOF
    assert_success
    assert_output ""
}

@test "lane block: an unterminated block is not harvested" {
    # A truncated comment must not hand back a half-read verdict.
    run devx_pr_review_all_lane_block codex <<'EOF'
<!-- ai-review:codex -->
판정: 블로킹
EOF
    assert_success
    assert_output ""
}

@test "lane block: no ai argument yields nothing" {
    run devx_pr_review_all_lane_block <<'EOF'
<!-- ai-review:codex -->
판정: 블로킹
<!-- /ai-review:codex -->
EOF
    assert_success
    assert_output ""
}

@test "lane block (PR #1573 review, agy+codex FOLLOW-UP): open and close markers on the same line are still harvested" {
    # The open-tag rule used to `next` immediately on match, so a close tag
    # trailing on that same line was never inspected and the block was lost
    # entirely (degrading the lane to unknown downstream).
    run devx_pr_review_all_lane_block agy <<'EOF'
<!-- ai-review:agy -->Verdict: LGTM<!-- /ai-review:agy -->
EOF
    assert_success
    assert_output "Verdict: LGTM"
}

@test "lane block (PR #1573 review, follow-up): a same-line block picks the right lane" {
    run devx_pr_review_all_lane_block agy <<'EOF'
<!-- ai-review:codex -->판정: 블로킹<!-- /ai-review:codex -->
<!-- ai-review:agy -->Verdict: LGTM<!-- /ai-review:agy -->
EOF
    assert_success
    assert_output "Verdict: LGTM"
}

@test "lane block: end-to-end -> verdict token" {
    run bash -c '
        . "'"${DOTFILES_ROOT}"'/shell-common/functions/devx_pr_review_all.sh"
        printf "%s\n" "<!-- ai-review:agy -->" "Verdict: BLOCKING" "<!-- /ai-review:agy -->" \
          | devx_pr_review_all_lane_block agy | devx_pr_review_all_verdict'
    assert_success
    assert_output "blocking"
}

# ── BUG 2: freshness via the optional head-sha argument ──────────────
# Without a sha, a block posted in an earlier round is indistinguishable from
# one this run just posted. A run that posted nothing (GH_DISABLE_AI_METRICS=1,
# --no-post-comment, a failed post) would then reuse a stale verdict — and a
# stale verdict can authorize a merge of code it never saw.

@test "lane block (bug 2): a stale sha's block is not harvested for a new sha" {
    run devx_pr_review_all_lane_block agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:0000111122223333 -->
Verdict: LGTM
<!-- /ai-review:agy:0000111122223333 -->
EOF
    assert_success
    assert_output ""
}

@test "lane block (bug 2): a stale block downstream reads as unknown" {
    run bash -c '
        . "'"${DOTFILES_ROOT}"'/shell-common/functions/devx_pr_review_all.sh"
        printf "%s\n" \
          "<!-- ai-review:agy:0000111122223333 -->" \
          "Verdict: LGTM" \
          "<!-- /ai-review:agy:0000111122223333 -->" \
          | devx_pr_review_all_lane_block agy deadbeefdeadbeef \
          | devx_pr_review_all_verdict'
    assert_success
    assert_output "unknown"
}

@test "lane block (bug 2): the matching sha's block is harvested" {
    run devx_pr_review_all_lane_block agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:0000111122223333 -->
Verdict: LGTM
<!-- /ai-review:agy:0000111122223333 -->
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: BLOCKING
<!-- /ai-review:agy:deadbeefdeadbeef -->
EOF
    assert_success
    assert_line "Verdict: BLOCKING"
    refute_output --partial "LGTM"
}

@test "lane block (bug 2): a sha-tagged block of another lane is not harvested" {
    run devx_pr_review_all_lane_block agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:codex:deadbeefdeadbeef -->
Verdict: BLOCKING
<!-- /ai-review:codex:deadbeefdeadbeef -->
EOF
    assert_success
    assert_output ""
}

@test "lane block (bug 2): an untagged block does not satisfy a sha request" {
    # The plain marker carries no freshness claim, so it must not be accepted
    # as evidence for a specific head.
    run devx_pr_review_all_lane_block agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->
EOF
    assert_success
    assert_output ""
}

@test "lane block (bug 2): a sha-tagged block whose close tag is untagged is not harvested" {
    run devx_pr_review_all_lane_block agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: LGTM
<!-- /ai-review:agy -->
EOF
    assert_success
    assert_output ""
}

@test "lane block (bug 2): no sha argument keeps today's behavior on plain markers" {
    # The marker gh:pr-review actually emits today carries no sha. Passing no
    # second argument must behave exactly as before: last complete block wins.
    run devx_pr_review_all_lane_block agy <<'EOF'
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->
<!-- ai-review:agy -->
Verdict: BLOCKING
<!-- /ai-review:agy -->
EOF
    assert_success
    assert_line "Verdict: BLOCKING"
    refute_output --partial "LGTM"
}

@test "lane block (bug 2): no sha argument makes no freshness claim" {
    # Omitting the sha means "do not check freshness", so a sha-tagged block
    # is still harvested — it is the caller that opted out of the check.
    run devx_pr_review_all_lane_block agy <<'EOF'
<!-- ai-review:agy:0000111122223333 -->
Verdict: BLOCKING
<!-- /ai-review:agy:0000111122223333 -->
EOF
    assert_success
    assert_line "Verdict: BLOCKING"
}

@test "lane block (bug 2): an empty sha argument is the same as none" {
    run devx_pr_review_all_lane_block agy "" <<'EOF'
<!-- ai-review:agy -->
Verdict: BLOCKING
<!-- /ai-review:agy -->
EOF
    assert_success
    assert_line "Verdict: BLOCKING"
}

# ── BUG 1: the documented call site must agree across bash/zsh/dash ──
# The abandoned aggregate took positional args and its documented call site
# was `AGG=$(devx_pr_review_all_aggregate $VERDICTS)` — an unquoted expansion
# relying on the shell to word-split "lgtm blocking" into two arguments. zsh
# does not word-split without SH_WORD_SPLIT, so the whole string arrived as
# ONE argument: lanes=1 and the blocking verdict vanished. This repo's default
# interactive shell is zsh, so the gate would have failed open there.
#
# These tests run the *documented* pipeline verbatim in all three shells. The
# abandoned suite passed only because it called the function directly with
# bash-native separate arguments, never simulating the real call site.

_two_lane_fixture() {
    cat >"${BATS_TEST_TMPDIR}/comments.md" <<'EOF'
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->
<!-- ai-review:codex -->
판정: 블로킹
<!-- /ai-review:codex -->
EOF
}

# The Step 5 call site from
# claude/skills/devx-pr-review-all/references/review-verdict-label.md, with
# `lane_ran` reduced to a fixed two-of-four so the other two lanes exercise
# the skipped-lane invariant (they contribute no line at all).
_two_lane_body() {
    printf "BODIES_FILE='%s'\n" "${BATS_TEST_TMPDIR}/comments.md"
    cat <<'BODY'
AGG=$(
    for ai in agy codex opencode hermes; do
        case "$ai" in
        agy | codex) ;;
        *) continue ;;
        esac
        v=$(devx_pr_review_all_lane_block "$ai" <"$BODIES_FILE" | devx_pr_review_all_verdict)
        printf '%s\n' "$v"
    done | devx_pr_review_all_aggregate
)
label=$(printf '%s\n' "$AGG" | sed -n 's/^label=//p')
lanes=$(printf '%s\n' "$AGG" | sed -n 's/^lanes=//p')
printf 'RESULT label=%s lanes=%s\n' "$label" "$lanes"
BODY
}

_run_in_dash() {
    command -v dash >/dev/null 2>&1 || skip "dash not available"
    run dash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export HOME='${HOME}'
        . '${DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        $1
    "
}

@test "bug 1 (bash): two-lane pipeline -> review-blocked, lanes=2" {
    _two_lane_fixture
    run_in_bash "$(_two_lane_body)"
    assert_success
    assert_output --partial "RESULT label=review-blocked lanes=2"
}

@test "bug 1 (zsh): two-lane pipeline -> review-blocked, lanes=2" {
    _two_lane_fixture
    run_in_zsh "$(_two_lane_body)"
    assert_success
    assert_output --partial "RESULT label=review-blocked lanes=2"
}

@test "bug 1 (dash): two-lane pipeline -> review-blocked, lanes=2" {
    _two_lane_fixture
    _run_in_dash "$(_two_lane_body)"
    assert_success
    assert_output --partial "RESULT label=review-blocked lanes=2"
}

_four_pass_body() {
    cat <<'BODY'
AGG=$(
    for v in lgtm concerns lgtm concerns; do
        printf '%s\n' "$v"
    done | devx_pr_review_all_aggregate
)
label=$(printf '%s\n' "$AGG" | sed -n 's/^label=//p')
lanes=$(printf '%s\n' "$AGG" | sed -n 's/^lanes=//p')
printf 'RESULT label=%s lanes=%s\n' "$label" "$lanes"
BODY
}

# The bug-3 template guard is a `case` pattern with quoted `[`, `|` and `]`.
# Quoting is what keeps them literal rather than a bracket expression, and
# that reading has to be the same in every shell this file is sourced into.
_classify_body() {
    cat <<'BODY'
for line in \
    "Verdict: BLOCKING | 5 findings" \
    "판정: [LGTM|우려있음|블로킹]" \
    "Verdict: [LGTM|CONCERNS|BLOCKING]" \
    "Verdict: [BLOCKING]" \
    "판정: 블로킹 [BLOCKER 4건]"; do
    printf 'RESULT %s\n' "$(printf '%s\n' "$line" | devx_pr_review_all_verdict)"
done
BODY
}

_assert_classified() {
    assert_success
    assert_line "RESULT blocking"
    assert_line "RESULT unknown"
    # 3 real verdicts, 2 template echoes.
    [ "$(printf '%s\n' "$output" | grep -c '^RESULT blocking$')" -eq 3 ] ||
        fail "expected 3 blocking classifications, got: $output"
    [ "$(printf '%s\n' "$output" | grep -c '^RESULT unknown$')" -eq 2 ] ||
        fail "expected 2 unknown classifications, got: $output"
}

@test "bug 3 (bash): template vs answered verdict classification" {
    run_in_bash "$(_classify_body)"
    _assert_classified
}

@test "bug 3 (zsh): template vs answered verdict classification" {
    run_in_zsh "$(_classify_body)"
    _assert_classified
}

@test "bug 3 (dash): template vs answered verdict classification" {
    _run_in_dash "$(_classify_body)"
    _assert_classified
}

@test "bug 1 (bash): four passing lanes -> review-passed, lanes=4" {
    run_in_bash "$(_four_pass_body)"
    assert_success
    assert_output --partial "RESULT label=review-passed lanes=4"
}

@test "bug 1 (zsh): four passing lanes -> review-passed, lanes=4" {
    run_in_zsh "$(_four_pass_body)"
    assert_success
    assert_output --partial "RESULT label=review-passed lanes=4"
}

@test "bug 1 (dash): four passing lanes -> review-passed, lanes=4" {
    _run_in_dash "$(_four_pass_body)"
    assert_success
    assert_output --partial "RESULT label=review-passed lanes=4"
}

# A skipped lane contributes no line, so "nothing was checked" stays
# distinguishable from "everything passed" in every shell.
_all_skipped_body() {
    cat <<'BODY'
AGG=$(
    for ai in agy codex opencode hermes; do
        continue
        printf '%s\n' lgtm
    done | devx_pr_review_all_aggregate
)
label=$(printf '%s\n' "$AGG" | sed -n 's/^label=//p')
lanes=$(printf '%s\n' "$AGG" | sed -n 's/^lanes=//p')
printf 'RESULT label=[%s] lanes=%s\n' "$label" "$lanes"
BODY
}

@test "bug 1 (bash): every lane skipped -> no label, lanes=0" {
    run_in_bash "$(_all_skipped_body)"
    assert_success
    assert_output --partial "RESULT label=[] lanes=0"
}

@test "bug 1 (zsh): every lane skipped -> no label, lanes=0" {
    run_in_zsh "$(_all_skipped_body)"
    assert_success
    assert_output --partial "RESULT label=[] lanes=0"
}

@test "bug 1 (dash): every lane skipped -> no label, lanes=0" {
    _run_in_dash "$(_all_skipped_body)"
    assert_success
    assert_output --partial "RESULT label=[] lanes=0"
}

# ---------------------------------------------------------------------------
# devx_pr_review_all_apply_label — the producer half of the merge gate (#1564)
# ---------------------------------------------------------------------------
#
# Until #1564 nothing in the repo WROTE these labels: the parser and the
# aggregator existed, `_gh_pr_drop_label` removed them, and the merge-train
# gate had nothing to read. This section pins the write side. `gh` and
# `_gh_pr_edit_safe_label` are stubbed as shell functions — no network, and
# the add-side helper has its own suite (tests/bats/functions/gh_pr_edit_safe.bats).

_apply_stub() {
    APPLY_LOG="${BATS_TEST_TMPDIR}/apply.log"
    : >"$APPLY_LOG"
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

@test "apply_label: a blocking lane labels review-blocked and clears the opposite" {
    _apply_stub
    printf '%s\n' lgtm blocking | devx_pr_review_all_apply_label 7 acme/widget github.com >"${BATS_TEST_TMPDIR}/out"
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '[OK] PR #7 labelled `review-blocked` (2 lane(s))'
    run cat "$APPLY_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/7/labels/review-passed'
    assert_output --partial 'add 7 review-blocked --repo acme/widget'
}

@test "apply_label: all-passing lanes label review-passed and clear review-blocked" {
    _apply_stub
    printf '%s\n' lgtm concerns | devx_pr_review_all_apply_label 7 acme/widget >"${BATS_TEST_TMPDIR}/out"
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '[OK] PR #7 labelled `review-passed` (2 lane(s))'
    run cat "$APPLY_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/7/labels/review-blocked'
    assert_output --partial 'add 7 review-passed --repo acme/widget'
}

# Absence is the third state and it must stay reachable: an empty stream is
# "nothing was checked", never a pass, and it must not write ANY label.
@test "apply_label: an empty verdict stream writes no label at all" {
    _apply_stub
    printf '' | devx_pr_review_all_apply_label 7 acme/widget >"${BATS_TEST_TMPDIR}/out"
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'no reviewer lane produced a verdict — PR #7 left unlabelled'
    run cat "$APPLY_LOG"
    assert_output ""
}

# A lane that ran but whose verdict could not be parsed is fail-closed too:
# `unknown` yields no label, so the train reads "not verified".
@test "apply_label: an unknown lane leaves the PR unlabelled" {
    _apply_stub
    printf '%s\n' lgtm unknown | devx_pr_review_all_apply_label 7 acme/widget >"${BATS_TEST_TMPDIR}/out"
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'left unlabelled'
    run cat "$APPLY_LOG"
    assert_output ""
}

# rc 3 = the label does not exist in the repo and _gh_pr_edit_safe_label
# refuses to auto-create it (#326). Name the fix, do not fail the run.
@test "apply_label: rc 3 from the add helper warns to provision the label" {
    _apply_stub
    STUB_ADD_RC=3
    printf '%s\n' blocking | devx_pr_review_all_apply_label 7 acme/widget >"${BATS_TEST_TMPDIR}/out"
    unset STUB_ADD_RC
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'label `review-blocked` missing in acme/widget'
    assert_output --partial 'gh:label-bootstrap'
}

@test "apply_label: any other add failure warns 'treat the PR as unverified'" {
    _apply_stub
    STUB_ADD_RC=1
    printf '%s\n' lgtm | devx_pr_review_all_apply_label 7 acme/widget >"${BATS_TEST_TMPDIR}/out"
    unset STUB_ADD_RC
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'labelling PR #7 failed — treat the PR as unverified'
}

# Soft-fail: every labelling outcome is rc 0, because an unlabelled PR already
# reads as "not verified" downstream. Only a usage error is a caller bug.
@test "apply_label: a failing add still returns 0 (soft-fail)" {
    _apply_stub
    STUB_ADD_RC=1
    run bash -c "
        . '${DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        _gh_pr_edit_safe_label() { return 1; }
        gh() { return 0; }
        printf 'lgtm\n' | devx_pr_review_all_apply_label 7 acme/widget
    "
    unset STUB_ADD_RC
    assert_success
}

@test "apply_label: a missing repo arg is a usage error (rc 2)" {
    _apply_stub
    run bash -c "
        . '${DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        printf 'lgtm\n' | devx_pr_review_all_apply_label 7
    "
    assert_failure 2
    assert_output --partial 'usage: devx_pr_review_all_apply_label'
}

# #1403 / #1407: with two hosts logged in, a bare `gh` writes the label to
# whichever server `gh repo set-default` picked. The host is pinned per call.
@test "apply_label: the host is pinned on both the DELETE and the add" {
    _apply_stub
    printf '%s\n' blocking | devx_pr_review_all_apply_label 7 acme/widget ghe.example.com >/dev/null
    run cat "$APPLY_LOG"
    assert_output --partial 'labels/review-passed [GH_HOST=ghe.example.com]'
    assert_output --partial 'add 7 review-blocked --repo acme/widget [GH_HOST=ghe.example.com]'
}

# ...and the caller's own GH_HOST survives, because the export is subshelled.
@test "apply_label: the caller's GH_HOST is not clobbered" {
    _apply_stub
    GH_HOST=original.example.com
    printf '%s\n' blocking | devx_pr_review_all_apply_label 7 acme/widget ghe.example.com >/dev/null
    [ "$GH_HOST" = "original.example.com" ] || fail "GH_HOST leaked: $GH_HOST"
    unset GH_HOST
}

# The whole point of a shared helper: the SKILL step must CALL it, not
# paraphrase the delete-then-add dance into prose an LLM can skip (#1524's
# lesson, applied to the producer side).
@test "doc-guard: devx:pr-review-all Step 3.5 calls the shared apply helper" {
    local _skill="${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    run grep -qF -- 'devx_pr_review_all_apply_label' "$_skill"
    assert_success
    run grep -qF -- 'Step 3.5' "$_skill"
    assert_success
}

# Ordering is load-bearing: read the head sha BEFORE Step 4 pushes, or every
# lane misses on the post-simplify sha and the gate silently labels nothing.
@test "doc-guard: Step 3.5 is documented as running before the push" {
    run grep -q 'before Step 4' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    assert_success
}

# The producer must pass the sha — omitting it is the stale-verdict hole.
@test "doc-guard: the SKILL passes head_sha to lane_block" {
    run grep -qF -- 'devx_pr_review_all_lane_block "$ai" "$head_sha"' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    assert_success
}
