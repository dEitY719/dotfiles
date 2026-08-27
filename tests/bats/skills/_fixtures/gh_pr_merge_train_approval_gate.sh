#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_train_approval_gate.sh
# Source-of-truth mirror for the approval-gate classification and the
# gate-off delegated review documented in
#   claude/skills/gh-pr-merge-train/references/approval-gate.md
#   claude/skills/gh-pr-merge-train/references/train-loop.md
#
# Issue #1519: `gh api` collapses every failure into a non-zero exit, so
# the train read a free-plan `403 Upgrade to GitHub Pro...` as "policy
# unreadable" and fail-closed forever.
#
# `none` is a WHITELIST, never a fallback: a 404, a 403 carrying GitHub's
# plan-limit message, or a cleanly-parsed 2xx. Every other answer — a 403
# from permission / rate-limit / SSO, a blank or unparseable 2xx body — is
# `unknown` and keeps the gate on (PR #1526 agy+codex review).
#
# Keep this file in sync with those two docs. If a snippet or a decision
# row changes, mirror it here so the bats suite catches the drift.

# ---------------------------------------------------------------------
# Stub for `gh api -i`. The real call is
#   GH_HOST="$TARGET_HOST" gh api -i "<path>"
# Tests inject one raw HTTP response per source:
#   FAKE_RULES_RESPONSE / FAKE_RULES_RC        (rules/branches/...)
#   FAKE_PROTECTION_RESPONSE / FAKE_PROTECTION_RC  (branches/.../protection)
# An empty response models "no HTTP response at all" (network failure).
# ---------------------------------------------------------------------
gh() {
    local path=
    while [ $# -gt 0 ]; do
        case "$1" in
            api | -i) ;;
            *) path="$1" ;;
        esac
        shift
    done
    # Record every probed path so tests can assert the percent-encoding the
    # doc's `@uri` step produces actually reaches the API (PR #1526 review).
    [ -n "${FAKE_PATH_LOG-}" ] && printf '%s\n' "$path" >>"$FAKE_PATH_LOG"
    case "$path" in
        *rules/branches*)
            printf '%s' "${FAKE_RULES_RESPONSE-}"
            return "${FAKE_RULES_RC-0}"
            ;;
        *protection*)
            printf '%s' "${FAKE_PROTECTION_RESPONSE-}"
            return "${FAKE_PROTECTION_RC-0}"
            ;;
    esac
    return 1
}

# Build a raw HTTP response the stub can serve. $1 status, $2 body.
train_gate_http() {
    printf 'HTTP/1.1 %s Whatever\r\nContent-Type: application/json\r\n\r\n%s' "$1" "$2"
}

# ---------------------------------------------------------------------
# Mirrors approval-gate.md -> "Classify each source by HTTP status".
# Echoes `none`, `unknown`, or the required approval count (>= 1).
# ---------------------------------------------------------------------
_gate_probe() {
    local _path="$1" _jq="$2" _out _status _body _n
    _out=$(gh api -i "$_path" 2>/dev/null)
    _status=$(printf '%s\n' "$_out" | sed -n '1s|^HTTP/[0-9.]* *\([0-9][0-9][0-9]\).*|\1|p')
    _body=$(printf '%s\n' "$_out" | sed '1,/^\r\{0,1\}$/d')
    case "$_status" in
        2??) ;;
        404)
            echo none
            return 0
            ;;
        403)
            # Only the plan-limit message means "no policy can exist";
            # permission / rate-limit / SSO denials fail closed.
            case "$_body" in
                *"Upgrade to GitHub Pro"*) echo none ;;
                *) echo unknown ;;
            esac
            return 0
            ;;
        *)
            echo unknown
            return 0
            ;;
    esac
    [ -n "$(printf '%s' "$_body" | tr -d '[:space:]')" ] || {
        echo unknown
        return 0
    }
    _n=$(printf '%s\n' "$_body" | jq -r "$_jq" 2>/dev/null) || {
        echo unknown
        return 0
    }
    case "$_n" in
        '' | null | 0) echo none ;;
        *[!0-9]*) echo unknown ;;
        *) echo "$_n" ;;
    esac
}

