#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_review.sh
# gh-pr-review — synchronous PR review delegation to an external AI CLI.
# Sibling of gh-pr-approve (gh_pr_approve.sh) and gh-pr-reply
# (gh_pr_reply.sh). Reads the same `--ai <codex|gemini|claude>` contract
# but does a single-shot opinion-collection run inline (no worktree spawn,
# no detached worker) — the skill's only side effect is one PR comment
# unless `--no-post-comment` is set.
#
# SSOT: this file owns the Step 1 arg-parse logic, the AI CLI dispatch,
# the prompt builder, and the PR comment body builder. The matching
# claude/skills/gh-pr-review/SKILL.md delegates to gh_pr_review on
# Steps 1, 5, and 6. The bats fixture
# tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh sources this
# file so the arg-parse contract has exactly one definition.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ============================================================================
# Section 1 — Argument parser (SSOT, mirrors SKILL.md Step 1)
# ============================================================================
# `gh_pr_review_parse` prints one `key=value` line per resolved arg on
# success, writes errors to stderr. Exit codes:
#   0 — parsed ok (or help requested)
#   2 — argument error (missing --ai, unknown --ai/--review, --user with
#       non-claude --ai, missing value, unknown flag)
#
# Runtime failures (unknown claude account on the live whitelist, missing
# CLI on PATH, PR auto-detect failure) belong to the main entrypoint —
# the parser stays pure so the bats fixture can exercise it in isolation.

gh_pr_review_parse() {
    local ai=""
    local review="default"
    local user=""
    local post_comment=1
    local pr=""
    local remote="origin"

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --ai)
            if [ "$#" -lt 2 ]; then
                echo "missing value for --ai" >&2
                return 2
            fi
            ai="$2"
            shift 2
            ;;
        --ai=*)
            ai="${1#--ai=}"
            shift
            ;;
        --review)
            if [ "$#" -lt 2 ]; then
                echo "missing value for --review" >&2
                return 2
            fi
            review="$2"
            shift 2
            ;;
        --review=*)
            review="${1#--review=}"
            shift
            ;;
        --user)
            if [ "$#" -lt 2 ]; then
                echo "missing value for --user" >&2
                return 2
            fi
            user="$2"
            shift 2
            ;;
        --user=*)
            user="${1#--user=}"
            shift
            ;;
        --no-post-comment)
            post_comment=0
            shift
            ;;
        -h | --help | help)
            echo "help_requested=1"
            return 0
            ;;
        --*)
            echo "Unknown flag: $1" >&2
            return 2
            ;;
        *)
            if [ -z "$pr" ]; then
                pr="$1"
            elif [ "$remote" = "origin" ]; then
                remote="$1"
            else
                echo "Unexpected positional arg: $1" >&2
                return 2
            fi
            shift
            ;;
        esac
    done

    if [ -z "$ai" ]; then
        echo "missing required flag: --ai <codex|gemini|claude>" >&2
        return 2
    fi

    case "$ai" in
    codex | gemini | claude) ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, gemini, claude)" >&2
        return 2
        ;;
    esac

    if [ -n "$user" ] && [ "$ai" != "claude" ]; then
        echo "--user is only valid with --ai claude (codex/gemini have no multi-account routing)" >&2
        return 2
    fi

    case "$review" in
    보통) review="default" ;;
    간단) review="quick" ;;
    꼼꼼 | 꼼꼼하게) review="thorough" ;;
    보안) review="security" ;;
    성능) review="performance" ;;
    esac

    case "$review" in
    default | quick | thorough | security | performance) ;;
    *)
        cat >&2 <<EOF
Unknown --review value: '$review'
Allowed: default | quick | thorough | security | performance
Korean aliases: 보통 | 간단 | 꼼꼼 (꼼꼼하게) | 보안 | 성능
EOF
        return 2
        ;;
    esac

    echo "ai=$ai"
    echo "review=$review"
    echo "user=$user"
    echo "post_comment=$post_comment"
    echo "pr=$pr"
    echo "remote=$remote"
    return 0
}

# ============================================================================
# Section 2 — AI CLI dispatch
# ============================================================================

