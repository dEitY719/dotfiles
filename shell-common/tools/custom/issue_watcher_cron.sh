#!/bin/bash
# shell-common/tools/custom/issue_watcher_cron.sh
# issue-watcher 5분 주기 감시 사이클 — 1회 tick (issue #1389).
#
# 전용 herdr workspace(label `issue-watcher`)의 고정 pane 하나에 claude 세션을
# 하나만 띄워 재사용한다. cron 이 5분마다 이 스크립트를 호출하면 tick 1회를
# 수행한다:
#   - 상태 파일이 없으면 workspace + agent 를 부트스트랩하고 기록한다.
#   - agent 가 idle/done 이면 dispatcher 프롬프트를 보낸다.
#   - agent 가 working/blocked 이면 이번 tick 을 건너뛴다(에러 아님, exit 0).
#   - agent 가 사라졌거나 pane 이 닫혔으면 재부트스트랩 후 프롬프트를 보낸다.
#   - 토큰 한도 게이트가 닫혀 있으면 dispatch 를 보류한다(issue #1436).
#
# Usage: issue_watcher_cron.sh [--cwd <PATH>] | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (and before it exports
# SHELL_COMMON), so resolve shell-common from this script's own location as a
# fallback. Both ux_lib and the claude integration below are loaded from here.
_IW_SHELL_COMMON="${SHELL_COMMON:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Same early return means ux_* can still be undefined here — every output path
# below depends on it.
if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${_IW_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# ============================================================
# Constants (SSOT for the watch cycle)
# ============================================================

_IW_LABEL="issue-watcher"
_IW_STATE_SUBDIR="issue-watcher"
_IW_STATE_BASENAME="herdr-watch.json"
_IW_LOCK_BASENAME=".lock"
# 받는 claude 세션에 그대로 전달된다. "@<name>" 만으로는 세션이 Skill/Agent 를
# 헷갈려 재시도했다(#1394) — 호출할 도구를 문장으로 명시해 그 오인 경로를 없앤다.
# herdr agent prompt 는 자유 문자열만 싣는 채널이라 구조적 도구 호출은 불가능하다.
# 한국어/영어를 함께 적는 것도 그래서다 — 세션 언어 설정에 덜 흔들리게 하는 중복.
_IW_PROMPT="issue-watcher:dispatcher 를 Agent 도구로 실행해 (run the issue-watcher:dispatcher agent via the Agent tool)"
# 5분 주기보다 여유 있게 4분 — cron tick 이 겹치지 않게 한다.
_IW_TIMEOUT_MS="240000"

# Rate-limit gate (issue #1436). Rationale for each value sits with the gate
# functions below; the values themselves live here with the rest of the SSOT.
# Gate state gets its own file so herdr-watch.json's schema — and every
# pre-#1436 copy of it — stays untouched.
_IW_LIMIT_STATE_BASENAME="rate-limit.json"
_IW_LIMIT_STRIKES="2"
_IW_LIMIT_BACKOFF_SECONDS="1800"

# Overwritten by _iw_read_state when a state file exists.
_IW_AGENT_NAME="iw-watch"
_IW_WORKSPACE_ID=""
_IW_PANE_ID=""
# cwd the workspace was bootstrapped with (persisted so a later tick can tell
# the user its --cwd is being ignored). Empty for pre-#1391 state files.
_IW_CWD=""

# ============================================================
# Helpers
# ============================================================

# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset (a cron
# environment can be that bare), so HOME is never referenced unguarded.
_iw_state_dir() {
    printf '%s/%s' \
        "${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}" \
        "${_IW_STATE_SUBDIR}"
}

_iw_state_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_STATE_BASENAME}"
}

# Extract one string field from JSON on stdin.
#   $1 = jq filter, e.g. '.result.pane.pane_id' (used when jq is available).
#        The POSIX fallback derives the flat key from the filter's last
#        dot-segment (here: pane_id) and matches that key anywhere in the doc.
_iw_json_value() {
    local _json _key
    _json=$(cat)
    [ -n "${_json}" ] || return 0

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "${_json}" | jq -r "${1} // empty" 2>/dev/null
        return 0
    fi

    _key="${1##*.}"

    # One JSON token per line first, so the greedy `.*` below cannot skip past
    # the wanted key into a later one on the same (single-line) document.
    printf '%s' "${_json}" |
        awk '{ gsub(/[,{}]/, "\n"); print }' |
        sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
        head -n 1
}

