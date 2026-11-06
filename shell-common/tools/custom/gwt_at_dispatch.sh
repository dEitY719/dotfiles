#!/bin/bash
# shell-common/tools/custom/gwt_at_dispatch.sh
# `gwt at` runner — one-shot unattended dispatch at a local HH:MM (#2355).
#
# The frontend (functions/git_worktree_at.sh) only prints help and execs this
# file, so every code path runs under bash whatever the user's shell is.
#
#   schedule  <HH:MM> --wt-name <slug> [--base <ref>] [--user <acct>] [--prompt <text...>]
#             validate now (the user is about to leave), write the job JSON,
#             start a detached `setsid` copy of this file on it, print a summary
#   list      job table; `lost` = pending/running whose runner pid is gone
#   cancel    <id> — pending jobs only; kills the runner after a pid+starttime
#             +cmdline check so a recycled pid is never signalled
#   --run     <job.json> — internal, the detached half: wall-clock wait, late
#             check, then the avatar-issue-watcher sequence (#2281):
#             gwt spawn -> CLAUDE_CONFIG_DIR -> herdr workspace/tab -> agent
#             start -> idle/settle -> `herdr agent prompt --wait`
#
# State: ${XDG_STATE_HOME:-$HOME/.local/state}/gwt-at/<id>.json + <id>.log
# (dir 700, files 600 — a prompt can carry tokens). The prompt travels in the
# job file, never in the detached argv.
#
# Linux only: setsid and /proc/<pid>/{stat,cmdline} are the liveness contract.
#
# No interactive guard: executed, never sourced.

set -u

# DOTFILES_ROOT / SHELL_COMMON + ux_lib, the same bootstrap as the cron
# entrypoints (#2144) — the detached copy has no interactive shell behind it.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/lib/cron_common.sh" && cron_bootstrap || exit 1
_GA_SHELL_COMMON="${SHELL_COMMON}"

for _ga_lib in lib/herdr_agent_name.sh lib/herdr_agent_lookup.sh tools/custom/lib/herdr_pane.sh; do
    if [ ! -f "${_GA_SHELL_COMMON}/${_ga_lib}" ]; then
        ux_error "${_ga_lib} not found under ${_GA_SHELL_COMMON} — gwt at cannot run."
        exit 1
    fi
    # shellcheck source=/dev/null
    . "${_GA_SHELL_COMMON}/${_ga_lib}" || exit 1
done

_GA_SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# ============================================================
# Constants (env overrides exist for the bats suite)
# ============================================================

_GA_AGENT_PREFIX="ga"
# Fire no later than this past fire_at (a laptop that slept through 20:00).
_GA_GRACE_S="${GWT_AT_GRACE_S:-1800}"
# Wall-clock re-check interval: a monotonic `sleep` stops during suspend.
_GA_TICK_S="${GWT_AT_TICK_S:-30}"
# Finished jobs older than this are hidden from `list` (shown with --all).
_GA_LIST_DAYS="${GWT_AT_LIST_DAYS:-3}"
# Serializes spawn -> tab create across jobs firing at the same minute.
_GA_LOCK_WAIT_S="${GWT_AT_LOCK_WAIT_S:-600}"
# herdr create retries (transient server hiccups) and their backoff.
_GA_CREATE_ATTEMPTS=3
_GA_RETRY_SLEEP="${GWT_AT_RETRY_SLEEP:-5}"
# The repo-wide "herdr just brought something up" constants — same values as
# avatar_issue_watcher.sh _IW_SETTLE_* / _IW_START_RETRY_SLEEP (#1571).
_GA_START_ATTEMPTS=3
_GA_START_RETRY_SLEEP="${GWT_AT_START_RETRY_SLEEP:-13}"
_GA_IDLE_POLL_MAX=10
_GA_IDLE_POLL_SLEEP="${GWT_AT_IDLE_POLL_SLEEP:-0.5}"
_GA_SETTLE_SECONDS="${GWT_AT_SETTLE_SECONDS:-13}"
_GA_SETTLE_POLL_SLEEP="${GWT_AT_SETTLE_POLL_SLEEP:-1}"
_GA_SETTLE_READ_LINES=15
_GA_SETTLE_NOT_READY_MARK="Not logged in"
_GA_PROMPT_TIMEOUT_MS="${GWT_AT_PROMPT_TIMEOUT_MS:-240000}"
_GA_ENTER_SLEEP="${GWT_AT_ENTER_SLEEP:-2}"

