#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_project_status.sh
# Push a projectV2 Status transition for an Issue or PR. Auto-discovers every
# projectV2 the target belongs to; for each project that has a "Status" field
# with an option matching the target name, updates the item's Status to that
# option.
#
# Failure is always quiet (returns 0) — the caller's primary job is shipping
# code, not board bookkeeping. Boards in repos that have no projectV2 attached
# (e.g. side projects without a board) are auto-detected: the helper finds
# zero project items and silently returns 0.
#
# Opt out with GH_PROJECT_STATUS_SYNC=0. The legacy gh-flow-era variable
# GH_FLOW_PROJECT_STATUS_SYNC=0 is still honored for backwards compatibility.
#
# Usage:
#   _gh_project_status_sync <issue|pr> <number> <target-status> [--only-from <list>]
#
# Examples:
#   _gh_project_status_sync issue 42 "In progress"
#   _gh_project_status_sync pr    17 "In review"
#   _gh_project_status_sync issue 42 "In progress" --only-from Backlog
#
# --only-from <list>: comma-separated whitelist of CURRENT Status values.
# If the item's current Status is not in the list, the transition is skipped
# for that project. Used to prevent regression — e.g. /gh-commit must not
# bounce an issue from "In review" back to "In progress" when a follow-up
# fix commit lands. Status names with internal spaces are supported
# ("Backlog,In progress"); do not pad with spaces around the comma.
#
# Verify pair (race absorption, issue #393):
# After every successful mutation the helper sleeps
# _GH_PROJECT_STATUS_VERIFY_SLEEP seconds (default 1) and re-queries the
# current Status. If the value reverted (a builtin workflow such as
# "Pull request linked to issue" overwrote our write asynchronously), the
# mutation is re-issued once. A second mismatch fails loud on stderr but
# still returns 0 to honor the helper's best-effort policy. Override
# _GH_PROJECT_STATUS_VERIFY_SLEEP=0 in tests to skip the wait.
#
# Fail-closed guard (issue #393, defense-in-depth):
# kind=pr + target="Approved" requires the PR's reviewDecision to equal
# APPROVED (looked up via `gh pr view --json reviewDecision`). Any other
# decision — REVIEW_REQUIRED, CHANGES_REQUESTED, or an unreachable gh —
# rejects the transition with exit code 2. Set
# _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 for an emergency bypass.
# Other targets (In review / Done / Backlog / etc.) and kind=issue are
# never gated.
#
# Return codes:
#   0 — success / no-op / best-effort skip (network flake, no project, etc.)
#   2 — fail-closed policy rejection (Approved guard)

