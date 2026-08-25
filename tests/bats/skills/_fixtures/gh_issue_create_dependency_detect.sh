#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh
# Source-of-truth mirror for the Step 2.6 detection flow documented in
# claude/skills/gh-issue-create/SKILL.md and
# references/dependency-detect.md.
#
# The skill itself runs inside Claude, but the detection half boils down
# to: "given the conversation text and the --no-auto-deps flag — which
# same-repo issue numbers should Step 4.5 pass to addBlockedBy?"
#
# The text->numbers half lives here, plus the Step 4.5 outcome
# classification (which id/mutation states produce the NF-1 warning). The
# GraphQL calls themselves are out of scope — the fixture never
# touches the network — but everything that decides what happens around
# them is mirrored, so NF-1 cannot regress unnoticed.
#
# Keep this file in sync with SKILL.md Step 2.6 + references/dependency-detect.md.
# If a trigger phrase is added or removed, mirror the change here so the
# bats suite catches drift.

# An issue reference, with the cross-repo `owner/repo` prefix optional so
# NF-2 can detect and reject it rather than silently mis-linking it to a
# same-numbered issue in $TARGET_REPO.
_GH_DEPS_REF='([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#[0-9]+'

# The F-1 trigger set. Korean forms trail the reference ("#13 완료 후"),
# English forms lead it ("depends on #13"). Plain mentions ("#13 참고",
# "#13 관련", a bare "#13") match nothing by construction.
#
# The 완료/해결 branch enumerates the conjugations that actually show up in
# chat (완료 후 / 완료되면 / 완료하고 / 해결 후 / …) instead of a looser
# "#N .* 후" — the reference and the trigger word must stay adjacent, or
# "#13 참고. 검토 후 진행" would link #13 to an unrelated clause.
# The colon after 선행 이슈 is optional so "선행이슈 #13" also matches.
_GH_DEPS_TRIGGERS="\
${_GH_DEPS_REF}[[:space:]]*(완료|해결)[[:space:]]*(후|뒤|되면|하고|하면)|\
${_GH_DEPS_REF}[[:space:]]*이후|\
depends[[:space:]]+on[[:space:]]+${_GH_DEPS_REF}|\
blocked[[:space:]]+by[[:space:]]+${_GH_DEPS_REF}|\
선행[[:space:]]*이슈[[:space:]]*[:：]?[[:space:]]*${_GH_DEPS_REF}"

# gh_issue_create_detect_deps
#   $1 — conversation text to scan
#   $2 — "1" if --no-auto-deps, "0" otherwise (default "0")
#
# Stdout: same-repo issue numbers, ascending and de-duped, one per line.
# Stderr: one `dependency-detect: cross-repo ...` line per NF-2 skip.
# Returns: 0 always — detection never blocks issue creation (NF-1).
gh_issue_create_detect_deps() {
    _text="$1"
    _no_auto="${2:-0}"

    # F-3: the escape hatch skips detection itself, not just the linking.
    if [ "$_no_auto" = "1" ]; then
        return 0
    fi

    # Two greps, never one per match: the first anchors a reference to a
    # trigger phrase (that anchoring is the whole false-positive defence),
    # the second pulls the reference back out. Every trigger alternative
    # embeds exactly one reference, so the two streams stay 1:1 and each
    # surviving line is either a same-repo number or an NF-2 cross-repo skip.
    # The trailing `|| true` is load-bearing, not defensive noise: "no
    # trigger in this conversation" is the common case and makes grep exit
    # 1, which under a caller's `set -e` + `set -o pipefail` would abort
    # before `return 0` and take the whole issue creation down with it.
    printf '%s\n' "$_text" |
        grep -oiE "$_GH_DEPS_TRIGGERS" |
        grep -oE "$_GH_DEPS_REF" |
        while IFS= read -r _ref; do
            case "$_ref" in
                */*)
                    printf 'dependency-detect: cross-repo dependency detected but not supported in v1 — skip (%s)\n' \
                        "$_ref" >&2
                    ;;
                *)
                    printf '%s\n' "${_ref#\#}"
                    ;;
            esac
        done | sort -n -u || true
    return 0
}

# gh_issue_create_dep_link_outcome
#   $1 — new issue node id  ("" when the lookup failed or returned null)
#   $2 — dep  issue node id ("" when the lookup failed or returned null)
#   $3 — addBlockedBy exit status ("0" = applied); ignored when either id
#        is empty, because the mutation is never reached in that case
#   $4 — dep issue number, for the warning line
#
# Mirrors the Step 4.5 decision in references/dependency-detect.md: an
# empty id is treated exactly like a rejected mutation, so a GraphQL null
# (deleted issue, replication lag on a just-created one, no read access)
# can never be handed to addBlockedBy as a literal "null".
#
# Stdout: nothing when the link was applied.
# Stderr: the single NF-1 warning line otherwise.
# Returns: 0 always — Step 4.5 never aborts, the issue already exists.
gh_issue_create_dep_link_outcome() {
    _new_id="$1"
    _dep_id="$2"
    _mutation_rc="$3"
    _dep_num="$4"

    if [ -n "$_new_id" ] && [ -n "$_dep_id" ] && [ "$_mutation_rc" = "0" ]; then
        return 0
    fi
    printf '[WARN] Blocked by #%s 링크 실패 — GH UI에서 수동 추가 필요\n' \
        "$_dep_num" >&2
    return 0
}