# ============================================================
# Clock / state
# ============================================================

# GWT_AT_NOW pins the clock for tests (no real sleep, deterministic dates).
_ga_now() {
    if [ -n "${GWT_AT_NOW:-}" ]; then
        printf '%s' "${GWT_AT_NOW}"
    else
        date +%s
    fi
}

_ga_state_dir() {
    _hp_state_dir gwt-at
}

# Echo the epoch of the next local <HH:MM> strictly after <now>: today when it
# is still ahead, else tomorrow (equal counts as passed). Shape is validated by
# the caller. GNU date only (see the Linux-only note in the header).
_ga_fire_epoch() {
    local _hhmm="$1" _now="$2" _today _e
    _today=$(date -d "@${_now}" +%F 2>/dev/null) || return 1
    _e=$(date -d "${_today} ${_hhmm}" +%s 2>/dev/null) || return 1
    if [ "${_e}" -le "${_now}" ]; then
        _e=$(date -d "$(date -d "${_today} +1 day" +%F) ${_hhmm}" +%s 2>/dev/null) || return 1
    fi
    printf '%s' "${_e}"
}

_ga_valid_hhmm() {
    case "$1" in
    [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) return 0 ;;
    esac
    return 1
}

# Field 22 of /proc/<pid>/stat (process start time), parsed after the last
# `)` because comm may itself contain spaces or parens. Empty when gone.
_ga_pid_starttime() {
    local _s
    _s=$(cat "/proc/$1/stat" 2>/dev/null) || return 0
    printf '%s' "${_s##*) }" | awk '{print $20}'
}

# True when <pid> is alive AND is the same process that recorded <starttime>.
_ga_pid_alive() {
    case "${1:-}" in '' | 0 | *[!0-9]*) return 1 ;; esac
    [ -n "${2:-}" ] && [ "$(_ga_pid_starttime "$1")" = "$2" ]
}

# True when <pid>'s cmdline is this runner working on job <id>.
_ga_pid_is_runner() {
    local _cmd
    _cmd=$(tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null) || return 1
    case "${_cmd}" in
    *gwt_at_dispatch.sh*"$2"*) return 0 ;;
    esac
    return 1
}

# jq <args...> applied to job file <1>, atomically (tmp + mv) under the state
# lock, so `cancel` and the runner never interleave a read-modify-write.
_ga_job_apply() {
    local _f="$1" _lock
    shift
    _lock="$(_ga_state_dir)/.job.lock"
    if command -v flock >/dev/null 2>&1 && (umask 077 && : >>"${_lock}") 2>/dev/null; then
        {
            flock -w 10 8 2>/dev/null || true
            _ga_job_swap "${_f}" "$@"
        } 8>>"${_lock}"
        return $?
    fi
    _ga_job_swap "${_f}" "$@"
}

_ga_job_swap() {
    local _f="$1" _tmp
    shift
    [ -f "${_f}" ] || return 1
    _tmp=$(mktemp "${_f}.tmp.XXXXXX" 2>/dev/null) || return 1
    if jq "$@" "${_f}" >"${_tmp}" 2>/dev/null && mv "${_tmp}" "${_f}" 2>/dev/null; then
        return 0
    fi
    rm -f "${_tmp}"
    return 1
}

# Transition job <1> from `pending` to <2>; rc 1 (file untouched) when it is
# no longer pending. The compare-and-set the cancel race hinges on.
_ga_job_claim() {
    # shellcheck disable=SC2016  # jq program text
    _ga_job_apply "$1" --arg s "$2" \
        'if .status == "pending" then .status = $s else error("not pending") end'
}

# Record the terminal <status> and <reason> on job <1>.
_ga_job_finish() {
    # shellcheck disable=SC2016  # jq program text
    _ga_job_apply "$1" --arg s "$2" --arg r "$3" --argjson t "$(_ga_now)" \
        '.status = $s | .exit_reason = $r | .finished_at = $t' ||
        ux_warning "Could not record status '$2' in $1."
}

_ga_field() {
    jq -r "$2 // empty" "$1" 2>/dev/null
}

