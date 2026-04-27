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
# turn-completion usage via `--json`, so we normalize the input/cached/
# output counts into a usage shape compatible with claude's. `gemini`
# exposes per-model token stats via `--output-format json`; we keep its
# native fields (total/cached/candidates/...) under `usage` and the
# per-model breakdown under `modelUsage`, since its cache semantics
# don't map cleanly onto claude's create/read split.

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
        _tmp=$(mktemp -t ai_usage_gemini.XXXXXX) || {
            printf '[ai-usage] mktemp failed; running gemini without tracking\n' >&2
            gemini --approval-mode=yolo --skip-trust -p "$_prompt"
            _ec=$?
            printf '{"ai":"gemini","ts":"%s","label":%s,"exit_code":%d,"tracking":"cli_failed"}\n' \
                "$_now" \
                "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
                "$_ec" >>"$_log"
            return $_ec
        }

        gemini --approval-mode=yolo --skip-trust --output-format json -p "$_prompt" >"$_tmp"
        _ec=$?

        if [ "$_ec" -ne 0 ] || ! [ -s "$_tmp" ]; then
            printf '{"ai":"gemini","ts":"%s","label":%s,"exit_code":%d,"tracking":"cli_failed"}\n' \
                "$_now" \
                "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
                "$_ec" >>"$_log"
            cat "$_tmp" 2>/dev/null
            rm -f "$_tmp"
            return $_ec
        fi

        # Echo just the human-readable response so the worker log stays
        # legible. The full JSON (including stats/error) lives in usage.jsonl.
        jq -r '.response // ""' <"$_tmp" 2>/dev/null

        # gemini's `.stats.models` is keyed by model name; one prompt can
        # accumulate counts under several models when an internal sub-agent
        # is invoked. We sum each `tokens.*` field across models for the
        # top-level usage block and keep the per-model split under
        # modelUsage for later analysis.
        if jq -e '(.stats.models | type) == "object"' <"$_tmp" >/dev/null 2>&1; then
            jq -c \
                --arg ts "$_now" \
                --arg label "$_label" \
                '{
                    ai: "gemini",
                    ts: $ts,
                    label: $label,
                    exit_code: 0,
                    tracking: "usage",
                    usage: (
                        [(.stats.models // {}) | to_entries[] | (.value.tokens // {})]
                        | reduce .[] as $t (
                            {input:0, prompt:0, candidates:0, total:0, cached:0, thoughts:0, tool:0};
                            .input      += ($t.input      // 0)
                            | .prompt   += ($t.prompt     // 0)
                            | .candidates += ($t.candidates // 0)
                            | .total    += ($t.total      // 0)
                            | .cached   += ($t.cached     // 0)
                            | .thoughts += ($t.thoughts   // 0)
                            | .tool     += ($t.tool       // 0)
                          )
                    ),
                    modelUsage: ((.stats.models // {}) | with_entries(.value = (.value.tokens // {})))
                }' <"$_tmp" >>"$_log" 2>/dev/null
        else
            printf '{"ai":"gemini","ts":"%s","label":%s,"exit_code":%d,"tracking":"usage_missing"}\n' \
                "$_now" \
                "$(printf '%s' "$_label" | jq -Rsc . 2>/dev/null || printf '"%s"' "$_label")" \
                "$_ec" >>"$_log"
        fi

        rm -f "$_tmp"
        return 0
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

    # One pass with jq -s computes per-runner aggregates. We deliberately
    # do NOT collapse claude+codex+gemini token counts into a single sum —
    # cache semantics differ (claude has create/read split, codex exposes
    # cached_input_tokens, gemini exposes its own total/cached), and a
    # mixed sum would silently lie about each. Cost is summed only over
    # claude because the other CLIs do not expose a billable amount.
    local _summary
    _summary=$(jq -s '
        [.[] | select(.ai == "claude" and ((.is_error // false) | not) and ((.tracking // "") != "cli_failed"))] as $claude_ok
        | [.[] | select(.ai == "claude" and ((.is_error // false) or ((.tracking // "") == "cli_failed")))] as $claude_err
        | [.[] | select(.ai == "codex" and ((.tracking // "") == "usage"))] as $codex_ok
        | [.[] | select(.ai == "codex" and ((.tracking // "") != "usage"))] as $codex_err
        | [.[] | select(.ai == "gemini" and ((.tracking // "") == "usage"))] as $gemini_ok
        | [.[] | select(.ai == "gemini" and ((.tracking // "") != "usage"))] as $gemini_err
        | {
            claude_n_ok:    ($claude_ok | length),
            claude_n_err:   ($claude_err | length),
            claude_in:      ([$claude_ok[].usage.input_tokens // 0]                | add // 0),
            claude_cc:      ([$claude_ok[].usage.cache_creation_input_tokens // 0] | add // 0),
            claude_cr:      ([$claude_ok[].usage.cache_read_input_tokens // 0]     | add // 0),
            claude_out:     ([$claude_ok[].usage.output_tokens // 0]               | add // 0),
            claude_cost:    ([$claude_ok[].total_cost_usd // 0]                    | add // 0),
            claude_wall_ms: ([$claude_ok[].duration_ms // 0]                       | add // 0),
            claude_api_ms:  ([$claude_ok[].duration_api_ms // 0]                   | add // 0),
            claude_turns:   ([$claude_ok[].num_turns // 0]                         | add // 0),
            claude_models:  ([$claude_ok[].modelUsage // {} | keys[]]              | unique),
            codex_n_ok:     ($codex_ok | length),
            codex_n_err:    ($codex_err | length),
            codex_in:       ([$codex_ok[].usage.input_tokens // 0]                 | add // 0),
            codex_cached:   ([$codex_ok[].usage.cache_read_input_tokens // 0]      | add // 0),
            codex_out:      ([$codex_ok[].usage.output_tokens // 0]                | add // 0),
            gemini_n_ok:    ($gemini_ok | length),
            gemini_n_err:   ($gemini_err | length),
            gemini_total:   ([$gemini_ok[].usage.total // 0]                       | add // 0),
            gemini_cached:  ([$gemini_ok[].usage.cached // 0]                      | add // 0),
            gemini_out:     ([$gemini_ok[].usage.candidates // 0]                  | add // 0),
            gemini_models:  ([$gemini_ok[].modelUsage // {} | keys[]]              | unique)
        }
    ' "$_log" 2>/dev/null)

    if [ -z "$_summary" ]; then
        printf '─── %s ─── (failed to parse %s)\n' "$_label" "$_log"
        return 0
    fi

    local _claude_n_ok _claude_n_err _claude_in _claude_cc _claude_cr _claude_out
    local _claude_cost _claude_wall _claude_api _claude_turns _claude_models
    local _codex_n_ok _codex_n_err _codex_in _codex_cached _codex_out
    local _gemini_n_ok _gemini_n_err _gemini_total _gemini_cached _gemini_out _gemini_models
    local _vals

    # Single jq fork emits all fields as TSV — same hot-path concern as
    # before (PR #224 review). `?` keeps it null-tolerant if a field is
    # absent in the upstream summary document.
    _vals=$(printf '%s' "$_summary" | jq -r '[
        .claude_n_ok?, .claude_n_err?,
        .claude_in?, .claude_cc?, .claude_cr?, .claude_out?,
        .claude_cost?, .claude_wall_ms?, .claude_api_ms?, .claude_turns?,
        ((.claude_models? // []) | join(", ")),
        .codex_n_ok?, .codex_n_err?,
        .codex_in?, .codex_cached?, .codex_out?,
        .gemini_n_ok?, .gemini_n_err?,
        .gemini_total?, .gemini_cached?, .gemini_out?,
        ((.gemini_models? // []) | join(", "))
    ] | @tsv' 2>/dev/null)

    if [ -z "$_vals" ]; then
        printf '─── %s ─── (failed to parse %s)\n' "$_label" "$_log"
        return 0
    fi

    # `read` runs in the current shell when fed by a here-doc, so the
    # locals stick. IFS=$'\t' is bash-specific; the file header already
    # pins the runtime to bash via the shell directive on line 2.
    IFS=$'\t' read -r \
        _claude_n_ok _claude_n_err \
        _claude_in _claude_cc _claude_cr _claude_out \
        _claude_cost _claude_wall _claude_api _claude_turns _claude_models \
        _codex_n_ok _codex_n_err \
        _codex_in _codex_cached _codex_out \
        _gemini_n_ok _gemini_n_err \
        _gemini_total _gemini_cached _gemini_out _gemini_models <<EOF
$_vals
EOF

    # Pre-format the integer/float fields into locals so the printf lines
    # below contain only `"$var"` references — the project's pre-commit
    # naming check flags any function-name that appears between two `"`
    # on the same line as user-facing text, even when it's a command
    # substitution. Splitting the formatting out sidesteps that rule.
    local _claude_in_fmt _claude_cc_fmt _claude_cr_fmt _claude_out_fmt _claude_cost_fmt
    local _codex_in_fmt _codex_cached_fmt _codex_out_fmt
    local _gemini_total_fmt _gemini_cached_fmt _gemini_out_fmt
    local _wall_s _api_s
    _claude_in_fmt=$(_ai_usage_fmt_int "${_claude_in:-0}")
    _claude_cc_fmt=$(_ai_usage_fmt_int "${_claude_cc:-0}")
    _claude_cr_fmt=$(_ai_usage_fmt_int "${_claude_cr:-0}")
    _claude_out_fmt=$(_ai_usage_fmt_int "${_claude_out:-0}")
    _claude_cost_fmt=$(printf '%.4f' "${_claude_cost:-0}" 2>/dev/null || printf '%s' "${_claude_cost:-0}")
    _codex_in_fmt=$(_ai_usage_fmt_int "${_codex_in:-0}")
    _codex_cached_fmt=$(_ai_usage_fmt_int "${_codex_cached:-0}")
    _codex_out_fmt=$(_ai_usage_fmt_int "${_codex_out:-0}")
    _gemini_total_fmt=$(_ai_usage_fmt_int "${_gemini_total:-0}")
    _gemini_cached_fmt=$(_ai_usage_fmt_int "${_gemini_cached:-0}")
    _gemini_out_fmt=$(_ai_usage_fmt_int "${_gemini_out:-0}")
    _wall_s=$((${_claude_wall:-0} / 1000))
    _api_s=$((${_claude_api:-0} / 1000))

    printf '─── %s ───\n' "$_label"
    printf '  Invocations:    claude=%s ok / %s failed · codex=%s ok / %s failed · gemini=%s ok / %s failed\n' \
        "${_claude_n_ok:-0}" "${_claude_n_err:-0}" \
        "${_codex_n_ok:-0}" "${_codex_n_err:-0}" \
        "${_gemini_n_ok:-0}" "${_gemini_n_err:-0}"
    if [ "${_claude_n_ok:-0}" -gt 0 ]; then
        printf '  claude:         %s fresh + %s cache-create + %s cache-read + %s out · $%s\n' \
            "$_claude_in_fmt" "$_claude_cc_fmt" "$_claude_cr_fmt" "$_claude_out_fmt" "$_claude_cost_fmt"
        if [ -n "$_claude_models" ] && [ "$_claude_models" != "" ]; then
            printf '    models:       %s\n' "$_claude_models"
        fi
    fi
    if [ "${_codex_n_ok:-0}" -gt 0 ]; then
        printf '  codex:          %s input (%s cached) + %s out · cost: n/a\n' \
            "$_codex_in_fmt" "$_codex_cached_fmt" "$_codex_out_fmt"
    fi
    if [ "${_gemini_n_ok:-0}" -gt 0 ]; then
        printf '  gemini:         %s total (%s cached) + %s out · cost: n/a\n' \
            "$_gemini_total_fmt" "$_gemini_cached_fmt" "$_gemini_out_fmt"
        if [ -n "$_gemini_models" ] && [ "$_gemini_models" != "" ]; then
            printf '    models:       %s\n' "$_gemini_models"
        fi
    fi
    if [ "${_claude_wall:-0}" -gt 0 ] || [ "${_claude_api:-0}" -gt 0 ] || [ "${_claude_turns:-0}" -gt 0 ]; then
        printf '  Wall / API:     %ss / %ss · turns: %s (claude only)\n' \
            "$_wall_s" "$_api_s" "${_claude_turns:-0}"
    fi
    printf '  Cost note:      claude tracked; codex/gemini cost excluded (no upstream cost field).\n'
    printf '  Log:            %s\n' "$_log"
    printf '────────────────────────────────────\n'
}
