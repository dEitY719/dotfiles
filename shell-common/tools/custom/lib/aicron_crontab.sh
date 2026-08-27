#!/bin/sh
# shell-common/tools/custom/lib/aicron_crontab.sh
# Marker-block crontab editing for aicron (issue #1472). Sourced by
# ../aicron.sh.
#
# D-4 — one job owns exactly one block, and nothing else in the table:
#
#   # BEGIN aicron:<job>
#   <schedule> <abs-path-to-aicron.sh> run <job>
#   # END aicron:<job>
#
# The contract that matters more than any feature here: every line OUTSIDE the
# markers survives an add and a remove byte for byte. These machines carry
# hand-written crontab lines (a karakeep sync, MAILTO=, comments) that no tool
# of ours is allowed to reformat, reorder or eat. That is why the edit is an
# awk filter over `crontab -l` rather than a regenerate-from-manifest write.
#
# The same contract is why a FAILED `crontab -l` may never look like an empty
# one — see aicron_crontab_dump_to. An unreadable table that reads as empty
# would make the next install write a crontab holding nothing but our own
# marker block, and every hand-written line would be gone.
#
# D-3 also makes this file the answer to "is job X installed" — the crontab is
# the SSOT for that, never the state file. That answer is deliberately
# three-valued (yes / no / unknown), because "unknown" collapsed into "no" is
# exactly what would let `add` overwrite a table it never managed to read.
#
# Note for editors: this file's basename carries an underscore, so the repo's
# naming check flags a function defined here that also shows up inside a
# double-quoted string. Assign first, quote later.

aicron_crontab_available() {
    command -v crontab >/dev/null 2>&1
}

# crontab(1)'s own stderr from the last failed dump, so the caller can name the
# real reason. It is a global because the dump's output channel is the table
# itself, and a pipeline would swallow anything returned any other way.
_AICRON_CRONTAB_ERR=""

# Read the current table into file <1>.
#
#   0   <1> holds the table — an EMPTY file when this user simply has no
#       crontab yet, which is a normal state, not a failure
#   1   the table could not be read; <1> is emptied and
#       _AICRON_CRONTAB_ERR carries crontab's stderr
#
# `crontab -l` exits non-zero for both cases, so the two are told apart by what
# it said: "no crontab for <user>" (any case) means the empty table, and so
# does a non-zero exit that produced no output at all — some locales translate
# the message away. Anything else is a real failure (EACCES, a broken cron
# install) and the callers that write must abort on it.
aicron_crontab_dump_to() {
    local _dest _errfile _rc _err _low
    _dest="$1"
    _AICRON_CRONTAB_ERR=""

    _errfile=$(aicron_mktemp aicron-crontab-err) || {
        _AICRON_CRONTAB_ERR="could not create a temp file for crontab's stderr"
        : >"${_dest}"
        return 1
    }
    crontab -l >"${_dest}" 2>"${_errfile}"
    _rc=$?
    _err=$(cat "${_errfile}" 2>/dev/null)
    rm -f "${_errfile}"
    [ "${_rc}" -eq 0 ] && return 0

    _low=$(printf '%s' "${_err}" | tr '[:upper:]' '[:lower:]')
    case "${_low}" in
    *"no crontab for"*)
        : >"${_dest}"
        return 0
        ;;
    esac
    if [ -z "${_err}" ] && [ ! -s "${_dest}" ]; then
        return 0
    fi

    _AICRON_CRONTAB_ERR="${_err:-crontab -l exited ${_rc}}"
    : >"${_dest}"
    return 1
}

# Every job name that owns a marker block in the already-dumped table <1>, one
# per line, in table order and including duplicates (doctor needs to see
# those).
aicron_crontab_names_in() {
    sed -n 's/^# BEGIN aicron:\(.*\)$/\1/p' "$1"
}

# How many marker blocks job <2> owns in the dumped table <1>. More than one is
# a doctor finding.
aicron_crontab_count_in() {
    aicron_crontab_names_in "$1" | grep -c -x -F -- "$2" || true
}

# The 5-field cron schedule installed for job <2> in the already-dumped table
# <1>, or empty when that job owns no block there. The schedule line inside a
# marker block is always `<5 schedule fields> <script> run <job>` (see the
# BEGIN/END contract at the top of this file), so the first 5 whitespace
# fields are the schedule regardless of how the script path is spelled.
# Stops at the first block on a duplicate job — doctor already reports
# duplicates separately (#1496).
aicron_crontab_schedule_in() {
    awk -v tag="$2" '
        $0 == "# BEGIN aicron:" tag { on = 1; next }
        $0 == "# END aicron:" tag   { on = 0 }
        on == 1 && NF >= 5 { print $1, $2, $3, $4, $5; exit }
    ' "$1"
}

