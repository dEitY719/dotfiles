#!/bin/sh
# shell-common/tools/custom/lib/aicron_report.sh
# The read-only views for aicron (issue #1472): list, status, doctor.
# Sourced by ../aicron.sh.
#
# Every one of these answers a question by joining the three stores rather
# than trusting any single one: the manifest says which jobs exist, the
# crontab says which are installed (D-3), the state dir says which are paused
# and how the last run went. Nothing here writes.
#
# Human output goes through ux_lib. `--json` output does not — it is raw
# printf on purpose, because it exists to be piped into jq, and an ANSI
# escape or a box-drawing border in the middle of it would make that a lie.
#
# Note for editors: this file's basename carries an underscore, so the repo's
# naming check flags a function defined here that also shows up inside a
# double-quoted string. Assign first, quote later.

# --- small shared helpers -------------------------------------------------

# One line summarising the last run, or "never". The three keys are written
# together by aicron_state_record, so they are read together too — one jq over
# the state file instead of one per key, on a path `list` walks per job.
aicron_report_last() {
    local _f _v _run
    _f=$(aicron_state_file "$1")
    _v=""
    [ -f "${_f}" ] && _v=$(jq -r '
        "\(.last_run // "")|\(.last_exit // "?")|\(.last_duration_sec // "?")"
    ' "${_f}" 2>/dev/null)
    _run="${_v%%|*}"
    if [ -z "${_run}" ]; then
        printf 'never'
        return 0
    fi
    _v="${_v#*|}"
    printf '%s (exit %s, %ss)' "${_run}" "${_v%%|*}" "${_v#*|}"
}

# The JSON object for one job. <2> is an extra object merged over it (or the
# literal `null`), which is how `status` adds its `running` key without a
# second copy of this shape.
aicron_report_job_json() {
    local _sched _script _desc _inst _state
    _sched=$(aicron_manifest_schedule "$1")
    _script=$(aicron_manifest_script "$1") || _script=""
    _desc=$(aicron_manifest_description "$1")
    _inst=false
    aicron_crontab_installed "$1" && _inst=true
    _state=$(aicron_state_json "$1")

    jq -n -c \
        --arg name "$1" \
        --arg schedule "${_sched}" \
        --arg script "${_script}" \
        --arg description "${_desc}" \
        --argjson installed "${_inst}" \
        --argjson state "${_state}" \
        --argjson extra "$2" '
        {
            name: $name,
            schedule: $schedule,
            script: $script,
            description: $description,
            installed: $installed,
            paused: ($state.paused // false),
            last_run: ($state.last_run // null),
            last_exit: ($state.last_exit // null),
            last_duration_sec: ($state.last_duration_sec // null)
        }
        + (if $extra == null then {} else $extra end)
    '
}

# --- list -----------------------------------------------------------------

# <1> is "json" or "text".
aicron_report_list() {
    local _tmp _n _inst _paused _last _mf _sd
    _tmp="${TMPDIR:-/tmp}/aicron-list.$$"
    aicron_manifest_names >"${_tmp}" 2>/dev/null || : >"${_tmp}"

    if [ "$1" = "json" ]; then
        {
            while IFS= read -r _n; do
                [ -n "${_n}" ] || continue
                aicron_report_job_json "${_n}" null
            done <"${_tmp}"
        } | jq -s '{jobs: .}'
        rm -f "${_tmp}"
        return 0
    fi

    ux_header "aicron jobs"
    ux_table_header "JOB" "INSTALLED / PAUSED" "LAST RUN"
    while IFS= read -r _n; do
        [ -n "${_n}" ] || continue
        _inst=no
        aicron_crontab_installed "${_n}" && _inst=yes
        _paused=no
        aicron_state_paused "${_n}" && _paused=yes
        _last=$(aicron_report_last "${_n}")
        ux_table_row "${_n}" "installed=${_inst}  paused=${_paused}" "${_last}"
    done <"${_tmp}"
    rm -f "${_tmp}"

    _mf=$(aicron_manifest_file)
    _sd=$(aicron_state_dir)
    ux_info ""
    ux_bullet_sub "manifest: ${_mf}"
    ux_bullet_sub "state:    ${_sd}"
    return 0
}

# --- status ---------------------------------------------------------------

# <1> = job, <2> = "json" or "text".
aicron_report_status() {
    local _running _extra _desc _sched _inst _paused _last _log

    if [ "$2" = "json" ]; then
        _running=false
        aicron_state_running "$1" && _running=true
        _extra=$(printf '{"running":%s}' "${_running}")
        aicron_report_job_json "$1" "${_extra}"
        return 0
    fi

    # The text view wants yes/no, so it builds yes/no — the same way the list
    # loop below does, rather than through a boolean and back again.
    _desc=$(aicron_manifest_description "$1")
    _sched=$(aicron_manifest_schedule "$1")
    _inst=no
    aicron_crontab_installed "$1" && _inst=yes
    _paused=no
    aicron_state_paused "$1" && _paused=yes
    _running=no
    aicron_state_running "$1" && _running=yes
    _last=$(aicron_report_last "$1")
    _log=$(aicron_run_log_path "$1")

    ux_header "aicron status: $1"
    ux_table_row "description" "${_desc}"
    ux_table_row "schedule" "${_sched}"
    ux_table_row "installed" "${_inst}"
    ux_table_row "paused" "${_paused}"
    ux_table_row "running now" "${_running}"
    ux_table_row "last run" "${_last}"
    ux_table_row "log" "${_log}"
    return 0
}

# --- doctor ---------------------------------------------------------------

# Emits one finding per line on stdout, nothing when everything agrees.
aicron_doctor_scan() {
    local _tmp _n _script _f _base _sd
    _tmp="${TMPDIR:-/tmp}/aicron-doctor.$$"

    # Both crontab findings come off one sorted dump, and the manifest job list
    # is read before them so "installed but not in the manifest" is a set
    # difference rather than a jq call per installed block.
    aicron_manifest_names >"${_tmp}.jobs" 2>/dev/null || : >"${_tmp}.jobs"
    aicron_crontab_names 2>/dev/null | sort >"${_tmp}.all" || : >"${_tmp}.all"

    # (a) a marker block whose job left the manifest.
    uniq "${_tmp}.all" | grep -F -x -v -f "${_tmp}.jobs" >"${_tmp}.orphan" 2>/dev/null || true
    while IFS= read -r _n; do
        [ -n "${_n}" ] || continue
        printf 'orphan crontab block: aicron:%s is installed but absent from the manifest\n' "${_n}"
    done <"${_tmp}.orphan"

    # (d) two blocks claiming the same job.
    uniq -d "${_tmp}.all" >"${_tmp}.dup" 2>/dev/null || : >"${_tmp}.dup"
    while IFS= read -r _n; do
        [ -n "${_n}" ] || continue
        printf 'duplicate marker blocks in the crontab for job %s\n' "${_n}"
    done <"${_tmp}.dup"

    # (b) a manifest job whose script is not on disk.
    while IFS= read -r _n; do
        [ -n "${_n}" ] || continue
        _script=$(aicron_manifest_script "${_n}") || _script=""
        if [ -z "${_script}" ] || [ ! -f "${_script}" ]; then
            printf 'job %s: script not found: %s\n' "${_n}" "${_script:-<unset>}"
        fi
    done <"${_tmp}.jobs"

    rm -f "${_tmp}.all" "${_tmp}.orphan" "${_tmp}.dup" "${_tmp}.jobs"

    # (c) a state file that stopped being JSON.
    _sd=$(aicron_state_dir)
    for _f in "${_sd}"/*.json; do
        [ -f "${_f}" ] || continue
        jq -e . "${_f}" >/dev/null 2>&1 && continue
        _base="${_f##*/}"
        printf 'corrupt state file: %s\n' "${_base}"
    done
    return 0
}

aicron_report_doctor() {
    local _tmp _line _n _mf _sd
    _tmp="${TMPDIR:-/tmp}/aicron-findings.$$"
    aicron_doctor_scan >"${_tmp}" 2>/dev/null || : >"${_tmp}"

    ux_header "aicron doctor"
    _mf=$(aicron_manifest_file)
    _sd=$(aicron_state_dir)
    ux_bullet_sub "manifest: ${_mf}"
    ux_bullet_sub "state:    ${_sd}"
    ux_info ""

    if [ ! -s "${_tmp}" ]; then
        ux_success "manifest, crontab and state agree"
        rm -f "${_tmp}"
        return 0
    fi

    while IFS= read -r _line; do
        [ -n "${_line}" ] || continue
        ux_warning "${_line}"
    done <"${_tmp}"
    _n=$(wc -l <"${_tmp}" | tr -d ' ')
    rm -f "${_tmp}"
    ux_info ""
    ux_info "${_n} problem(s) found"
    return 0
}