_iw_write_state() {
    local _dir _file
    _dir=$(_iw_state_dir)
    _file=$(_iw_state_file)

    if ! mkdir -p "${_dir}"; then
        ux_error "Cannot create state directory: ${_dir}"
        return 1
    fi

    # Fixed-shape object — printf is the data writer here, not UX output.
    printf '{ "workspace_id": "%s", "pane_id": "%s", "agent_name": "%s", "cwd": "%s" }\n' \
        "${_IW_WORKSPACE_ID}" "${_IW_PANE_ID}" "${_IW_AGENT_NAME}" "${_IW_CWD}" >"${_file}"
}

# Populate _IW_* from the state file. Returns non-zero when the file is
# absent or incomplete, which the caller treats as "bootstrap needed".
#
# Parses into locals and commits to the globals only once every required field
# is present: an empty/corrupt state file must leave the defaults (notably
# _IW_AGENT_NAME) intact, or the bootstrap that follows would run
# `herdr agent start ""`.
_iw_read_state() {
    local _file _json _ws _pane _agent _cwd
    _file=$(_iw_state_file)
    [ -f "${_file}" ] || return 1

    _json=$(cat "${_file}" 2>/dev/null) || return 1
    _ws=$(printf '%s' "${_json}" | _iw_json_value '.workspace_id')
    _pane=$(printf '%s' "${_json}" | _iw_json_value '.pane_id')
    _agent=$(printf '%s' "${_json}" | _iw_json_value '.agent_name')
    # Optional — state files written before the field existed have no cwd.
    _cwd=$(printf '%s' "${_json}" | _iw_json_value '.cwd')

    [ -n "${_ws}" ] || return 1
    [ -n "${_pane}" ] || return 1
    [ -n "${_agent}" ] || return 1

    _IW_WORKSPACE_ID="${_ws}"
    _IW_PANE_ID="${_pane}"
    _IW_AGENT_NAME="${_agent}"
    _IW_CWD="${_cwd}"
}

# Echo the CLAUDE_CONFIG_DIR the bootstrapped pane must run `claude` with —
# the same account routing `claude_yolo` applies (issue #1393). herdr's
# `--kind` enum has no `claude-yolo`, so the two effects of that wrapper are
# reproduced here instead: this env var, plus the
# `-- --dangerously-skip-permissions` tail on `herdr agent start`.
#
# Returns:
#   0  directory echoed on stdout
#   1  unknown account / missing directory (fail-fast, message already printed)
#   2  HOME unset — nothing to route against; caller degrades to no --env
#
# One narrow exception to the fail-fast (PR #1395 review): a user who never ran
# `claude-accounts setup` has no CLAUDE_ENABLED_ACCOUNTS whitelist at all and
# never named an account, so `_claude_resolve_account` rejects even the implicit
# `personal` default. Before #1393 the pane ran bare `claude` and worked for
# them; routing must not turn that into a hard failure, so ~/.claude is used
# when it exists. Every other resolution failure still fails fast — an explicit
# CLAUDE_DEFAULT_ACCOUNT whose dir is missing, or a non-empty whitelist that
# does not list the account, are real misconfigurations and silently switching
# accounts there would route the pane at the wrong credentials.
#
# claude.sh is sourced inside a subshell on purpose:
#   - its interactive guard (`case $- in *i*`) defines nothing at all in a
#     non-interactive cron run unless DOTFILES_FORCE_INIT is exported first;
#   - the subshell keeps its ~40 functions and aliases out of this script.
# ux_* diagnostics go to stderr (ux_error) or are suppressed, so only the
# resolved directory ever reaches stdout.
_iw_resolve_config_dir() {
    [ -n "${HOME:-}" ] || return 2

    (
        # Captured before claude.sh is sourced: the *caller's* environment is
        # what says whether the single-account fallback below applies.
        # set-but-empty CLAUDE_DEFAULT_ACCOUNT counts as explicitly set.
        _enabled="${CLAUDE_ENABLED_ACCOUNTS:-}"
        _default_set=0
        [ -z "${CLAUDE_DEFAULT_ACCOUNT+x}" ] || _default_set=1

        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT

        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/tools/integrations/claude.sh" >&2 || {
            ux_error "Cannot load ${_IW_SHELL_COMMON}/tools/integrations/claude.sh — CLAUDE_CONFIG_DIR unresolvable."
            exit 1
        }

        # Internal-PC single-account override (issue #571): the multi-account
        # layout is off there, so this branch must run before account
        # resolution — an empty CLAUDE_ENABLED_ACCOUNTS must not fail the tick.
        if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
            _cfg_dir="$HOME/.claude"
        else
            _account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
            _cfg_dir=$(_claude_resolve_account "${_account}") || {
                # No multi-account opt-in at all *and* no account was asked
                # for — the pre-#1393 single-account user. ux_* writes to
                # stdout, which this subshell reserves for the resolved path.
                if [ -z "${_enabled}" ] && [ "${_default_set}" -eq 0 ] &&
                    [ -d "$HOME/.claude" ]; then
                    ux_warning "CLAUDE_ENABLED_ACCOUNTS not configured — falling back to \$HOME/.claude (single-account mode)." >&2
                    ux_info "Run 'claude-accounts setup' to opt into multi-account routing." >&2
                    printf '%s' "$HOME/.claude"
                    exit 0
                fi
                ux_error "Unknown claude account: ${_account} — cannot set CLAUDE_CONFIG_DIR for the watcher pane."
                ux_info "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
                exit 1
            }
        fi

        if [ ! -d "${_cfg_dir}" ]; then
            ux_error "Claude account directory missing: ${_cfg_dir} — cannot bootstrap the watcher pane."
            ux_info "Run: claude-accounts setup"
            exit 1
        fi

        printf '%s' "${_cfg_dir}"
    )
}