# _gh_pr_review_require_ai_cli — validates that the requested AI CLI is
# one of the three allowed values AND that its binary is on PATH.
# Exits 1 with `Required CLI '<name>' not found in PATH` if the binary
# is missing (matches references/ai-cli-invocation.md § "PATH pre-flight").
# Exits 2 with `Unknown --ai value: '...'` if the value is unknown.
_gh_pr_review_require_ai_cli() {
    local ai="$1"
    case "$ai" in
    codex | gemini | claude) ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, gemini, claude)" >&2
        return 2
        ;;
    esac
    if ! command -v "$ai" >/dev/null 2>&1; then
        echo "Required CLI '$ai' not found in PATH" >&2
        return 1
    fi
    return 0
}

# _gh_pr_review_resolve_claude_account — for --ai claude --user <name>,
# loads the claude integration helper (`_claude_resolve_account`) and
# returns the resolved CLAUDE_CONFIG_DIR on stdout. Exits 1 with the
# canonical "Unknown claude account" line on unknown names.
_gh_pr_review_resolve_claude_account() {
    local user="$1"
    if ! command -v _claude_resolve_account >/dev/null 2>&1; then
        local _helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/integrations/claude.sh"
        # shellcheck disable=SC1090
        [ -f "$_helper" ] && . "$_helper"
    fi
    if ! command -v _claude_resolve_account >/dev/null 2>&1; then
        echo "claude account routing helper not available — load shell-common/tools/integrations/claude.sh" >&2
        return 1
    fi
    local _cfg
    if ! _cfg=$(_claude_resolve_account "$user" 2>/dev/null); then
        local _allowed
        _allowed=$(_claude_resolve_account --list 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        echo "Unknown claude account: '$user' (allowed: $_allowed)" >&2
        return 1
    fi
    printf '%s\n' "$_cfg"
    return 0
}

# _gh_pr_review_stderr_is_noise — returns 0 (true) when a stderr line is
# known informational/startup output from one of the supported CLIs, not
# an actual failure cause. Keeps the noise list explicit so future CLI
# updates can extend it without rewriting the dispatcher.
_gh_pr_review_stderr_is_noise() {
    case "$1" in
    "Reading prompt from stdin"*) return 0 ;; # codex exec startup banner
    "Loaded prompt"*) return 0 ;;             # codex exec follow-up banner
    "") return 0 ;;                           # blank line
    esac
    return 1
}

# _gh_pr_review_run_ai — pipes PROMPT_FILE into the chosen AI CLI per
# references/ai-cli-invocation.md. Returns the CLI's exit code. On
# non-zero exit, prints the full captured stderr (indented) to the
# caller's stderr AND keeps the temp stderr file at a predictable path
# so the user can re-inspect it. On zero exit, the stderr file is
# cleaned up automatically.
#
# Issue #694:
#   - Bug A — `gemini -p` requires a string argument (yargs). Read the
#     prompt into a variable so the CLI sees a valid positional value.
#   - Bug B — `head -n 1` of stderr surfaced informational banners
#     (e.g. codex's "Reading prompt from stdin...") as the failure
#     reason. The dispatcher now skips known-noise prefixes when
#     building the one-line summary AND emits the full stderr below it.
#
# Args: $1 = ai (codex|gemini|claude), $2 = PROMPT_FILE, $3 = optional
# CLAUDE_CONFIG_DIR (claude --user routing). Stdout of the CLI streams to
# the caller's stdout; stderr is captured for the failure summary.
_gh_pr_review_run_ai() {
    local ai="$1"
    local prompt_file="$2"
    local cfg_dir="${3:-}"
    # Predictable path so the user can re-read it after a failure.
    local _stderr_file="/tmp/gh-pr-review-stderr.$$.$ai.log"
    : >"$_stderr_file"
    local _rc=0
    case "$ai" in
    codex)
        codex exec --color=never <"$prompt_file" 2>"$_stderr_file" || _rc=$?
        ;;
    gemini)
        # `gemini -p` is non-interactive headless mode and REQUIRES a
        # string argument (yargs) — `gemini -p <file` raises "Not enough
        # arguments following: p". Slurp the prompt and pass it on argv.
        # The inline path keeps prompts well under ARG_MAX (~128 KB on
        # Linux); large diffs (≥ 800 additions+deletions) go through the
        # subagent delegation path before reaching this function.
        local _gemini_prompt
        _gemini_prompt=$(cat "$prompt_file")
        gemini -p "$_gemini_prompt" 2>"$_stderr_file" || _rc=$?
        ;;
    claude)
        if [ -n "$cfg_dir" ]; then
            CLAUDE_CONFIG_DIR="$cfg_dir" claude -p <"$prompt_file" 2>"$_stderr_file" || _rc=$?
        else
            claude -p <"$prompt_file" 2>"$_stderr_file" || _rc=$?
        fi
        ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, gemini, claude)" >&2
        rm -f "$_stderr_file"
        return 2
        ;;
    esac
    if [ "$_rc" -ne 0 ]; then
        # Find the first stderr line that is NOT a known informational
        # banner. Falls back to the literal first line so an unknown
        # CLI startup message still produces something.
        local _summary="" _line
        while IFS= read -r _line; do
            if ! _gh_pr_review_stderr_is_noise "$_line"; then
                _summary="$_line"
                break
            fi
        done <"$_stderr_file"
        if [ -z "$_summary" ]; then
            _summary=$(head -n 1 "$_stderr_file" 2>/dev/null)
        fi
        echo "External AI CLI '$ai' failed (exit $_rc): ${_summary:-<no stderr>}" >&2
        echo "  full stderr saved to: $_stderr_file" >&2
        echo "  --- stderr (last 20 lines) ---" >&2
        tail -n 20 "$_stderr_file" 2>/dev/null | sed 's/^/  /' >&2
        echo "  --- end stderr ---" >&2
        # Intentionally do NOT rm — leave the file for the user.
        return "$_rc"
    fi
    rm -f "$_stderr_file"
    return 0
}

