#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/ai_usage.sh
# AI runner invocation wrapper that records per-call token usage and cost,
# plus an aggregator that summarises a run's totals.
#
# Used by gh_flow.sh, gh_pr_approve.sh, gh_pr_reply.sh so every detached
# worker writes a `usage.jsonl` next to its `log` and prints a totals
# block at exit. Background: 7 parallel claude `-p` sessions on the
# Opus 1M-context default model burned a MAX user's 5h quota in ≈10 min;
# without this helper the cost of each invocation was invisible.
#
# Format of usage.jsonl: one JSON object per ai invocation. For the
# `claude` runner we store the full upstream `usage`, `total_cost_usd`,
# and timing fields (everything is parseable by jq). `codex` exposes
# turn-completion usage via `--json`, so we normalize that into the same
# usage shape. `gemini` still only records exit code because its CLI
# does not expose a stable parseable usage block here.

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Format an integer with thousand separators, sh/awk only (locale-independent).
_ai_usage_fmt_int() {
    awk -v n="${1:-0}" 'BEGIN {
        # Strip a possible leading sign so we only insert separators on digits.
        sign = ""
        if (substr(n, 1, 1) == "-") { sign = "-"; n = substr(n, 2) }
        len = length(n)
        out = ""
        for (i = 1; i <= len; i++) {
            out = out substr(n, i, 1)
            if (i < len && (len - i) % 3 == 0) out = out ","
        }
        print sign out
    }'
}