# Create the dedicated workspace, start a claude agent in its root pane, and
# persist the resulting ids. Idempotent at the tick level: only ever called
# when there is no usable state.
_iw_bootstrap() {
    local _cwd="$1" _ws_json _cfg_dir=""

    _cfg_dir=$(_iw_resolve_config_dir)
    case "$?" in
    0) ;;
    2)
        _cfg_dir=""
        ux_warning "HOME is unset — starting claude without CLAUDE_CONFIG_DIR account routing."
        ;;
    *)
        return 1
        ;;
    esac

    ux_info "Bootstrapping herdr workspace (label: ${_IW_LABEL}, cwd: ${_cwd})"
    _IW_CWD="${_cwd}"

    # POSIX-safe optional argument (no bash arrays): build the flag list in the
    # positional parameters, which are function-local here.
    set -- --cwd "${_cwd}" --label "${_IW_LABEL}" --no-focus
    [ -z "${_cfg_dir}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_cfg_dir}"

    _ws_json=$(herdr workspace create "$@" 2>/dev/null) ||
        _ws_json=""

    _IW_WORKSPACE_ID=$(printf '%s' "${_ws_json}" | _iw_json_value '.result.workspace.workspace_id')
    _IW_PANE_ID=$(printf '%s' "${_ws_json}" | _iw_json_value '.result.root_pane.pane_id')

    if [ -z "${_IW_WORKSPACE_ID}" ] || [ -z "${_IW_PANE_ID}" ]; then
        ux_error "herdr workspace create failed — no workspace_id/pane_id in the response."
        return 1
    fi

    # `-- ARG...` is passed through to the pane's claude invocation. Unattended
    # cron ticks must never stop on a permission-approval prompt (issue #1393).
    if ! herdr agent start "${_IW_AGENT_NAME}" --kind claude --pane "${_IW_PANE_ID}" \
        -- --dangerously-skip-permissions >/dev/null 2>&1; then
        ux_error "herdr agent start ${_IW_AGENT_NAME} failed (pane ${_IW_PANE_ID})."
        return 1
    fi

    _iw_write_state || return 1

    ux_success "Bootstrapped workspace=${_IW_WORKSPACE_ID} pane=${_IW_PANE_ID} agent=${_IW_AGENT_NAME}"
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query (agent missing / pane closed).
_iw_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "${_IW_AGENT_NAME}" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _iw_json_value '.result.agent.agent_status'
}