# ============================================================================
# Section 3 — Prompt builder
# ============================================================================
# Bodies are copied verbatim from
# claude/skills/gh-pr-review/references/review-presets.md so the shell
# entrypoint and the SKILL agree on the exact prompt every CLI sees.

_gh_pr_review_common_prefix() {
    cat <<'EOF'
You are reviewing a GitHub pull request as a second-opinion reviewer.
You DO NOT submit a decision (no approve / request-changes) — the
human and the primary reviewer handle that. Your job is to surface
specific, actionable findings.

Classification (use these exact labels for every finding):
  - BLOCKER   — would break or regress if merged as-is.
  - FOLLOW-UP — non-blocking quality issue worth tracking.
  - PRAISE    — concrete diff location worth highlighting.

Format (one line per finding):
  [BLOCKER|FOLLOW-UP|PRAISE] <path>:<line> — <one-sentence reason>

Reply in the dominant language of the PR diff (Korean if the diff is
Korean-dominant, otherwise English). Be concise; no preamble; do not
restate the diff.
EOF
}

_gh_pr_review_preset_body() {
    case "$1" in
    default)
        cat <<'EOF'
Review across 7 dimensions in balance. Skip categories the diff does
not exercise. Flag concrete file:line items only.

1. Correctness — does the code do what the PR title/body claims?
2. Conventions — naming, file location, error-handling idioms match
   surrounding code (CLAUDE.md / AGENTS.md if present).
3. Security — input validation, shell-injection, hardcoded secrets,
   unsafe eval, missing authn/z.
4. Performance — N+1, unnecessary I/O in hot loops, missing caching.
5. Tests — new paths covered? Absence of tests for new logic is usually
   a BLOCKER.
6. Docs / comments — public API changes without doc updates, stale
   references, lies in comments.
7. Backward compatibility — breaking API/CLI/config changes flagged?
   Migration path documented?
EOF
        ;;
    quick)
        cat <<'EOF'
Quick first-pass scan. ONLY surface BLOCKER findings — items that
would break or regress if merged as-is. Skip PRAISE entirely. Limit
FOLLOW-UP to at most 2 items where the harm is obvious.

Focus on:
- Correctness regressions (logic bugs, off-by-one, wrong condition).
- Security (shell injection, hardcoded secrets, unsafe eval, missing
  input validation).

Do NOT flag style, naming, or doc nits — those belong in a thorough
pass. Target output length: under 200 words.
EOF
        ;;
    thorough)
        cat <<'EOF'
