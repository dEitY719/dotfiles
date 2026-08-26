#!/bin/sh
# shell-common/tools/custom/lib/aicron_state.sh
# Per-job state, paths and locks for aicron (issue #1472). Sourced by
# ../aicron.sh.
#
# D-3: the crontab is the SSOT for "is this job installed", so `installed` is
# deliberately NOT a state key. The state file holds only what nothing else
# can answer:
#
#   paused             set by `aicron pause` / `aicron resume`
#   last_run           ISO-8601 UTC stamp of the last completed run
#   last_exit          that run's exit code
#   last_duration_sec  how long it took
#
# Layout under <state-dir> (AICRON_STATE_DIR, else $XDG_STATE_HOME/aicron):
#
#   <job>.json        the state file above
#   <job>.lock        the per-job run lock (flock, non-blocking)
#   logs/<job>.log    the default log, plus one rolled generation .log.1
#   .crontab.lock     serialises crontab read-modify-write (NF-1)
#
# Note for editors: this file's basename carries an underscore, so the repo's
# naming check (git/hooks/checks/naming_check.sh) flags any function defined
# here that also appears inside a double-quoted string. That is why every
# call site below assigns first (`_d=$(aicron_state_dir)`) instead of
# inlining `"$(aicron_state_dir)"`.

aicron_state_dir() {
    printf '%s' "${AICRON_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-}/.local/state}/aicron}"
}

aicron_state_file() {
    local _d
    _d=$(aicron_state_dir)
    printf '%s/%s.json' "${_d}" "$1"
}

aicron_state_lock() {
    local _d
    _d=$(aicron_state_dir)
    printf '%s/%s.lock' "${_d}" "$1"
}

aicron_state_log() {
    local _d
    _d=$(aicron_state_dir)
    printf '%s/logs/%s.log' "${_d}" "$1"
}

aicron_state_crontab_lock() {
    local _d
    _d=$(aicron_state_dir)
    printf '%s/.crontab.lock' "${_d}"
}

# Create the state dir (and its logs/ subdir). Non-zero when the result is not
# writable — the caller then runs the job anyway and skips recording, because
# a broken state dir must never stop cron work from happening.
aicron_state_ensure() {
    local _d
    _d=$(aicron_state_dir)
    mkdir -p "${_d}/logs" 2>/dev/null || mkdir -p "${_d}" 2>/dev/null || true
    [ -d "${_d}" ] && [ -w "${_d}" ]
}

# True when the state file exists but is not parseable JSON.
aicron_state_corrupt() {
    local _f
    _f=$(aicron_state_file "$1")
    [ -f "${_f}" ] || return 1
    jq -e . "${_f}" >/dev/null 2>&1 && return 1
    return 0
}

# The whole state object, or `{}` when the file is absent or corrupt. Used by
# the --json renderers.
aicron_state_json() {
    local _f _j
    _f=$(aicron_state_file "$1")
    if [ -f "${_f}" ]; then
        _j=$(jq -c . "${_f}" 2>/dev/null) || _j=""
        if [ -n "${_j}" ]; then
            printf '%s' "${_j}"
            return 0
        fi
    fi
    printf '%s' '{}'
}

# One field, or nothing when absent/corrupt. <2> is a jq path (e.g. `.paused`).
aicron_state_read() {
    local _f _v
    _f=$(aicron_state_file "$1")
    [ -f "${_f}" ] || return 0
    _v=$(jq -r "$2 // empty" "${_f}" 2>/dev/null) || return 0
    printf '%s' "${_v}"
}

aicron_state_paused() {
    local _v
    _v=$(aicron_state_read "$1" '.paused')
    [ "${_v}" = "true" ]
}

# Merge <2>=<3> (a JSON value) into the state file, replacing a corrupt or
# missing file with a fresh object rather than failing.
aicron_state_set() {
    local _f _tmp _base
    _f=$(aicron_state_file "$1")
    _base='{}'
    if [ -f "${_f}" ] && jq -e . "${_f}" >/dev/null 2>&1; then
        _base=$(cat "${_f}")
    fi
    _tmp="${_f}.tmp.$$"
    if ! printf '%s' "${_base}" |
        jq --arg k "$2" --argjson v "$3" '.[$k] = $v' >"${_tmp}" 2>/dev/null; then
        rm -f "${_tmp}"
        return 1
    fi
    mv "${_tmp}" "${_f}" 2>/dev/null || {
        rm -f "${_tmp}"
        return 1
    }
}

# D-5 step 7 — the three run-result keys, written together so a state file can
# never carry a last_run from one execution and a last_exit from another.
aicron_state_record() {
    local _f _tmp _base
    _f=$(aicron_state_file "$1")
    _base='{}'
    if [ -f "${_f}" ] && jq -e . "${_f}" >/dev/null 2>&1; then
        _base=$(cat "${_f}")
    fi
    _tmp="${_f}.tmp.$$"
    if ! printf '%s' "${_base}" | jq \
        --arg r "$2" --argjson e "$3" --argjson d "$4" \
        '.last_run = $r | .last_exit = $e | .last_duration_sec = $d' \
        >"${_tmp}" 2>/dev/null; then
        rm -f "${_tmp}"
        return 1
    fi
    mv "${_tmp}" "${_f}" 2>/dev/null || {
        rm -f "${_tmp}"
        return 1
    }
}

# True when a run of <1> currently holds the job lock. Probing with a
# non-blocking flock is the only honest answer: a PID file would go stale the
# moment a run is killed.
aicron_state_running() {
    local _lock
    _lock=$(aicron_state_lock "$1")
    [ -f "${_lock}" ] || return 1
    command -v flock >/dev/null 2>&1 || return 1
    if flock -n "${_lock}" true >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
