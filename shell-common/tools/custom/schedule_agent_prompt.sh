#!/bin/bash
# shell-common/tools/custom/schedule_agent_prompt.sh
# One-shot scheduler that types a prompt into explicitly selected herdr agent
# panes at a local HH:MM, and submits it (issue #1768).
#
# The failure this generalises (2026-09-05): a `/restart` was typed into a pane
# by hand and the Enter never followed, so the intended restart simply never
# ran. Nothing looked wrong — the call was accepted, it just had no effect.
# Every design choice below exists to make that shape impossible:
#
#   one call        `herdr agent prompt <pane> <text> --wait --until <state>`
#                   submits the text AND the agent-appropriate submission key
#                   atomically. Hand-chaining `pane send-text` with
#                   `agent send-keys ... enter` and a sleep would reproduce the
#                   original bug's shape (two calls, one blind delay, no
#                   confirmation) rather than fix it.
#   --wait          the confirmation. herdr answers `agent_prompt_stalled` when
#                   the agent never leaves its pre-submission state, and that
#                   is an injection FAILURE for that target, recorded as
#                   `stalled` — not a success we merely could not observe. A
#                   timeout AFTER that state change is the opposite case: the
#                   prompt landed, the agent is simply still working when the
#                   bound elapses (`submitted-working`).
#   exact cwd       a prompt lands on a pane, so the target must be the pane
#                   the user named — never a plausible neighbour. Zero or two
#                   matches refuse to inject rather than guess.
#   per target      each target resolves and injects on its own; one failure
#                   never skips the rest, and the job's exit status still says
#                   something went wrong.
#
# Usage:
#   schedule_agent_prompt.sh --at HH:MM --agent-cwd PATH [--agent-cwd PATH]...
#                            [--prompt TEXT] [--dry-run]
#   schedule_agent_prompt.sh --status
#   schedule_agent_prompt.sh --cancel [JOB_ID]
#   schedule_agent_prompt.sh --help
#
# No interactive guard: this file is executed, never sourced (same as
# session_doctor_cron.sh and every other tools/custom entry point).

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (before it exports
# SHELL_COMMON), so resolve shell-common from this script's own location as a
# fallback — the two-tier resolution session_doctor_cron.sh uses.
_SAP_SHELL_COMMON="${SHELL_COMMON:-$(cd "$(dirname "$0")/../.." && pwd)}"

if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${_SAP_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_SAP_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# The herdr SSOT (issue #1569): `herdr agent list` behind one wrapper, and the
# physical-path resolver. Both are reused rather than re-derived — see
# _sap_resolve_pane for the one predicate this file does NOT take from there.
if [ ! -f "${_SAP_SHELL_COMMON}/functions/herdr_agent_lookup.sh" ]; then
    ux_error "herdr_agent_lookup.sh not found under ${_SAP_SHELL_COMMON}/functions — cannot resolve agent panes."
    exit 1
fi
# shellcheck source=/dev/null
. "${_SAP_SHELL_COMMON}/functions/herdr_agent_lookup.sh" || exit 1

# The absolute path of this file, resolved before anything can change the
# working directory: the detached waiter re-executes it.
_SAP_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ============================================================
# Constants
# ============================================================

_SAP_DEFAULT_PROMPT="/restart"

# `--wait` bounds how long herdr is given to observe the agent leaving its
# pre-submission state. Generous (the target may be mid-turn when the clock
# strikes) but finite: a wait that never ends is the same as no confirmation.
_SAP_TIMEOUT_MS="${SCHEDULE_AGENT_PROMPT_TIMEOUT_MS:-60000}"

# The state `--wait` waits for. Empty on purpose: herdr's own default already
# matches `idle`, `done` OR `blocked` — every state a submitted prompt can
# settle into. Pinning `idle` narrowed that to one, so an agent that settled
# as `done` or `blocked` was reported as a failed injection even though the
# prompt had landed (PR #1770, codex BLOCKER). The env var still pins a single
# state for an agent whose settled state is known.
_SAP_UNTIL="${SCHEDULE_AGENT_PROMPT_UNTIL:-}"

# How often the detached waiter wakes to re-check the clock. Chunked rather
# than one long `sleep` so a suspended laptop cannot oversleep the whole wait,
# and so `--cancel` never has to outlive a day-long sleep.
_SAP_TICK_S="${SCHEDULE_AGENT_PROMPT_TICK_S:-30}"

_SAP_AT=""
_SAP_PROMPT="${_SAP_DEFAULT_PROMPT}"
_SAP_TARGETS=""
_SAP_DRY_RUN=0
_SAP_NL="
"

# ============================================================
# State — ${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/schedule-agent-prompt
# ============================================================

# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset, and a
# detached process can inherit an environment that bare. Same rule
# lib/session_doctor_state.sh follows.
_sap_state_dir() {
    printf '%s/dotfiles/schedule-agent-prompt' \
        "${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}"
}

_sap_lock_file() {
    _sap_d=$(_sap_state_dir)
    printf '%s/.state.lock' "${_sap_d}"
}

_sap_state_ensure() {
    _sap_d=$(_sap_state_dir)
    mkdir -p "${_sap_d}" 2>/dev/null || true
    # A job file carries the prompt text verbatim and the target cwd paths, so
    # a permissive umask would publish both to every account on the machine
    # (PR #1770, agy FOLLOW-UP). Best effort: a directory we cannot chmod is
    # still one the writability check below can reject on its own terms.
    chmod 700 "${_sap_d}" 2>/dev/null || true
    [ -d "${_sap_d}" ] && [ -w "${_sap_d}" ]
}

_sap_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf ''
}

# Apply jq arguments and a program to job file <1>, under the write lock.
#
# A separate lock file rather than the job file itself, and the whole
# read-modify-write inside it: `--cancel` and the dispatcher can touch one job
# at the same moment (that race IS cancellation), and a lock that ended before
# the rename would let one of the two writes land on a file the other had
# already replaced. Best effort throughout — no flock, or a holder that will
# not let go, degrades to an unlocked write rather than a lost job.
_sap_job_apply() {
    _sap_f="$1"
    shift
    _sap_lock=$(_sap_lock_file)

    if command -v flock >/dev/null 2>&1 && { : >>"${_sap_lock}"; } 2>/dev/null; then
        {
            flock -w 5 8 2>/dev/null || true
            _sap_job_swap "${_sap_f}" "$@"
        } 8>>"${_sap_lock}"
        return $?
    fi
    _sap_job_swap "${_sap_f}" "$@"
}

_sap_job_swap() {
    _sap_f="$1"
    shift
    [ -f "${_sap_f}" ] || return 1

    _sap_tmp=$(mktemp "${_sap_f}.tmp.XXXXXX" 2>/dev/null) || return 1
    if jq "$@" "${_sap_f}" >"${_sap_tmp}" 2>/dev/null; then
        mv "${_sap_tmp}" "${_sap_f}" 2>/dev/null && return 0
    fi
    rm -f "${_sap_tmp}"
    return 1
}

_sap_job_files() {
    _sap_d=$(_sap_state_dir)
    for _sap_f in "${_sap_d}"/*.json; do
        [ -f "${_sap_f}" ] || continue
        printf '%s\n' "${_sap_f}"
    done
}

# ============================================================
# Target resolution
# ============================================================

# _sap_resolve_pane <physical-cwd> — the pane_id of the ONE agent launched in
# <physical-cwd>.
#
#   0   exactly one match; the pane id is on stdout
#   1   herdr could not be asked (call failed, or answered nothing)
#   3   herdr answered; no agent has this cwd
#   4   herdr answered; two or more agents have this cwd
#
# Why this is not herdr_agent_match_for_cwd, despite that file being the
# repo's anti-drift SSOT for "which pane is at this path": its matching policy
# is deliberately different and wrong here. It matches `cwd` OR
# `foreground_cwd` on a directory boundary, and on multiple matches it takes
# the first and warns. That policy answers "is ANY agent still working
# somewhere under this worktree" — the right question for closing a tab or
# counting concurrency, where a near-miss costs nothing. This tool's answer
# decides where a keystroke lands, so it needs the opposite: `cwd` only
# (`foreground_cwd` drifts with every `cd`, while `cwd` is the pane's
# restart-stable launch identity), exact equality (a sibling checkout must
# never absorb its neighbour's prompt), and a refusal — never a first-match
# guess — when the count is not exactly one. Pointing this back at
# herdr_agent_match_for_cwd would silently restore all three.
#
# What it DOES reuse from that file is everything that is not the predicate:
# herdr_agent_list_json (one `herdr agent list`, rc 1 = unreachable, never
# "no agents") and herdr_agent_physical_path.
_sap_resolve_pane() {
    [ -n "${1-}" ] || return 3

    _sap_json=$(herdr_agent_list_json) || return 1

    _sap_panes=$(printf '%s' "${_sap_json}" | jq -r --arg p "$1" '
        if (.result.agents | type) == "array" then
          .result.agents[]? | select((.cwd // "") == $p) | (.pane_id // "")
        else error("no agent list") end
    ' 2>/dev/null) || return 1

    # Also covers a matched agent carrying no pane_id: herdr cannot be asked
    # to type into an empty pane id, and reporting success for it would be
    # the accepted-call-no-effect failure all over again.
    [ -n "${_sap_panes}" ] || return 3

    _sap_count=$(printf '%s\n' "${_sap_panes}" | grep -c '^') || _sap_count=0
    [ "${_sap_count}" -eq 1 ] || return 4

    printf '%s' "${_sap_panes}"
}

# Report why <cwd> could not be resolved, for rc <2>. One place, so the
# registration check and the dispatcher say the same thing.
_sap_resolve_error() {
    case "$2" in
    1) ux_error "herdr could not be asked about ${1} — nothing was injected. (Is the herdr server running?)" ;;
    4) ux_error "2 or more agents report cwd ${1} — refusing to guess which pane was meant." ;;
    *) ux_error "No agent reports cwd ${1} (exact match on the pane's launch cwd) — nothing to inject into." ;;
    esac
}

# _sap_resolve_target <cwd> — physical-path resolution plus _sap_resolve_pane,
# the two-step lookup both the dispatcher and the registration plan need
# before they can act on a --agent-cwd. On stdout: the pane id (rc 0) or
# nothing; rc mirrors _sap_resolve_pane's.
_sap_resolve_target() {
    _sap_phys=$(herdr_agent_physical_path "$1")
    _sap_resolve_pane "${_sap_phys}"
}

# ============================================================
# Injection
# ============================================================

# _sap_inject <pane> <prompt> — one `herdr agent prompt`, on stdout as
# `<outcome><TAB><observed-state><TAB><detail>`.
#
# outcome is `submitted`, `submitted-working`, `stalled` or `errored`; rc
# mirrors it (0 / 0 / 1 / 1).
_sap_inject() {
    if [ -n "${_SAP_UNTIL}" ]; then
        _sap_out=$(herdr agent prompt "$1" "$2" \
            --wait --until "${_SAP_UNTIL}" --timeout "${_SAP_TIMEOUT_MS}" 2>&1)
    else
        _sap_out=$(herdr agent prompt "$1" "$2" \
            --wait --timeout "${_SAP_TIMEOUT_MS}" 2>&1)
    fi
    _sap_rc=$?

    # herdr answers JSON on success; anything else (a plain-text error) leaves
    # the state empty rather than inventing one.
    _sap_state=$(printf '%s' "${_sap_out}" |
        jq -r '.result.agent_status // .result.state // ""' 2>/dev/null) || _sap_state=""

    _sap_detail=$(printf '%s' "${_sap_out}" | tr '\n\t' '  ' | cut -c1-200)

    if [ "${_sap_rc}" -eq 0 ]; then
        printf 'submitted\t%s\t%s' "${_sap_state}" "${_sap_detail}"
        return 0
    fi

    # Three different incidents hide behind a non-zero rc, and only two of them
    # are injection failures:
    #
    #   agent_prompt_stalled  herdr watched for 5s and the agent never left its
    #                         pre-submission state — the prompt did not take.
    #                         This IS the 2026-09-05 shape, and the one outcome
    #                         this tool exists to catch.
    #   any other timeout     reached only AFTER that state change, so the
    #                         prompt landed; the agent is still working when
    #                         the bound elapses. Calling that a failed
    #                         injection misreports a delivered prompt
    #                         (PR #1770, codex BLOCKER).
    #   anything else         herdr never accepted the call at all.
    case "${_sap_out}" in
    *agent_prompt_stalled*)
        printf 'stalled\t%s\t%s' "${_sap_state}" "${_sap_detail}"
        return 1
        ;;
    *timeout* | *Timeout* | *"timed out"* | *"Timed out"*)
        printf 'submitted-working\t%s\t%s' "${_sap_state}" "${_sap_detail}"
        return 0
        ;;
    esac
    printf 'errored\t%s\t%s' "${_sap_state}" "${_sap_detail}"
    return 1
}

# ============================================================
# Dispatch (the detached half)
# ============================================================

# Sleep until <1> (epoch seconds), in _SAP_TICK_S chunks.
_sap_wait_until() {
    while :; do
        _sap_left=$(($1 - $(date '+%s')))
        [ "${_sap_left}" -gt 0 ] || return 0
        [ "${_sap_left}" -gt "${_SAP_TICK_S}" ] && _sap_left="${_SAP_TICK_S}"
        sleep "${_sap_left}"
    done
}

# Is job <1> still pending? Says why not, so a `--dispatch` run by hand does
# not look like it silently did nothing.
_sap_pending() {
    _sap_status=$(jq -r '.status // ""' "$1" 2>/dev/null) || _sap_status=""
    [ "${_sap_status}" = "pending" ] && return 0
    ux_info "Job $(jq -r '.id // "?"' "$1" 2>/dev/null) is ${_sap_status:-unreadable} — not dispatching."
    return 1
}

_sap_dispatch() {
    _sap_job="$1"

    if [ ! -f "${_sap_job}" ]; then
        ux_error "No such job file: ${_sap_job}"
        return 1
    fi

    # Claim the job before the wait: `--cancel` kills this pid, and a job
    # whose pid is still the registering shell's could not be stopped.
    # shellcheck disable=SC2016  # jq program text — $p is jq's variable
    _sap_job_apply "${_sap_job}" --argjson p "$$" '.pid = $p' || true

    # Checked twice, before the wait and after it. Before, so a job cancelled
    # while this process was still starting up does not sit there for hours;
    # after, because that is when cancellation normally happens.
    _sap_pending "${_sap_job}" || return 0

    _sap_at=$(jq -r '.at_epoch // 0' "${_sap_job}" 2>/dev/null) || _sap_at=0
    _sap_wait_until "${_sap_at}"

    # Re-read, never trust the pre-sleep copy: cancellation happens during the
    # wait, and a kill that failed (a pid that had already been recycled, a
    # process that would not die) leaves this check as the only thing between
    # a cancelled job and a keystroke.
    _sap_pending "${_sap_job}" || return 0

    _sap_prompt=$(jq -r '.prompt // ""' "${_sap_job}" 2>/dev/null)
    _sap_failed=0

    # A here-doc, not a pipe: the failure counter has to survive the loop.
    while IFS= read -r _sap_cwd; do
        [ -n "${_sap_cwd}" ] || continue
        _sap_dispatch_one "${_sap_job}" "${_sap_cwd}" "${_sap_prompt}" || _sap_failed=1
    done <<EOF
$(jq -r '.targets[]?' "${_sap_job}" 2>/dev/null)
EOF

    if [ "${_sap_failed}" -eq 0 ]; then
        _sap_job_apply "${_sap_job}" '.status = "completed"' || true
        ux_success "Job complete — every target was submitted."
        return 0
    fi

    _sap_job_apply "${_sap_job}" '.status = "failed"' || true
    ux_error "Job complete with failures — see 'schedule-agent-prompt --status'."
    return 1
}

# One target: resolve, inject, record. Never returns early past the recording
# step — an unresolved or refused target is a result, not a silence.
_sap_dispatch_one() {
    _sap_jf="$1"
    _sap_c="$2"
    _sap_p="$3"

    _sap_pane=$(_sap_resolve_target "${_sap_c}")
    _sap_rrc=$?
    if [ "${_sap_rrc}" -ne 0 ]; then
        _sap_resolve_error "${_sap_c}" "${_sap_rrc}"
        _sap_record "${_sap_jf}" "${_sap_c}" "" "unresolved" "" "resolve rc=${_sap_rrc}"
        return 1
    fi

    _sap_res=$(_sap_inject "${_sap_pane}" "${_sap_p}")
    _sap_irc=$?
    _sap_outcome=$(printf '%s' "${_sap_res}" | cut -f1)
    _sap_st=$(printf '%s' "${_sap_res}" | cut -f2)
    _sap_dt=$(printf '%s' "${_sap_res}" | cut -f3)

    _sap_record "${_sap_jf}" "${_sap_c}" "${_sap_pane}" "${_sap_outcome}" "${_sap_st}" "${_sap_dt}"

    if [ "${_sap_irc}" -eq 0 ]; then
        ux_success "${_sap_c} (${_sap_pane}): ${_sap_outcome} — agent state ${_sap_st:-unknown}."
        return 0
    fi
    ux_error "${_sap_c} (${_sap_pane}): ${_sap_outcome} — agent state ${_sap_st:-unknown}. ${_sap_dt}"
    return 1
}

# Append one result to the job log. Every field the safety contract asks for:
# when, which cwd, which pane, the prompt's fate and the state herdr observed
# after the wait.
_sap_record() {
    _sap_stamp=$(_sap_now)
    # shellcheck disable=SC2016  # jq program text — $t/$c/$p/$o/$s/$d are jq's
    _sap_job_apply "$1" \
        --arg c "$2" --arg p "$3" --arg o "$4" --arg s "$5" --arg d "$6" --arg t "${_sap_stamp}" \
        '.results += [{at: $t, cwd: $c, pane_id: $p, outcome: $o, state: $s, detail: $d}]' ||
        ux_warning "Could not record the result for $2 — the job log is incomplete."
}

# ============================================================
# Registration
# ============================================================

# Local HH:MM -> epoch seconds, today. Empty output = not a time this machine
# can name.
#
# Two dialects because both are supported platforms (PR #1770, codex BLOCKER):
# GNU `date -d` first, then BSD/macOS `date -j -f`. On BSD `-d` is the
# daylight-savings flag, not "parse this date string", so the GNU form fails
# there and EVERY `--at` registration died on macOS with "could not turn --at
# into a local time". The BSD form is given the full date explicitly rather
# than relying on `-f '%H:%M'` field defaulting, which would inherit the
# current *second* and drift the wake-up by up to 59s.
_sap_epoch_for() {
    date -d "today $1" '+%s' 2>/dev/null ||
        date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') $1:00" '+%s' 2>/dev/null ||
        printf ''
}

_sap_register() {
    _sap_epoch=$(_sap_epoch_for "${_SAP_AT}")
    if [ -z "${_sap_epoch}" ]; then
        ux_error "Could not turn --at ${_SAP_AT} into a local time on this machine."
        return 1
    fi

    # Reject, never roll forward: "22:50" typed at 23:10 is a typo far more
    # often than it is a request for tomorrow night, and the difference is 24
    # unattended hours.
    if [ "${_sap_epoch}" -le "$(date '+%s')" ]; then
        ux_error "--at ${_SAP_AT} is in the past today — refusing to silently schedule it for tomorrow."
        return 1
    fi

    # Resolve every target NOW, so a typo is a message rather than a job that
    # quietly does nothing hours later. The dispatcher resolves again at
    # dispatch time: panes move, and the answer that matters is the one taken
    # when the prompt is actually sent.
    _sap_plan=""
    while IFS= read -r _sap_cwd; do
        [ -n "${_sap_cwd}" ] || continue
        _sap_pane=$(_sap_resolve_target "${_sap_cwd}")
        _sap_rrc=$?
        if [ "${_sap_rrc}" -ne 0 ]; then
            _sap_resolve_error "${_sap_cwd}" "${_sap_rrc}"
            return 1
        fi
        _sap_plan="${_sap_plan}${_sap_cwd}	${_sap_pane}${_SAP_NL}"
    done <<EOF
${_SAP_TARGETS}
EOF

    ux_header "schedule-agent-prompt"
    ux_info "At ${_SAP_AT} (local), submit this prompt to each target below:"
    ux_bullet "prompt: ${_SAP_PROMPT}"
    while IFS='	' read -r _sap_cwd _sap_pane; do
        [ -n "${_sap_cwd}" ] || continue
        ux_bullet_sub "${_sap_cwd} -> pane ${_sap_pane}"
    done <<EOF
${_sap_plan}
EOF

    if [ "${_SAP_DRY_RUN}" -eq 1 ]; then
        ux_success "Dry run — validated only. No job was registered and nothing was sent to herdr."
        return 0
    fi

    if ! _sap_state_ensure; then
        _sap_d=$(_sap_state_dir)
        ux_error "State directory is not writable (${_sap_d}) — a job that cannot be recorded cannot be cancelled either."
        return 1
    fi

    _sap_id="$(date '+%Y%m%d-%H%M%S')-$$"
    _sap_d=$(_sap_state_dir)
    _sap_file="${_sap_d}/${_sap_id}.json"
    _sap_log="${_sap_d}/${_sap_id}.log"

    # The targets survive as a newline-joined string right up to here, so this
    # is where they become JSON — one jq -R -s, rather than hand-quoting each
    # path into a literal array.
    _sap_targets_json=$(printf '%s' "${_SAP_TARGETS}" |
        jq -R -s 'split("\n") | map(select(length > 0))')

    if ! jq -n --arg id "${_sap_id}" --arg at "${_SAP_AT}" --argjson e "${_sap_epoch}" \
        --arg p "${_SAP_PROMPT}" --arg c "$(_sap_now)" \
        --argjson t "${_sap_targets_json}" \
        '{id: $id, created: $c, at: $at, at_epoch: $e, prompt: $p,
          status: "pending", pid: 0, results: [], targets: $t}' \
        >"${_sap_file}"; then
        ux_error "Could not write the job file (${_sap_file})."
        return 1
    fi

    # nohup rather than setsid: both survive the terminal closing, but nohup
    # execs in place, so `$!` really is the waiter's pid — with setsid the
    # shell may fork it, leaving `$!` pointing at a process that exits
    # immediately and a `--cancel` that kills nothing. (The waiter overwrites
    # `.pid` with its own `$$` first thing regardless, so the record is right
    # either way; this only keeps the window between the two writes honest.)
    nohup "${_SAP_SELF}" --dispatch "${_sap_file}" >>"${_sap_log}" 2>&1 </dev/null &
    _sap_pid=$!
    # shellcheck disable=SC2016  # jq program text — $p is jq's variable
    _sap_job_apply "${_sap_file}" --argjson p "${_sap_pid}" '.pid = $p' || true

    ux_success "Registered job ${_sap_id} (pid ${_sap_pid}) — dispatching at ${_SAP_AT}."
    ux_info "Log: ${_sap_log}"
    return 0
}

# ============================================================
# --status / --cancel
# ============================================================

_sap_status_cmd() {
    _sap_any=0
    while IFS= read -r _sap_jobf; do
        [ -n "${_sap_jobf}" ] || continue
        _sap_any=1
        ux_section "$(jq -r '.id // "?"' "${_sap_jobf}" 2>/dev/null)"
        ux_bullet "at $(jq -r '.at // "?"' "${_sap_jobf}" 2>/dev/null) — status $(jq -r '.status // "?"' "${_sap_jobf}" 2>/dev/null)"
        ux_bullet "prompt: $(jq -r '.prompt // ""' "${_sap_jobf}" 2>/dev/null)"
        while IFS= read -r _sap_line; do
            [ -n "${_sap_line}" ] || continue
            ux_bullet_sub "${_sap_line}"
        done <<EOF
$(jq -r '(.targets[]? | "target " + .),
         (.results[]? | "result " + .cwd + " (" + (.pane_id // "-") + "): " + .outcome
                        + " [" + (.state // "") + "]")' "${_sap_jobf}" 2>/dev/null)
EOF
    done <<EOF
$(_sap_job_files)
EOF

    if [ "${_sap_any}" -eq 0 ]; then
        ux_info "No scheduled jobs."
    fi
    return 0
}

# Cancel <1> (a job id), or every pending job when <1> is empty.
#
# Two halves, and both are needed: the status flips first (the dispatcher
# re-reads it after its sleep, so a job whose kill failed still refuses to
# inject), then the waiting process is killed (so a cancelled job does not sit
# around until its hour).
# Is <1> still this tool's own waiter? The pid was recorded when the job was
# registered and is read back minutes-to-hours later, by which time the OS may
# well have handed it to something else — and `kill` on a recycled pid signals
# a stranger (PR #1770, agy FOLLOW-UP). `ps -o args=` rather than
# /proc/<pid>/cmdline: the same portability line the `date` fix draws, since
# macOS has no /proc. No `ps` at all degrades to not killing, which is safe —
# the status flip above already stops the dispatcher.
_sap_is_our_waiter() {
    case "$(ps -p "$1" -o args= 2>/dev/null)" in
    *schedule_agent_prompt*) return 0 ;;
    esac
    return 1
}

_sap_cancel_cmd() {
    _sap_want="${1-}"
    _sap_any=0

    while IFS= read -r _sap_jobf; do
        [ -n "${_sap_jobf}" ] || continue
        _sap_id=$(jq -r '.id // ""' "${_sap_jobf}" 2>/dev/null)
        _sap_st=$(jq -r '.status // ""' "${_sap_jobf}" 2>/dev/null)
        if [ -n "${_sap_want}" ]; then
            [ "${_sap_id}" = "${_sap_want}" ] || continue
            case "${_sap_st}" in
            pending) ;;
            *)
                ux_error "Job ${_sap_id} is already ${_sap_st} — nothing to cancel."
                return 1
                ;;
            esac
        else
            [ "${_sap_st}" = "pending" ] || continue
        fi

        _sap_job_apply "${_sap_jobf}" '.status = "cancelled"' || true
        _sap_pid=$(jq -r '.pid // 0' "${_sap_jobf}" 2>/dev/null)
        if [ -n "${_sap_pid}" ] && [ "${_sap_pid}" -gt 0 ] 2>/dev/null &&
            _sap_is_our_waiter "${_sap_pid}"; then
            kill "${_sap_pid}" 2>/dev/null || true
        fi
        ux_success "Cancelled job ${_sap_id}."
        _sap_any=1
    done <<EOF
$(_sap_job_files)
EOF

    if [ "${_sap_any}" -eq 0 ]; then
        if [ -n "${_sap_want}" ]; then
            ux_error "No such job: ${_sap_want}"
            return 1
        fi
        ux_info "No pending jobs to cancel."
    fi
    return 0
}

# ============================================================
# Help
# ============================================================

_sap_usage() {
    ux_header "schedule-agent-prompt"
    ux_info "Usage: schedule-agent-prompt --at HH:MM --agent-cwd PATH [--agent-cwd PATH]... [--prompt TEXT] [--dry-run]"
    ux_info "       schedule-agent-prompt --status | --cancel [JOB_ID] | --help"
    ux_info "At a local HH:MM today, submit one prompt into each named herdr agent pane — text and Enter together."
    ux_bullet "options"
    ux_bullet_sub "--at HH:MM         local time, today only. A past time is rejected, never rolled to tomorrow."
    ux_bullet_sub "--agent-cwd PATH   the agent's launch directory. Required, repeatable — one per target pane."
    ux_bullet_sub "--prompt TEXT      what to submit. Default: ${_SAP_DEFAULT_PROMPT}. Passed to herdr verbatim."
    ux_bullet_sub "--dry-run          validate and print the plan; register nothing, send nothing."
    ux_bullet_sub "--status           list every job with its targets and per-target outcome."
    ux_bullet_sub "--cancel [JOB_ID]  cancel one job, or every pending job when no id is given."
    ux_bullet_sub "-h, --help, help   this help."
    ux_bullet "targeting"
    ux_bullet_sub "a target is the agent whose herdr 'cwd' EQUALS the given path, after symlink resolution"
    ux_bullet_sub "foreground_cwd is never matched — it drifts with the pane's own 'cd'"
    ux_bullet_sub "zero or 2+ matches refuse to inject: this tool never guesses which pane you meant"
    ux_bullet "submission"
    ux_bullet_sub "herdr agent prompt <pane> <TEXT> --wait ${_SAP_UNTIL:+--until ${_SAP_UNTIL} }--timeout ${_SAP_TIMEOUT_MS}"
    ux_bullet_sub "one call submits the text AND the agent's Enter key — never a send-text plus a blind sleep"
    ux_bullet_sub "an agent that never leaves its pre-submission state is a FAILURE, recorded as 'stalled'"
    ux_bullet_sub "a timeout after that state change is 'submitted-working' — the prompt landed, the turn is long"
    ux_bullet_sub "targets are independent: one failure never skips the others"
    ux_bullet "prerequisites"
    ux_bullet_sub "herdr on PATH with a reachable server, and jq"
    ux_bullet_sub "the target agents already running — a cwd with no agent is refused at registration"
    ux_bullet "environment"
    ux_bullet_sub "SCHEDULE_AGENT_PROMPT_UNTIL       pin --wait to ONE state (default: herdr's idle/done/blocked)"
    ux_bullet_sub "SCHEDULE_AGENT_PROMPT_TIMEOUT_MS  --wait bound in ms (default ${_SAP_TIMEOUT_MS})"
    ux_bullet_sub "SCHEDULE_AGENT_PROMPT_TICK_S      waiter wake-up interval (default ${_SAP_TICK_S})"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/dotfiles/schedule-agent-prompt/<job-id>.json"
    ux_bullet_sub "…/<job-id>.log   the detached waiter's own output"
    ux_bullet "example"
    ux_bullet_sub "schedule-agent-prompt --at 22:50 --agent-cwd ~/para/project/skills --prompt \"/restart\""
}

# ============================================================
# Main
# ============================================================

main() {
    _sap_cmd=""
    _sap_arg=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _sap_usage
            exit 0
            ;;
        --status)
            _sap_cmd="status"
            shift
            ;;
        --cancel)
            _sap_cmd="cancel"
            case "${2-}" in
            "" | --*) ;;
            *)
                _sap_arg="$2"
                shift
                ;;
            esac
            shift
            ;;
        --dispatch)
            # Internal: the detached waiter re-enters here.
            [ "$#" -ge 2 ] || {
                ux_error "--dispatch requires a job file."
                exit 1
            }
            _sap_cmd="dispatch"
            _sap_arg="$2"
            shift 2
            ;;
        --at)
            [ "$#" -ge 2 ] || {
                ux_error "--at requires HH:MM."
                exit 1
            }
            _SAP_AT="$2"
            shift 2
            ;;
        --agent-cwd)
            [ "$#" -ge 2 ] || {
                ux_error "--agent-cwd requires a path."
                exit 1
            }
            _SAP_TARGETS="${_SAP_TARGETS}$2${_SAP_NL}"
            shift 2
            ;;
        --prompt)
            [ "$#" -ge 2 ] || {
                ux_error "--prompt requires TEXT."
                exit 1
            }
            _SAP_PROMPT="$2"
            shift 2
            ;;
        --dry-run)
            _SAP_DRY_RUN=1
            shift
            ;;
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'schedule-agent-prompt --help' for usage."
            exit 1
            ;;
        esac
    done

    # jq reads herdr's answer and every job file; there is no reduced mode.
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot read herdr's agent list or the job files."
        exit 1
    fi

    case "${_sap_cmd}" in
    status)
        _sap_status_cmd
        exit $?
        ;;
    cancel)
        _sap_cancel_cmd "${_sap_arg}"
        exit $?
        ;;
    dispatch)
        _sap_dispatch "${_sap_arg}"
        exit $?
        ;;
    esac

    if [ -z "${_SAP_AT}" ]; then
        ux_error "--at HH:MM is required."
        ux_info "Run 'schedule-agent-prompt --help' for usage."
        exit 1
    fi

    # Shape first, meaning second: `date -d` happily reads "10:5" as 10:05 on
    # some builds, and a schedule the user did not mean is worse than an error.
    case "${_SAP_AT}" in
    [0-9][0-9]:[0-9][0-9]) ;;
    *)
        ux_error "--at must be HH:MM (24-hour, zero-padded) — got: ${_SAP_AT}"
        exit 1
        ;;
    esac
    case "${_SAP_AT}" in
    [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) ;;
    *)
        ux_error "--at is not a valid 24-hour local time: ${_SAP_AT}"
        exit 1
        ;;
    esac

    if [ -z "${_SAP_TARGETS}" ]; then
        ux_error "At least one --agent-cwd PATH is required."
        ux_info "Run 'schedule-agent-prompt --help' for usage."
        exit 1
    fi

    while IFS= read -r _sap_cwd; do
        [ -n "${_sap_cwd}" ] || continue
        if [ ! -d "${_sap_cwd}" ]; then
            ux_error "--agent-cwd is not a directory: ${_sap_cwd}"
            exit 1
        fi
    done <<EOF
${_SAP_TARGETS}
EOF

    if ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — there is nothing to schedule a prompt into."
        exit 1
    fi

    _sap_register
    exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