# Wait for a freshly (re-)bootstrapped agent to report idle before prompting it.
# `herdr agent start` only confirms the pane looks interactive — a claude process
# can have drawn its prompt box before its key-input loop accepts Enter, so the
# dispatcher text is typed but never submitted and herdr's fixed 5s stall check
# fires `agent_prompt_stalled` (issue #1399). The first-bootstrap path gets this
# grace for free from the status query that follows it; this gives the
# re-bootstrap path the same. Capped at ~5s (10 checks, 0.5s apart): far below
# the 5-minute tick interval, and hitting the cap still dispatches because the
# stall retry in _iw_dispatch is the second line of defence.
_iw_wait_for_idle() {
    local _i=0 _status _get_failed=0

    while [ "${_i}" -lt 10 ]; do
        if _status=$(_iw_agent_status); then
            [ "${_status}" != "idle" ] || return 0
        else
            _status=""
            _get_failed=$((_get_failed + 1))
        fi
        _i=$((_i + 1))
        [ "${_i}" -lt 10 ] || break
        sleep 0.5
    done

    # Health-check failures (agent missing / pane closed) and a merely slow
    # `starting` pane both fall through to this warning today — surface the
    # failure count so a genuinely-gone agent doesn't read as "just slow"
    # (PR #1400 codex review).
    if [ "${_get_failed}" -gt 0 ]; then
        ux_warning "Agent ${_IW_AGENT_NAME} did not report idle within ~5s (${_get_failed}/10 health-check failures) — dispatching anyway."
    else
        ux_warning "Agent ${_IW_AGENT_NAME} did not report idle within ~5s — dispatching anyway."
    fi
}

# Echo herdr's JSON response on stdout; the exit code is herdr's own.
_iw_prompt_once() {
    herdr agent prompt "${_IW_AGENT_NAME}" "${_IW_PROMPT}" \
        --wait --timeout "${_IW_TIMEOUT_MS}" 2>/dev/null
}

_iw_dispatch() {
    local _json _code _rc=0 _post_stall_status

    _json=$(_iw_prompt_once) || _rc=$?

    # Only `agent_prompt_stalled` is retried: it means the keystroke was dropped
    # by a not-yet-ready input loop (issue #1399), which a second later is gone.
    # Every other error is a real failure and must not be re-sent — a duplicate
    # prompt would start a second dispatcher cycle.
    if [ "${_rc}" -ne 0 ]; then
        _code=$(printf '%s' "${_json}" | _iw_json_value '.error.code')
        if [ "${_code}" = "agent_prompt_stalled" ]; then
            # `agent_prompt_stalled` only proves herdr saw no state change
            # within its fixed 5s window — it does NOT prove the prompt was
            # never submitted (PR #1400 codex review). `working` is positive
            # evidence the first call *did* land, so retrying would type the
            # same dispatcher text into an already-busy pane; any other
            # status gives no such evidence, so the retry proceeds as before.
            _post_stall_status=$(_iw_agent_status) || _post_stall_status=""
            if [ "${_post_stall_status}" = "working" ]; then
                ux_warning "herdr reported agent_prompt_stalled but agent is already working — treating as delivered, not retrying."
                _rc=0
            else
                ux_warning "herdr reported agent_prompt_stalled — retrying once."
                sleep 1
                _rc=0
                _json=$(_iw_prompt_once) || _rc=$?
            fi
        fi
    fi

    if [ "${_rc}" -eq 0 ]; then
        ux_success "Dispatched to ${_IW_AGENT_NAME}: ${_IW_PROMPT}"
        return 0
    fi

    ux_error "herdr agent prompt failed for agent ${_IW_AGENT_NAME}."
    return 1
}

# ============================================================
# Rate-limit gate (issue #1436)
# ============================================================

