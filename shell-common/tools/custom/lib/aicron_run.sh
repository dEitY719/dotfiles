#!/bin/sh
# shell-common/tools/custom/lib/aicron_run.sh
# The `run` executor for aicron (issue #1472). Sourced by ../aicron.sh.
#
# D-5 — the order is the whole design, so it is worth stating once:
#
#   1 look the job up in the manifest        missing script -> exit 1
#   2 paused?                                -> exit 0, silently
#   3 take the per-job lock, non-blocking    already held -> exit 0, silently
#   4 roll the log if it outgrew the cap (D-7)
#   5 build the environment (defaults ∪ job)
#   6 exec the script, appending stdout+stderr to the log
#   7 record last_run / last_exit / last_duration_sec
#   8 propagate the job's exit code
#
# Steps 2 and 3 exit 0 on purpose: cron mails the user on any non-zero exit,
# and "this job is paused" or "the previous run is still going" are normal
# outcomes, not incidents. Step 8 propagates on purpose too — a real failure
# has to stay diagnosable, both in the mail cron sends and in the state file.
#
# D-8 — the exit codes this file can produce, on top of the router's 1 and 2:
#
#   0   the job succeeded, or step 2/3 declined to run it
#   4   the run took the lock and then died without reporting a code (OOM,
#       SIGKILL). Its own code is unknowable; what must not happen is cron
#       being told 0, so this one is reported as the failure it is.
#   *   the job's own exit code
#
# Nothing here evaluates manifest content. The env lines go to `env` as
# NAME=VALUE arguments and the args go to the script as argv; neither passes
# through a shell.
#
# Note for editors: this file's basename carries an underscore, so the repo's
# naming check flags a function defined here that also shows up inside a
# double-quoted string. Assign first, quote later.

# 7 MiB, overridable from the environment — the bats suite sets it to a
# handful of bytes rather than writing 7 MiB of fixture.
: "${_AICRON_LOG_MAX_BYTES:=7340032}"

# What the rc file holds between "the lock was taken" and "the job returned".
# Finding it still there means the run started and never got to write a real
# code — the caller turns that into exit 4 rather than the silent 0 an empty
# file (the lock was declined, nothing ran) means.
_AICRON_RC_STARTED=started

# The log this job writes to: its manifest `log` override, else the default
# under the state dir.
aicron_run_log_path() {
    local _l
    _l=$(aicron_manifest_log "$1")
    if [ -n "${_l}" ]; then
        printf '%s' "${_l}"
        return 0
    fi
    aicron_state_log "$1"
}

# D-7 — one generation, kept with `wc -c` rather than `stat` because the two
# systems this runs on disagree about `stat`'s flags and `wc` does not.
aicron_run_rollover() {
    local _log _size
    _log="$1"
    [ -f "${_log}" ] || return 0
    _size=$(wc -c <"${_log}" 2>/dev/null | tr -d ' ')
    [ -n "${_size}" ] || return 0
    if [ "${_size}" -gt "${_AICRON_LOG_MAX_BYTES}" ]; then
        mv "${_log}" "${_log}.1" 2>/dev/null || true
    fi
    return 0
}

