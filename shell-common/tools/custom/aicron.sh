#!/bin/bash
# shell-common/tools/custom/aicron.sh
# Manifest-driven management of this machine's cron jobs (issue #1472).
#
# shellcheck shell=sh
#   ^ deliberately not line 2. It has to sit inside the leading comment block
#     (before the first command) for shellcheck to apply it file-wide, and it
#     has to sit below the summary line, because mytool_help.sh reads the
#     first meaningful comment as this tool's one-line description and
#     docs/guide/commands/mytool.md is generated from that.
#
# The problem it replaces: cron jobs were installed by hand with `crontab -e`,
# so the schedule, the environment and the log path of every job lived only in
# one user's crontab on one machine. Nothing was reviewable, nothing was
# reproducible on a second PC, and pausing a job meant commenting a line out
# and remembering to put it back.
#
#   cron-jobs.json   version-controlled, reviewable: what runs, when, with
#                    which arguments and environment
#   crontab          the SSOT for "is this job installed" (D-3) — aicron never
#                    duplicates that answer into a state file
#   state dir        the part nothing else can hold: paused, and how the last
#                    run went
#
# The shebang says bash because tests/bats/tools/custom_tools.bats requires one
# for every script in this directory, but the body is strict POSIX sh and
# `sh aicron.sh ...` is a tested path (NF-3) — cron gives a job /bin/sh and a
# nearly empty environment, and this file has to survive both.
#
# Usage: aicron.sh <list|add|remove|pause|resume|status|run|doctor|help> [...]

# ============================================================
# Bootstrap
# ============================================================
#
# `set -u` is deliberately switched on at the END of this block, not here:
# ux_lib.sh tests $BASH_VERSION bare to detect its host shell, which under
# `sh` is an unset parameter and would abort the script before it printed
# anything. Everything in the bootstrap guards its own expansions with `:-`.
#
# This directory's init.sh is deliberately NOT sourced. Everything it exports
# (DOTFILES_ROOT, SHELL_COMMON) is derived below from this file's own location
# instead — see the comment there for why that override is wanted — and ux_lib
# is loaded below as well, so sourcing it would add nothing but a bash-vs-sh
# fork in the bootstrap. It could not be sourced unconditionally in any case:
# its closing direct-exec guard dereferences ${BASH_SOURCE[0]}, which dash
# rejects outright as a bad substitution, and NF-3 requires this file to run
# under /bin/sh.

# realpath is not guaranteed to exist; this idiom is.
_AICRON_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The absolute path cron will invoke. It goes into the marker block verbatim,
# so it must not depend on anyone's PATH or cwd.
_AICRON_SELF="${_AICRON_DIR}/$(basename -- "$0")"

# Derived from this file's own location rather than inherited, and
# unconditionally so — the same rule init.sh applies. A `run` inherits
# whatever DOTFILES_ROOT the calling shell happened to export (often another
# checkout, or a stale one), and resolving a manifest's relative `script`
# paths against a checkout other than the one holding the manifest is exactly
# the class of surprise this tool exists to remove. Letting the answer depend
# on which shell ran the script would be worse still: init.sh already
# overrides the environment under bash, so honouring it under sh would make
# `bash aicron.sh` and `sh aicron.sh` disagree.
SHELL_COMMON="$(CDPATH='' cd -- "${_AICRON_DIR}/../.." && pwd)"
DOTFILES_ROOT="$(CDPATH='' cd -- "${SHELL_COMMON}/.." && pwd)"
export SHELL_COMMON DOTFILES_ROOT

# Every output path below depends on ux_*, and under `sh` nothing has loaded
# it yet.
if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# The logic lives in lib/, mirroring claude/skills/devx-ssh-delegate/lib/:
# this file routes arguments and nothing else.
for _aicron_mod in aicron_manifest aicron_state aicron_crontab aicron_run aicron_report; do
    # shellcheck source=/dev/null
    . "${_AICRON_DIR}/lib/${_aicron_mod}.sh" || exit 1
done
unset _aicron_mod

set -u

# ============================================================
# Usage
# ============================================================