# Echo the status `list` shows: the stored one, or `lost` when a pending /
# running job's runner is no longer the process that recorded it.
_ga_effective_status() {
    local _st _pid _start
    _st=$(_ga_field "$1" .status)
    case "${_st}" in
    pending | running)
        _pid=$(_ga_field "$1" .pid)
        _start=$(_ga_field "$1" .pid_starttime)
        _ga_pid_alive "${_pid}" "${_start}" || _st="lost"
        ;;
    esac
    printf '%s' "${_st}"
}

# ============================================================
# Repo / worktree
# ============================================================

# Main checkout of the checkout at <1> — a linked worktree resolves to the one
# that owns it (#2281 rule; copy of avatar_issue_watcher.sh _iw_main_checkout).
_ga_main_checkout() {
    local _common
    _common=$(cd "$1" 2>/dev/null && _c=$(git rev-parse --git-common-dir 2>/dev/null) &&
        cd "${_c}" && pwd -P) || return 1
    case "${_common}" in
    */.git) dirname "${_common}" ;;
    *) git -C "$1" rev-parse --show-toplevel 2>/dev/null ;;
    esac
}

# Worktree of main checkout <1> on `wt/<2>/<index>` with the highest index.
_ga_find_worktree() {
    git -C "$1" worktree list --porcelain 2>/dev/null | awk -v p="refs/heads/wt/$2/" '
        /^worktree / { wt = substr($0, 10) }
        /^branch / {
            b = substr($0, 8)
            if (index(b, p) != 1) next
            k = substr(b, length(p) + 1)
            if (k ~ /^[0-9]+$/ && (best == "" || k + 0 > best + 0)) { best = k; path = wt }
        }
        END { if (path != "") print path }'
}

# `gwt spawn --wt-name <2> [--base <3>]` from main checkout <1>, cron-safe.
# Copy of avatar_issue_watcher.sh _iw_gwt_spawn (#2281) — `_iw_*` is internal
# to that script and re-extracting it into a lib is a Non-Goal of #2355.
_ga_gwt_spawn() {
    (
        set +u # the gwt files are written for interactive shells, not nounset
        export DOTFILES_FORCE_INIT=1
        cd "$1" || exit 1
        # shellcheck source=/dev/null
        . "${_GA_SHELL_COMMON}/functions/git_worktree.sh" || exit 1
        # shellcheck source=/dev/null
        . "${_GA_SHELL_COMMON}/functions/git_worktree_spawn.sh" || exit 1
        if [ -n "${3:-}" ]; then
            git_worktree_spawn --wt-name "$2" --base "$3"
        else
            git_worktree_spawn --wt-name "$2"
        fi
    )
}

# CLAUDE_CONFIG_DIR for account <1> (empty: CLAUDE_DEFAULT_ACCOUNT / personal).
# rc as _hp_resolve_config_dir: 0 ok, 1 unusable (message printed), 2 no HOME.
_ga_config_dir() {
    if [ -n "${1:-}" ]; then
        CLAUDE_DEFAULT_ACCOUNT="$1" _hp_resolve_config_dir "${_GA_SHELL_COMMON}" gwt-at stderr "$1"
    else
        _hp_resolve_config_dir "${_GA_SHELL_COMMON}" gwt-at stderr ""
    fi
}

# ============================================================
# schedule
# ============================================================