# Token-limit exhaustion is invisible to this tick by default: `herdr agent
# prompt` hands the dispatcher prompt over and returns, so a claude session
# that starts and then stops on a spent quota still reads as a delivered
# dispatch. Worse, by then the dispatcher has created the `issue-<n>`
# worktrees its own dedup check keys on, so those issues are never offered
# again — exhaustion becomes silent loss, not merely waste.
#
# The gate below holds dispatches after repeated unhealthy cycles and reopens
# itself on a timer. It is deliberately evidence-poor and fail-open (NF-1): a
# detector that can wedge the watcher is worse than the leak it guards.
#
# Why it watches this agent and not the `iw-<n>` panes the issue's option A
# names: the tick cannot address those panes. Their issue numbers are chosen by
# the dispatcher inside the pane and never reported back, and `herdr agent
# list` carries no agent-name field to recover them from. The same signal is
# reachable one level up — a spent quota stops the `iw-watch` claude session
# too, so its dispatcher prompt draws no state change, herdr answers
# `agent_prompt_stalled`, the retry stalls as well and `_iw_dispatch` fails.
# `_iw_agent_status` (option A's own helper) then separates a real wall from an
# unrelated hiccup: an agent reporting `working`/`blocked` is alive and busy,
# so that failure earns no strike.

_iw_limit_state_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_LIMIT_STATE_BASENAME}"
}

# Echo one field of the gate state file, or nothing. A missing file, an
# unreadable one and an absent field are all "nothing" on purpose — every
# caller reads that as "no gate" and proceeds (NF-1).
_iw_limit_read() {
    local _file
    _file=$(_iw_limit_state_file)
    [ -f "${_file}" ] || return 0
    _iw_json_value ".$1" <"${_file}" 2>/dev/null
}

# Persist strikes + backoff deadline. Both are written as JSON *strings*: the
# jq-less branch of _iw_json_value only matches quoted values, and a bare cron
# environment is exactly where jq is likely to be missing.
_iw_limit_write() {
    local _dir _file
    _dir=$(_iw_state_dir)
    _file=$(_iw_limit_state_file)

    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — the rate-limit gate will not survive this tick."
        return 1
    fi

    if ! printf '{ "strikes": "%s", "backoff_until": "%s" }\n' "$1" "$2" >"${_file}" 2>/dev/null; then
        ux_warning "Cannot write ${_file} — the rate-limit gate will not survive this tick."
        return 1
    fi
}

_iw_limit_clear() {
    rm -f "$(_iw_limit_state_file)" 2>/dev/null || true
}

# Echo epoch seconds, or nothing when the clock is unreadable.
_iw_now() {
    local _now
    _now=$(date +%s 2>/dev/null) || return 0
    case "${_now}" in
    '' | *[!0-9]*) return 0 ;;
    esac
    printf '%s' "${_now}"
}

# The gate itself. Returns 0 when this tick may dispatch, non-zero when it must
# hold. Every unexpected input answers 0 — see NF-1.
_iw_limit_gate_check() {
    local _until _now _left

    [ -f "$(_iw_limit_state_file)" ] || return 0

    _until=$(_iw_limit_read backoff_until)
    case "${_until}" in
    *[!0-9]*)
        ux_warning "Rate-limit state is unreadable (backoff_until='${_until}') — dispatching anyway."
        return 0
        ;;
    '')
        # Present but fieldless: a truncated write or a hand edit. Strike
        # bookkeeping never produces this — _iw_limit_write always emits both
        # fields.
        ux_warning "Rate-limit state file has no backoff deadline — dispatching anyway."
        return 0
        ;;
    esac

    # 0 is the resting value written while strikes accumulate: evidence on
    # record, gate still open.
    [ "${_until}" -gt 0 ] || return 0

    _now=$(_iw_now)
    if [ -z "${_now}" ]; then
        ux_warning "Cannot read the clock — rate-limit gate ignored this tick."
        return 0
    fi

    # A deadline further out than twice its own length cannot have been written
    # by this script; a clock jump or a hand edit did it. Expiring beats
    # stalling forever (F-3).
    _left=$((_until - _now))
    if [ "${_left}" -le 0 ] || [ "${_left}" -gt $((_IW_LIMIT_BACKOFF_SECONDS * 2)) ]; then
        ux_info "Rate-limit gate reopened — backoff expired, resuming dispatch."
        _iw_limit_clear
        return 0
    fi

    ux_warning "Rate-limit gate closed — holding dispatch for ~$(((_left + 59) / 60))m (no worktree is created this tick)."
    return 1
}

