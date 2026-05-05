#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_edit_safe.sh
#
# Wrappers around `gh pr edit` that gracefully fall back to the REST API
# when the GraphQL Projects(classic) deprecation warning trips a fatal
# exit code in the wrapped command.
#
# Background (issue #326, Bug B): on repos with classic Projects attached
# (e.g. dEitY719/dotfiles), `gh pr edit ... --add-label` and
# `--body-file` print the deprecation warning to stderr and exit 1,
# leaving the label or body unmutated. The REST endpoints
# (`POST /repos/:owner/:repo/issues/:n/labels` and
# `PATCH /repos/:owner/:repo/pulls/:n`) do not trigger the GraphQL
# warning, so a single retry through them recovers without any user
# action. Symptom seen on PR #325: labels silently dropped, body
# mutation silently skipped.
#
# Both helpers stay silent on success and emit a single one-line note
# on stderr when the fallback path is taken, so callers can tell from
# logs whether the GraphQL path or the REST path actually applied the
# change. Failure on the fallback path returns the REST exit code so
# the caller can react.
#
# Usage:
#   _pr_edit_safe_label  <pr-number> <label>           [--repo <owner/repo>]
#   _pr_edit_safe_body   <pr-number> <body-file-path>  [--repo <owner/repo>]
#
# When --repo is omitted, $GH_REPO is used; if also empty, the helper
# resolves it via `gh repo view --json nameWithOwner -q .nameWithOwner`.
#
# Important: the label helper does NOT verify the label exists in the
# repo. POST /issues/:n/labels auto-creates missing labels — which
# violates the gh-pr "never create labels on the fly" rule. Callers
# (notably gh-pr's safe-apply loop in pr-body-template.md) MUST
# pre-filter the candidate list against `gh label list` before calling
# this wrapper.

# Resolve --repo / $GH_REPO / current cwd into stdout owner/repo.
# Returns non-zero only if every resolution path fails. Silent on stderr.
_pr_edit_safe_resolve_repo() {
    if [ -n "$1" ]; then
        printf '%s\n' "$1"
        return 0
    fi
    if [ -n "${GH_REPO:-}" ]; then
        printf '%s\n' "$GH_REPO"
        return 0
    fi
    _gh_pr_safe_resolved=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
        unset _gh_pr_safe_resolved
        return 1
    }
    [ -z "$_gh_pr_safe_resolved" ] && {
        unset _gh_pr_safe_resolved
        return 1
    }
    printf '%s\n' "$_gh_pr_safe_resolved"
    unset _gh_pr_safe_resolved
}

# Internal: parse [--repo <owner/repo>] from a varargs tail and echo the
# resolved repo on stdout. Fails (returns 1) only when --repo is supplied
# without a value or all resolution paths come up empty.
_pr_edit_safe_parse_repo() {
    _gh_pr_safe_explicit=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --repo)
            if [ -z "${2-}" ]; then
                printf '[gh-pr-edit-safe] --repo requires an argument\n' >&2
                unset _gh_pr_safe_explicit
                return 1
            fi
            _gh_pr_safe_explicit="$2"
            shift 2
            ;;
        *) shift ;;
        esac
    done
    _pr_edit_safe_resolve_repo "$_gh_pr_safe_explicit"
    _gh_pr_safe_rc=$?
    unset _gh_pr_safe_explicit
    return "$_gh_pr_safe_rc"
}