_ga_schedule() {
    local _hhmm="" _name="" _base="" _account="" _prompt="" _prompt_set=0

    if [ "$#" -gt 0 ]; then
        _hhmm="$1"
        shift
    fi
    if ! _ga_valid_hhmm "${_hhmm}"; then
        ux_error "Invalid time: '${_hhmm}' — use 24-hour HH:MM (e.g. 20:00, 08:30)."
        ux_info "Run: gwt at --help"
        return 2
    fi

    # gwt spawn grammar (#650): --prompt is trailing and greedy.
    while [ "$#" -gt 0 ]; do
        if [ "${_prompt_set}" = 1 ]; then
            _prompt="${_prompt:+${_prompt} }$1"
            shift
            continue
        fi
        case "$1" in
        --wt-name | --base | --user)
            if [ "$#" -lt 2 ] || [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
                ux_error "$1 requires a value"
                return 2
            fi
            case "$1" in
            --wt-name) _name="$2" ;;
            --base) _base="$2" ;;
            --user) _account="$2" ;;
            esac
            shift 2
            ;;
        --prompt)
            _prompt_set=1
            shift
            ;;
        *)
            ux_error "Unknown argument: $1"
            ux_info "Run: gwt at --help"
            return 2
            ;;
        esac
    done

    if [ -z "${_name}" ]; then
        ux_error "--wt-name <slug> is required"
        return 2
    fi
    case "${_name}" in
    -* | */* | *" "*)
        ux_error "Invalid --wt-name: '${_name}' (no '/', no spaces, no leading dash)"
        return 2
        ;;
    esac

    local _c
    for _c in jq setsid herdr; do
        if ! command -v "${_c}" >/dev/null 2>&1; then
            ux_error "${_c} not found in PATH — gwt at needs it."
            return 1
        fi
    done
    if [ ! -r /proc/self/stat ]; then
        ux_error "/proc is not available — gwt at tracks its runner through /proc (Linux only)."
        return 1
    fi
    for _c in functions/git_worktree.sh functions/git_worktree_spawn.sh; do
        if [ ! -f "${_GA_SHELL_COMMON}/${_c}" ]; then
            ux_error "${_c} not found under ${_GA_SHELL_COMMON} — the runner could not spawn a worktree."
            return 1
        fi
    done

    local _repo
    if ! _repo=$(_ga_main_checkout .) || [ -z "${_repo}" ]; then
        ux_error "Not inside a git repository — run gwt at from the repo to work on."
        return 1
    fi

    local _agent
    if ! _agent=$(herdr_agent_name "${_GA_AGENT_PREFIX}" "$(basename "${_repo}")" "${_name}"); then
        ux_error "herdr agent name '${_GA_AGENT_PREFIX}-<repo>-${_name}' is invalid or over 32 chars — shorten --wt-name."
        ux_info "Allowed: lowercase a-z 0-9 _ - ; the repo part is cut to 16 chars."
        return 1
    fi

    if [ -n "${_base}" ] && ! git -C "${_repo}" rev-parse --verify --quiet "${_base}" >/dev/null 2>&1; then
        ux_error "--base '${_base}' is not a valid ref in ${_repo}."
        return 1
    fi

    # rc 2 (HOME unset) is not fatal: the runner then starts without routing.
    _ga_config_dir "${_account}" >/dev/null
    case "$?" in 0 | 2) ;; *) return 1 ;; esac

    local _agents
    if ! _agents=$(herdr_agent_list_json); then
        ux_error "herdr server is not reachable ('herdr agent list' failed) — start herdr and retry."
        return 1
    fi
    if printf '%s' "${_agents}" | jq -e --arg n "${_agent}" \
        '[.result.agents[]? | select(.name == $n)] | length > 0' >/dev/null 2>&1; then
        ux_error "herdr agent '${_agent}' is already running — close it or pick another --wt-name."
        return 1
    fi

    local _dir
    _dir=$(_ga_state_dir)
    if ! (umask 077 && mkdir -p "${_dir}") || ! chmod 700 "${_dir}"; then
        ux_error "Cannot create state directory ${_dir}."
        return 1
    fi

    local _f _st
    for _f in "${_dir}"/*.json; do
        [ -f "${_f}" ] || continue
        [ "$(_ga_field "${_f}" .agent_name)" = "${_agent}" ] || continue
        _st=$(_ga_effective_status "${_f}")
        case "${_st}" in
        pending | running)
            ux_error "Job $(_ga_field "${_f}" .id) (${_st}) already targets agent ${_agent} — cancel it or pick another --wt-name."
            return 1
            ;;
        esac
    done

    local _now _fire _id _job _log
    _now=$(_ga_now)
    if ! _fire=$(_ga_fire_epoch "${_hhmm}" "${_now}"); then
        ux_error "Could not compute the fire time for ${_hhmm} (GNU date required)."
        return 1
    fi
    _id="$(date -d "@${_now}" +%m%d-%H%M%S)-$$"
    _job="${_dir}/${_id}.json"
    _log="${_dir}/${_id}.log"

    if ! (umask 077 && jq -n \
        --arg id "${_id}" --argjson fire "${_fire}" --arg repo "${_repo}" \
        --arg wt "${_name}" --arg base "${_base}" --arg prompt "${_prompt}" \
        --arg account "${_account}" --arg agent "${_agent}" --argjson now "${_now}" \
        '{id: $id, fire_at: $fire, repo: $repo, wt_name: $wt, base: $base,
          prompt: $prompt, account: $account, agent_name: $agent,
          pid: 0, pid_starttime: "", status: "pending",
          created_at: $now, finished_at: null, exit_reason: ""}' >"${_job}" &&
        : >>"${_log}"); then
        ux_error "Could not write the job file ${_job}."
        return 1
    fi

    if [ "${GWT_AT_NO_DETACH:-0}" = 1 ]; then
        ux_info "GWT_AT_NO_DETACH=1 — job written, runner not started."
    else
        # New session: survives the terminal closing and the user logging out.
        setsid bash "${_GA_SELF}" --run "${_job}" </dev/null >>"${_log}" 2>&1 &
        local _pid=$! _start="" _i=0
        # Record pid+starttime here too, so `list` right after scheduling is
        # not `lost` while the runner is still starting (it re-records itself).
        while [ -z "${_start}" ] && [ "${_i}" -lt 20 ]; do
            _start=$(_ga_pid_starttime "${_pid}")
            _i=$((_i + 1))
        done
        # shellcheck disable=SC2016  # jq program text
        _ga_job_apply "${_job}" --argjson p "${_pid}" --arg s "${_start}" \
            'if .pid == 0 then .pid = $p | .pid_starttime = $s else . end' || true
    fi

    ux_header "gwt at — scheduled"
    ux_info "  Job:    ${_id}"
    ux_info "  Fires:  $(date -d "@${_fire}" '+%Y-%m-%d (%a) %H:%M')"
    ux_info "  Repo:   ${_repo}"
    ux_info "  Name:   ${_name}${_base:+ (base ${_base})}"
    ux_info "  Agent:  ${_agent}${_account:+ (account ${_account})}"
    ux_info "  Prompt: ${_prompt:-(none — claude opens idle)}"
    ux_info "  Log:    ${_log}"
    ux_warning "claude runs WITHOUT permission prompts (--dangerously-skip-permissions)."
    ux_info "Survives terminal close and logout; lost on reboot; skipped (missed) if it wakes >$((_GA_GRACE_S / 60))m late."
    ux_info "Manage: gwt at list | gwt at cancel ${_id}"
}

# ============================================================
# list / cancel
# ============================================================

_ga_list() {
    local _all=0 _dir _f _st _now _fin _any=0 _p
    [ "${1:-}" = "--all" ] && _all=1
    _dir=$(_ga_state_dir)
    _now=$(_ga_now)

    for _f in "${_dir}"/*.json; do
        [ -f "${_f}" ] || continue
        _st=$(_ga_effective_status "${_f}")
        case "${_st}" in
        pending | running) ;;
        *)
            _fin=$(_ga_field "${_f}" .finished_at)
            [ -n "${_fin}" ] || _fin=$(_ga_field "${_f}" .fire_at)
            if [ "${_all}" = 0 ] && [ -n "${_fin}" ] &&
                [ $((_now - _fin)) -gt $((_GA_LIST_DAYS * 86400)) ]; then
                continue
            fi
            ;;
        esac
        if [ "${_any}" = 0 ]; then
            ux_header "gwt at jobs"
            ux_table_header "ID" "FIRES" "STATUS" "REPO/WT-NAME  PROMPT"
            _any=1
        fi
        _p=$(_ga_field "${_f}" .prompt)
        [ "${#_p}" -le 30 ] || _p="${_p:0:27}..."
        ux_table_row "$(_ga_field "${_f}" .id)" \
            "$(date -d "@$(_ga_field "${_f}" .fire_at)" '+%m-%d %H:%M' 2>/dev/null)" \
            "${_st}" \
            "$(basename "$(_ga_field "${_f}" .repo)")/$(_ga_field "${_f}" .wt_name)  ${_p:--}"
    done

    if [ "${_any}" = 0 ]; then
        ux_info "No gwt at jobs (finished ones older than ${_GA_LIST_DAYS}d hidden; see: gwt at list --all)."
    fi
    return 0
}

_ga_cancel() {
    local _id="${1:-}" _job _st _pid _start
    case "${_id}" in
    '' | */* | .*)
        ux_error "Usage: gwt at cancel <id>   (ids: gwt at list)"
        return 2
        ;;
    esac
    _job="$(_ga_state_dir)/${_id}.json"
    if [ ! -f "${_job}" ]; then
        ux_error "No such job: ${_id}"
        return 1
    fi

    _st=$(_ga_effective_status "${_job}")
    if [ "${_st}" != "pending" ]; then
        case "${_st}" in
        running) ux_error "Job ${_id} already fired (running) — refusing to cancel a half-built dispatch." ;;
        lost) ux_error "Job ${_id} is lost — its runner is gone (reboot?); nothing to cancel." ;;
        *) ux_error "Job ${_id} is ${_st:-unreadable} — only pending jobs can be cancelled." ;;
        esac
        return 1
    fi

    _pid=$(_ga_field "${_job}" .pid)
    _start=$(_ga_field "${_job}" .pid_starttime)
    if ! _ga_pid_alive "${_pid}" "${_start}" || ! _ga_pid_is_runner "${_pid}" "${_id}"; then
        ux_error "pid ${_pid} is not this job's runner — not killing it."
        return 1
    fi

    # Compare-and-set first: a runner that wakes now re-reads `cancelled` and
    # exits even if the kill below loses the race.
    if ! _ga_job_claim "${_job}" cancelled; then
        ux_error "Job ${_id} fired just now — refusing to cancel."
        return 1
    fi
    # shellcheck disable=SC2016  # jq program text
    _ga_job_apply "${_job}" --argjson t "$(_ga_now)" \
        '.finished_at = $t | .exit_reason = "cancelled by user"' || true
    kill "${_pid}" 2>/dev/null || true
    ux_success "Cancelled job ${_id}."
}