Deep-dive review. Cover the 7 dimensions from the default preset, AND
add:

8. Architecture trade-offs — does the chosen abstraction fit the
   problem? Are there cheaper alternatives that achieve the same goal?
9. Test coverage gaps — which branches/edge cases are not exercised
   even when there ARE tests? Be specific: list the missing scenarios.
10. Adjacent-system impact — what other modules / scripts / docs
    depend on changed surface area? Are those callers updated?
11. Migration / rollout — if behavior changes silently, how would a
    user notice? Is there a feature flag or version gate?

Be exhaustive. PRAISE concrete diff locations worth highlighting.
EOF
        ;;
    security)
        cat <<'EOF'
Security-focused review. Other dimensions are out of scope for THIS
invocation — the caller will run a separate review for correctness,
performance, etc.

Look for:
- Injection (shell, SQL, command, prompt) at any user-controlled input.
- Hardcoded secrets, tokens, credentials in code, tests, or examples.
- Authn/authz — missing checks, broken access control, privilege
  escalation paths.
- Supply chain — new dependencies, pinned versions, install-script
  integrity (signed-by, checksums).
- Data handling — PII logging, unredacted error messages, insecure
  defaults.
- Crypto — homerolled primitives, weak algorithms, missing nonce/IV.
- Race conditions on filesystem (TOCTOU), env var injection, signal
  handling.

Classify each finding as BLOCKER (exploitable) or FOLLOW-UP (defense
in depth). PRAISE specific security-positive patterns when present.
EOF
        ;;
    performance)
        cat <<'EOF'
Performance-focused review. Other dimensions are out of scope for
THIS invocation — the caller will run a separate review for
correctness, security, etc.

Look for:
- N+1 patterns (DB, API, filesystem).
- Unnecessary I/O inside hot loops (fork, exec, network, disk).
- Allocation hotspots — repeated string concatenation, large buffers
  in loops, missing pre-sizing.
- Missing caching on expensive idempotent calls.
- Synchronous calls that should be batched / pipelined.
- Algorithmic complexity worse than necessary (O(n²) where O(n log n)
  fits, etc.).

Quantify when possible: "executes ~N times per request" or "scales
linearly with X". Flag only concrete wins — avoid premature
optimization theatre. Classify each finding as BLOCKER (production
hot path) or FOLLOW-UP (visible only at scale).
EOF
        ;;
    *)
        echo "Unknown preset: '$1'" >&2
        return 2
        ;;
    esac
}

# _gh_pr_review_build_prompt — writes `<prefix>\n\n<preset>\n\n<diff>`
# to the given file. Args: $1 = preset, $2 = output file, $3 = pr_number,
# $4 = target_repo, $5 = base_ref, $6 = head_ref. The diff is fetched
# with `gh pr diff`; the function does not enforce a size gate (the
# SKILL still controls the large-diff delegation path in Step 4).
_gh_pr_review_build_prompt() {
    local preset="$1"
    local out="$2"
    local pr="$3"
    local repo="$4"
    local base="${5:-?}"
    local head="${6:-?}"

    {
        _gh_pr_review_common_prefix
        echo ""
        _gh_pr_review_preset_body "$preset" || return $?
        echo ""
        printf -- '--- PR DIFF (PR #%s, repo %s, base %s → head %s) ---\n' \
            "$pr" "$repo" "$base" "$head"
        gh pr diff "$pr" --repo "$repo" 2>/dev/null || true
        printf -- '--- END PR DIFF ---\n'
    } >"$out"
}

# ============================================================================
# Section 4 — PR comment body builder + post
# ============================================================================
# Mirrors references/post-comment.md verbatim. The `<details>` wrappers
# and the `<!-- ai-review:* -->` / `<!-- ai-metrics:gh-pr-review -->`
# markers are the SSOT for cross-skill ai-metrics aggregation.

# Per-preset baseline human-review time (hours). Defaults from
# references/post-comment.md § "Human time baseline".
_gh_pr_review_human_h() {
    case "$1" in
    quick) echo "0.3" ;;
    default) echo "1.0" ;;
    thorough) echo "2.5" ;;
    security) echo "1.5" ;;
    performance) echo "1.5" ;;
    *) echo "1.0" ;;
    esac
}

