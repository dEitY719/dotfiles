#!/bin/sh
# shell-common/tools/custom/lib/cron_common.sh
# Bootstrap and single-instance lock shared by the cron entrypoints (#2144).
# cron_bootstrap: ../issue_watcher_cron.sh, ../pr_merge_train_cron.sh,
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
cron_bootstrap() {
    # shellcheck source=/dev/null
    . "$(dirname "$0")/init.sh"
}

# Single-instance guard for one cron tick.
#   $1 = state dir, $2 = lock basename,
#   $3 = tick name for the skip warning (empty: skip silently)
#
# A cron tick can fire while the previous one is still running; without a lock
# both would observe the same work and both act. Deliberately non-blocking: a
# skipped tick just retries on the next period. Returns non-zero only when
# another tick holds the lock; a missing flock or an unusable state dir
# soft-degrades to "no protection" rather than failing (#1440).
# Must run in the caller's shell (not a subshell): fd 9 has to outlive it.
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
        [ -z "${3:-}" ] || ux_warning "another $3 tick is already running — skip"
        return 1
    fi
}