# Apply an existing label to a PR. The label MUST already exist in the
# repo — this helper does NOT call `gh label list` itself.
_pr_edit_safe_label() {
    if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
        printf '[gh-pr-edit-safe] usage: _pr_edit_safe_label <pr> <label> [--repo <owner/repo>]\n' >&2
        return 2
    fi
    _gh_pr_safe_pr="$1"
    _gh_pr_safe_label="$2"
    shift 2

    _gh_pr_safe_repo=$(_pr_edit_safe_parse_repo "$@") || {
        printf '[gh-pr-edit-safe] could not resolve owner/repo for #%s\n' "$_gh_pr_safe_pr" >&2
        unset _gh_pr_safe_pr _gh_pr_safe_label
        return 2
    }

    _gh_pr_safe_err=$(mktemp -t gh-pr-edit-safe.XXXXXX) || {
        unset _gh_pr_safe_pr _gh_pr_safe_label _gh_pr_safe_repo
        return 1
    }

    gh pr edit "$_gh_pr_safe_pr" --repo "$_gh_pr_safe_repo" \
        --add-label "$_gh_pr_safe_label" 2>"$_gh_pr_safe_err"
    _gh_pr_safe_rc=$?

    if [ "$_gh_pr_safe_rc" -ne 0 ] &&
        grep -q 'Projects (classic) is being deprecated' "$_gh_pr_safe_err"; then
        printf '[gh-pr-edit-safe] gh pr edit --add-label hit Projects(classic) deprecation; retrying via REST for #%s\n' \
            "$_gh_pr_safe_pr" >&2
        gh api -X POST "repos/$_gh_pr_safe_repo/issues/$_gh_pr_safe_pr/labels" \
            -f "labels[]=$_gh_pr_safe_label" >/dev/null 2>&1
        _gh_pr_safe_rc=$?
    elif [ "$_gh_pr_safe_rc" -ne 0 ]; then
        cat "$_gh_pr_safe_err" >&2
    fi

    rm -f "$_gh_pr_safe_err"
    unset _gh_pr_safe_pr _gh_pr_safe_label _gh_pr_safe_repo _gh_pr_safe_err
    _gh_pr_safe_final_rc="$_gh_pr_safe_rc"
    unset _gh_pr_safe_rc
    return "$_gh_pr_safe_final_rc"
}

# Replace the body of a PR. Reads the new body verbatim from <body-file>.
_pr_edit_safe_body() {
    if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
        printf '[gh-pr-edit-safe] usage: _pr_edit_safe_body <pr> <body-file> [--repo <owner/repo>]\n' >&2
        return 2
    fi
    _gh_pr_safe_pr="$1"
    _gh_pr_safe_body_file="$2"
    if [ ! -r "$_gh_pr_safe_body_file" ]; then
        printf '[gh-pr-edit-safe] body file not readable: %s\n' "$_gh_pr_safe_body_file" >&2
        unset _gh_pr_safe_pr _gh_pr_safe_body_file
        return 2
    fi
    shift 2

    _gh_pr_safe_repo=$(_pr_edit_safe_parse_repo "$@") || {
        printf '[gh-pr-edit-safe] could not resolve owner/repo for #%s\n' "$_gh_pr_safe_pr" >&2
        unset _gh_pr_safe_pr _gh_pr_safe_body_file
        return 2
    }

    _gh_pr_safe_err=$(mktemp -t gh-pr-edit-safe.XXXXXX) || {
        unset _gh_pr_safe_pr _gh_pr_safe_body_file _gh_pr_safe_repo
        return 1
    }

    gh pr edit "$_gh_pr_safe_pr" --repo "$_gh_pr_safe_repo" \
        --body-file "$_gh_pr_safe_body_file" 2>"$_gh_pr_safe_err"
    _gh_pr_safe_rc=$?

    if [ "$_gh_pr_safe_rc" -ne 0 ] &&
        grep -q 'Projects (classic) is being deprecated' "$_gh_pr_safe_err"; then
        printf '[gh-pr-edit-safe] gh pr edit --body-file hit Projects(classic) deprecation; retrying via REST for #%s\n' \
            "$_gh_pr_safe_pr" >&2
        # Read the body from the file so we avoid the gh `-F field=@file`
        # ambiguity (gh treats `@file` only on a few projection fields).
        _gh_pr_safe_payload=$(cat "$_gh_pr_safe_body_file")
        gh api -X PATCH "repos/$_gh_pr_safe_repo/pulls/$_gh_pr_safe_pr" \
            -f body="$_gh_pr_safe_payload" >/dev/null 2>&1
        _gh_pr_safe_rc=$?
        unset _gh_pr_safe_payload
    elif [ "$_gh_pr_safe_rc" -ne 0 ]; then
        cat "$_gh_pr_safe_err" >&2
    fi

    rm -f "$_gh_pr_safe_err"
    unset _gh_pr_safe_pr _gh_pr_safe_body_file _gh_pr_safe_repo _gh_pr_safe_err
    _gh_pr_safe_final_rc="$_gh_pr_safe_rc"
    unset _gh_pr_safe_rc
    return "$_gh_pr_safe_final_rc"
}
