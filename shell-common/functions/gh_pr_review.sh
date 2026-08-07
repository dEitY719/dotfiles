#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_review.sh
# gh-pr-review — synchronous PR review delegation to an external AI CLI.
# Sibling of gh-pr-approve (gh_pr_approve.sh) and gh-pr-reply
# (gh_pr_reply.sh). Reads the same `--ai <codex|agy|claude>` contract
# but does a single-shot opinion-collection run inline (no worktree spawn,
# no detached worker) — the skill's only side effect is one PR comment
# unless `--no-post-comment` is set.
#
# SSOT: this file owns the Step 1 arg-parse logic, the AI CLI dispatch,
# the prompt builder, and the PR comment body builder. The matching
# claude/skills/gh-pr-review/SKILL.md delegates to gh_pr_review on
# Steps 1, 4 (PROMPT_FILE path allocation only), 5, and 6. The bats fixture
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
        echo "missing required flag: --ai <codex|agy|claude>" >&2
        return 2
    fi

    case "$ai" in
    codex | agy | claude) ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, agy, claude)" >&2
        return 2
        ;;
    esac

    if [ -n "$user" ] && [ "$ai" != "claude" ]; then
        echo "--user is only valid with --ai claude (codex/agy have no multi-account routing)" >&2
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

    printf '%s\n' \
        "ai=$ai" \
        "review=$review" \
        "user=$user" \
        "post_comment=$post_comment" \
        "pr=$pr" \
        "remote=$remote"
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
    codex | agy | claude) ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, agy, claude)" >&2
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

# _gh_pr_review_mktemp_safe — SSOT for temp-path allocation in this module.
# Args: $1 = mktemp template ending in `XXXXXX` (e.g. /tmp/foo.XXXXXX).
# Prints the allocated path on stdout and returns 0; prints nothing and
# returns 1 when no path could be allocated safely.
#
# Issue #1283: the old call sites fell back to a bare `$$`-suffixed path
# whenever mktemp failed (unwritable /tmp, quota) and later wrote to it
# with a plain `>` redirect. A local attacker who guesses the PID can
# pre-plant a symlink there and have that redirect clobber whatever the
# link points at. The fallback here creates the path under `set -C`
# (noclobber) in a subshell, which opens with O_CREAT|O_EXCL: a
# pre-existing file *or* symlink makes the create fail, and the caller
# aborts instead of writing through it. A genuine PID-reuse collision
# fails the same way, which is the safe outcome.
_gh_pr_review_mktemp_safe() {
    local _template="$1"
    # Fallback is derived from the template so the two can never drift:
    # strip the mktemp placeholder, append this shell's PID.
    local _fallback="${_template%XXXXXX}$$"
    local _path
    if _path=$(mktemp "$_template" 2>/dev/null) && [ -n "$_path" ]; then
        printf '%s\n' "$_path"
        return 0
    fi
    if (
        set -C
        # `mktemp` always creates 0600; a plain `>` redirect instead honours
        # the caller's ambient umask, so under the common `022` the prompt /
        # AI-output / comment-body temp files would be world-readable to
        # other local users (codex review, PR #1284). Tighten inside the
        # subshell so the caller's umask is left untouched.
        umask 077
        : >"$_fallback"
    ) 2>/dev/null; then
        printf '%s\n' "$_fallback"
        return 0
    fi
    return 1
}

# _gh_pr_review_mktemp_prompt — lane-discriminated unique prompt-file path.
# SSOT for PROMPT_FILE naming (issue #1276). Mirrors the `$ai`-discriminated
# mktemp template used for the stderr file in _gh_pr_review_run_ai: the
# `XXXXXX` suffix avoids the predictable-PID symlink-attack class, and the
# `$ai` + PR discriminators keep parallel lanes apart. devx:pr-review-all
# dispatches agy and codex as separate subagents in the same turn — a shared
# or hardcoded prompt path lets one lane clobber the other's prompt, so both
# CLIs review byte-identical input and the run silently false-passes.
# Args: $1 = ai (codex|agy|claude), $2 = PR number (for debuggability).
# Prints a path on stdout; returns non-zero and prints nothing when no
# path could be allocated safely (see _gh_pr_review_mktemp_safe for the
# noclobber fallback), so this stays the single place that knows the
# PROMPT_FILE naming template.
# Both args are sanitized to `[A-Za-z0-9_-]` before touching the path —
# an unvalidated PR token (e.g. containing `/`) could otherwise steer
# the mktemp template outside /tmp (codex review, PR #1282 / issue #1276).
_gh_pr_review_mktemp_prompt() {
    local ai pr
    ai=$(printf '%s' "${1:-unknown}" | tr -cd 'A-Za-z0-9_-')
    pr=$(printf '%s' "${2:-0}" | tr -cd 'A-Za-z0-9_-')
    [ -n "$ai" ] || ai="unknown"
    [ -n "$pr" ] || pr="0"
    _gh_pr_review_mktemp_safe "/tmp/gh-pr-review-prompt.$ai.$pr.XXXXXX"
}