# ============================================================
# --run (the detached half)
# ============================================================

_ga_herdr_message() {
    local _json="$1" _errfile="$2" _msg
    _msg=$(printf '%s' "${_json}" | _hp_json_value '.error.message')
    if [ -z "${_msg}" ] && [ -s "${_errfile}" ]; then
        _msg=$(_hp_json_value '.error.message' <"${_errfile}")
        [ -n "${_msg}" ] || _msg=$(head -n 1 "${_errfile}" 2>/dev/null)
    fi
    printf '%s' "${_msg}"
}

# Start agent <1> on pane <2>; retries only agent_pane_busy, accepts the
# trust dialog. On failure _GA_FAIL holds `<code>: <herdr sentence>`.
_ga_start_agent() {
    local _agent="$1" _pane="$2" _errf _json _code _i=1
    _errf=$(mktemp) || _errf=/dev/null
    while :; do
        if _json=$(_hp_agent_start "${_agent}" "${_pane}" "${_errf}"); then
            [ "${_errf}" = /dev/null ] || rm -f "${_errf}"
            return 0
        fi
        _code=$(_hp_herdr_error_code "${_json}" "${_errf}")
        if [ "${_code}" = "agent_not_ready" ] && _hp_accept_trust_dialog "${_pane}"; then
            ux_info "Accepted the trust-folder dialog on pane ${_pane}."
            [ "${_errf}" = /dev/null ] || rm -f "${_errf}"
            return 0
        fi
        if [ "${_code}" != "agent_pane_busy" ] || [ "${_i}" -ge "${_GA_START_ATTEMPTS}" ]; then
            break
        fi
        ux_warning "agent start hit agent_pane_busy (${_i}/${_GA_START_ATTEMPTS}) — retrying in ${_GA_START_RETRY_SLEEP}s."
        [ "${_GA_START_RETRY_SLEEP}" = 0 ] || sleep "${_GA_START_RETRY_SLEEP}"
        _i=$((_i + 1))
    done
    _GA_FAIL="${_code:-unknown}: $(_ga_herdr_message "${_json}" "${_errf}")"
    [ "${_errf}" = /dev/null ] || rm -f "${_errf}"
    return 1
}