# Record the outcome of the dispatch just attempted. $1 is _iw_dispatch's exit
# status. Two consecutive unhealthy dispatches shut the gate; one healthy one
# wipes the slate, so `_IW_LIMIT_STRIKES` really does count consecutive
# failures. 1 would hold the watcher over a single transient herdr blip; 2 buys
# that evidence for one extra tick (~5 min).
_iw_limit_record() {
    local _rc="$1" _status _strikes _now

    if [ "${_rc}" -eq 0 ]; then
        # A prompt herdr accepted means the agent changed state, i.e. it is
        # processing — `--wait` would not have returned otherwise.
        _iw_limit_clear
        return 0
    fi

    _status=$(_iw_agent_status) || _status=""
    case "${_status}" in
    working | blocked)
        ux_info "Dispatch failed but agent ${_IW_AGENT_NAME} is ${_status} — not a token-limit signal, gate untouched."
        _iw_limit_clear
        return 0
        ;;
    esac

    _strikes=$(_iw_limit_read strikes)
    case "${_strikes}" in
    '' | *[!0-9]*) _strikes=0 ;;
    esac
    _strikes=$((_strikes + 1))

    if [ "${_strikes}" -lt "${_IW_LIMIT_STRIKES}" ]; then
        ux_warning "Dispatch failed with agent ${_IW_AGENT_NAME} at '${_status:-none}' (${_strikes}/${_IW_LIMIT_STRIKES}) — possible token-limit exhaustion."
        _iw_limit_write "${_strikes}" "0" || true
        return 0
    fi

    _now=$(_iw_now)
    if [ -z "${_now}" ]; then
        ux_warning "Cannot read the clock — rate-limit gate left open despite ${_strikes} failed dispatches."
        return 0
    fi

    # Claude's quota windows run for hours, so a short backoff would only
    # re-dispatch into the same wall; 30 minutes keeps the recovery latency
    # (F-3) well inside one window while cutting the burn rate to zero.
    ux_warning "Rate-limit gate closed for $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — ${_strikes} consecutive dispatches failed with the agent idle (likely token limit)."
    _iw_limit_write "0" "$((_now + _IW_LIMIT_BACKOFF_SECONDS))" || true
}

# Gate + dispatch + bookkeeping as one step, so both call sites in main() stay
# short and cannot drift apart.
#   0  dispatched
#   1  dispatch failed (caller exits 1, unchanged from pre-#1436)
#   2  gate closed, nothing dispatched (caller exits 0 — a hold, not an error)
_iw_gated_dispatch() {
    local _rc=0

    _iw_limit_gate_check || return 2

    _iw_dispatch || _rc=$?
    _iw_limit_record "${_rc}"
    return "${_rc}"
}

# Single-instance guard. A cron tick can fire while the previous one is still
# blocked in `herdr agent prompt --wait`; without a lock both would observe
# `idle` and both dispatch, breaking the one-cycle-at-a-time invariant.
# Deliberately non-blocking: a skipped tick just retries 5 minutes later.
# Returns non-zero only when another tick holds the lock; a missing flock or an
# unusable state dir soft-degrades to "no protection" rather than failing.
_iw_acquire_lock() {
    local _dir _lock
    _dir=$(_iw_state_dir)
    _lock="${_dir}/${_IW_LOCK_BASENAME}"

    if ! command -v flock >/dev/null 2>&1; then
        ux_warning "flock not found — running without single-instance protection"
        return 0
    fi

    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — running without single-instance protection"
        return 0
    fi

    # The 2>/dev/null must be scoped to the group, not attached to `exec`:
    # `exec 9>FILE 2>/dev/null` applies *both* redirections permanently, muting
    # the whole script's stderr — every later ux_error would vanish from the
    # cron log. The group restores fd 2 on exit while fd 9 persists.
    if ! { exec 9>"${_lock}"; } 2>/dev/null; then
        ux_warning "Cannot open lock file (${_lock}) — running without single-instance protection"
        return 0
    fi

    if ! flock -n 9; then
        ux_warning "another issue_watcher_cron tick is already running — skip"
        return 1
    fi
}