# _gh_pr_review_run_ai — pipes PROMPT_FILE into the chosen AI CLI per
# references/ai-cli-invocation.md. Returns the CLI's exit code. On
# non-zero exit, prints the full captured stderr (indented) to the
# caller's stderr AND keeps the temp stderr file at a predictable path
# so the user can re-inspect it. On zero exit, the stderr file is
# cleaned up automatically.
#
# Issue #694:
#   - Bug B — `head -n 1` of stderr surfaced informational banners
#     (e.g. codex's "Reading prompt from stdin...") as the failure
#     reason. The dispatcher now skips known-noise prefixes when
#     building the one-line summary AND emits the full stderr below it.
#
# Args: $1 = ai (codex|agy|claude), $2 = PROMPT_FILE, $3 = optional
# CLAUDE_CONFIG_DIR (claude --user routing), $4 = optional pre-allocated
# stderr temp path. Stdout of the CLI streams to the caller's stdout;
# stderr is captured for the failure summary.
_gh_pr_review_run_ai() {
    local ai="$1"
    local prompt_file="$2"
    local cfg_dir="${3:-}"
    # Temp path comes from `_gh_pr_review_mktemp_safe`, this module's SSOT
    # allocator (issue #1283): mktemp first, then a noclobber fallback that
    # refuses a pre-planted symlink or regular file instead of writing
    # through it. Routed through the helper for consistency with the other
    # three call sites (PROMPT_FILE / AI_OUT / BODY_FILE) — issue #1286.
    # The `$ai` discriminator stays in the name so the user can grep for
    # "the agy run" vs "the codex run" when several invocations linger
    # after failures.
    #
    # Issue #1294: when $4 is given the *caller* already allocated the path
    # (same allocator, same template). A self-allocated path is a local of
    # this function, so gh_pr_review's INT/TERM handler cannot see it and a
    # Ctrl-C during the CLI run leaks it into /tmp. Callers that care hand
    # the path down so it sits in the handler's `rm -f` list; the
    # self-allocating branch stays for direct callers (and tests).
    local _stderr_file="${4:-}"
    if [ -z "$_stderr_file" ] &&
        ! _stderr_file=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-stderr.$ai.XXXXXX"); then
        echo "Could not create stderr temp file under /tmp" >&2
        return 1
    fi
    local _rc=0
    local _prompt_size
    local _prompt_content
    case "$ai" in
    codex)
        codex exec --color=never <"$prompt_file" 2>"$_stderr_file" || _rc=$?
        ;;
    agy)
        # `agy --print` runs the Antigravity CLI non-interactively but
        # takes the prompt as a value argument, not stdin. The kernel caps
        # a single argv string at MAX_ARG_STRLEN (32 pages = 131072 bytes
        # on Linux) — a large PR diff would blow past that as a bare
        # "Argument list too long" exec failure, so guard it explicitly.
        _prompt_size=$(wc -c <"$prompt_file")
        if [ "$_prompt_size" -ge 131072 ]; then
            printf 'agy --print: prompt is %s bytes, over the %s-byte argv limit (MAX_ARG_STRLEN) — use --ai codex or --ai claude for this PR instead.\n' \
                "$_prompt_size" 131072 >"$_stderr_file"
            _rc=1
        elif ! _prompt_content=$(cat "$prompt_file" 2>"$_stderr_file"); then
            _rc=1
        else
            agy --print "$_prompt_content" 2>>"$_stderr_file" || _rc=$?
        fi
        ;;
    claude)
        if [ -n "$cfg_dir" ]; then
            CLAUDE_CONFIG_DIR="$cfg_dir" claude -p <"$prompt_file" 2>"$_stderr_file" || _rc=$?
        else
            claude -p <"$prompt_file" 2>"$_stderr_file" || _rc=$?
        fi
        ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, agy, claude)" >&2
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

Adopt a critical, skeptical stance. Do not rubber-stamp. Actively
look for weak assumptions, missing edge cases, and alternative
approaches the PR did not consider.