# Send <2> to agent <1> and confirm it landed. One Enter recovery on
# agent_prompt_stalled (the text is typed but unsubmitted, #1443) — never a
# second prompt, so the task cannot run twice.
_ga_prompt() {
    local _agent="$1" _prompt="$2" _json _rc=0 _code
    _json=$(herdr agent prompt "${_agent}" "${_prompt}" --wait \
        --timeout "${_GA_PROMPT_TIMEOUT_MS}" 2>&1) || _rc=$?
    [ "${_rc}" -eq 0 ] && return 0

    _code=$(printf '%s' "${_json}" | _hp_json_value '.error.code')
    if [ "${_code}" = "agent_prompt_stalled" ]; then
        [ "$(_hp_agent_status "${_agent}")" = "working" ] && return 0
        herdr agent send-keys "${_agent}" Enter >/dev/null 2>&1 || true
        [ "${_GA_ENTER_SLEEP}" = 0 ] || sleep "${_GA_ENTER_SLEEP}"
        [ "$(_hp_agent_status "${_agent}")" = "working" ] && return 0
    fi
    _GA_FAIL="${_code:-unknown}: $(printf '%s' "${_json}" | _hp_json_value '.error.message')"
    return 1
}

# Release the dispatch lock (fd 9). Grouped so the 2>/dev/null does not stick
# to the whole script the way a bare `exec ... 2>/dev/null` would.
_ga_unlock() {
    { exec 9>&-; } 2>/dev/null
}