_iw_usage() {
    ux_header "issue_watcher_cron"
    ux_info "Usage: issue_watcher_cron.sh [--cwd <PATH>] | [-h|--help|help]"
    ux_info "Runs one issue-watcher tick against the dedicated herdr workspace."
    ux_bullet "options"
    ux_bullet_sub "--cwd <PATH>   workspace working directory (default: git repo root)"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_STATE_BASENAME}"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_LIMIT_STATE_BASENAME}   (rate-limit gate)"
    ux_bullet "rate-limit gate"
    ux_bullet_sub "${_IW_LIMIT_STRIKES} dispatches in a row that fail with the agent idle close the gate"
    ux_bullet_sub "while closed the tick holds: no dispatcher prompt, no worktree, exit 0"
    ux_bullet_sub "it reopens by itself after $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — delete ${_IW_LIMIT_STATE_BASENAME} to reopen it now"
    ux_bullet "claude session (claude-yolo parity)"
    ux_bullet_sub "the pane runs claude --dangerously-skip-permissions (unattended cron)"
    ux_bullet_sub "internal setup mode  → CLAUDE_CONFIG_DIR=\$HOME/.claude"
    ux_bullet_sub "otherwise            → CLAUDE_CONFIG_DIR=\$HOME/.claude-\${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    ux_bullet_sub "  (that account must be listed in \$CLAUDE_ENABLED_ACCOUNTS)"
    ux_bullet_sub "no \$CLAUDE_ENABLED_ACCOUNTS and no \$CLAUDE_DEFAULT_ACCOUNT → \$HOME/.claude if it exists"
    ux_bullet_sub "the resolved directory must already exist — the tick fails fast otherwise"
    ux_bullet "crontab"
    ux_bullet_sub "*/5 * * * * /path/to/issue_watcher_cron.sh >> ~/.local/state/issue-watcher/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _status _rc

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _iw_usage
            exit 0
            ;;
        --cwd)
            if [ "$#" -lt 2 ]; then
                ux_error "--cwd requires a PATH argument."
                exit 1
            fi
            _cwd="$2"
            shift 2
            ;;
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'issue_watcher_cron.sh --help' for usage."
            exit 1
            ;;
        esac
    done

    if [ -z "${_cwd}" ]; then
        _cwd=$(git rev-parse --show-toplevel 2>/dev/null) || _cwd=""
    fi
    [ -n "${_cwd}" ] || _cwd="$PWD"

    ux_header "issue-watcher tick"

    if ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot run the issue-watcher tick."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    _iw_acquire_lock || exit 0

    if _iw_read_state; then
        ux_info "Reusing state: workspace=${_IW_WORKSPACE_ID} pane=${_IW_PANE_ID} agent=${_IW_AGENT_NAME}"
        # One global issue-watcher workspace by design (issue #1389): a later
        # --cwd never re-bootstraps, so say so instead of silently ignoring it.
        if [ -n "${_IW_CWD}" ] && [ "${_IW_CWD}" != "${_cwd}" ]; then
            ux_warning "Workspace was bootstrapped for ${_IW_CWD} — ignoring --cwd ${_cwd} (single global issue-watcher workspace)."
        fi
    else
        _iw_bootstrap "${_cwd}" || exit 1
    fi

    _status=$(_iw_agent_status) || _status=""

    case "${_status}" in
    idle | done)
        _iw_gated_dispatch
        _rc=$?
        [ "${_rc}" -ne 2 ] || exit 0
        [ "${_rc}" -eq 0 ] || exit 1
        ;;
    working | blocked)
        ux_warning "Agent ${_IW_AGENT_NAME} is ${_status} — skip this tick (previous cycle still running or awaiting approval)."
        exit 0
        ;;
    *)
        ux_warning "Agent ${_IW_AGENT_NAME} unreachable (status: ${_status:-none}) — stale state, re-bootstrapping."
        _iw_bootstrap "${_cwd}" || exit 1
        _iw_wait_for_idle
        _iw_gated_dispatch
        _rc=$?
        [ "${_rc}" -ne 2 ] || exit 0
        [ "${_rc}" -eq 0 ] || exit 1
        ;;
    esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