aicron_usage() {
    ux_header "aicron — manifest-driven cron job management"
    ux_info "Usage: aicron <command> [arguments]"
    ux_info ""
    ux_section "Commands"
    ux_table_row "list [--json]" "every manifest job: installed, paused, last run"
    ux_table_row "add <job>" "install the job's crontab block (--schedule <expr> to override)"
    ux_table_row "remove <job>" "drop the job's crontab block (also cleans a doctor orphan); the state file is kept"
    ux_table_row "pause <job>" "stop running the job; the crontab entry stays"
    ux_table_row "resume <job>" "undo pause"
    ux_table_row "status <job> [--json]" "running now, schedule, last run result"
    ux_table_row "run <job>" "one execution, identical to the one cron performs"
    ux_table_row "doctor" "check manifest, crontab and state against each other"
    ux_table_row "help" "this text (also -h, --help)"
    ux_info ""
    ux_section "Environment"
    ux_table_row "AICRON_MANIFEST" "manifest path (default: shell-common/tools/custom/cron-jobs.json)"
    ux_table_row "AICRON_STATE_DIR" "state dir (default: \$XDG_STATE_HOME/aicron)"
    ux_info ""
    ux_section "Exit codes"
    ux_bullet "0 — success, or a normal skip (paused, or already running)"
    ux_bullet "1 — usage or argument error"
    ux_bullet "2 — unknown job"
    ux_bullet "3 — crontab operation failed, or its current table could not be read"
    ux_bullet "4 — a run took the lock and was killed before it reported a code"
    ux_bullet "otherwise — the job's own exit code, propagated by run"
    ux_info ""
    ux_section "Examples"
    ux_bullet_sub "aicron list"
    ux_bullet_sub "aicron add issue-watcher --schedule '*/3 * * * *'"
    ux_bullet_sub "aicron pause merge-train"
    ux_bullet_sub "aicron status issue-watcher --json | jq .last_exit"
    return 0
}

# ============================================================
# Argument routing
# ============================================================

# The argument shape every job-scoped command shares: exactly one name, and
# nothing after it.
#
# Rejecting the extra word rather than ignoring it is the point.
# `aicron run issue-watcher --dry-run` silently dropping the flag is how a run
# does something other than what was asked, and the same typo on `remove`
# would edit the crontab the user did not mean to edit.
aicron_one_job_arg() {
    if [ "$#" -lt 1 ] || [ -z "$1" ]; then
        ux_error "a job name is required — see 'aicron help'"
        return 1
    fi
    if [ "$#" -gt 1 ]; then
        shift
        ux_error "unexpected argument: $1 — this command takes exactly one job name"
        return 1
    fi
    return 0
}

# Shared front half of every job-scoped command: the shape above (1), and the
# name has to be a manifest job (2).
aicron_resolve_job() {
    aicron_one_job_arg "$@" || return 1
    if ! aicron_manifest_has "$1"; then
        ux_error "unknown job: $1"
        return 2
    fi
    return 0
}

# The plumbing add and remove share: crontab(1) has to exist, the edit runs
# under the crontab lock, and either failure is exit 3. <1> names the job for
# the messages; <2..> is the edit to perform.
aicron_edit_crontab() {
    _job="$1"
    shift
    if ! aicron_crontab_available; then
        ux_error "crontab command not found — cannot update ${_job}"
        return 3
    fi
    aicron_state_ensure || true
    _lock=$(aicron_state_crontab_lock)
    if ! aicron_crontab_guard "${_lock}" "$@"; then
        ux_error "crontab update failed for ${_job}"
        return 3
    fi
    return 0
}

aicron_cmd_list() {
    _fmt=text
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --json)
            _fmt=json
            shift
            ;;
        *)
            ux_error "unknown option for list: $1"
            return 1
            ;;
        esac
    done
    aicron_manifest_check || return 1
    aicron_report_list "${_fmt}"
}

aicron_cmd_add() {
    _job=""
    _sched=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --schedule)
            if [ "$#" -lt 2 ]; then
                ux_error "--schedule requires a cron expression"
                return 1
            fi
            _sched="$2"
            shift 2
            ;;
        -*)
            ux_error "unknown option for add: $1"
            return 1
            ;;
        *)
            if [ -n "${_job}" ]; then
                ux_error "add takes exactly one job name"
                return 1
            fi
            _job="$1"
            shift
            ;;
        esac
    done

    aicron_manifest_check || return 1
    aicron_resolve_job "${_job}" || return $?

    if [ -z "${_sched}" ]; then
        _sched=$(aicron_manifest_schedule "${_job}")
    fi
    if [ -z "${_sched}" ]; then
        ux_error "no schedule for ${_job} in the manifest and none given with --schedule"
        return 1
    fi

    aicron_edit_crontab "${_job}" \
        aicron_crontab_install "${_job}" "${_sched}" "${_AICRON_SELF}" || return $?
    ux_success "installed ${_job} — ${_sched}"
}

# remove is the only job-scoped command that does NOT require manifest
# membership, and it has to be: an orphan block (one whose manifest entry was
# deleted) is precisely what doctor reports, and if remove refused those the
# drift doctor finds could not be fixed with aicron at all. Every other
# command still requires the manifest — running or pausing a job nothing
# describes has no meaning.
aicron_cmd_remove() {
    aicron_one_job_arg "$@" || return 1
    aicron_manifest_check || return 1
    _job="$1"

    if ! aicron_manifest_has "${_job}"; then
        if ! aicron_crontab_available; then
            ux_error "crontab command not found — cannot update ${_job}"
            return 3
        fi
        _state=$(aicron_crontab_state "${_job}")
        case "${_state}" in
        yes)
            ux_info "${_job} is not in the manifest — removing its orphan crontab block"
            ;;
        unknown)
            ux_error "could not read the crontab (${_AICRON_CRONTAB_ERR}) — cannot tell whether ${_job} is installed"
            return 3
            ;;
        *)
            ux_error "unknown job: ${_job}"
            return 2
            ;;
        esac
    fi

    aicron_edit_crontab "${_job}" aicron_crontab_uninstall "${_job}" || return $?
    ux_success "removed ${_job} from the crontab — its state file was kept"
}

# <1> is the paused flag to write: true for pause, false for resume.
aicron_cmd_set_paused() {
    _flag="$1"
    shift
    aicron_manifest_check || return 1
    aicron_resolve_job "$@" || return $?
    _job="$1"

    if ! aicron_state_ensure; then
        _sd=$(aicron_state_dir)
        ux_error "state dir is not writable: ${_sd}"
        return 1
    fi
    if ! aicron_state_set "${_job}" paused "${_flag}"; then
        ux_error "could not update the state file for ${_job}"
        return 1
    fi
    if [ "${_flag}" = "true" ]; then
        ux_success "paused ${_job} — its crontab entry is untouched"
    else
        ux_success "resumed ${_job}"
    fi
}

aicron_cmd_status() {
    _job=""
    _fmt=text
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --json)
            _fmt=json
            shift
            ;;
        -*)
            ux_error "unknown option for status: $1"
            return 1
            ;;
        *)
            if [ -n "${_job}" ]; then
                ux_error "status takes exactly one job name"
                return 1
            fi
            _job="$1"
            shift
            ;;
        esac
    done

    aicron_manifest_check || return 1
    aicron_resolve_job "${_job}" || return $?
    aicron_report_status "${_job}" "${_fmt}"
}

aicron_cmd_run() {
    aicron_manifest_check || return 1
    aicron_resolve_job "$@" || return $?
    aicron_run_job "$1"
}

aicron_cmd_doctor() {
    if [ "$#" -gt 0 ]; then
        ux_error "doctor takes no arguments"
        return 1
    fi
    aicron_manifest_check || return 1
    aicron_report_doctor
}

main() {
    if [ "$#" -eq 0 ]; then
        aicron_usage
        ux_error "no command given"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq is required by aicron — install it with ensure_jq.sh"
        return 1
    fi

    _cmd="$1"
    shift
    case "${_cmd}" in
    help | -h | --help)
        aicron_usage
        ;;
    list)
        aicron_cmd_list "$@"
        ;;
    add)
        aicron_cmd_add "$@"
        ;;
    remove)
        aicron_cmd_remove "$@"
        ;;
    pause)
        aicron_cmd_set_paused true "$@"
        ;;
    resume)
        aicron_cmd_set_paused false "$@"
        ;;
    status)
        aicron_cmd_status "$@"
        ;;
    run)
        aicron_cmd_run "$@"
        ;;
    doctor)
        aicron_cmd_doctor "$@"
        ;;
    *)
        ux_error "unknown command: ${_cmd}"
        ux_info "Run 'aicron help' for usage."
        return 1
        ;;
    esac
}

if [ "${0##*/}" = "aicron.sh" ]; then
    main "$@"
    exit $?
fi