_RULES_JQ='[.[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | max // empty'
_PROTECTION_JQ='.required_pull_request_reviews.required_approving_review_count // empty'

# ---------------------------------------------------------------------
# Mirrors approval-gate.md -> "Combining the two sources" (#1519 F-3, F-4)
# and report-format.md -> "The `approval gate:` field" (#1519 NF-1).
# Echoes "<on|off>|<header text>".
# ---------------------------------------------------------------------
_gate_combine() {
    local _base="$1" _ruleset="$2" _classic="$3"
    local _max=0 _src=''
    case "$_ruleset" in
        none | unknown) ;;
        *) _max="$_ruleset" _src=ruleset ;;
    esac
    case "$_classic" in
        none | unknown) ;;
        *) [ "$_classic" -gt "$_max" ] && { _max="$_classic" _src=protection; } ;;
    esac
    if [ "$_max" -ge 1 ]; then
        printf 'on|%s: %s approvals\n' "$_src" "$_max"
    elif [ "$_ruleset" = unknown ] || [ "$_classic" = unknown ]; then
        printf 'on|fail-closed: %s policy unreadable\n' "$_base"
    else
        printf 'off|no policy on %s\n' "$_base"
    fi
}

# One base branch end to end: probe both sources, combine, echo the verdict.
train_gate_verdict() {
    local _base="$1" _base_enc _ruleset _classic
    # Mirrors the doc's `BASE_ENC=$(jq -rn --arg b "$BASE" '"'"'$b|@uri'"'"')`
    # step — both endpoints take the ref as ONE path segment, so a base like
    # release/2026.08 must arrive as release%2F2026.08.
    _base_enc=$(jq -rn --arg b "$_base" '$b|@uri')
    _ruleset=$(_gate_probe "repos/o/r/rules/branches/$_base_enc" "$_RULES_JQ")
    _classic=$(_gate_probe "repos/o/r/branches/$_base_enc/protection" "$_PROTECTION_JQ")
    _gate_combine "$_base" "$_ruleset" "$_classic"
}

# ---------------------------------------------------------------------
# Mirrors approval-gate.md -> "Applying it per PR".
# $1 gate (on|off), $2 reviewDecision. Echoes proceed | delegate | skip:<reason>.
# ---------------------------------------------------------------------
train_pr_route() {
    local _gate="$1" _rd="$2"
    [ "$_rd" = "APPROVED" ] && {
        printf 'proceed\n'
        return 0
    }
    if [ "$_gate" = "on" ]; then
        printf 'skip:approval required (reviewDecision=%s)\n' "$_rd"
    elif [ -n "$_rd" ]; then
        printf 'skip:gh:pr-merge refuses reviewDecision=%s\n' "$_rd"
    else
        printf 'delegate\n'
    fi
}

# #1519 F-8: the same head was already reviewed by $ME. Returns 0 when the
# delegated review must NOT be re-run.
train_review_suppressed() {
    local _last="$1" _head="$2"
    [ -n "$_last" ] && [ "$_last" = "$_head" ]
}

# ---------------------------------------------------------------------
# Mirrors train-loop.md -> "Delegated review on the gate-off path" step 3.
# $1 board Status ("" = unreadable), $2 ran_this_tick (1|0),
# $3 skill_rc (non-zero = the gh:pr-approve call itself failed, #1519 F-9).
# ---------------------------------------------------------------------
train_delegated_outcome() {
    local _board="$1" _ran="$2" _rc="${3-0}"
    [ "$_rc" -ne 0 ] && {
        printf 'skip:self-record failed\n'
        return 0
    }
    [ "$_board" = "Approved" ] && {
        printf 'proceed\n'
        return 0
    }
    [ -z "$_board" ] && {
        printf 'skip:board unreadable — approval unconfirmed\n'
        return 0
    }
    if [ "$_ran" = "1" ]; then
        printf 'skip:self-record withheld approval (BLOCKER)\n'
    else
        printf 'skip:approval withheld (unchanged since review)\n'
    fi
}