# 4-bytes-per-token heuristic, rounded to nearest 500, floor 1000.
# Args: $1 = path to PROMPT_FILE.
_gh_pr_review_estimate_tokens() {
    local f="$1"
    local raw tokens
    raw=$(wc -c <"$f" 2>/dev/null || echo 0)
    tokens=$((raw / 4))
    tokens=$(((tokens + 250) / 500 * 500))
    [ "$tokens" -lt 1000 ] && tokens=1000
    echo "$tokens"
}

# Builds the PR comment body to the given output file. Args: $1 = output
# file, $2 = AI name, $3 = preset, $4 = path to AI stdout, $5 = tokens,
# $6 = human_h, $7 = elapsed_min. The verbatim AI stdout is inlined
# between `<!-- ai-review:* -->` markers; the metrics footer follows
# the dotfiles SSOT (#317 / PR #320 / #367).
_gh_pr_review_build_comment_body() {
    local out="$1"
    local ai="$2"
    local preset="$3"
    local ai_out="$4"
    local tokens="$5"
    local human_h="$6"
    local elapsed="$7"

    {
        printf '<details>\n'
        printf '<summary>🤖 AI Review · %s · --review=%s</summary>\n\n' "$ai" "$preset"
        printf '<!-- ai-review:%s -->\n' "$ai"
        cat "$ai_out"
        printf '\n<!-- /ai-review:%s -->\n\n' "$ai"
        printf '</details>\n\n'
        printf -- '---\n'
        printf '<details>\n'
        printf '<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n' \
            "$tokens" "$human_h" "$elapsed"
        printf '<!-- ai-metrics:gh-pr-review -->\n'
        printf '📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n' "$tokens" "$human_h" "$elapsed"
        printf '<!-- /ai-metrics:gh-pr-review -->\n\n'
        printf '</details>\n'
    } >"$out"
}

# _gh_pr_review_post_comment — wraps `gh pr comment --body-file`. Honors
# the two skip paths from SKILL.md Step 6: `--no-post-comment` (post=0)
# and `GH_DISABLE_AI_METRICS=1`. On gh failure the function prints the
# canonical `[WARN] PR comment post failed` line and returns 0 so the
# overall flow stays soft-fail.
#
# Args: $1 = pr_number, $2 = target_repo, $3 = body_file, $4 = post_flag
# (1=on, 0=off). Echoes one of: "<url>", "skipped (--no-post-comment)",
# "skipped (GH_DISABLE_AI_METRICS=1)", "[WARN] post failed".
_gh_pr_review_post_comment() {
    local pr="$1"
    local repo="$2"
    local body_file="$3"
    local post="${4:-1}"

    if [ "$post" = "0" ]; then
        echo "skipped (--no-post-comment)"
        return 0
    fi
    if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
        echo "skipped (GH_DISABLE_AI_METRICS=1)"
        return 0
    fi
    local _url
    if _url=$(gh pr comment "$pr" --repo "$repo" --body-file "$body_file" 2>&1); then
        printf '%s\n' "$_url"
        return 0
    fi
    echo "[WARN] PR comment post failed — output retained on stdout" >&2
    echo "[WARN] post failed"
    return 0
}

# ============================================================================
# Section 5 — PR resolution + pre-flight
# ============================================================================

