#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_discussion.sh
# GraphQL wrappers for the GitHub Discussions write API. The REST endpoints
# for Discussions are read-only — `createDiscussion` and friends only exist
# in GraphQL — so this helper centralises the mutation + the lookup chain
# (repository ID -> category ID) the mutation depends on.
#
# Background (issue #617, #618):
# `gh:discussion-create` and `gh:discussion-convert` both need the same
# three create-side primitives: resolve a repository node ID, resolve a
# Discussion category node ID by name, and POST a `createDiscussion`
# mutation. `gh:discussion-convert` additionally needs to fetch an
# existing Discussion and to close / lock / comment on it. Keeping all
# Discussion GraphQL strings in one helper lets the skills stay focused
# on conversation routing while the contract with GitHub's API lives in
# one auditable file.
#
# Usage:
#   _gh_discussion_repo_id     <owner> <repo>
#       Print the repository node ID on stdout. Exit non-zero on lookup
#       failure (network, auth, or missing repo).
#
#   _gh_discussion_category_id <owner> <repo> <category-name>
#       Print the matching Discussion category node ID on stdout. Exit 1
#       when Discussions are disabled on the repo (empty list returned),
#       exit 2 when the category name does not resolve.
#
#   _gh_discussion_create      <repo-id> <category-id> <title> <body-file>
#       POST createDiscussion. Print the Discussion URL on stdout. Exit
#       non-zero on mutation failure (auth, validation, network).
#
#   _gh_discussion_fetch       <owner> <repo> <number>
#       Print a JSON object on stdout with keys: id, number, title, body,
#       url, locked, closed, category (flattened from category.name).
#       Exit 1 on lookup failure or when the discussion does not exist.
#
#   _gh_discussion_comment     <discussion-node-id> <body-file>
#       POST addDiscussionComment. Print the comment URL on stdout.
#       Exit non-zero on mutation failure.
#
#   _gh_discussion_close       <discussion-node-id> [reason]
#       POST closeDiscussion. `reason` defaults to RESOLVED; allowed
#       values: RESOLVED, OUTDATED, DUPLICATE. Print "closed" on success.
#       Exit non-zero on mutation failure.
#
#   _gh_discussion_lock        <discussion-node-id>
#       POST lockLockable (reason RESOLVED). Print "locked" on success.
#       Exit non-zero on mutation failure.
#
# Repo node ID and category ID lookups are cheap enough to do per call —
# do not introduce a disk cache (see references/cache-decision in the
# accompanying skill) until a profile shows it matters.
#
# Failure policy: every helper writes a single `[gh-discussion] <reason>`
# line to stderr and returns a non-zero exit code so the caller can
# present the user with an actionable message. Helpers never call
# `exit` — they `return` so a sourced caller stays in the same shell.
#
# NOTE: This file intentionally has NO interactive guard. It is a pure
# function-defining library (no top-level side effects) consumed by the
# `gh:discussion-create`, `gh:discussion-convert`, and `gh:issue-create`
# skills in non-interactive bash (Claude Code's Bash tool runs
# `bash --noprofile --norc`). An interactive guard would `return 0`
# before defining the helpers, breaking the skills with
# `command not found`. Mirrors the same NOTE in gh_project_status.sh
# (PR #497). See issue #720.

