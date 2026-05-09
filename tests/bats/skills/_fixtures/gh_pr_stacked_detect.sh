#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_stacked_detect.sh
# Source-of-truth mirror for the Stage 1/2 detection block documented in
#   claude/skills/gh-pr/references/stacked-pr.md
#
# The skill itself runs inside a Claude session, but the detection logic
# is pure bash that can be tested in isolation — given a synthetic repo
# tree (Stage 1) or a fake `gh pr list`/ancestor result set (Stage 2),
# does the code pick the right BASE_BRANCH / PARENT_PR?
#
# Tests inject Stage-2 inputs via FAKE_OPEN_PRS, FAKE_ANCESTOR_REFS,
# FAKE_NONDEFAULT_REFS so we don't need a live `gh` or a real ancestor
# graph. Stage 1 is exercised against real (mktemp) directory trees.
#
# Keep this file in sync with references/stacked-pr.md. If the skill
# block changes, mirror the change here so the bats suite catches drift.

# ── Stage 1 ────────────────────────────────────────────────────────────
is_stacked_pr_repo() {
    local _repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$_repo_root" ] || return 1

    [ -f "$_repo_root/.github/workflows/stacked-closes-rollup.yml" ] && return 0

    local _f
    for _f in CLAUDE.md AGENTS.md .claude/github-integration.md; do
        [ -f "$_repo_root/$_f" ] || continue
        grep -qE 'claude-enter-issue|stacked[[:space:]-]?PR|Depends on #' \
            "$_repo_root/$_f" 2>/dev/null && return 0
    done

    [ -d "$_repo_root/agent-toolbox" ] && return 0

    return 1
}

# ── Argument parsing ───────────────────────────────────────────────────
parse_stacked_args() {
    STACK_MODE=auto
    STACK_PARENT=
    STACK_BASE=
    ISSUE_NUMBER=
    local _flags_seen=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --no-stack)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=no-stack
                shift
                ;;
            --parent-pr)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=parent-pr
                if [ $# -lt 2 ]; then
                    printf 'gh:pr: --parent-pr requires a PR number\n' >&2
                    return 3
                fi
                STACK_PARENT="$2"
                if ! printf '%s' "${STACK_PARENT-}" | grep -qE '^[1-9][0-9]*$'; then
                    printf 'gh:pr: --parent-pr requires a positive integer (got %s)\n' \
                        "${STACK_PARENT:-<empty>}" >&2
                    return 3
                fi
                shift 2
                ;;
            --base)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=base
                if [ $# -lt 2 ]; then
                    printf 'gh:pr: --base requires a branch name\n' >&2
                    return 3
                fi
                STACK_BASE="$2"
                if [ -z "${STACK_BASE-}" ]; then
                    printf 'gh:pr: --base requires a branch name\n' >&2
                    return 3
                fi
                shift 2
                ;;
            *)
                if [ -z "$ISSUE_NUMBER" ] &&
                    printf '%s' "$1" | grep -qE '^[1-9][0-9]*$'; then
                    ISSUE_NUMBER="$1"
                fi
                shift
                ;;
        esac
    done

    if [ "$_flags_seen" -gt 1 ]; then
        printf 'gh:pr: --no-stack / --parent-pr / --base are mutually exclusive\n' >&2
        return 2
    fi

    return 0
}

# ── Stage 2 ────────────────────────────────────────────────────────────
_gh_pr_default_open_pr_list() {
    if [ -n "${FAKE_OPEN_PRS+set}" ]; then
        printf '%s\n' "$FAKE_OPEN_PRS"
        return 0
    fi
    gh pr list --state open --json number,headRefName \
        --jq '.[] | "\(.number) \(.headRefName)"' 2>/dev/null
}

_gh_pr_default_is_ancestor() {
    local _ref="$1" _ar
    if [ -n "${FAKE_ANCESTOR_REFS+set}" ]; then
        for _ar in $FAKE_ANCESTOR_REFS; do
            [ "$_ar" = "$_ref" ] && return 0
        done
        return 1
    fi
    git merge-base --is-ancestor "$_ref" HEAD 2>/dev/null
}

_gh_pr_default_default_tip_diff_check() {
    local _ref="$1" _default_tip="$2" _r
    if [ -n "${FAKE_NONDEFAULT_REFS+set}" ]; then
        for _r in $FAKE_NONDEFAULT_REFS; do
            [ "$_r" = "$_ref" ] && return 0
        done
        return 1
    fi
    local _base_with_default _base_with_head
    _base_with_default=$(git merge-base HEAD "$_default_tip" 2>/dev/null)
    _base_with_head=$(git merge-base HEAD "$_ref" 2>/dev/null)
    [ -n "$_base_with_default" ] && [ -n "$_base_with_head" ] &&
        [ "$_base_with_head" != "$_base_with_default" ]
}

find_parent_pr_candidates() {
    local _default_branch="$1"
    local _default_tip="origin/$_default_branch"
    local _line _pr _head _candidates

    _candidates=$(_gh_pr_default_open_pr_list)
    [ -z "$_candidates" ] && return 0

    while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        _pr="${_line%% *}"
        _head="${_line#* }"
        [ "$_head" = "$_default_branch" ] && continue
        if [ -z "${FAKE_OPEN_PRS+set}" ]; then
            git fetch origin "$_head" --quiet 2>/dev/null || continue
        fi
        _gh_pr_default_is_ancestor "origin/$_head" || continue
        _gh_pr_default_default_tip_diff_check "origin/$_head" "$_default_tip" || continue
        printf '%s:%s\n' "$_pr" "$_head"
    done <<EOF
$_candidates
EOF
}