_gh_project_status_sync() {
    local _kind="$1" _num="$2" _target="$3"
    [ "$#" -ge 3 ] && shift 3

    local _only_from=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --only-from)
                if [ -z "${2-}" ]; then
                    printf '[gh-project-status] --only-from requires an argument\n' >&2
                    return 0
                fi
                _only_from="$2"
                shift 2
                ;;
            *)
                printf '[gh-project-status] unknown option: %s\n' "$1" >&2
                return 0
                ;;
        esac
    done

    # Opt-out: either env var disables the sync.
    if [ "${GH_PROJECT_STATUS_SYNC-1}" = "0" ] \
        || [ "${GH_FLOW_PROJECT_STATUS_SYNC-1}" = "0" ]; then
        return 0
    fi
    if [ -z "$_kind" ] || [ -z "$_num" ] || [ -z "$_target" ]; then
        return 0
    fi

    local _q_field
    case "$_kind" in
        issue) _q_field='issue' ;;
        pr) _q_field='pullRequest' ;;
        *)
            printf '[gh-project-status] invalid kind=%s, skipping\n' "$_kind" >&2
            return 0
            ;;
    esac

    # Fail-closed guard (issue #393): only an APPROVED PR may land in the
    # "Approved" column. Other Statuses are unaffected. UNKNOWN (gh pr view
    # failure) is treated as non-APPROVED — preferring a loud refusal over
    # a possibly-incorrect mutation. Bypass via
    # _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 (explicit operator intent).
    if [ "$_kind" = "pr" ] \
        && [ "$_target" = "Approved" ] \
        && [ "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-0}" != "1" ]; then
        local _decision
        _decision=$(gh pr view "$_num" --json reviewDecision \
                    --jq '.reviewDecision? // empty' 2>/dev/null) \
            || _decision="UNKNOWN"
        if [ -z "$_decision" ]; then
            _decision="UNKNOWN"
        fi
        if [ "$_decision" != "APPROVED" ]; then
            printf '[gh-project-status] refusing PR #%s -> "Approved": reviewDecision=%s\n' \
                "$_num" "$_decision" >&2
            printf '[gh-project-status]   bypass: _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1\n' >&2
            return 2
        fi
    fi

    # Resolve owner/repo via gh, with one 5s retry on transient failure
    # (e.g. graphql socket reset). Mirrors the mutation step's retry —
    # without it, a single transient `gh repo view` flake silently aborts
    # the whole sync (issue #341). Override _GH_PROJECT_STATUS_RETRY_SLEEP
    # in tests to skip the wait.
    local _owner _repo _resolved
    if ! _resolved=$(_gh_project_status_resolve_owner_repo); then
        sleep "${_GH_PROJECT_STATUS_RETRY_SLEEP-5}"
        if ! _resolved=$(_gh_project_status_resolve_owner_repo); then
            printf '[gh-project-status] could not determine owner/repo, skipping\n' >&2
            return 0
        fi
    fi
    _owner="${_resolved%% *}"
    _repo="${_resolved#* }"

    # Single query: per projectV2 item, return
    #   project.id | item.id | field.id | target_option.id | current_status_name
    # The current_status_name is needed for --only-from gating.
    local _records
    _records=$(gh api graphql \
        -f query="
          query(\$owner: String!, \$repo: String!, \$number: Int!, \$target: String!) {
            repository(owner: \$owner, name: \$repo) {
              ${_q_field}(number: \$number) {
                projectItems(first: 10) {
                  nodes {
                    id
                    fieldValueByName(name: \"Status\") {
                      ... on ProjectV2ItemFieldSingleSelectValue { name }
                    }
                    project {
                      id
                      field(name: \"Status\") {
                        ... on ProjectV2SingleSelectField {
                          id
                          options(names: [\$target]) { id name }
                        }
                      }
                    }
                  }
                }
              }
            }
          }" \
        -f owner="$_owner" -f repo="$_repo" -F number="$_num" -f target="$_target" \
        --jq ".data.repository.${_q_field}.projectItems.nodes[]
              | select(.project?.field?.options? | length > 0)
              | \"\(.project?.id)|\(.id)|\(.project?.field?.id)|\(.project?.field?.options?[0]?.id)|\(.fieldValueByName?.name? // \"\")\"" \
        2>/dev/null) || {
        printf '[gh-project-status] query failed for %s #%s (target=%s)\n' \
            "$_kind" "$_num" "$_target" >&2
        return 0
    }

    if [ -z "$_records" ]; then
        printf '[gh-project-status] %s #%s not in any project with "%s" option\n' \
            "$_kind" "$_num" "$_target" >&2
        return 0
    fi

    # Avoid subshell — heredoc instead of pipe (zsh/bash tracing parity).
    local _proj _item _field _option _current
    while IFS='|' read -r _proj _item _field _option _current; do
        [ -z "$_proj" ] && continue

        # --only-from guard: skip when current Status is not in the whitelist.
        if [ -n "$_only_from" ] \
            && ! _gh_project_status_in_list "$_current" "$_only_from"; then
            printf '[gh-project-status] %s #%s skipped (current="%s" not in only-from="%s")\n' \
                "$_kind" "$_num" "$_current" "$_only_from" >&2
            continue
        fi

        # Mutate + verify pair (issue #393). Retry-on-flake (5s, _RETRY_SLEEP)
        # and verify-then-re-set (1s, _VERIFY_SLEEP) live in the helper so
        # this loop body stays focused on per-project gating.
        _gh_project_status_set_and_verify \
            "$_kind" "$_num" "$_proj" "$_item" "$_field" "$_option" "$_target"
    done <<EOF
$_records
EOF

    return 0
}

