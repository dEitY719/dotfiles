#!/usr/bin/env bash
# claude/tools/hook-perf-report.sh
#
# Regression measurement for the PostToolUse:Bash hook latency budget
# (issue #1258). Reproduces the issue's baseline methodology so a fix can be
# re-verified later instead of re-measured by hand every time:
#
#   Source A — Claude Code transcripts (~/.claude*/projects/**/*.jsonl).
#     Every hook invocation lands as a `{"type":"attachment"}` line whose
#     `.attachment.type` starts with `hook_`, carrying `.attachment.command`
#     (the registered hook command string) and `.attachment.durationMs` (the
#     wall-clock the user's turn actually waited). Filtered to the dispatcher
#     by matching --hook against `.attachment.command`.
#
#   Source B — the dispatcher's own stage log written by
#     claude/hooks/post-bash-dispatch.sh (#1258), i.e.
#     ${XDG_STATE_HOME:-$HOME/.local/state}/claude/post-bash-dispatch-timing.log
#     with one `<entry-ms> <pre-invoke-ms> <post-exit-ms> <handler>` line per
#     ROUTED invocation. Splits source A's single number into
#     dispatch-overhead vs handler cost, which is what #1144 lacked.
#
# MANUAL diagnostic — it depends on live transcripts that exist on a working
# machine but not in CI or a fresh clone, so it is deliberately NOT wired into
# `mise run test` / mise.toml. Run it by hand:
#
#   claude/tools/hook-perf-report.sh
#   claude/tools/hook-perf-report.sh --hook plugin-sync.sh --days 7
#
# Best-effort like the hooks themselves: missing roots, missing jq and empty
# samples degrade to a printed notice, never a crash.
#
# Reference: issue #1258 (target: median < 2000ms, p99 < 5000ms).

set -u

TARGET_MEDIAN_MS=2000
TARGET_P99_MS=5000

HOOK_MATCH="post-bash-dispatch.sh"
DAYS=""
TIMING_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/claude/post-bash-dispatch-timing.log"
# Every Claude Code config dir on this machine (multi-account layout). Globbed
# rather than listed: the accounts differ per PC and the default one is
# `personal` (~/.claude-personal), so any fixed list silently under-samples
# somewhere. A non-matching glob or a missing dir is skipped below.
TRANSCRIPT_ROOTS="$(printf '%s ' "$HOME"/.claude*/projects)"