# _gh_pr_review_parse_remote_url — extracts `owner/repo` from a github
# remote URL. Accepts both forms produced by `git remote get-url`:
#
#   https://github.com/owner/repo.git
#   git@github.com:owner/repo.git
#   ssh://git@github.com/owner/repo.git
#   git+https://github.com/owner/repo
#
# Prints `owner/repo` to stdout and returns 0 on success. Returns 1 with
# an error message on stderr when the URL is not a github remote or the
# extracted value does not match the `owner/repo` shape.
#
# Issue #694 Bug C — the previous code called `gh repo view` without
# `-R <url>`, so the user-supplied `<remote>` argument was silently
# ignored and the real `gh` error was swallowed by `2>/dev/null`.
# Splitting URL parsing into a pure-shell helper makes the contract
# bats-testable and removes the network dependency from the resolution
# step entirely.
_gh_pr_review_parse_remote_url() {
    local _url="${1:-}"
    if [ -z "$_url" ]; then
        echo "empty remote URL" >&2
        return 1
    fi
    case "$_url" in
    *github.com*) ;;
    *)
        echo "remote URL is not a github.com remote: $_url" >&2
        return 1
        ;;
    esac
    local _slug
    # Strip everything up to and including `github.com[:/]`, then drop a
    # trailing `.git`. Works for https://, git@host:, ssh:// and the
    # rarer git+https:// prefix because they all converge on github.com.
    _slug=$(printf '%s' "$_url" | sed -E 's#^.*github\.com[:/]+##; s#\.git/?$##; s#/$##')
    if ! printf '%s' "$_slug" | grep -qE '^[^/[:space:]]+/[^/[:space:]]+$'; then
        echo "Could not parse owner/repo from remote URL: $_url" >&2
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}

# _gh_pr_review_resolve_target_repo — given a remote name in the current
# git repo, returns `owner/repo` by consulting `git remote get-url` and
# parsing the URL. On failure prints the actionable cause to stderr
# (which remote was tried, the URL value if any) and returns 1. Network
# round-trips are avoided entirely; gh's auth state and default-repo
# cache no longer affect this step (Bug C from issue #694).
_gh_pr_review_resolve_target_repo() {
    local _remote="${1:-origin}"
    local _url
    if ! _url=$(git remote get-url "$_remote" 2>&1); then
        echo "Remote '$_remote' not found in this repo:" >&2
        echo "  git remote get-url '$_remote' → $_url" >&2
        git remote -v >&2
        return 1
    fi
    local _slug
    if ! _slug=$(_gh_pr_review_parse_remote_url "$_url"); then
        echo "  remote='$_remote' url='$_url'" >&2
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}

_gh_pr_review_resolve_pr_number() {
    # Echoes the PR number; non-zero exit if neither arg nor branch resolves.
    local explicit="${1:-}"
    if [ -n "$explicit" ]; then
        printf '%s\n' "$explicit"
        return 0
    fi
    local pr
    if ! pr=$(gh pr view --json number -q .number 2>/dev/null); then
        echo "No PR found for current branch; pass PR number explicitly" >&2
        return 1
    fi
    if [ -z "$pr" ]; then
        echo "No PR found for current branch; pass PR number explicitly" >&2
        return 1
    fi
    printf '%s\n' "$pr"
}

# _gh_pr_review_fetch_meta — one-shot fetch of every PR field the main
# entrypoint needs (state, isDraft, baseRefName, headRefName). One
# network round-trip beats four. The raw JSON is echoed verbatim so the
# caller can extract whichever subset it cares about; on fetch failure
# (network blip, no permission, deleted PR) it returns 1 with the raw
# `gh` stderr suppressed — the caller surfaces the user-facing error.
_gh_pr_review_fetch_meta() {
    local pr="$1" repo="$2"
    gh pr view "$pr" --repo "$repo" \
        --json state,isDraft,baseRefName,headRefName 2>/dev/null
}

# _gh_pr_review_preflight_pr_state — pure-shell gate on pre-fetched
# metadata. Decoupled from the `gh` call so the consolidation in
# `_gh_pr_review_fetch_meta` stays a single round-trip. CI status is
# intentionally NOT checked (opinion collection works on red CI too).
#
# Args: $1 = pr_number, $2 = state, $3 = isDraft ("true"/"false"/empty).
_gh_pr_review_preflight_pr_state() {
    local pr="$1" state="$2" draft="$3"
    case "$state" in
    OPEN) ;;
    "")
        echo "PR #$pr could not be fetched (empty state)" >&2
        return 1
        ;;
    *)
        echo "PR #$pr is $state; aborting" >&2
        return 1
        ;;
    esac
    if [ "$draft" = "true" ]; then
        echo "PR #$pr is DRAFT; aborting" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# Section 6 — Help + main entrypoint
# ============================================================================

