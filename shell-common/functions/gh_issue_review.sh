#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/gh_issue_review.sh
# gh-issue-review — one GitHub issue, one external AI CLI, one issue comment
# (issue #2381). The execution engine of gh-issue:review-all; a fan-out over
# several CLIs is lib/ai_fanout.sh's job, one lane per call of this engine.
#
# Reuses the PR engine's CLI runner and output gate from lib/ai_cli_run.sh
# (same `--ai` set, same timeouts, same "exit 0 is not a review" rule) and
# never sources functions/gh_pr_review.sh, so the issue skill can vendor this
# file without the PR code.
#
# PATH executable: tools/custom/gh_issue_review.sh (~/.local/bin/gh-issue-review,
# #2195 pattern) sources this file and calls _gh_issue_review_main.

# #1454/#1505 foreign-checkout guard — the issue skill sources this file
# standalone, exactly like gh_pr_review.sh (see that file for the rationale).
if [ -n "${ZSH_VERSION-}" ]; then
    _drg_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    _drg_self="${BASH_SOURCE[0]-}"
else
    _drg_self=""
fi
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_drg_self" "gh-issue-review"
else
    printf '[gh-issue-review] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

# Same ux_error loading as gh_pr_review.sh (#2257): an already-defined one
# wins (a fan-out lane defines a plain one), else ux_lib, else plain stderr.
if ! command -v ux_error >/dev/null 2>&1; then
    _gir_ux_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/ux_lib/ux_lib.sh"
    # shellcheck disable=SC1090
    [ -r "$_gir_ux_lib" ] && . "$_gir_ux_lib"
    unset _gir_ux_lib
    if ! command -v ux_error >/dev/null 2>&1; then
        ux_error() { printf '%s\n' "$1" >&2; }
    fi
fi

# CLI runner + output gate, the github.com host predicate and the setup-mode
# reader. A missing gh_host.sh or setup_mode_read.sh is not an error here:
# the leak guard below treats either one's absence as "check required"
# (fail closed, AGENTS.md Correction Rules).
# shellcheck disable=SC1091
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/ai_cli_run.sh" ||
    ux_error "[gh-issue-review] could not load lib/ai_cli_run.sh (#2381)"
# shellcheck disable=SC1091
[ -r "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/gh_host.sh" ] &&
    . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/gh_host.sh"
# shellcheck disable=SC1091
[ -r "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/util/setup_mode_read.sh" ] &&
    . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/util/setup_mode_read.sh"

# Native help (#2136): summary by default, `--list`, `--all`/`usage` = full.
gh_issue_review_help() {
    case "${1-}" in
    "" | -h | --help | help) _gh_issue_review_help_summary ;;
    --list | list | section | sections) _gh_issue_review_help_list_sections ;;
    --all | all | usage) _gh_issue_review_help_full ;;
    *)
        ux_error "Unknown section: $1"
        _gh_issue_review_help_list_sections
        return 1
        ;;
    esac
}

_gh_issue_review_help_summary() {
    ux_info "Usage: gh-issue-review-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "usage: gh-issue-review --ai <ai> --repo <owner/repo> --host <host> [--workdir <dir>] <issue#>"
    ux_bullet_sub "details: gh-issue-review-help usage"
}

_gh_issue_review_help_list_sections() {
    printf '%s\n' "usage"
}