# Steps 4-8 for job <1> (<2> = its script, <3> = 1 when the state dir is
# usable and the run may be logged and recorded).
aicron_run_exec() {
    local _job _script _rec _log _start _end _rc _stamp _envfile _argfile _kv _k _a
    _job="$1"
    _script="$2"
    _rec="$3"

    _log=$(aicron_run_log_path "${_job}")
    if [ "${_rec}" = "1" ]; then
        aicron_run_rollover "${_log}"
    fi

    _envfile=$(aicron_mktemp aicron-env) || {
        ux_error "could not create a temp file for ${_job}'s environment"
        return 1
    }
    _argfile=$(aicron_mktemp aicron-args) || {
        rm -f "${_envfile}"
        ux_error "could not create a temp file for ${_job}'s arguments"
        return 1
    }
    aicron_manifest_env "${_job}" >"${_envfile}" 2>/dev/null || : >"${_envfile}"
    aicron_manifest_args "${_job}" >"${_argfile}" 2>/dev/null || : >"${_argfile}"

    # Build `env NAME=VALUE ... <script> <args...>` in the positional
    # parameters. Reading from a file rather than a pipe keeps the loop in
    # this shell — a `while read` on the right of a pipe runs in a subshell
    # and the argv would be discarded with it.
    set --
    while IFS= read -r _kv; do
        [ -n "${_kv}" ] || continue
        case "${_kv}" in
        [A-Za-z_]*=*) ;;
        *) continue ;;
        esac
        _k="${_kv%%=*}"
        case "${_k}" in
        *[!A-Za-z0-9_]*) continue ;;
        esac
        set -- "$@" "${_kv}"
    done <"${_envfile}"
    set -- "$@" "${_script}"
    while IFS= read -r _a; do
        set -- "$@" "${_a}"
    done <"${_argfile}"
    rm -f "${_envfile}" "${_argfile}"

    _start=$(date -u +%s)
    if [ "${_rec}" = "1" ] && : >>"${_log}" 2>/dev/null; then
        env "$@" >>"${_log}" 2>&1
        _rc=$?
    else
        # No usable log: let the output through so cron mails it instead of
        # dropping the only record of what happened.
        env "$@"
        _rc=$?
    fi
    # One `date`: the epoch seconds and the stamp describe the same instant,
    # and two calls could straddle a second boundary.
    _end=$(date -u '+%s %Y-%m-%dT%H:%M:%SZ')
    _stamp="${_end#* }"
    _end="${_end%% *}"

    if [ "${_rec}" = "1" ]; then
        aicron_state_record "${_job}" "${_stamp}" "${_rc}" "$((_end - _start))" ||
            ux_warning "could not record the run result for ${_job}"
    fi
    return ${_rc}
}

# The `run <job>` entry point. <1> is known to be a manifest job — the
# unknown-job exit 2 is the router's call, not this one's.
aicron_run_job() {
    local _job _script _sd _rec _lock _rcfile _rc
    _job="$1"

    _script=$(aicron_manifest_script "${_job}")
    if [ -z "${_script}" ] || [ ! -f "${_script}" ]; then
        ux_error "job script not found for ${_job}: ${_script}"
        return 1
    fi

    if aicron_state_corrupt "${_job}"; then
        ux_warning "state file for ${_job} was not valid JSON — rewriting it"
    fi

    if aicron_state_paused "${_job}"; then
        return 0
    fi

    _rec=1
    if ! aicron_state_ensure; then
        # Both halves matter: the lock file lives in that same directory, so
        # losing it costs the single-instance guarantee as well as the record,
        # and two overlapping cron ticks can then run the job at once.
        _sd=$(aicron_state_dir)
        ux_warning "state dir is not writable (${_sd}) — running ${_job} unrecorded AND without single-instance protection"
        _rec=0
    fi

    if [ "${_rec}" = "0" ] || ! command -v flock >/dev/null 2>&1; then
        [ "${_rec}" = "1" ] &&
            ux_warning "flock not found — running ${_job} without single-instance protection"
        aicron_run_exec "${_job}" "${_script}" "${_rec}"
        return $?
    fi

    # The subshell's own exit status cannot carry the job's code (it collides
    # with the "lock was busy" answer), so the code travels through a file —
    # and the file has to distinguish three things, not two:
    #
    #   empty      step 3 declined the lock; nothing ran               -> 0
    #   `started`  the lock was taken and the subshell died before it
    #              could write a code (OOM, SIGKILL)                   -> 4
    #   a number   the job's own exit code                             -> it
    #
    # Without the sentinel the middle case is indistinguishable from the
    # first, and a job killed mid-run reports success to cron.
    _lock=$(aicron_state_lock "${_job}")
    _rcfile=$(aicron_mktemp aicron-rc) || {
        ux_error "could not create a temp file to carry ${_job}'s exit code"
        return 1
    }
    (
        flock -n 9 || exit 0
        printf '%s' "${_AICRON_RC_STARTED}" >"${_rcfile}"
        aicron_run_exec "${_job}" "${_script}" 1
        printf '%s' "$?" >"${_rcfile}"
    ) 9>>"${_lock}"

    if [ ! -s "${_rcfile}" ]; then
        rm -f "${_rcfile}"
        return 0
    fi
    _rc=$(cat "${_rcfile}")
    rm -f "${_rcfile}"
    if [ "${_rc}" = "${_AICRON_RC_STARTED}" ]; then
        ux_error "${_job} took the run lock and then died without reporting an exit code — treating it as a failure, not a success"
        return 4
    fi
    return "${_rc}"
}
