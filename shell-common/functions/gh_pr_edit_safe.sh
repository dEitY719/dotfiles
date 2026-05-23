#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_edit_safe.sh
# REST-fallback wrappers for `gh pr edit` PR mutations that fail silently on
# repos with a classic GitHub Projects board attached.
#
# Background (issue #326):
# `gh pr edit` issues a GraphQL request that resolves the PR's `projectCards`
# field. After the GitHub Projects(classic) sunset (2024-05) that field is
# deprecated, and GitHub returns a deprecation warning. `gh` treats the
# warning as a fatal error → exit 1, with the requested mutation NOT applied.
# Visible symptoms: silent label drops, body-update no-ops.
#
# These helpers retry via the REST endpoint, which is GraphQL-free and
# unaffected by the deprecation. The first attempt still uses `gh pr edit`
# so repos without a classic board pay no overhead.
#
# Usage:
#   _gh_pr_edit_safe_label  <pr-number> <label>     [--repo owner/name]
#   _gh_pr_edit_safe_body   <pr-number> <body-file> [--repo owner/name]
#
# Repo resolution precedence:
#   1. Explicit --repo flag
#   2. GH_REPO env var
#   3. `gh repo view --json nameWithOwner --jq .nameWithOwner` (current dir)
#
# Return codes:
#   0  — primary `gh pr edit` succeeded, OR REST fallback applied successfully
#   1  — primary failed for a non-deprecation reason (stderr passed through)
#   2  — usage error (missing args, unknown option, repo unresolved)
#   3  — REST fallback refused (label does not exist; would auto-create)
#
# Defensive checks:
#   _gh_pr_edit_safe_label validates the label exists in the repo before
#   hitting the REST endpoint. Without this guard, POST /labels would
#   auto-create a missing label silently — see project memory
#   `feedback_gh_label_no_autocreate.md`.
#
# NOTE: This file intentionally has NO interactive guard. It is a pure
# function-defining library (no top-level side effects) consumed by the
# `gh:pr` skill in non-interactive bash (Claude Code's Bash tool runs
# `bash --noprofile --norc`). An interactive guard would `return 0`
# before defining `_gh_pr_edit_safe_label` / `_gh_pr_edit_safe_body`,
# breaking PR body / label edits with `command not found`. Mirrors the
# same NOTE in gh_project_status.sh (PR #497). See issue #720.

_gh_pr_edit_safe__deprecation_marker='Projects (classic) is being deprecated'

_gh_pr_edit_safe__resolve_repo() {
    if [ -n "$1" ]; then
        printf '%s' "$1"
        return 0
    fi
    if [ -n "${GH_REPO-}" ]; then
        printf '%s' "$GH_REPO"
        return 0
    fi
    gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null
}

_gh_pr_edit_safe_label() {
    local _pr="$1" _label="$2"
    [ "$#" -ge 2 ] && shift 2

    local _repo_flag=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --repo)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-edit-safe] --repo requires an argument\n' >&2
                    return 2
                fi
                _repo_flag="$2"
                shift 2
                ;;
            *)
                printf '[gh-pr-edit-safe] unknown option: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done

    if [ -z "$_pr" ] || [ -z "$_label" ]; then
        printf '[gh-pr-edit-safe] usage: _gh_pr_edit_safe_label <pr> <label> [--repo owner/name]\n' >&2
        return 2
    fi

    local _repo
    _repo=$(_gh_pr_edit_safe__resolve_repo "$_repo_flag")
    if [ -z "$_repo" ]; then
        printf '[gh-pr-edit-safe] could not resolve repo (pass --repo or set GH_REPO)\n' >&2
        return 2
    fi

    local _err
    _err=$(mktemp) || return 2

    if gh pr edit "$_pr" --repo "$_repo" --add-label "$_label" >/dev/null 2>"$_err"; then
        rm -f "$_err"
        return 0
    fi

    if ! grep -q "$_gh_pr_edit_safe__deprecation_marker" "$_err"; then
        cat "$_err" >&2
        rm -f "$_err"
        return 1
    fi

    # Deprecation-warning path: validate label exists before REST fallback,
    # else POST /labels would silently create a new label (issue #326).
    if ! gh label list --repo "$_repo" --limit 200 --json name --jq '.[].name' 2>/dev/null \
        | grep -Fxq "$_label"; then
        printf '[gh-pr-edit-safe] label "%s" not in %s; refusing REST fallback (would auto-create)\n' \
            "$_label" "$_repo" >&2
        rm -f "$_err"
        return 3
    fi

    if gh api -X POST "repos/$_repo/issues/$_pr/labels" \
        -f "labels[]=$_label" >/dev/null 2>"$_err"; then
        rm -f "$_err"
        return 0
    fi

    cat "$_err" >&2
    rm -f "$_err"
    return 1
}

_gh_pr_edit_safe_body() {
    local _pr="$1" _body_file="$2"
    [ "$#" -ge 2 ] && shift 2

    local _repo_flag=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --repo)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-edit-safe] --repo requires an argument\n' >&2
                    return 2
                fi
                _repo_flag="$2"
                shift 2
                ;;
            *)
                printf '[gh-pr-edit-safe] unknown option: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done

    if [ -z "$_pr" ] || [ -z "$_body_file" ]; then
        printf '[gh-pr-edit-safe] usage: _gh_pr_edit_safe_body <pr> <body-file> [--repo owner/name]\n' >&2
        return 2
    fi
    if [ ! -f "$_body_file" ]; then
        printf '[gh-pr-edit-safe] body-file not found: %s\n' "$_body_file" >&2
        return 2
    fi

    local _repo
    _repo=$(_gh_pr_edit_safe__resolve_repo "$_repo_flag")
    if [ -z "$_repo" ]; then
        printf '[gh-pr-edit-safe] could not resolve repo (pass --repo or set GH_REPO)\n' >&2
        return 2
    fi

    local _err
    _err=$(mktemp) || return 2

    if gh pr edit "$_pr" --repo "$_repo" --body-file "$_body_file" >/dev/null 2>"$_err"; then
        rm -f "$_err"
        return 0
    fi

    if ! grep -q "$_gh_pr_edit_safe__deprecation_marker" "$_err"; then
        cat "$_err" >&2
        rm -f "$_err"
        return 1
    fi

    # Build {"body": "<file-contents>"} as JSON for the REST PATCH.
    # jq --rawfile slurps the file losslessly, preserving newlines and
    # escapes that would mangle if passed via shell args.
    local _payload
    if ! _payload=$(jq -n --rawfile body "$_body_file" '{body: $body}' 2>"$_err"); then
        cat "$_err" >&2
        rm -f "$_err"
        return 1
    fi

    if printf '%s' "$_payload" | gh api -X PATCH "repos/$_repo/pulls/$_pr" \
        --input - >/dev/null 2>"$_err"; then
        rm -f "$_err"
        return 0
    fi

    cat "$_err" >&2
    rm -f "$_err"
    return 1
}

# Self-check (issue #724): catch silent breakage where this file sources
# cleanly but its public wrappers never get defined — interactive-guard
# regression, syntax error mid-file, future rename. Without these wrappers
# label / body edits fall back to plain `gh pr edit`, which silently exits 1
# on repos with classic Projects attached (the original #326 bug this helper
# was written to absorb). rc stays 0 — best-effort contract preserved.
if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1 \
    || ! command -v _gh_pr_edit_safe_body >/dev/null 2>&1; then
    printf '[gh_pr_edit_safe] BUG: _gh_pr_edit_safe_{label,body} undefined after source — PR edit safe-fallback will silently no-op. See dotfiles #724.\n' >&2
fi
:
