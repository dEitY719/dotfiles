#!/bin/sh
# shell-common/tools/custom/lib/cron_common.sh
# Bootstrap and single-instance lock shared by the cron entrypoints (#2144).
# cron_bootstrap: ../avatar_issue_watcher.sh, ../pr_merge_train_cron.sh,
# ../session_doctor_cron.sh, ../schedule_agent_prompt.sh. cron_acquire_lock: the
# first three (the first two via _hp_acquire_lock). schedule_agent_prompt keeps
# its own blocking fd-8 write lock — a different job, not a tick guard.
#
# Usage (from a tools/custom/*.sh entrypoint):
#   . "$(dirname "$0")/lib/cron_common.sh" && cron_bootstrap || exit 1
#
# Sourced explicitly — tools/custom is never auto-sourced. aicron.sh does not
# use it: it must run under dash, and init.sh's direct-exec guard is bash-only.

# Source ../init.sh (DOTFILES_ROOT / SHELL_COMMON / ux_lib). Since #2144 init.sh
# loads ux_lib and exports SHELL_COMMON under DOTFILES_TEST_MODE=1 too, so the
# per-script "SHELL_COMMON fallback + ux_lib reload" blocks are gone.
# Resolves init.sh against $0, the same way every entrypoint always did.
# Sourced from inside a function: init.sh must keep using plain assignments and
# `export` at top level — a `local`/`declare` there would vanish on return.
cron_bootstrap() {
    # readlink -f: $0 may be a ~/.local/bin symlink (#2195); readlink can be
    # missing from a stripped PATH (tests), so fall back to the plain $0.
    local _cron_self
    _cron_self=$(readlink -f "$0" 2>/dev/null) || _cron_self=$0
    # shellcheck source=/dev/null
    . "$(dirname "$_cron_self")/init.sh"
}

# Single-instance guard for one cron tick.
#   $1 = state dir, $2 = lock basename,
#   $3 = tick name for the skip warning (empty: skip silently)
#   $4 = optional wait in seconds (#2315): a positive integer waits up to that
#        long for the holder (flock -w) instead of skipping; empty or anything
#        else keeps the non-blocking default every cron tick relies on
#
# A cron tick can fire while the previous one is still running; without a lock
# both would observe the same work and both act. Non-blocking by default: a
# skipped tick just retries on the next period. A caller with no retry behind
# it (a targeted run a human started) passes $4 instead, so its request is
# queued rather than lost. Returns non-zero only when another tick holds the
# lock (or still holds it after the wait); a missing flock or an unusable state
# dir soft-degrades to "no protection" rather than failing (#1440).
# Must run in the caller's shell (not a subshell): the lock lives as long as it.
# Release early with cron_release_lock.
cron_acquire_lock() {
    local _dir="$1" _lock
    _lock="${_dir}/$2"

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
        case "${4:-}" in
        '' | *[!0-9]* | 0)
            { exec 9>&-; } 2>/dev/null
            [ -z "${3:-}" ] || {
                ux_warning "another $3 tick is already running — skip"
                _cron_lock_holders "${_lock}"
            }
            return 1
            ;;
        esac

        ux_info "waiting for the running ${3:-cron} tick (<=${4}s)..."
        if ! flock -w "$4" 9; then
            { exec 9>&-; } 2>/dev/null
            ux_error "timed out after ${4}s waiting for the running ${3:-cron} tick"
            _cron_lock_holders "${_lock}"
            return 1
        fi
    fi
    _cron_lock_detach
}

# Hand the lock on fd 9 to a holder process and close fd 9 here (#2365).
# bash cannot mark fd 9 close-on-exec, so every child of the tick inherited
# it, and flock belongs to the open file description: a long-lived child
# (herdr -> claude -> a session dbus-daemon) kept the lock after the tick
# ended, and every later tick skipped. The holder is the only other process
# with the description; setpriv --pdeathsig kills it when this shell exits,
# so the lock still ends with the tick, while children spawned from here on
# carry no lock fd. The PPID check closes the window where the shell exits
# before the death signal is armed. No setpriv (non-Linux): keep fd 9 — the
# old behavior, leak-prone but still a working lock.
_cron_lock_detach() {
    # shellcheck disable=SC3028  # bash callers; $$ is the fallback
    local _owner="${BASHPID:-$$}" _sleep
    _CRON_LOCK_PID=""
    setpriv --pdeathsig KILL true 2>/dev/null || return 0
    # The system sleep, not a PATH shim: a stub that returns would drop the lock.
    _sleep=$(command -pv sleep 2>/dev/null) || return 0
    # shellcheck disable=SC2016  # $PPID/$1/$2 expand in the holder's sh
    setpriv --pdeathsig KILL sh -c '[ "$PPID" = "$1" ] && exec "$2" 2147483647' \
        _ "${_owner}" "${_sleep}" </dev/null >/dev/null 2>&1 &
    _CRON_LOCK_PID=$!
    # A holder that already died (exec failed) would take the lock with it once
    # fd 9 closes below: keep fd 9 instead, the unprotected-children fallback.
    kill -0 "${_CRON_LOCK_PID}" 2>/dev/null || {
        _CRON_LOCK_PID=""
        return 0
    }
    # Off the job table: a caller's bare `wait` (session_doctor_cron's
    # injections) must not block on a holder that never exits by itself.
    # shellcheck disable=SC3044  # bash callers
    disown "${_CRON_LOCK_PID}" 2>/dev/null
    { exec 9>&-; } 2>/dev/null
}

# Release a lock taken by cron_acquire_lock before the tick ends (a caller
# that only needs it around part of its work). Safe to call twice.
cron_release_lock() {
    if [ -n "${_CRON_LOCK_PID:-}" ]; then
        # Disowned, so no `wait`: the kernel closes the lock fd as it dies.
        kill -KILL "${_CRON_LOCK_PID}" 2>/dev/null
        _CRON_LOCK_PID=""
    fi
    { exec 9>&-; } 2>/dev/null
    return 0
}

# Name who holds a busy lock, so a stuck lock is diagnosable from the cron
# log alone (#2365). Best effort: silent without fuser or when it finds none.
_cron_lock_holders() {
    local _pids _pid _list=""
    command -v fuser >/dev/null 2>&1 || return 0
    _pids=$(fuser "$1" 2>/dev/null) || return 0
    for _pid in ${_pids}; do
        # ppid: the lock holder is a `sleep` whose parent is the real tick.
        _list="${_list} ${_pid}($(ps -o comm= -p "${_pid}" 2>/dev/null) ppid=$(ps -o ppid= -p "${_pid}" 2>/dev/null | tr -d ' '))"
    done
    [ -z "${_list}" ] || ux_info "lock ${1} held by:${_list}"
}

# Run a dotfiles_tools module: cron_py <module> [args...] (#2157).
# The shell/Python call contract (docs/.ssot/shell-vs-python.md): stdin in,
# stdout out, exit 0/1 = answer, 2 = unreadable input. The package is stdlib
# only, so the system python3 on cron's PATH runs it with no venv. -E -s drop
# PYTHONPATH and user site; the cd makes `-m` import from tools/py, a path this
# repo owns, instead of whatever directory the tick was started in.
cron_py() {
    (cd "${SHELL_COMMON:?cron_py: SHELL_COMMON unset}/../tools/py" && python3 -E -s -m "$@")
}