Classification (use these exact labels for every finding):
  - BLOCKER   — would break or regress if merged as-is.
  - FOLLOW-UP — non-blocking quality issue worth tracking.
  - PRAISE    — concrete diff location worth highlighting.

Format (one line per finding):
  [BLOCKER|FOLLOW-UP|PRAISE] <path>:<line> — <one-sentence reason>

Assumption check (mandatory): identify at least one assumption in the
PR that is treated as obviously correct but is actually questionable
(a design choice, a claim in the description, an "obviously safe"
change). State it as one line: "Assumption: <what> — <why it's
questionable>". If you genuinely find none after actively looking,
say so explicitly: "Assumption: none found."

Verdict (mandatory, last line): a single overall call on the PR —
  판정: [LGTM|우려있음|블로킹]        (Korean-dominant diff)
  Verdict: [LGTM|CONCERNS|BLOCKING]  (English-dominant diff)

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
    printf '%s\n' "$tokens"
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
    printf '%s\n' "[WARN] PR comment post failed — output retained on stdout" >&2
    printf '%s\n' "[WARN] post failed"
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
    # Issue #703 — the parser used to be `github.com`-only, which made
    # /gh-pr-reply, /gh-pr-approve and /gh-pr-review reject GHE remotes
    # on the `internal` PC. Delegating to the SSOT helper in
    # shell-common/functions/gh_host.sh keeps both hosts working while
    # leaving this function's call sites untouched.
    # shellcheck disable=SC1091
    . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_host.sh"
    _gh_parse_owner_repo_url "$@"
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
  gh-pr-review --ai <codex|agy|claude> [flags] [<pr-number>] [<remote>]
  gh-pr-review -h | --help | help

Flags:
  --ai <codex|agy|claude>      required; external CLI to delegate to
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
  gh-pr-review --ai agy --review thorough 99
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
  130 — interrupted (Ctrl-C / SIGINT or SIGTERM); temp files are
      removed and no PR comment is posted
EOF
}

