#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_audit_builtin_workflows.sh
# Audit projectV2 boards attached to the current repo for builtin workflow
# policy violations.
#
# Current policy (one rule, expandable as we observe more violations):
#
#   "Pull request linked to issue" must be DISABLED.
#
# Why this rule exists:
# When ON, this builtin asynchronously rewrites the linked issue's Status
# whenever a PR references it (#393 verify pair documents the race). It
# fights every deterministic Status transition the gh-flow / gh-pr-merge
# helpers issue. Disabling it lets these helpers own Status transitions
# without write-loops.
#
# Usage:
#   gh_audit_builtin_workflows                  # audit current repo's projects
#   gh_audit_builtin_workflows --repo o/r       # audit explicit repo
#   gh_audit_builtin_workflows -h | --help      # print help
#
# Aliases:
#   gh-audit-builtin-workflows
#
# Exit codes:
#   0 — all attached projectV2 boards policy-compliant (or no project / no
#       board access — silent skip, like other gh_project_status_* helpers)
#   2 — at least one attached projectV2 has a forbidden workflow ENABLED
#
# Project-agnostic: works in any repo where the caller has `gh` configured.
# Repos without a projectV2 attachment exit 0 with a "no projects" notice.

# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------

gh_audit_builtin_workflows_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "gh-audit-builtin-workflows"
        ux_section "Usage"
        ux_bullet "gh-audit-builtin-workflows"
        ux_bullet "gh-audit-builtin-workflows --repo owner/name"
        ux_bullet "gh-audit-builtin-workflows -h | --help"
        ux_section "Policy"
        ux_bullet "\"Pull request linked to issue\" must be DISABLED on every"
        ux_bullet "  attached projectV2 board. ON triggers async Status rewrites"
        ux_bullet "  that race with deterministic helpers (issue #393)."
        ux_section "Exit codes"
        ux_bullet "0 — compliant (or no projects attached / no access)"
        ux_bullet "2 — at least one violation detected"
    else
        cat <<'HELP'
gh-audit-builtin-workflows — audit projectV2 builtin workflow policy

Usage:
  gh-audit-builtin-workflows
  gh-audit-builtin-workflows --repo owner/name
  gh-audit-builtin-workflows -h | --help

Policy:
  "Pull request linked to issue" must be DISABLED on every attached
  projectV2 board. ON triggers async Status rewrites that race with
  deterministic helpers (issue #393).

Exit codes:
  0  compliant (or no projects attached / no access)
  2  at least one violation detected
HELP
    fi
}

# ---------------------------------------------------------------------------
# Owner/repo resolution — same precedence as _gh_pr_edit_safe helpers:
#   1. --repo flag
#   2. GH_REPO env var
#   3. `gh repo view --json nameWithOwner`
# Prints "<owner> <repo>" on stdout, returns 1 on failure.
# ---------------------------------------------------------------------------

_gh_audit_builtin_workflows_resolve_repo() {
    local _explicit="$1"
    local _spec=""

    if [ -n "$_explicit" ]; then
        _spec="$_explicit"
    elif [ -n "${GH_REPO-}" ]; then
        _spec="$GH_REPO"
    else
        _spec=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || return 1
    fi

    [ -z "$_spec" ] && return 1
    case "$_spec" in
    */*) ;;
    *) return 1 ;;
    esac
    printf '%s %s\n' "${_spec%/*}" "${_spec#*/}"
}

# ---------------------------------------------------------------------------
# Forbidden workflow names — case statement (no fork, no command substitution).
# Add new patterns above the catch-all `*)` line as new violations are
# discovered. Reviewer note (PR #402): the prior heredoc-list pattern forked
# a subshell on every check; case is O(1) and avoids the fork entirely.
# ---------------------------------------------------------------------------

_gh_audit_builtin_workflows_is_forbidden() {
    case "$1" in
    "Pull request linked to issue") return 0 ;;
    *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Main entry point.
# ---------------------------------------------------------------------------