# Run the projectV2 Status mutation, then verify the value stuck via a single
# follow-up GraphQL read. If a builtin workflow ("Pull request linked to
# issue", "Item closed", etc.) overwrote our write asynchronously, re-issue
# the mutation once. A second mismatch fails loud on stderr but still
# returns 0 — the helper's contract with callers is best-effort.
#
# Args: kind num proj item field option target
# Returns: 0 (always — preserves the helper's best-effort policy).
#
# Sleep knobs:
#   _GH_PROJECT_STATUS_RETRY_SLEEP — wait between mutation attempts on flake
#                                    (default 5).
#   _GH_PROJECT_STATUS_VERIFY_SLEEP — wait before each verify read so the
#                                     builtin workflow has time to fire and
#                                     be observed (default 1).
# Both default to 0 in bats tests via env override.
_gh_project_status_set_and_verify() {
    local _kind="$1" _num="$2"
    local _proj="$3" _item="$4" _field="$5" _option="$6" _target="$7"
    local _actual _retry_label=''

    if ! _gh_project_status_mutate "$_proj" "$_item" "$_field" "$_option"; then
        sleep "${_GH_PROJECT_STATUS_RETRY_SLEEP-5}"
        if ! _gh_project_status_mutate "$_proj" "$_item" "$_field" "$_option"; then
            printf '[gh-project-status] mutation failed for %s #%s (target=%s)\n' \
                "$_kind" "$_num" "$_target" >&2
            return 0
        fi
        _retry_label=' after 1 retry'
    fi

    # Verify pair as a 2-attempt loop: sleep → query → compare. If attempt 1
    # mismatches, log the race and re-mutate before attempt 2. A third
    # attempt is intentionally not made — it would risk a write-loop with
    # the builtin workflow. Always returns 0 (best-effort policy, #393).
    local _attempt
    for _attempt in 1 2; do
        sleep "${_GH_PROJECT_STATUS_VERIFY_SLEEP-1}"
        _actual=$(_gh_project_status_query_current "$_kind" "$_num")

        if [ "$_actual" = "$_target" ]; then
            if [ "$_attempt" -eq 1 ]; then
                printf '[gh-project-status] %s #%s -> "%s" (verified%s)\n' \
                    "$_kind" "$_num" "$_target" "$_retry_label"
            else
                printf '[gh-project-status] %s #%s -> "%s" (verified after re-set)\n' \
                    "$_kind" "$_num" "$_target"
            fi
            return 0
        fi

        if [ "$_attempt" -eq 2 ]; then
            printf '[gh-project-status] ERROR: %s #%s verify failed twice (target="%s", actual="%s"). Manual intervention may be needed.\n' \
                "$_kind" "$_num" "$_target" "$_actual" >&2
            return 0
        fi

        # Race observed — re-set once before the second verify attempt.
        printf '[gh-project-status] %s #%s reverted to "%s", re-setting...\n' \
            "$_kind" "$_num" "$_actual" >&2
        if ! _gh_project_status_mutate "$_proj" "$_item" "$_field" "$_option"; then
            printf '[gh-project-status] ERROR: re-set mutation failed for %s #%s\n' \
                "$_kind" "$_num" >&2
            return 0
        fi
    done
}

# Best-effort read of the current Status for an issue/PR. Returns the first
# non-empty Status value found across the item's project memberships — for
# multi-board items the verify pair only checks one board's value, but every
# board runs the same builtin workflows so observing one race surface is
# sufficient for the recovery contract.
#
# Args: kind num
# Output (stdout): current Status name or empty string when no project /
#                  no Status / gh failure.
# Returns: 0 always.
_gh_project_status_query_current() {
    local _kind="$1" _num="$2"
    [ -z "$_kind" ] && return 0
    [ -z "$_num" ] && return 0

    local _q_field
    case "$_kind" in
        issue) _q_field='issue' ;;
        pr) _q_field='pullRequest' ;;
        *) return 0 ;;
    esac

    local _owner _repo _resolved
    _resolved=$(_gh_project_status_resolve_owner_repo) || return 0
    _owner="${_resolved%% *}"
    _repo="${_resolved#* }"

    gh api graphql \
        -f query="
          query(\$owner: String!, \$repo: String!, \$number: Int!) {
            repository(owner: \$owner, name: \$repo) {
              ${_q_field}(number: \$number) {
                projectItems(first: 10) {
                  nodes {
                    fieldValueByName(name: \"Status\") {
                      ... on ProjectV2ItemFieldSingleSelectValue { name }
                    }
                  }
                }
              }
            }
          }" \
        -f owner="$_owner" -f repo="$_repo" -F number="$_num" \
        --jq ".data.repository.${_q_field}.projectItems.nodes[]
              | .fieldValueByName?.name?
              | select(. != null and . != \"\")" \
        2>/dev/null \
        | head -n 1
    return 0
}