# The dispatch proper. rc 0 = done; rc 1 = failed with _GA_FAIL set.
_ga_dispatch() {
    local _job="$1" _repo _name _base _prompt _account _agent _cfg _rc=0
    local _wt _label _ws _json _pane _tab _attempt=1

    _repo=$(_ga_field "${_job}" .repo)
    _name=$(_ga_field "${_job}" .wt_name)
    _base=$(_ga_field "${_job}" .base)
    _prompt=$(_ga_field "${_job}" .prompt)
    _account=$(_ga_field "${_job}" .account)
    _agent=$(_ga_field "${_job}" .agent_name)

    _cfg=$(_ga_config_dir "${_account}") || _rc=$?
    case "${_rc}" in
    0) ;;
    2)
        _cfg=""
        ux_warning "HOME is unset — starting claude without CLAUDE_CONFIG_DIR routing."
        ;;
    *)
        _GA_FAIL="account_unusable: ${_account:-default} (see log)"
        return 1
        ;;
    esac

    # spawn -> tab create, one job at a time (workspace label race, quota).
    # fd 9 is released before the long prompt wait.
    _hp_acquire_lock "$(_ga_state_dir)" .dispatch.lock gwt-at "${_GA_LOCK_WAIT_S}" || {
        _GA_FAIL="dispatch_lock_timeout: another gwt at job held the lock >${_GA_LOCK_WAIT_S}s"
        return 1
    }

    if ! _ga_gwt_spawn "${_repo}" "${_name}" "${_base}"; then
        _ga_unlock
        _GA_FAIL="gwt_spawn_failed: ${_repo} --wt-name ${_name}"
        return 1
    fi
    _wt=$(_ga_find_worktree "${_repo}" "${_name}")
    if [ -z "${_wt}" ] || [ ! -d "${_wt}" ]; then
        _ga_unlock
        _GA_FAIL="worktree_missing: no wt/${_name}/* after spawn"
        return 1
    fi
    ux_info "Worktree: ${_wt}"
    _label=$(basename "${_repo}")

    while :; do
        _GA_FAIL=""
        _tab=""
        if ! _ws=$(_hp_workspace_for_label "${_cfg}" "${_label}" "${_repo}"); then
            _GA_FAIL="herdr_workspace_failed: label ${_label}"
        elif ! _json=$(_hp_herdr_create "${_cfg}" "${_wt}" "${_agent}" tab create --workspace "${_ws}"); then
            _GA_FAIL="herdr_tab_create_failed: $(printf '%s' "${_json}" | _hp_json_value '.error.code')"
        else
            _pane=$(printf '%s' "${_json}" | _hp_json_first pane_id)
            _tab=$(printf '%s' "${_json}" | _hp_json_first tab_id)
            if [ -z "${_pane}" ]; then
                _GA_FAIL="herdr_tab_create_failed: no pane_id"
            elif _ga_start_agent "${_agent}" "${_pane}"; then
                break
            fi
        fi
        [ -z "${_tab}" ] || herdr tab close "${_tab}" >/dev/null 2>&1 || true
        ux_warning "Attempt ${_attempt}/${_GA_CREATE_ATTEMPTS} failed — ${_GA_FAIL}"
        if [ "${_attempt}" -ge "${_GA_CREATE_ATTEMPTS}" ]; then
            _ga_unlock
            return 1
        fi
        [ "${_GA_RETRY_SLEEP}" = 0 ] || sleep $((_GA_RETRY_SLEEP * _attempt))
        _attempt=$((_attempt + 1))
    done
    _ga_unlock
    ux_info "Agent ${_agent} started (tab ${_tab}, pane ${_pane})."

    _hp_wait_for_idle "${_agent}" "${_GA_IDLE_POLL_MAX}" "${_GA_IDLE_POLL_SLEEP}" prompting
    [ -z "${_prompt}" ] && {
        ux_success "No prompt — claude left idle in ${_wt}."
        return 0
    }
    _hp_settle "${_agent}" "${_GA_SETTLE_SECONDS}" "${_GA_SETTLE_POLL_SLEEP}" \
        "${_GA_SETTLE_READ_LINES}" "${_GA_SETTLE_NOT_READY_MARK}"
    _ga_prompt "${_agent}" "${_prompt}" || return 1
    ux_success "Prompt landed on ${_agent}."
}

