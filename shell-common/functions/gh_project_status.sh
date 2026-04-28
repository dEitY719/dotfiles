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

    # Resolve owner/repo via gh.
    local _owner _repo
    if ! read -r _owner _repo <<EOF
$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"' 2>/dev/null)
EOF
    then
        printf '[gh-project-status] could not determine owner/repo, skipping\n' >&2
        return 0
    fi
    if [ -z "$_owner" ] || [ -z "$_repo" ]; then
        printf '[gh-project-status] could not determine owner/repo, skipping\n' >&2
        return 0
    fi

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

        # One retry on mutation flake (GraphQL connection reset etc.).
        # 5s fixed backoff — long enough to ride out transient resets,
        # short enough to keep callers responsive. Query-stage retry is
        # intentionally not added here (boards-not-attached looks like a
        # transient failure to gh; tracked separately).
        if _gh_project_status_mutate "$_proj" "$_item" "$_field" "$_option"; then
            printf '[gh-project-status] %s #%s -> "%s"\n' "$_kind" "$_num" "$_target"
        else
            sleep 5
            if _gh_project_status_mutate "$_proj" "$_item" "$_field" "$_option"; then
                printf '[gh-project-status] %s #%s -> "%s" (after 1 retry)\n' \
                    "$_kind" "$_num" "$_target"
            else
                printf '[gh-project-status] mutation failed for %s #%s (target=%s)\n' \
                    "$_kind" "$_num" "$_target" >&2
            fi
        fi
    done <<EOF
$_records
EOF

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