# ISO-8601 timestamp with seconds. `date -Iseconds` is GNU; the fallback
# keeps Alpine/macOS workers honest.
_ai_usage_now() {
    date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ---------------------------------------------------------------------------
# Public: run one AI prompt and append a usage record to <log>
# ---------------------------------------------------------------------------
# $1 = ai runner (claude|codex|gemini)
# $2 = absolute path to usage.jsonl (created/appended)
# $3 = label for this invocation (e.g. "/gh-pr-approve 42") — recorded so
#      the per-step breakdown is readable when reviewing the log
# $4 = the prompt to send (passed verbatim to the runner)
#
# Behaviour:
# - claude: invoked with `--output-format json`, the JSON is captured to a
#   tempfile, the human-readable `.result` is echoed to stdout (so the
#   worker log stays useful), and one compact JSON object is appended to
#   the usage log. Returns 1 if the upstream `is_error` flag is true,
#   otherwise the CLI exit code (so the worker's "skill failed" branch
#   still triggers correctly).
# - codex: invoked with `--json`; we capture the JSONL transcript to a
#   tempfile, echo the final assistant message for log readability, and
#   append a normalized usage record when `turn.completed.usage` exists.
# - gemini: invoked unchanged; we append a minimal record with
#   tracking:"unsupported" so the summary clearly says we have no
#   numbers for those calls (rather than silently reporting 0 tokens).
_ai_usage_run() {
    local _ai="$1" _log="$2" _label="$3" _prompt="$4"
    local _tmp _tmp_msg _ec _is_error _now

    if [ -z "$_ai" ] || [ -z "$_log" ]; then
        printf '[ai-usage] internal error: _ai_usage_run requires <ai> <log> <label> <prompt>\n' >&2
        return 2
    fi

    # Make sure the directory holding the log exists; `mkdir -p` is cheap
    # and removes a class of "log went missing" race conditions when two
    # workers share an ancestor dir but not the same state dir.
    mkdir -p "$(dirname "$_log")" 2>/dev/null || true

    _now=$(_ai_usage_now)

    case "$_ai" in
    claude)
        # Capture JSON to a tempfile so we can both (a) print the human
        # result to the worker log and (b) parse usage. Stderr passes
        # through untouched — claude prints diagnostic noise there and
        # we want the worker log to still see it.
        _tmp=$(mktemp -t ai_usage.XXXXXX) || {
            printf '[ai-usage] mktemp failed; running without tracking\n' >&2
            claude --dangerously-skip-permissions -p "$_prompt"
            return $?
        }

        claude --dangerously-skip-permissions -p "$_prompt" --output-format json >"$_tmp"
        _ec=$?

        # If the CLI itself crashed (network, auth, etc.) we have no
        # JSON to parse. Still record the failure so the summary's
        # invocation count includes it, then echo whatever stdout
        # produced (likely an error message).
        if [ "$_ec" -ne 0 ] || ! [ -s "$_tmp" ]; then
            printf '{"ai":"claude","ts":"%s","label":%s,"exit_code":%d,"tracking":"cli_failed"}\n' \
                "$_now" \
                "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
                "$_ec" >>"$_log"
            cat "$_tmp" 2>/dev/null
            rm -f "$_tmp"
            return $_ec
        fi

        # is_error reflects "the assistant failed", separate from the
        # CLI exit code. Workers rely on a non-zero return to flip
        # state to failed:*, so propagate is_error as exit 1.
        _is_error=$(jq -r '.is_error // false' <"$_tmp" 2>/dev/null)

        # Echo just the human-readable result so the worker's log stays
        # legible. The full JSON lives in usage.jsonl for diagnostics.
        jq -r '.result // ""' <"$_tmp" 2>/dev/null

        # Append a compact, jq-friendly record. Keep usage/modelUsage
        # nested so per-model cost can be broken out later if needed.
        jq -c \
            --arg ts "$_now" \
            --arg label "$_label" \
            '{
                ai: "claude",
                ts: $ts,
                label: $label,
                session_id: .session_id,
                is_error: (.is_error // false),
                num_turns: (.num_turns // 0),
                duration_ms: (.duration_ms // 0),
                duration_api_ms: (.duration_api_ms // 0),
                total_cost_usd: (.total_cost_usd // 0),
                usage: (.usage // {}),
                modelUsage: (.modelUsage // {})
            }' <"$_tmp" >>"$_log" 2>/dev/null

        rm -f "$_tmp"
        if [ "$_is_error" = "true" ]; then
            return 1
        fi
        return 0
        ;;
    codex)
        _tmp=$(mktemp -t ai_usage_codex.XXXXXX) || {
            printf '[ai-usage] mktemp failed; running codex without tracking\n' >&2
            codex exec --dangerously-bypass-approvals-and-sandbox "$_prompt"
            return $?
        }
        _tmp_msg=$(mktemp -t ai_usage_codex_msg.XXXXXX) || {
            rm -f "$_tmp"
            printf '[ai-usage] mktemp failed; running codex without tracking\n' >&2
            codex exec --dangerously-bypass-approvals-and-sandbox "$_prompt"
            return $?
        }

        codex exec \
            --json \
            --output-last-message "$_tmp_msg" \
            --dangerously-bypass-approvals-and-sandbox \
            "$_prompt" >"$_tmp"
        _ec=$?

        if [ -s "$_tmp_msg" ]; then
            cat "$_tmp_msg"
        fi

        if [ "$_ec" -ne 0 ] || ! [ -s "$_tmp" ]; then
            printf '{"ai":"codex","ts":"%s","label":%s,"exit_code":%d,"tracking":"cli_failed"}\n' \
                "$_now" \
                "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
                "$_ec" >>"$_log"
            jq -r 'select(.type == "error") | .message // empty' <"$_tmp" 2>/dev/null >&2
            rm -f "$_tmp" "$_tmp_msg"
            return $_ec
        fi

        if jq -e 'select(.type == "turn.completed" and (.usage | type == "object"))' <"$_tmp" >/dev/null 2>&1; then
            jq -cs \
                --arg ts "$_now" \
                --arg label "$_label" \
                'map(select(.type == "turn.completed" and (.usage | type == "object"))) | last as $done
                | {
                    ai: "codex",
                    ts: $ts,
                    label: $label,
                    exit_code: 0,
                    tracking: "usage",
                    usage: {
                        input_tokens: ($done.usage.input_tokens // 0),
                        cache_creation_input_tokens: 0,
                        cache_read_input_tokens: ($done.usage.cached_input_tokens // 0),
                        output_tokens: ($done.usage.output_tokens // 0)
                    }
                }' <"$_tmp" >>"$_log" 2>/dev/null
        else
            printf '{"ai":"codex","ts":"%s","label":%s,"exit_code":%d,"tracking":"usage_missing"}\n' \
                "$_now" \
                "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
                "$_ec" >>"$_log"
        fi

        rm -f "$_tmp" "$_tmp_msg"
        return 0
        ;;
    gemini)
        gemini --yolo -p "$_prompt"
        _ec=$?
        printf '{"ai":"gemini","ts":"%s","label":%s,"exit_code":%d,"tracking":"unsupported"}\n' \
            "$_now" \
            "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
            "$_ec" >>"$_log"
        return $_ec
        ;;
    *)
        printf '[ai-usage] invalid ai runner: %s\n' "$_ai" >&2
        return 2
        ;;
    esac
}

# ---------------------------------------------------------------------------
# Public: print a human-readable summary of <log> on stdout
# ---------------------------------------------------------------------------
# $1 = absolute path to usage.jsonl
# $2 = optional label for the summary block header (default "Token Usage")
#
# Output is plain stdout (no ux_* helpers) so it shows up identically in
# both the foreground orchestrator's terminal and the worker's tail-able
# log file. Missing jq → we still print a one-liner pointing at the raw
# log so a human can still investigate.
_ai_usage_summary() {
    local _log="$1" _label="${2:-Token Usage}"

    if [ ! -f "$_log" ] || [ ! -s "$_log" ]; then
        printf '─── %s ─── (no invocations recorded)\n' "$_label"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        printf '─── %s ─── (jq missing; raw log: %s)\n' "$_label" "$_log"
        return 0
    fi

    # One pass with jq -s aggregates every record that actually contains a
    # normalized usage block. That includes assistant-side failures with
    # usage (still billable) and excludes pure CLI failures where the tool
    # died before we received usage. Invocation counts stay split so users
    # can distinguish successful runs from failed-but-billed ones.
    local _summary
    _summary=$(jq -s '
        [.[] | select(.ai == "claude" and ((.is_error // false) | not) and ((.tracking // "") != "cli_failed"))] as $claude_ok
        | [.[] | select(.ai == "claude" and ((.is_error // false) or ((.tracking // "") == "cli_failed")))] as $claude_err
        | [.[] | select(.ai == "codex" and ((.tracking // "") == "usage"))] as $codex_ok
        | [.[] | select(.ai == "codex" and ((.tracking // "") != "usage"))] as $codex_err
        | [.[] | select(.tracking == "unsupported")] as $other
        | [.[] | select((.usage | type?) == "object")] as $tracked
        | {
            claude_ok: ($claude_ok | length),
            claude_err: ($claude_err | length),
            codex_ok: ($codex_ok | length),
            codex_err: ($codex_err | length),
            other:     ($other | length),
            input_tokens:   ([$tracked[].usage.input_tokens // 0]                | add // 0),
            cache_creation: ([$tracked[].usage.cache_creation_input_tokens // 0] | add // 0),
            cache_read:     ([$tracked[].usage.cache_read_input_tokens // 0]     | add // 0),
            output_tokens:  ([$tracked[].usage.output_tokens // 0]               | add // 0),
            cost_usd:       ([.[] | select(.ai == "claude") | .total_cost_usd // 0]  | add // 0),
            wall_ms:        ([.[] | select(.ai == "claude") | .duration_ms // 0]      | add // 0),
            api_ms:         ([.[] | select(.ai == "claude") | .duration_api_ms // 0]  | add // 0),
            turns:          ([.[] | select(.ai == "claude") | .num_turns // 0]        | add // 0),
            models:         ([.[] | select(.ai == "claude") | .modelUsage // {} | keys[]] | unique)
        }
    ' "$_log" 2>/dev/null)

    if [ -z "$_summary" ]; then
        printf '─── %s ─── (failed to parse %s)\n' "$_label" "$_log"
        return 0
    fi

    local _claude_ok _claude_err _codex_ok _codex_err _other _in _cc _cr _out _cost _wall _api _turns _models _total_in
    _claude_ok=$(printf '%s' "$_summary" | jq -r '.claude_ok')
    _claude_err=$(printf '%s' "$_summary" | jq -r '.claude_err')
    _codex_ok=$(printf '%s' "$_summary" | jq -r '.codex_ok')
    _codex_err=$(printf '%s' "$_summary" | jq -r '.codex_err')
    _other=$(printf '%s' "$_summary" | jq -r '.other')
    _in=$(printf '%s' "$_summary" | jq -r '.input_tokens')
    _cc=$(printf '%s' "$_summary" | jq -r '.cache_creation')
    _cr=$(printf '%s' "$_summary" | jq -r '.cache_read')
    _out=$(printf '%s' "$_summary" | jq -r '.output_tokens')
    _cost=$(printf '%s' "$_summary" | jq -r '.cost_usd')
    _wall=$(printf '%s' "$_summary" | jq -r '.wall_ms')
    _api=$(printf '%s' "$_summary" | jq -r '.api_ms')
    _turns=$(printf '%s' "$_summary" | jq -r '.turns')
    _models=$(printf '%s' "$_summary" | jq -r '.models | join(", ")')

    # Input-side total: fresh input + cache creation + cache reads.
    _total_in=$((${_in:-0} + ${_cc:-0} + ${_cr:-0}))

    # Pre-format the integer/float fields into locals so the printf lines
    # below contain only `"$var"` references — the project's pre-commit
    # naming check flags any function-name that appears between two `"`
    # on the same line as user-facing text, even when it's a command
    # substitution. Splitting the formatting out sidesteps that rule.
    local _in_fmt _cc_fmt _cr_fmt _total_in_fmt _out_fmt _cost_fmt _wall_s _api_s
    _in_fmt=$(_ai_usage_fmt_int "${_in:-0}")
    _cc_fmt=$(_ai_usage_fmt_int "${_cc:-0}")
    _cr_fmt=$(_ai_usage_fmt_int "${_cr:-0}")
    _total_in_fmt=$(_ai_usage_fmt_int "${_total_in:-0}")
    _out_fmt=$(_ai_usage_fmt_int "${_out:-0}")
    _cost_fmt=$(printf '%.4f' "${_cost:-0}" 2>/dev/null || printf '%s' "${_cost:-0}")
    _wall_s=$((${_wall:-0} / 1000))
    _api_s=$((${_api:-0} / 1000))

    printf '─── %s ───\n' "$_label"
    printf '  Invocations:    claude=%s ok / %s failed · codex=%s ok / %s failed' \
        "${_claude_ok:-0}" \
        "${_claude_err:-0}" \
        "${_codex_ok:-0}" \
        "${_codex_err:-0}"
    if [ "${_other:-0}" -gt 0 ]; then
        printf ' · %s untracked (gemini)' "$_other"
    fi
    printf '\n'
    if [ -n "$_models" ] && [ "$_models" != "" ]; then
        printf '  Models:         %s\n' "$_models"
    fi
    printf '  Input tokens:   %s (fresh)\n'       "$_in_fmt"
    printf '  Cache creation: %s\n'               "$_cc_fmt"
    printf '  Cache read:     %s\n'               "$_cr_fmt"
    printf '  Input total:    %s (incl. cache)\n' "$_total_in_fmt"
    printf '  Output tokens:  %s\n'               "$_out_fmt"
    printf '  Cost (USD):     $%s (claude only)\n' "$_cost_fmt"
    if [ "${_wall:-0}" -gt 0 ] || [ "${_api:-0}" -gt 0 ] || [ "${_turns:-0}" -gt 0 ]; then
        printf '  Wall / API:     %ss / %ss\n'        "$_wall_s" "$_api_s"
        printf '  Turns:          %s\n'               "${_turns:-0}"
    fi
    printf '  Log:            %s\n'               "$_log"
    printf '────────────────────────────────────\n'
}