_ga_run() {
    local _job="$1" _id _fire _now _left _st
    if [ ! -f "${_job}" ]; then
        ux_error "No such job file: ${_job}"
        return 1
    fi
    _id=$(_ga_field "${_job}" .id)
    ux_info "[$(date '+%F %T')] runner $$ for job ${_id}"

    # shellcheck disable=SC2016  # jq program text
    _ga_job_apply "${_job}" --argjson p "$$" --arg s "$(_ga_pid_starttime $$)" \
        'if .status == "pending" then .pid = $p | .pid_starttime = $s else . end' || true

    _fire=$(_ga_field "${_job}" .fire_at)
    while :; do
        _st=$(_ga_field "${_job}" .status)
        if [ "${_st}" != "pending" ]; then
            ux_info "Job ${_id} is ${_st:-unreadable} — exiting."
            return 0
        fi
        _now=$(_ga_now)
        _left=$((_fire - _now))
        [ "${_left}" -gt 0 ] || break
        [ "${_left}" -le "${_GA_TICK_S}" ] || _left="${_GA_TICK_S}"
        sleep "${_left}"
    done

    if [ $((_now - _fire)) -gt "${_GA_GRACE_S}" ]; then
        _ga_job_claim "${_job}" missed || return 0
        _ga_job_finish "${_job}" missed "woke $(((_now - _fire) / 60))m late (grace $((_GA_GRACE_S / 60))m)"
        ux_warning "Job ${_id} missed — woke $(((_now - _fire) / 60))m after its fire time."
        return 0
    fi

    if ! _ga_job_claim "${_job}" running; then
        ux_info "Job ${_id} was cancelled just before firing — exiting."
        return 0
    fi
    ux_info "[$(date '+%F %T')] firing job ${_id}"

    _GA_FAIL=""
    if _ga_dispatch "${_job}"; then
        _ga_job_finish "${_job}" "done" ""
        return 0
    fi
    ux_error "Job ${_id} failed — ${_GA_FAIL}"
    _ga_job_finish "${_job}" failed "${_GA_FAIL}"
    return 1
}

# ============================================================
# main
# ============================================================

main() {
    case "${1:-}" in
    -h | --help | help)
        ux_info "Usage: gwt_at_dispatch.sh <HH:MM> --wt-name <slug> [...] | list [--all] | cancel <id>"
        ux_info "Front end and full help: gwt at --help"
        ;;
    --run)
        [ "$#" -ge 2 ] || {
            ux_error "--run requires a job file"
            return 2
        }
        _ga_run "$2"
        ;;
    list | ls | cancel)
        # Every field read goes through jq; without it list shows blanks.
        command -v jq >/dev/null 2>&1 || {
            ux_error "jq not found in PATH — gwt at needs it."
            return 1
        }
        case "$1" in
        cancel) shift; _ga_cancel "$@" ;;
        *) shift; _ga_list "$@" ;;
        esac
        ;;
    *)
        _ga_schedule "$@"
        ;;
    esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