# _gh_pr_review_disarm_trap — shared by every INT/TERM exit path inside
# gh_pr_review (the trap body itself included) so the disarm-and-restore
# pair lives in exactly one place instead of six near-identical copies.
# Relies on bash/zsh-sh-emulation dynamic scoping to see the caller's
# `_saved_traps` local without it being passed as an argument — same
# scoping `_gh_pr_review_*` helpers already lean on throughout this file.
_gh_pr_review_disarm_trap() {
    trap - INT TERM
    [ -z "${_saved_traps-}" ] || eval "$_saved_traps"
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
    # AI_STDERR_FILE is _gh_pr_review_run_ai's stderr capture, allocated
    # here rather than inside that helper so the INT/TERM handler below can
    # reach it too (issue #1294 — see the helper's own comment). Empty until
    # its allocation point at Step 5, which the handler tolerates: it is in
    # the `rm -f` list from the moment it is armed and `rm -f ""` is a
    # documented no-op.
    local AI_STDERR_FILE=""
    if ! PROMPT_FILE=$(_gh_pr_review_mktemp_prompt "$ai" "$PR_NUMBER"); then
        echo "Could not create prompt temp file under /tmp" >&2
        return 1
    fi
    # Issue #1286 — interrupt cleanup. Without a trap, Ctrl-C during the
    # (potentially minutes-long) external AI CLI run, or during the
    # `gh pr diff` inside the prompt builder, unwinds this function
    # outright: none of the `rm -f` cascades below ever run and all three
    # temp files leak into /tmp. A later run that recycles the same PID
    # then hits the noclobber fallback and fails closed on its own litter.
    #
    # Installed here — right after the first successful allocation — so it
    # covers the earliest point any of the four files can exist. AI_OUT,
    # BODY_FILE and AI_STDERR_FILE are still empty strings at this instant;
    # `rm -f ""` is a documented no-op, so the single handler stays correct
    # throughout.
    #
    # The handler ends in `return 130` (128 + SIGINT) on purpose: a trap
    # action alone does NOT abort the function — both bash and zsh resume
    # at the next command after the handler returns, which would carry a
    # half-finished run into Step 6 and post a comment built from files
    # the handler just deleted.
    #
    # Issue #1294 — for that `return 130` to reach the *caller* under zsh,
    # the interrupted command must not be evaluated as a condition. zsh
    # discards a trap's return status when the signal lands in an `if` test
    # (the `if` then falls through with its own status 0), and likewise for
    # a *subshell* on the left of `||`. Measured under zsh 5.9: `if ! cmd`
    # → 0, `( … ) || rc=$?` → 0, but `cmd || rc=$?` → 130 and `( … )`
    # followed by `rc=$?` → 130. bash reports 130 for all four. So every
    # guard from here to Step 5 is written as `cmd || { … }`, and Step 5's
    # subshell stands alone with its status read on the next line; the
    # surviving `if`s only test `[ … ]`, which cannot be interrupted.
    #
    # Every `return` past this point must disarm the handler first. This
    # function is sourced into the user's interactive shell, so a leaked
    # handler would silently override their Ctrl-C at the prompt on every
    # later command — and reference locals that no longer exist.
    #
    # Disarming is `trap - INT TERM` *plus* re-arming whatever the caller
    # already had: bash traps are global to the shell, so a bare reset
    # deletes the caller's own handler as a side effect (bats' own
    # `bats_interrupt_trap` is a live example of a caller that has one).
    # zsh needs no snapshot — under `emulate -L sh` its traps are
    # function-local, so the caller's are restored on return for free.
    # Every disarm point below — including the trap body itself — goes
    # through `_gh_pr_review_disarm_trap` so the reset-plus-restore pair
    # can't drift out of sync between the six exit paths.
    local _saved_traps=""
    if [ -n "${BASH_VERSION-}" ]; then
        _saved_traps=$(
            trap -p INT
            trap -p TERM
        )
    fi
    trap 'rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE" "$AI_STDERR_FILE" 2>/dev/null; _gh_pr_review_disarm_trap; return 130' INT TERM

    AI_OUT=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX") || {
        echo "Could not create AI output temp file under /tmp" >&2
        _gh_pr_review_disarm_trap
        rm -f "$PROMPT_FILE"
        return 1
    }
    BODY_FILE=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-body.XXXXXX") || {
        echo "Could not create comment body temp file under /tmp" >&2
        _gh_pr_review_disarm_trap
        rm -f "$PROMPT_FILE" "$AI_OUT"
        return 1
    }

    _gh_pr_review_build_prompt "$review" "$PROMPT_FILE" \
        "$PR_NUMBER" "$TARGET_REPO" "${base:-?}" "${head:-?}" || {
        _gh_pr_review_disarm_trap
        rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE"
        return 1
    }

    # ---- Step 5: dispatch external AI CLI ----
    # Tee CLI stdout: stream to the user's terminal verbatim AND capture
    # it for the PR comment body. `set -o pipefail` is scoped to this
    # subshell so a non-zero exit from `_gh_pr_review_run_ai` propagates
    # past the trailing `tee`; without it the pipeline always inherits
    # tee's (usually 0) exit code and the failure branch never runs.
    #
    # The CLI's stderr capture is allocated here, not inside
    # _gh_pr_review_run_ai, so the handler above can delete it on Ctrl-C —
    # a helper-local path is invisible to it and leaked into /tmp
    # (issue #1294). Allocation failure is fatal for the same reason it is
    # inside the helper: without it a CLI failure has no diagnosable cause.
    AI_STDERR_FILE=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-stderr.$ai.XXXXXX") || {
        echo "Could not create stderr temp file under /tmp" >&2
        _gh_pr_review_disarm_trap
        rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE"
        return 1
    }
    # The subshell stands alone and its status is read from `$?` on the next
    # line, instead of the former `if ! ( … ); then`. Under zsh an interrupt
    # that lands inside a subshell used as an `if` condition — or as the left
    # side of `||` — loses the INT handler's `return 130` and the caller sees
    # 0 (issue #1294; see the trap comment above). Only the plain
    # command-then-`$?` form propagates it. The subshell itself, its
    # `pipefail` and the `tee` are unchanged.
    local _rc=0
    (
        set -o pipefail
        _gh_pr_review_run_ai "$ai" "$PROMPT_FILE" "$CFG_DIR" "$AI_STDERR_FILE" | tee "$AI_OUT"
    )
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        _gh_pr_review_disarm_trap
        # AI_STDERR_FILE is deliberately NOT removed: a genuine CLI failure
        # leaves it for the user to inspect (the helper prints its path).
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

    _gh_pr_review_disarm_trap
    rm -f "$PROMPT_FILE" "$AI_OUT" "$BODY_FILE" "$AI_STDERR_FILE"
    return 0
}

# ============================================================================
# Aliases — hyphenated command names per shell-common convention
# ============================================================================

alias gh-pr-review='gh_pr_review'
alias gh-pr-review-help='gh_pr_review_help'
