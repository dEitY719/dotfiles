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
# D-3 also makes this file the answer to "is job X installed" — the crontab is
# the SSOT for that, never the state file.
#
# Note for editors: this file's basename carries an underscore, so the repo's
# naming check flags a function defined here that also shows up inside a
# double-quoted string. Assign first, quote later.

aicron_crontab_available() {
    command -v crontab >/dev/null 2>&1
}

# The current table, or nothing at all. `crontab -l` exits non-zero with "no
# crontab for <user>" when the table is empty, which is not an error here.
aicron_crontab_dump() {
    crontab -l 2>/dev/null || true
}

# Every job name that currently owns a marker block, one per line, in table
# order and including duplicates (doctor needs to see those).
aicron_crontab_names() {
    aicron_crontab_dump | sed -n 's/^# BEGIN aicron:\(.*\)$/\1/p'
}

# How many marker blocks job <1> owns. More than one is a doctor finding.
aicron_crontab_count() {
    aicron_crontab_names | grep -c -x -F -- "$1" || true
}

aicron_crontab_installed() {
    local _n
    _n=$(aicron_crontab_count "$1")
    [ "${_n:-0}" -gt 0 ]
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
    _tmp="${TMPDIR:-/tmp}/aicron-crontab.$$"
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
    {
        aicron_crontab_dump | aicron_crontab_strip "$1"
        printf '# BEGIN aicron:%s\n' "$1"
        printf '%s %s run %s\n' "$2" "$3" "$1"
        printf '# END aicron:%s\n' "$1"
    } | aicron_crontab_write
}

# Drop job <1>'s block(s). The state file is deliberately left alone — a
# removed job that gets re-added keeps its pause flag and its last result.
aicron_crontab_uninstall() {
    aicron_crontab_dump | aicron_crontab_strip "$1" | aicron_crontab_write
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