# "yes", "no" or "unknown" for job <1>, dumping the table itself. The views
# that answer this for many jobs at once dump ONCE and call
# aicron_crontab_count_in instead of paying for a `crontab -l` per job.
aicron_crontab_state() {
    local _f _n
    _f=$(aicron_mktemp aicron-crontab) || {
        printf 'unknown'
        return 0
    }
    if ! aicron_crontab_dump_to "${_f}"; then
        rm -f "${_f}"
        printf 'unknown'
        return 0
    fi
    _n=$(aicron_crontab_count_in "${_f}" "$1")
    rm -f "${_f}"
    if [ "${_n:-0}" -gt 0 ]; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# stdin -> stdout, minus every marker block belonging to job <1>. Anything
# outside those markers is passed through untouched.
aicron_crontab_strip() {
    awk -v tag="$1" '
        $0 == "# BEGIN aicron:" tag { skip = 1; next }
        $0 == "# END aicron:" tag   { skip = 0; next }
        skip != 1                   { print }
    '
}

# stdin becomes the new table. Both editors below go through here, so the
# temp file (which is what stops a half-written table reaching `crontab -`)
# and the exit code of the install exist in one place.
aicron_crontab_write() {
    local _tmp _rc
    _tmp=$(aicron_mktemp aicron-crontab-new) || {
        ux_error "could not create a temp file for the new crontab"
        return 1
    }
    cat >"${_tmp}" 2>/dev/null
    crontab - <"${_tmp}"
    _rc=$?
    rm -f "${_tmp}"
    return ${_rc}
}

# Add or replace job <1>'s block: <2> = schedule, <3> = absolute path of
# aicron.sh. Stripping first is what makes a repeated `add` a replace rather
# than a second block.
aicron_crontab_install() {
    local _cur _rc
    _cur=$(aicron_mktemp aicron-crontab) || {
        ux_error "could not create a temp file for the crontab dump"
        return 1
    }
    if ! aicron_crontab_dump_to "${_cur}"; then
        rm -f "${_cur}"
        ux_error "could not read the current crontab (${_AICRON_CRONTAB_ERR}) — refusing to rewrite it"
        return 1
    fi
    {
        aicron_crontab_strip "$1" <"${_cur}"
        printf '# BEGIN aicron:%s\n' "$1"
        printf '%s %s run %s\n' "$2" "$3" "$1"
        printf '# END aicron:%s\n' "$1"
    } | aicron_crontab_write
    _rc=$?
    rm -f "${_cur}"
    return ${_rc}
}

# Drop job <1>'s block(s). The state file is deliberately left alone — a
# removed job that gets re-added keeps its pause flag and its last result.
aicron_crontab_uninstall() {
    local _cur _rc
    _cur=$(aicron_mktemp aicron-crontab) || {
        ux_error "could not create a temp file for the crontab dump"
        return 1
    }
    if ! aicron_crontab_dump_to "${_cur}"; then
        rm -f "${_cur}"
        ux_error "could not read the current crontab (${_AICRON_CRONTAB_ERR}) — refusing to rewrite it"
        return 1
    fi
    aicron_crontab_strip "$1" <"${_cur}" | aicron_crontab_write
    _rc=$?
    rm -f "${_cur}"
    return ${_rc}
}

# NF-1 — run <2..> under an exclusive lock on <1> so two aicron processes
# cannot interleave a read-modify-write and lose one of the two edits.
#
# A missing flock degrades to a warning rather than a failure (the edit is
# still far more likely to succeed than to race), but a lock we cannot take
# is exit 3: that one means another edit is genuinely in flight.
aicron_crontab_guard() {
    local _lock
    _lock="$1"
    shift
    if ! command -v flock >/dev/null 2>&1; then
        ux_warning "flock not found — editing the crontab without an edit lock"
        "$@"
        return $?
    fi
    if ! : >>"${_lock}" 2>/dev/null; then
        ux_warning "edit lock is not writable (${_lock}) — editing without it"
        "$@"
        return $?
    fi
    (
        flock -w 10 9 || exit 3
        "$@"
    ) 9>>"${_lock}"
}