gh_audit_builtin_workflows() {
    local _repo_flag=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            gh_audit_builtin_workflows_help
            return 0
            ;;
        --repo)
            if [ -z "${2-}" ]; then
                printf '[gh-audit-builtin-workflows] --repo requires an argument\n' >&2
                return 2
            fi
            _repo_flag="$2"
            shift 2
            ;;
        *)
            printf '[gh-audit-builtin-workflows] unknown option: %s\n' "$1" >&2
            return 2
            ;;
        esac
    done

    local _resolved _owner _repo
    if ! _resolved=$(_gh_audit_builtin_workflows_resolve_repo "$_repo_flag"); then
        printf '[gh-audit-builtin-workflows] could not resolve repo (pass --repo or set GH_REPO)\n' >&2
        return 2
    fi
    _owner="${_resolved%% *}"
    _repo="${_resolved#* }"

    # GraphQL: list every projectV2 attached to the repo and each project's
    # builtin workflows. The `workflows` connection is publicly queryable,
    # but `enabled` requires write access on the project. When the caller
    # lacks access, GitHub returns a partial result with `null` workflows —
    # that's why we filter `.workflows?.nodes? // []` rather than failing.
    #
    # Output shape: one record per workflow, tab-separated:
    #   project_url \t project_title \t workflow_name \t enabled (true|false)
    # Tab is safer than `|` because project titles may contain that character
    # (PR #402 review). Null-safe `// empty` on `.repository?` keeps callers
    # from blowing up if GitHub returns a malformed response.
    #
    # GraphQL variables ($owner, $repo) are bound via -f below — single-quoted
    # query string is intentional (would otherwise interpolate at shell level).
    # Variables: $owner String!, $repo String!
    # shellcheck disable=SC2016
    local _records
    _records=$(gh api graphql \
        -f query='
          query($owner: String!, $repo: String!) {
            repository(owner: $owner, name: $repo) {
              projectsV2(first: 20) {
                nodes {
                  number
                  title
                  url
                  workflows(first: 50) {
                    nodes { name enabled number }
                  }
                }
              }
            }
          }' \
        -f owner="$_owner" -f repo="$_repo" \
        --jq '.data.repository? // empty
              | .projectsV2?.nodes[]?
              | . as $p
              | (.workflows?.nodes? // [])[]?
              | "\($p.url)\t\($p.title)\t\(.name)\t\(.enabled)"' \
        2>/dev/null) || {
        printf '[gh-audit-builtin-workflows] graphql query failed for %s/%s\n' \
            "$_owner" "$_repo" >&2
        return 2
    }

    if [ -z "$_records" ]; then
        if type ux_success >/dev/null 2>&1; then
            ux_success "no projectV2 attached to ${_owner}/${_repo} (or no workflow access) — nothing to audit"
        else
            printf '[gh-audit-builtin-workflows] %s/%s: no projectV2 attached (or no workflow access) — nothing to audit\n' \
                "$_owner" "$_repo"
        fi
        return 0
    fi

    # Iterate without subshell — heredoc not pipe (zsh/bash tracing parity,
    # pre-commit hook enforces this in this repo).
    local _violations=0
    local _url _title _name _enabled
    while IFS=$'\t' read -r _url _title _name _enabled; do
        [ -z "$_name" ] && continue
        if _gh_audit_builtin_workflows_is_forbidden "$_name" &&
            [ "$_enabled" = "true" ]; then
            _violations=$((_violations + 1))
            if type ux_error >/dev/null 2>&1; then
                ux_error "✗ ${_title}: \"${_name}\" is ENABLED"
                ux_bullet "  Settings → Workflows: ${_url}/workflows"
            else
                printf '✗ %s: "%s" is ENABLED\n' "$_title" "$_name"
                printf '  Settings → Workflows: %s/workflows\n' "$_url"
            fi
        fi
    done <<EOF
$_records
EOF

    if [ "$_violations" -eq 0 ]; then
        if type ux_success >/dev/null 2>&1; then
            ux_success "✅ ${_owner}/${_repo}: all attached projectV2 boards policy-compliant"
        else
            printf '✅ %s/%s: all attached projectV2 boards policy-compliant\n' \
                "$_owner" "$_repo"
        fi
        return 0
    fi

    printf '\n' >&2
    printf '[gh-audit-builtin-workflows] %d violation(s) — disable the workflow(s) above and re-run.\n' \
        "$_violations" >&2
    return 2
}

# ---------------------------------------------------------------------------
# Aliases (hyphenated command names per shell-common convention)
# ---------------------------------------------------------------------------

alias gh-audit-builtin-workflows='gh_audit_builtin_workflows'
alias gh-audit-builtin-workflows-help='gh_audit_builtin_workflows_help'