_gh_issue_review_help_full() {
    cat <<'EOF'
gh-issue-review — have an external AI CLI review one GitHub issue (the spec,
not code) and post the review as one issue comment.

Usage:
  gh-issue-review --ai <ai> --repo <owner/repo> --host <host> [--workdir <dir>] <issue#>
  gh-issue-review -h | --help | help

Flags:
  --ai <codex|agy|claude|opencode|hermes>   required; reviewer CLI
  --repo <owner/repo>   required; never defaulted (dual-host safety, #1403)
  --host <host>         required; GH_HOST for every gh call
  --workdir <dir>       the CLI runs here so it can check the issue's claims
                        against code (opencode gets it as --dir). Omitted:
                        the caller's cwd (opencode: an empty temp dir)

Behavior:
  - Comments carrying <!-- ai-issue-review: are left out of the material.
  - Perspective from the title prefix: feat / fix / common.
  - Skips (exit 0) when this gh login already posted the same <ai> review
    for the same issue body (marker <!-- ai-issue-review:<ai>:<body-hash12> -->).
  - Leak guard: setup-mode internal (or unreadable) + github.com target ->
    the comment must not match LEAK_PATTERNS_ERE; an empty variable blocks.

Exit: 0 posted or skipped | 1 runtime / output gate / CLI failure (CLI rc
      passes through, 124 = timeout) | 2 argument error | 3 leak-guard
EOF
}

# gh_issue_review_parse — pure arg parser, one `key=value` line per arg on
# stdout; rc 2 with the reason on stderr. --repo/--host are mandatory.
gh_issue_review_parse() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local ai="" repo="" host="" workdir="" issue=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            echo "help_requested=1"
            return 0
            ;;
        --ai | --repo | --host | --workdir)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                ux_error "$1 requires a value"
                return 2
            fi
            case "$1" in
            --ai) ai="$2" ;;
            --repo) repo="$2" ;;
            --host) host="$2" ;;
            --workdir) workdir="$2" ;;
            esac
            shift 2
            ;;
        -*)
            ux_error "Unknown flag: $1"
            return 2
            ;;
        *)
            if [ -n "$issue" ]; then
                ux_error "Unexpected argument: $1"
                return 2
            fi
            issue="$1"
            shift
            ;;
        esac
    done
    [ -n "$ai" ] || { ux_error "--ai is required"; return 2; }
    [ -n "$repo" ] || { ux_error "--repo <owner/repo> is required (never defaulted, #1403)"; return 2; }
    [ -n "$host" ] || { ux_error "--host <host> is required (never defaulted, #1403)"; return 2; }
    case "$repo" in
    */*/* | /* | */ | *[!A-Za-z0-9._/-]*)
        ux_error "--repo must be <owner>/<repo>: '$repo'"
        return 2
        ;;
    */*) ;;
    *)
        ux_error "--repo must be <owner>/<repo>: '$repo'"
        return 2
        ;;
    esac
    case "$host" in *[!A-Za-z0-9.:-]*)
        ux_error "--host must be a bare host name: '$host'"
        return 2
        ;;
    esac
    case "$issue" in
    '' | *[!0-9]* | 0*)
        ux_error "<issue#> must be a positive integer: '$issue'"
        return 2
        ;;
    esac
    if [ -n "$workdir" ] && [ ! -d "$workdir" ]; then
        ux_error "--workdir is not a directory: '$workdir'"
        return 2
    fi
    printf '%s\n' "ai=$ai" "repo=$repo" "host=$host" "workdir=$workdir" "issue=$issue"
}

# _gh_issue_review_perspective <title> — feat | fix | common, from the
# conventional-commit prefix (`feat:`, `fix(scope)!:` ...).
_gh_issue_review_perspective() {
    case "$(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]')" in
    feat:* | feat\(*\):* | feat!:* | feat\(*\)!:*) echo feat ;;
    fix:* | fix\(*\):* | fix!:* | fix\(*\)!:*) echo fix ;;
    *) echo common ;;
    esac
}

_gh_issue_review_common_prefix() {
    cat <<'EOF'
You are reviewing a GitHub ISSUE — a spec for work not yet done — as a
second-opinion reviewer. You do not decide whether it gets built; your job is
to surface specific, actionable gaps before anyone implements it. Read only:
never modify, create or delete a file.

Adopt a critical, skeptical stance. Do not rubber-stamp.

Priority 1 — omissions: what an implementer will need that the issue does not
say (requirements, edge cases, failure modes, completion criteria, affected
callers / tests / docs, rollout).
Priority 2 — fact check: test every factual claim about the codebase (paths,
line numbers, function names, current behavior) against the code in your
current working directory. Mark each as CONFIRMED, WRONG (say what is true)
or UNVERIFIABLE.

Classification (use these exact labels for every finding):
  - BLOCKER   — the issue cannot be implemented correctly as written.
  - FOLLOW-UP — a gap worth fixing in the issue, not blocking.
  - PRAISE    — a concrete part of the spec worth keeping.

Format (one line per finding):
  [BLOCKER|FOLLOW-UP|PRAISE] <issue section or path:line> — <one-sentence reason>

Verdict (mandatory, last line): a single overall call on the issue —
  판정: [LGTM|우려있음|블로킹]        (Korean-dominant issue)
  Verdict: [LGTM|CONCERNS|BLOCKING]  (English-dominant issue)

Reply in the dominant language of the issue. Be concise; no preamble; do not
restate the issue.
EOF
}

_gh_issue_review_perspective_body() {
    case "$1" in
    feat)
        cat <<'EOF'
Perspective: new feature. Check that the acceptance criteria are executable,
that inputs, outputs and failure behavior are specified, which existing
modules and callers the feature touches, whether backward compatibility or a
migration is needed, and whether scope is bounded (non-goals stated).
EOF
        ;;
    fix)
        cat <<'EOF'
Perspective: bug fix. Check that the root cause is identified (not just the
symptom), that reproduction steps exist, that a regression test is named,
whether other call sites share the same defect, and what else the fix could
break.
EOF
        ;;
    *)
        cat <<'EOF'
Perspective: general. Check that the goal is unambiguous, the completion
criteria are observable, dependencies on other issues or systems are named,
and the scope fits one change.
EOF
        ;;
    esac
}

# _gh_issue_review_hash12 — first 12 hex chars of sha256(stdin).
_gh_issue_review_hash12() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -c1-12
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -c1-12
    else
        return 1
    fi
}

# _gh_issue_review_leak_check <host> <file> — rc 0: safe to post; rc 3: held,
# reason on stdout. The check applies when the target is github.com AND the
# setup mode is internal — exactly _gh_push_github_com_forbidden, which also
# reads a missing mode reader as internal. A missing gh_host.sh likewise means
# "check required" (fail closed). Then the whole comment must not match
# LEAK_PATTERNS_ERE (the pre-push leak guard's variable,
# git/config/pre-push-rules.sh); empty or invalid patterns block.
_gh_issue_review_leak_check() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local host="$1" file="$2" _grc=0
    if command -v _gh_push_github_com_forbidden >/dev/null 2>&1 &&
        ! _gh_push_github_com_forbidden "$host"; then
        return 0
    fi
    if [ -z "${LEAK_PATTERNS_ERE-}" ]; then
        echo "leak-guard: LEAK_PATTERNS_ERE is empty, cannot check a github.com post from an internal PC"
        return 3
    fi
    grep -Eq -- "$LEAK_PATTERNS_ERE" "$file" 2>/dev/null || _grc=$?
    case "$_grc" in
    1) return 0 ;;
    0) echo "leak-guard: the review matches LEAK_PATTERNS_ERE" ;;
    *) echo "leak-guard: LEAK_PATTERNS_ERE could not be applied (grep exit $_grc)" ;;
    esac
    return 3
}

# _gh_issue_review_build_comment <out> <ai> <hash12> <ref> <ai-out> <tokens>
# <elapsed-min> — marker pair around the verbatim review; the metrics footer
# mirrors the PR engine's (_gh_pr_review_build_comment_body).
_gh_issue_review_build_comment() {
    local tag="$2:$3"
    {
        printf '<details>\n'
        printf '<summary>AI Issue Review · %s</summary>\n\n' "$2"
        printf '<!-- ai-issue-review:%s -->\n' "$tag"
        # shellcheck disable=SC2016  # literal backticks: markdown code span
        printf '리뷰 기준: `%s`\n\n' "$4"
        cat "$5"
        printf '\n<!-- /ai-issue-review:%s -->\n\n' "$tag"
        printf '</details>\n\n'
        printf -- '---\n'
        printf '<details>\n'
        printf '<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~0.5 h · 🤖 ~%s min</summary>\n\n' "$6" "$7"
        printf '<!-- ai-metrics:gh-issue-review -->\n'
        printf '📊 ~%s tokens · 👤 ~0.5 h · 🤖 ~%s min\n' "$6" "$7"
        printf '<!-- /ai-metrics:gh-issue-review -->\n\n'
        printf '</details>\n'
    } >"$1"
}

_gh_issue_review_main() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    case "${1:-}" in "" | -h | --help | help)
        _gh_issue_review_help_full
        return 0
        ;;
    esac
    local _start _parsed _k _v ai="" repo="" host="" workdir="" issue=""
    _start=$(date +%s)
    _parsed=$(gh_issue_review_parse "$@") || return $?
    case "$_parsed" in *help_requested=1*)
        _gh_issue_review_help_full
        return 0
        ;;
    esac
    while IFS='=' read -r _k _v; do
        case "$_k" in
        ai) ai="$_v" ;; repo) repo="$_v" ;; host) host="$_v" ;;
        workdir) workdir="$_v" ;; issue) issue="$_v" ;;
        esac
    done <<EOF
$_parsed
EOF
    command -v gh >/dev/null 2>&1 || { ux_error "Required CLI 'gh' not found in PATH"; return 1; }
    local _cli_rc=0
    _gh_pr_review_require_ai_cli "$ai" || _cli_rc=$?
    [ "$_cli_rc" -eq 0 ] || return "$_cli_rc"
    # Function-local: every gh child is pinned, the caller's GH_HOST survives.
    local GH_HOST="$host"
    export GH_HOST

    # ---- material: title, body, non-marker comments ----
    local _title _body _comments _hash _login _seen
    _title=$(gh issue view "$issue" --repo "$repo" --json title --jq .title) || {
        ux_error "Could not read issue #$issue from $repo on $host"
        return 1
    }
    _body=$(gh issue view "$issue" --repo "$repo" --json body --jq .body) || {
        ux_error "Could not read the body of issue #$issue"
        return 1
    }
    _hash=$(printf '%s' "$_body" | _gh_issue_review_hash12) || {
        ux_error "Neither sha256sum nor shasum is available for the body hash"
        return 1
    }

    # ---- duplicate guard: only this host's own login counts (#1639) ----
    _login=$(gh api user --jq .login) || _login=""
    if [ -z "$_login" ]; then
        ux_error "Could not resolve the gh login on $host"
        return 1
    fi
    case "$_login" in *[!A-Za-z0-9_.-]*)
        ux_error "Unexpected gh login: '$_login'"
        return 1
        ;;
    esac
    _seen=$(gh issue view "$issue" --repo "$repo" --json comments \
        --jq "[.comments[] | select(.author.login == \"$_login\") | select(.body | contains(\"<!-- ai-issue-review:$ai:$_hash -->\"))] | length") || {
        ux_error "Could not read the comments of issue #$issue"
        return 1
    }
    if [ "${_seen:-0}" != 0 ]; then
        printf '[SKIP] issue #%s already reviewed by %s for body %s\n' "$issue" "$ai" "$_hash"
        return 0
    fi
    _comments=$(gh issue view "$issue" --repo "$repo" --json comments \
        --jq '.comments[] | select(.body | contains("<!-- ai-issue-review:") | not) | "--- comment by @\(.author.login) at \(.createdAt) ---\n\(.body)\n"') || {
        ux_error "Could not read the comments of issue #$issue"
        return 1
    }

    # ---- review basis: <branch>@<short-sha> of the tree the CLI reads ----
    local _ref _br _sha
    _br=$(git -C "${workdir:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null) || _br="unknown"
    _sha=$(git -C "${workdir:-.}" rev-parse --short HEAD 2>/dev/null) || _sha="unknown"
    _ref="$_br@$_sha"

    local _prompt="" _out="" _err="" _bodyf="" _rc=0 _reject _why _kind
    _kind=$(_gh_issue_review_perspective "$_title")
    if ! { _prompt=$(_gh_pr_review_mktemp_safe "/tmp/gh-issue-review-prompt.$ai.$issue.XXXXXX") &&
        _out=$(_gh_pr_review_mktemp_safe "/tmp/gh-issue-review-out.XXXXXX") &&
        _err=$(_gh_pr_review_mktemp_safe "/tmp/gh-issue-review-stderr.$ai.XXXXXX") &&
        _bodyf=$(_gh_pr_review_mktemp_safe "/tmp/gh-issue-review-body.XXXXXX"); }; then
        ux_error "Could not create temp files under /tmp"
        rm -f "$_prompt" "$_out" "$_err"
        return 1
    fi
    {
        _gh_issue_review_common_prefix
        echo ""
        _gh_issue_review_perspective_body "$_kind"
        echo ""
        if [ -n "$workdir" ]; then
            printf 'Code to check claims against: your current working directory (%s).\n\n' "$_ref"
        else
            printf 'Your current working directory may not be this repository; mark claims you cannot check UNVERIFIABLE.\n\n'
        fi
        printf -- '--- ISSUE #%s (%s) ---\n# %s\n\n%s\n' "$issue" "$repo" "$_title" "$_body"
        [ -z "$_comments" ] || printf -- '\n--- COMMENTS ---\n%s\n' "$_comments"
        printf -- '--- END ISSUE ---\n'
    } >"$_prompt"

    _gh_pr_review_run_ai "$ai" "$_prompt" "" "$_err" "$workdir" \
        "첨부 파일의 지시사항에 따라 이슈를 리뷰해줘." >"$_out" || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        rm -f "$_prompt" "$_out" "$_bodyf"
        return "$_rc"
    fi
    _reject=$(_gh_pr_review_check_output "$_out") || :
    if [ -n "$_reject" ]; then
        ux_error "External AI CLI '$ai' $_reject — no comment posted"
        echo "  full stderr saved to: $_err" >&2
        rm -f "$_prompt" "$_bodyf"
        if grep -q '[^[:space:]]' "$_out" 2>/dev/null; then
            echo "  full stdout saved to: $_out" >&2
        else
            rm -f "$_out"
        fi
        return 1
    fi

    local _tokens _elapsed
    _tokens=$(($(wc -c <"$_prompt") / 4))
    _tokens=$(((_tokens + 250) / 500 * 500))
    [ "$_tokens" -lt 1000 ] && _tokens=1000
    _elapsed=$((($(date +%s) - _start) / 60))
    _gh_issue_review_build_comment "$_bodyf" "$ai" "$_hash" "$_ref" "$_out" "$_tokens" "$_elapsed"
    rm -f "$_prompt" "$_out" "$_err"

    _why=$(_gh_issue_review_leak_check "$host" "$_bodyf") || {
        ux_error "$_why — no comment posted"
        echo "  held comment saved to: $_bodyf" >&2
        return 3
    }
    local _url
    _url=$(gh issue comment "$issue" --repo "$repo" --body-file "$_bodyf") || {
        ux_error "Posting the review comment on issue #$issue failed"
        echo "  comment body saved to: $_bodyf" >&2
        return 1
    }
    rm -f "$_bodyf"
    printf '[OK] issue #%s reviewed by %s — comment: %s\n' "$issue" "$ai" "$_url"
    return 0
}

# Interactive wrapper over the PATH executable (#2195 pattern).
gh_issue_review() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/gh_issue_review.sh "$@"
}

alias gh-issue-review='gh_issue_review'
alias gh-issue-review-help='gh_issue_review_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help gh_issue_review_help "[Development] gh-issue-review external-AI issue review"
_register_func gh_issue_review "Delegate a GitHub issue review to an external AI CLI"