gh_pr_review_help() {
    # The hyphenated alias is the canonical user-facing command name;
    # the help text mirrors claude/skills/gh-pr-review/references/help.md
    # so `gh-pr-review -h` and `/gh-pr-review help` produce equivalent
    # surface area.
    cat <<'EOF'
gh-pr-review — delegate a GitHub PR's review to an external AI CLI
for a second opinion. Streams the AI's findings to stdout and posts
them as a PR comment by default. Does NOT submit a decision.

Usage:
  gh-pr-review --ai <codex|gemini|claude> [flags] [<pr-number>] [<remote>]
  gh-pr-review -h | --help | help

Flags:
  --ai <codex|gemini|claude>   required; external CLI to delegate to
  --review <preset>            default 'default'; KR aliases supported
                               enum: default | quick | thorough |
                                     security | performance
                               KR:   보통 | 간단 | 꼼꼼 (꼼꼼하게) |
                                     보안 | 성능
  --user <name>                claude only; multi-account routing via
                               _claude_resolve_account
  --no-post-comment            skip the PR comment; stdout only

Positional:
  <pr-number>                  optional — auto-detect from current
                               branch via `gh pr view`
  <remote>                     default 'origin'

Examples:
  gh-pr-review --ai codex 99
  gh-pr-review --ai gemini --review thorough 99
  gh-pr-review --ai claude --review 꼼꼼 99
  gh-pr-review --ai claude --user work 99
  gh-pr-review --ai codex --no-post-comment 99
  gh-pr-review --ai codex 99 upstream

Exit codes:
  0 — review completed (or comment soft-failed but stdout has output)
  1 — runtime failure (missing CLI, unknown claude user, PR fetch
      failed, external CLI returned non-zero, gh not authenticated)
  2 — argument error (missing --ai, unknown --ai/--review, --user with
      non-claude --ai)
EOF
}

# gh_pr_review — orchestrator. Maps SKILL.md Steps 1–7 to this function.
gh_pr_review() {
    # zsh compatibility — keep the rest of the function POSIX-shaped.
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
    "" | -h | --help | help)
        gh_pr_review_help
        return 0
        ;;
    esac

    local START_TS
    START_TS=$(date +%s)

    # ---- Step 1: parse args ----
    local _parsed
    if ! _parsed=$(gh_pr_review_parse "$@"); then
        return $?
    fi
    if printf '%s\n' "$_parsed" | grep -q '^help_requested=1$'; then
        gh_pr_review_help
        return 0
    fi

    local ai="" review="" user="" post_comment="" pr="" remote=""
    # Read each `key=value` line into the matching local. The keys are
    # a fixed allow-list (ai/review/user/post_comment/pr/remote); any
    # other key is silently ignored. `eval "$_parsed"` would be shorter
    # but would let a shell metacharacter inside a user-supplied value
    # (e.g. `--review "$(rm -rf …)"`) execute — the `while read` loop
    # treats each value as data, not code.
    local _k _v
    while IFS='=' read -r _k _v; do
        case "$_k" in
        ai) ai="$_v" ;;
        review) review="$_v" ;;
        user) user="$_v" ;;
        post_comment) post_comment="$_v" ;;
        pr) pr="$_v" ;;
        remote) remote="$_v" ;;
        esac
    done <<EOF