_gh_discussion_repo_id() {
    local _owner="${1:-}" _repo="${2:-}"
    if [ -z "$_owner" ] || [ -z "$_repo" ]; then
        printf '[gh-discussion] usage: _gh_discussion_repo_id <owner> <repo>\n' >&2
        return 2
    fi

    local _err _id
    _err=$(mktemp) || return 1

    # GraphQL variables ($owner, $repo) are NOT shell vars — they are bound
    # via the -f flags below, so single quotes are intended.
    # Variables: $owner String!, $repo String!
    # shellcheck disable=SC2016
    _id=$(gh api graphql \
        -f query='
          query($owner: String!, $repo: String!) {
            repository(owner: $owner, name: $repo) { id }
          }' \
        -f owner="$_owner" -f repo="$_repo" \
        --jq '.data.repository.id' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ] || [ -z "$_id" ] || [ "$_id" = "null" ]; then
        printf '[gh-discussion] repository lookup failed for %s/%s\n' \
            "$_owner" "$_repo" >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi

    rm -f "$_err"
    printf '%s\n' "$_id"
}

_gh_discussion_category_id() {
    local _owner="${1:-}" _repo="${2:-}" _category="${3:-}"
    if [ -z "$_owner" ] || [ -z "$_repo" ] || [ -z "$_category" ]; then
        printf '[gh-discussion] usage: _gh_discussion_category_id <owner> <repo> <category>\n' >&2
        return 2
    fi

    local _err _list
    _err=$(mktemp) || return 1

    # Pull every category in one shot (repos rarely have > 10) and let jq
    # match by name. Doing the filter client-side keeps the GraphQL string
    # short and avoids edge cases around case sensitivity in the API.
    # Variables: $owner String!, $repo String!
    # shellcheck disable=SC2016
    _list=$(gh api graphql \
        -f query='
          query($owner: String!, $repo: String!) {
            repository(owner: $owner, name: $repo) {
              discussionCategories(first: 25) {
                nodes { id name }
              }
            }
          }' \
        -f owner="$_owner" -f repo="$_repo" \
        --jq '.data.repository.discussionCategories.nodes' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ]; then
        printf '[gh-discussion] category lookup failed for %s/%s\n' \
            "$_owner" "$_repo" >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi
    rm -f "$_err"

    # Empty list -> Discussions feature disabled on the repo. Distinct
    # exit code (1) so the skill can show the "enable in repo settings"
    # hint without confusing it with a missing category.
    if [ -z "$_list" ] || [ "$_list" = "null" ] || [ "$_list" = "[]" ]; then
        printf '[gh-discussion] Discussions not enabled on %s/%s — enable in repo settings -> Features\n' \
            "$_owner" "$_repo" >&2
        return 1
    fi

    local _id
    _id=$(printf '%s' "$_list" |
        jq -r --arg name "$_category" \
            '.[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .id' |
        head -n 1)

    if [ -z "$_id" ]; then
        printf '[gh-discussion] category "%s" not found on %s/%s; available:\n' \
            "$_category" "$_owner" "$_repo" >&2
        printf '%s' "$_list" | jq -r '.[].name | "  - " + .' >&2
        return 2
    fi

    printf '%s\n' "$_id"
}

_gh_discussion_create() {
    local _repo_id="${1:-}" _category_id="${2:-}" _title="${3:-}" _body_file="${4:-}"
    if [ -z "$_repo_id" ] || [ -z "$_category_id" ] || [ -z "$_title" ] ||
        [ -z "$_body_file" ]; then
        printf '[gh-discussion] usage: _gh_discussion_create <repo-id> <category-id> <title> <body-file>\n' >&2
        return 2
    fi
    if [ ! -f "$_body_file" ]; then
        printf '[gh-discussion] body-file not found: %s\n' "$_body_file" >&2
        return 2
    fi

    local _err _url
    _err=$(mktemp) || return 1

    # GraphQL variables ($repoId, $categoryId, $title, $body) are NOT shell
    # vars — they are bound via the -f flags below, so single quotes are
    # intended.
    # Variables: $repoId ID!, $categoryId ID!, $title String!, $body String!
    # shellcheck disable=SC2016
    _url=$(gh api graphql \
        -f query='
          mutation($repoId: ID!, $categoryId: ID!, $title: String!, $body: String!) {
            createDiscussion(input: {
              repositoryId: $repoId,
              categoryId:   $categoryId,
              title:        $title,
              body:         $body
            }) {
              discussion { url }
            }
          }' \
        -f repoId="$_repo_id" \
        -f categoryId="$_category_id" \
        -f title="$_title" \
        -F "body=@$_body_file" \
        --jq '.data.createDiscussion.discussion.url' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ] || [ -z "$_url" ] || [ "$_url" = "null" ]; then
        printf '[gh-discussion] createDiscussion mutation failed\n' >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi

    rm -f "$_err"
    printf '%s\n' "$_url"
}

_gh_discussion_fetch() {
    local _owner="${1:-}" _repo="${2:-}" _num="${3:-}"
    if [ -z "$_owner" ] || [ -z "$_repo" ] || [ -z "$_num" ]; then
        printf '[gh-discussion] usage: _gh_discussion_fetch <owner> <repo> <number>\n' >&2
        return 2
    fi
    case "$_num" in
        '' | *[!0-9]*)
            printf '[gh-discussion] discussion number must be a positive integer\n' >&2
            return 2
            ;;
    esac

    local _err _json
    _err=$(mktemp) || return 1

    # GraphQL variables ($owner, $repo, $num) are NOT shell vars — single
    # quotes around the query are intended.
    # Variables: $owner String!, $repo String!, $num Int!
    # shellcheck disable=SC2016
    _json=$(gh api graphql \
        -f query='
          query($owner: String!, $repo: String!, $num: Int!) {
            repository(owner: $owner, name: $repo) {
              discussion(number: $num) {
                id
                number
                title
                body
                url
                locked
                closed
                category { name }
              }
            }
          }' \
        -f owner="$_owner" -f repo="$_repo" -F "num=$_num" \
        --jq '.data.repository.discussion' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ] || [ -z "$_json" ] || [ "$_json" = "null" ]; then
        printf '[gh-discussion] discussion #%s not found on %s/%s\n' \
            "$_num" "$_owner" "$_repo" >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi

    rm -f "$_err"
    # Flatten category.name -> category for ergonomic jq downstream.
    printf '%s' "$_json" | jq -c '. + {category: .category.name}'
}

_gh_discussion_comment() {
    local _disc_id="${1:-}" _body_file="${2:-}"
    if [ -z "$_disc_id" ] || [ -z "$_body_file" ]; then
        printf '[gh-discussion] usage: _gh_discussion_comment <discussion-id> <body-file>\n' >&2
        return 2
    fi
    if [ ! -f "$_body_file" ]; then
        printf '[gh-discussion] body-file not found: %s\n' "$_body_file" >&2
        return 2
    fi

    local _err _url
    _err=$(mktemp) || return 1

    # Variables: $discId ID!, $body String!
    # shellcheck disable=SC2016
    _url=$(gh api graphql \
        -f query='
          mutation($discId: ID!, $body: String!) {
            addDiscussionComment(input: {
              discussionId: $discId,
              body:         $body
            }) {
              comment { url }
            }
          }' \
        -f discId="$_disc_id" \
        -F "body=@$_body_file" \
        --jq '.data.addDiscussionComment.comment.url' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ] || [ -z "$_url" ] || [ "$_url" = "null" ]; then
        printf '[gh-discussion] addDiscussionComment mutation failed\n' >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi

    rm -f "$_err"
    printf '%s\n' "$_url"
}

_gh_discussion_close() {
    local _disc_id="${1:-}" _reason="${2:-RESOLVED}"
    if [ -z "$_disc_id" ]; then
        printf '[gh-discussion] usage: _gh_discussion_close <discussion-id> [reason]\n' >&2
        return 2
    fi
    case "$_reason" in
        RESOLVED | OUTDATED | DUPLICATE) ;;
        *)
            printf '[gh-discussion] close reason must be RESOLVED, OUTDATED, or DUPLICATE (got: %s)\n' \
                "$_reason" >&2
            return 2
            ;;
    esac

    local _err _state
    _err=$(mktemp) || return 1

    # Variables: $discId ID!, $reason DiscussionCloseReason!
    # shellcheck disable=SC2016
    _state=$(gh api graphql \
        -f query='
          mutation($discId: ID!, $reason: DiscussionCloseReason!) {
            closeDiscussion(input: {
              discussionId: $discId,
              reason:       $reason
            }) {
              discussion { closed }
            }
          }' \
        -f discId="$_disc_id" \
        -f reason="$_reason" \
        --jq '.data.closeDiscussion.discussion.closed' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ] || [ "$_state" != "true" ]; then
        printf '[gh-discussion] closeDiscussion mutation failed\n' >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi

    rm -f "$_err"
    printf 'closed\n'
}

_gh_discussion_lock() {
    local _disc_id="${1:-}"
    if [ -z "$_disc_id" ]; then
        printf '[gh-discussion] usage: _gh_discussion_lock <discussion-id>\n' >&2
        return 2
    fi

    local _err _state
    _err=$(mktemp) || return 1

    # lockLockable accepts any Lockable (Issue, PR, Discussion). Reason
    # RESOLVED matches the policy in docs/.ssot/discussions-policy.md.
    # Variables: $id ID!
    # shellcheck disable=SC2016
    _state=$(gh api graphql \
        -f query='
          mutation($id: ID!) {
            lockLockable(input: {
              lockableId: $id,
              lockReason: RESOLVED
            }) {
              lockedRecord { locked }
            }
          }' \
        -f id="$_disc_id" \
        --jq '.data.lockLockable.lockedRecord.locked' 2>"$_err")
    local _rc=$?

    if [ "$_rc" -ne 0 ] || [ "$_state" != "true" ]; then
        printf '[gh-discussion] lockLockable mutation failed\n' >&2
        if [ -s "$_err" ]; then
            sed 's/^/[gh-discussion] /' "$_err" >&2
        fi
        rm -f "$_err"
        return 1
    fi

    rm -f "$_err"
    printf 'locked\n'
}