_usage() {
    cat <<EOF
Usage: hook-perf-report.sh [options]

  --hook <substr>   Match this substring against the transcript's hook
                    command (default: post-bash-dispatch.sh).
  --days <N>        Only read transcripts modified within the last N days.
  --timing-log <p>  Override the dispatcher stage log path.
  --roots "<a> <b>" Override the transcript search roots (space separated).
  -h, --help        Print this help.

Reports count / median / p90 / p99 / max in milliseconds and a PASS/FAIL
verdict against median < ${TARGET_MEDIAN_MS}ms and p99 < ${TARGET_P99_MS}ms (issue #1258).
EOF
}

# --- statistics -------------------------------------------------------------

# Read one number per line on stdin, print "<count> <min> <p50> <p90> <p99>
# <max>". Nearest-rank percentiles (idx = ceil(p/100 * n), clamped), computed
# with sort+awk only — no jq -s, no python. Empty input prints all zeros.
hook_perf_stats() {
    grep -E '^[0-9]+$' | sort -n | awk '
        { v[NR] = $1 }
        function pct(p,    i) {
            i = int((p * n + 99) / 100)
            if (i < 1) { i = 1 }
            if (i > n) { i = n }
            return v[i]
        }
        END {
            n = NR
            if (n == 0) { print "0 0 0 0 0 0"; exit }
            printf "%d %d %d %d %d %d\n", n, v[1], pct(50), pct(90), pct(99), v[n]
        }
    '
}

# Print a labelled stats line from a "<count> <min> <p50> <p90> <p99> <max>"
# tuple produced by hook_perf_stats.
_print_stats() {
    local label="$1" n min p50 p90 p99 max
    read -r n min p50 p90 p99 max <<<"$2"
    if [ "${n:-0}" -eq 0 ]; then
        printf '  %-22s (no samples)\n' "$label"
        return 0
    fi
    printf '  %-22s n=%-5s min=%-7s p50=%-7s p90=%-7s p99=%-7s max=%s\n' \
        "$label" "$n" "$min" "$p50" "$p90" "$p99" "$max"
}

# --- source A: transcripts --------------------------------------------------

# Emit one durationMs per matching hook attachment. `grep -F` prefilters the
# jsonl lines so jq only parses the handful that mention the hook.
_transcript_durations() {
    local root find_args=()
    [ -n "$DAYS" ] && find_args=(-mtime "-$DAYS")
    for root in $TRANSCRIPT_ROOTS; do
        [ -d "$root" ] || continue
        find "$root" -type f -name '*.jsonl' "${find_args[@]+${find_args[@]}}" \
            -exec grep -h -F -- "$HOOK_MATCH" {} + 2>/dev/null
    done | jq -r --arg m "$HOOK_MATCH" '
        select(.type == "attachment")
        | select((.attachment.type // "") | startswith("hook_"))
        | select((.attachment.command // "") | contains($m))
        | .attachment.durationMs // empty
    ' 2>/dev/null
}

# --- source B: dispatcher stage log ----------------------------------------

# Print `field$1 - field$2` per stage-log row (1 entry, 2 pre-invoke, 3
# post-exit). $3, when given, restricts to one handler (field 4). Rows that
# are malformed, non-numeric or out of order are dropped.
_timing_deltas() {
    local a="$1" b="$2" want="${3:-}"
    [ -f "$TIMING_LOG" ] || return 0
    awk -v want="$want" -v a="$a" -v b="$b" '
        NF >= 4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
            if (want != "" && $4 != want) { next }
            d = $a - $b
            if (d >= 0) { print d }
        }
    ' "$TIMING_LOG" 2>/dev/null
}

# --- main -------------------------------------------------------------------

# PASS/FAIL one metric ($1 label, $2 value) against its budget ($3). Returns 1
# when the budget is blown, so callers can OR the verdicts into one exit code.
_verdict() {
    if [ "$2" -lt "$3" ]; then
        printf 'PASS  %s %sms < %sms\n' "$1" "$2" "$3"
        return 0
    fi
    printf 'FAIL  %s %sms >= %sms\n' "$1" "$2" "$3"
    return 1
}

_hook_perf_main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --hook) HOOK_MATCH="${2:-}"; shift 2 ;;
            --days) DAYS="${2:-}"; shift 2 ;;
            --timing-log) TIMING_LOG="${2:-}"; shift 2 ;;
            --roots) TRANSCRIPT_ROOTS="${2:-}"; shift 2 ;;
            -h | --help | help) _usage; return 0 ;;
            *) printf 'hook-perf-report: unknown option: %s\n' "$1" >&2; _usage >&2; return 2 ;;
        esac
    done

    printf '=== PostToolUse hook latency (#1258) ===\n'
    printf 'hook match : %s\n' "$HOOK_MATCH"
    printf 'transcripts: %s\n' "$TRANSCRIPT_ROOTS"
    printf 'stage log  : %s%s\n' "$TIMING_LOG" \
        "$([ -f "$TIMING_LOG" ] || printf ' (absent)')"
    printf '\n'

    local total_stats="0 0 0 0 0 0"
    if command -v jq >/dev/null 2>&1; then
        total_stats=$(_transcript_durations | hook_perf_stats)
    else
        printf 'note: jq not found — transcript source skipped.\n'
    fi
    printf 'Transcript durationMs (what the user waited)\n'
    _print_stats "total" "$total_stats"
    printf '\n'

    printf 'Dispatcher stage log (routed invocations only)\n'
    _print_stats "entry->invoke" "$(_timing_deltas 2 1 | hook_perf_stats)"
    _print_stats "invoke->exit" "$(_timing_deltas 3 2 | hook_perf_stats)"
    _print_stats "entry->exit" "$(_timing_deltas 3 1 | hook_perf_stats)"
    # Per-handler breakdown derived from field 4 of the log itself, so a newly
    # routed handler reports without this tool having to learn its name.
    awk 'NF >= 4 { print $4 }' "$TIMING_LOG" 2>/dev/null | sort -u |
        while IFS= read -r handler; do
            _print_stats "  $handler" "$(_timing_deltas 3 2 "$handler" | hook_perf_stats)"
        done
    printf '\n'

    # Verdict from source A — that is the number the issue's targets describe.
    local n median p99 _skip
    read -r n _skip median _skip p99 _skip <<<"$total_stats"
    if [ "$n" -eq 0 ]; then
        printf 'VERDICT: NO DATA — no hook attachments matched "%s".\n' "$HOOK_MATCH"
        return 0
    fi
    local rc=0
    _verdict median "$median" "$TARGET_MEDIAN_MS" || rc=1
    _verdict p99 "$p99" "$TARGET_P99_MS" || rc=1
    return "$rc"
}

# Sourced (tests reuse hook_perf_stats / _timing_deltas) → define only.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    _hook_perf_main "$@"
fi