$_parsed
EOF

    # ---- Step 2: pre-flight ----
    if ! command -v gh >/dev/null 2>&1; then
        echo "Required CLI 'gh' not found in PATH" >&2
        return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        echo "Required CLI 'git' not found in PATH" >&2
        return 1
    fi
    if ! _gh_pr_review_require_ai_cli "$ai"; then
        return $?
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "gh CLI not authenticated; run 'gh auth login'" >&2
        return 1
    fi

    # Resolve target repo by parsing the user-supplied remote's URL
    # directly. Bypasses `gh repo view`'s default-repo auto-detection —
    # the user-supplied `$remote` arg now actually controls the lookup
    # (issue #694 Bug C). Helper writes the actionable failure (which
    # remote, which URL) to stderr on its own; no `2>/dev/null` to
    # swallow the real cause.
    local TARGET_REPO
    if ! TARGET_REPO=$(_gh_pr_review_resolve_target_repo "$remote"); then
        return 1
    fi

    # Resolve PR number — explicit arg wins, otherwise auto-detect.
    local PR_NUMBER
    if ! PR_NUMBER=$(_gh_pr_review_resolve_pr_number "$pr"); then
        return 1
    fi

    # One consolidated `gh pr view` fetches state + isDraft + base/head
    # refs in a single round-trip; the preflight gate and the diff
    # header below both consume this single JSON blob (Rule 19 — fewer
    # process forks, fewer network calls).
    local _meta state isDraft base head
    _meta=$(_gh_pr_review_fetch_meta "$PR_NUMBER" "$TARGET_REPO")
    if [ -z "$_meta" ]; then
        echo "PR #$PR_NUMBER could not be fetched from $TARGET_REPO" >&2
        return 1
    fi
    state=$(printf '%s' "$_meta" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
    isDraft=$(printf '%s' "$_meta" | sed -n 's/.*"isDraft":\(true\|false\).*/\1/p')
    base=$(printf '%s' "$_meta" | sed -n 's/.*"baseRefName":"\([^"]*\)".*/\1/p')
    head=$(printf '%s' "$_meta" | sed -n 's/.*"headRefName":"\([^"]*\)".*/\1/p')

    if ! _gh_pr_review_preflight_pr_state "$PR_NUMBER" "$state" "$isDraft"; then
        return 1
    fi

    # Resolve claude account up front so an unknown name fails before
    # the (potentially long) AI CLI invocation.
    local CFG_DIR=""
    if [ "$ai" = "claude" ] && [ -n "$user" ]; then
        if ! CFG_DIR=$(_gh_pr_review_resolve_claude_account "$user"); then
            return 1
        fi
    fi

    # ---- Step 3 + 4: build prompt + diff into a temp file ----
    local PROMPT_FILE BODY_FILE AI_OUT
    PROMPT_FILE=$(mktemp 2>/dev/null) || PROMPT_FILE="/tmp/gh-pr-review-prompt.$$"
    AI_OUT=$(mktemp 2>/dev/null) || AI_OUT="/tmp/gh-pr-review-out.$$"
    BODY_FILE=$(mktemp 2>/dev/null) || BODY_FILE="/tmp/gh-pr-review-body.$$"

    if ! _gh_pr_review_build_prompt "$review" "$PROMPT_FILE" \
        "$PR_NUMBER" "$TARGET_REPO" "${base:-?}" "${head:-?}"; then
        rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE"
        return 1
    fi

    # ---- Step 5: dispatch external AI CLI ----
    # Tee CLI stdout: stream to the user's terminal verbatim AND capture
    # it for the PR comment body. `set -o pipefail` is scoped to this
    # subshell so a non-zero exit from `_gh_pr_review_run_ai` propagates
    # past the trailing `tee`; without it the pipeline always inherits
    # tee's (usually 0) exit code and the failure branch never runs.
    if ! (
        set -o pipefail
        _gh_pr_review_run_ai "$ai" "$PROMPT_FILE" "$CFG_DIR" | tee "$AI_OUT"
    ); then
        local _rc=$?
        rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE"
        return "$_rc"
    fi

    # ---- Step 6: post PR comment ----
    local TOKENS HUMAN_H ELAPSED
    TOKENS=$(_gh_pr_review_estimate_tokens "$PROMPT_FILE")
    HUMAN_H=$(_gh_pr_review_human_h "$review")
    ELAPSED=$((($(date +%s) - START_TS) / 60))

    _gh_pr_review_build_comment_body "$BODY_FILE" "$ai" "$review" "$AI_OUT" \
        "$TOKENS" "$HUMAN_H" "$ELAPSED"

    local COMMENT_RESULT
    COMMENT_RESULT=$(_gh_pr_review_post_comment "$PR_NUMBER" "$TARGET_REPO" \
        "$BODY_FILE" "$post_comment")

    # ---- Step 7: report ----
    printf '[OK] PR #%s reviewed by %s (--review=%s) — comment: %s\n' \
        "$PR_NUMBER" "$ai" "$review" "$COMMENT_RESULT"

    rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE"
    return 0
}

# ============================================================================
# Aliases — hyphenated command names per shell-common convention
# ============================================================================

alias gh-pr-review='gh_pr_review'
alias gh-pr-review-help='gh_pr_review_help'