# Resolve cwd's GitHub owner/repo via `gh repo view`. Prints
# "<owner> <repo>" on success; returns non-zero on failure (gh exit,
# empty output, or partial output). Extracted so the auto-detect step in
# _gh_project_status_sync can mirror the mutation step's single-retry
# pattern (issue #341): without retry, one transient `gh repo view`
# socket reset silently aborts the sync.
_gh_project_status_resolve_owner_repo() {
    local _output _owner _repo
    _output=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"' 2>/dev/null) || return 1
    [ -z "$_output" ] && return 1
    if ! read -r _owner _repo <<EOF
$_output
EOF
    then
        return 1
    fi
    [ -z "$_owner" ] && return 1
    [ -z "$_repo" ] && return 1
    printf '%s %s\n' "$_owner" "$_repo"
    return 0
}

# Run the projectV2 Status mutation. Args: proj, item, field, option (all ids).
# Extracted to a helper so the loop can retry it once without duplicating
# the multi-line GraphQL query block. Stays silent — caller logs outcomes.
_gh_project_status_mutate() {
    # GraphQL variables ($proj, $item, ...) are NOT shell vars — they
    # are bound via the -f flags below, so single quotes are intended.
    # shellcheck disable=SC2016
    gh api graphql \
        -f query='
          mutation($proj: ID!, $item: ID!, $field: ID!, $option: String!) {
            updateProjectV2ItemFieldValue(input: {
              projectId: $proj
              itemId: $item
              fieldId: $field
              value: { singleSelectOptionId: $option }
            }) { clientMutationId }
          }' \
        -f proj="$1" -f item="$2" -f field="$3" -f option="$4" \
        >/dev/null 2>&1
}

# Print one closing-issue number per line for PR <num> in <owner/repo>.
# Stays silent on every failure mode (boards-not-set-up, GraphQL errors,
# missing args, malformed repo) so the caller's for-loop just iterates over
# nothing and the merge report is never blocked.
#
# Why this is a helper instead of `gh pr view --json closingIssuesReferences`:
# the `--json` projection on `gh` 2.45.0 does not list
# `closingIssuesReferences` in its allow-list — invoking it prints
# "Unknown JSON field" and exits non-zero (#264). The GraphQL schema has the
# connection so we go around the CLI's allow-list with a direct query.
#
# Args: <pr-number> <owner/repo>
_gh_pr_closing_issue_numbers() {
    local _pr="$1" _repo="$2"
    [ -z "$_pr" ] && return 0
    [ -z "$_repo" ] && return 0
    case "$_repo" in
        */*) ;;
        *) return 0 ;;
    esac
    local _owner _name
    _owner="${_repo%/*}"
    _name="${_repo#*/}"
    [ -z "$_owner" ] && return 0
    [ -z "$_name" ] && return 0

    # GraphQL variables ($owner, $repo, $num) are bound via the -f/-F flags
    # below, so single quotes around the query are intentional.
    # shellcheck disable=SC2016
    gh api graphql \
        -f owner="$_owner" -f repo="$_name" -F num="$_pr" \
        -f query='query($owner: String!, $repo: String!, $num: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $num) {
              closingIssuesReferences(first: 20) { nodes { number } }
            }
          }
        }' \
        --jq '.data.repository?.pullRequest?.closingIssuesReferences?.nodes[]?.number // empty' \
        2>/dev/null
    return 0
}

# Membership test: returns 0 when $1 equals any comma-separated entry of $2.
# Uses pure parameter expansion to keep Status names with internal spaces
# (e.g. "In progress") intact. Empty $1 never matches.
_gh_project_status_in_list() {
    local _val="$1" _list="$2"
    [ -z "$_val" ] && return 1
    case ",${_list}," in
        *",${_val},"*) return 0 ;;
    esac
    return 1
}
