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
# It also owns aicron_mktemp, the one place any part of aicron is allowed to
# create a temp file — see the comment on that function.
#
# Note for editors: this file's basename carries an underscore, so the repo's
# naming check (git/hooks/checks/naming_check.sh) flags any function defined
# here that also appears inside a double-quoted string. That is why every
# call site below assigns first (`_d=$(aicron_state_dir)`) instead of
# inlining `"$(aicron_state_dir)"`.

# A private temp file whose name cannot be guessed, printed on stdout.
#
# Every temp path in aicron goes through here. The predictable
# TMPDIR/aicron-<thing>.<pid> shape this replaces is attackable on a shared
# /tmp: anyone who can plant a symlink at that path before we open it
# redirects the write — and one of those writes is a crontab dump, another is
# a job's exit code. `mktemp` failing is a hard failure with no fallback,
# because a fallback to a fixed name is the hole itself.
aicron_mktemp() {
    local _t
    _t=$(mktemp "${TMPDIR:-/tmp}/$1.XXXXXX" 2>/dev/null) || return 1
    [ -n "${_t}" ] || return 1
    printf '%s' "${_t}"
}

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

# The atomic write both setters below share: apply the jq arguments and
# program in <2..> to job <1>'s state object and swap the result in. A file
# that is missing, or that stopped being JSON, is replaced by a fresh object
# rather than failing the write.
aicron_state_apply() {
    local _f _tmp
    _f=$(aicron_state_file "$1")
    shift
    # Same directory as the target so the closing `mv` stays a rename inside
    # one filesystem, and unguessable for the same reason every other temp
    # name here is.
    _tmp=$(mktemp "${_f}.tmp.XXXXXX" 2>/dev/null) || return 1
    if [ -f "${_f}" ] && jq -e . "${_f}" >/dev/null 2>&1; then
        jq "$@" "${_f}" >"${_tmp}" 2>/dev/null || {
            rm -f "${_tmp}"
            return 1
        }
    else
        printf '%s' '{}' | jq "$@" >"${_tmp}" 2>/dev/null || {
            rm -f "${_tmp}"
            return 1
        }
    fi
    mv "${_tmp}" "${_f}" 2>/dev/null || {
        rm -f "${_tmp}"
        return 1
    }
}

# Merge <2>=<3> (a JSON value) into the state file.
aicron_state_set() {
    # shellcheck disable=SC2016  # jq program text — $k/$v are jq's variables
    aicron_state_apply "$1" --arg k "$2" --argjson v "$3" '.[$k] = $v'
}

# D-5 step 7 — the three run-result keys, written together so a state file can
# never carry a last_run from one execution and a last_exit from another.
aicron_state_record() {
    # shellcheck disable=SC2016  # jq program text — $r/$e/$d are jq's variables
    aicron_state_apply "$1" --arg r "$2" --argjson e "$3" --argjson d "$4" \
        '.last_run = $r | .last_exit = $e | .last_duration_sec = $d'
}

# "running", "idle" or "unknown" for job <1>. Probing with a non-blocking
# flock is the only honest answer: a PID file would go stale the moment a run
# is killed.
#
# The third value is the point. flock(1) answers 0 for "the lock is free" and
# 1 for "someone holds it", but anything else — no flock binary, a lock file
# it cannot open (66) — means the probe never found out. Reporting that as
# "not running" is what makes a wedged job look healthy on a dashboard, so it
# is reported as unknown and the caller says so.
aicron_state_probe() {
    local _lock _rc
    _lock=$(aicron_state_lock "$1")
    [ -f "${_lock}" ] || {
        printf 'idle'
        return 0
    }
    command -v flock >/dev/null 2>&1 || {
        printf 'unknown'
        return 0
    }
    flock -n "${_lock}" true >/dev/null 2>&1
    _rc=$?
    case "${_rc}" in
    0) printf 'idle' ;;
    1) printf 'running' ;;
    *) printf 'unknown' ;;
    esac
}
