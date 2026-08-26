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
# Two of those answers are three-valued, and the third value is never folded
# into the reassuring one: a crontab that could not be read reports `installed`
# as unknown (not "no"), and a lock probe that could not decide reports
# `running` as unknown (not "no"). A read-only view that quietly says "not
# installed" is what lets `add` overwrite a table nobody managed to read, and
# a monitor that says "not running" for a job it could not probe reads as
# healthy. Both come with a warning on stderr — stderr, so `--json` stays
# machine-readable.
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

# Said once per view, on stderr, when the crontab could not be read.
aicron_report_warn_crontab() {
    ux_warning "could not read the crontab (${_AICRON_CRONTAB_ERR}) — 'installed' below is unknown, not no" >&2
}

# `true`, `false` or `null` for job <3> against the already-dumped table <1>,
# where <2> is 1 when that dump succeeded. null = we do not know.
aicron_report_installed_json() {
    local _n
    if [ "$2" != "1" ]; then
        printf 'null'
        return 0
    fi
    _n=$(aicron_crontab_count_in "$1" "$3")
    if [ "${_n:-0}" -gt 0 ]; then
        printf 'true'
    else
        printf 'false'
    fi
}

# The same answer in the text views' yes/no/unknown form.
aicron_report_installed_text() {
    local _v
    _v=$(aicron_report_installed_json "$1" "$2" "$3")
    case "${_v}" in
    true) printf 'yes' ;;
    false) printf 'no' ;;
    *) printf 'unknown' ;;
    esac
}

# The JSON object for one job. <2> is an extra object merged over it (or the
# literal `null`), which is how `status` adds its `running` key without a
# second copy of this shape. <3> is the installed value as JSON — `true`,
# `false`, or `null` when the crontab could not be read.
aicron_report_job_json() {
    local _sched _script _desc _state
    _sched=$(aicron_manifest_schedule "$1")
    _script=$(aicron_manifest_script "$1") || _script=""
    _desc=$(aicron_manifest_description "$1")
    _state=$(aicron_state_json "$1")

    jq -n -c \
        --arg name "$1" \
        --arg schedule "${_sched}" \
        --arg script "${_script}" \
        --arg description "${_desc}" \
        --argjson installed "$3" \
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
    local _tmp _table _ok _n _inst _paused _last _mf _sd
    _tmp=$(aicron_mktemp aicron-list) || {
        ux_error "could not create a temp file for the job list"
        return 1
    }
    aicron_manifest_names >"${_tmp}" 2>/dev/null || : >"${_tmp}"

    # One dump for the whole view: the installed answer is a lookup in this
    # table, not a `crontab -l` per job.
    _table=$(aicron_mktemp aicron-table) || {
        rm -f "${_tmp}"
        ux_error "could not create a temp file for the crontab dump"
        return 1
    }
    _ok=1
    aicron_crontab_dump_to "${_table}" || _ok=0
    [ "${_ok}" = "1" ] || aicron_report_warn_crontab

    if [ "$1" = "json" ]; then
        {
            while IFS= read -r _n; do
                [ -n "${_n}" ] || continue
                _inst=$(aicron_report_installed_json "${_table}" "${_ok}" "${_n}")
                aicron_report_job_json "${_n}" null "${_inst}"
            done <"${_tmp}"
        } | jq -s '{jobs: .}'
        rm -f "${_tmp}" "${_table}"
        return 0
    fi

    ux_header "aicron jobs"
    ux_table_header "JOB" "INSTALLED / PAUSED" "LAST RUN"
    while IFS= read -r _n; do
        [ -n "${_n}" ] || continue
        _inst=$(aicron_report_installed_text "${_table}" "${_ok}" "${_n}")
        _paused=no
        aicron_state_paused "${_n}" && _paused=yes
        _last=$(aicron_report_last "${_n}")
        ux_table_row "${_n}" "installed=${_inst}  paused=${_paused}" "${_last}"
    done <"${_tmp}"
    rm -f "${_tmp}" "${_table}"

    _mf=$(aicron_manifest_file)
    _sd=$(aicron_state_dir)
    ux_info ""
    ux_bullet_sub "manifest: ${_mf}"
    ux_bullet_sub "state:    ${_sd}"
    return 0
}

# --- status ---------------------------------------------------------------

# Said once, on stderr, when the lock probe could not decide.
aicron_report_warn_probe() {
    ux_warning "could not probe the run lock for $1 — 'running' is unknown, not no" >&2
}

# <1> = job, <2> = "json" or "text".
aicron_report_status() {
    local _table _ok _probe _running _extra _inst _desc _sched _paused _last _log

    _table=$(aicron_mktemp aicron-table) || {
        ux_error "could not create a temp file for the crontab dump"
        return 1
    }
    _ok=1
    aicron_crontab_dump_to "${_table}" || _ok=0
    [ "${_ok}" = "1" ] || aicron_report_warn_crontab

    _probe=$(aicron_state_probe "$1")
    [ "${_probe}" = "unknown" ] && aicron_report_warn_probe "$1"

    if [ "$2" = "json" ]; then
        case "${_probe}" in
        running) _running=true ;;
        idle) _running=false ;;
        *) _running=null ;;
        esac
        _extra=$(printf '{"running":%s}' "${_running}")
        _inst=$(aicron_report_installed_json "${_table}" "${_ok}" "$1")
        rm -f "${_table}"
        aicron_report_job_json "$1" "${_extra}" "${_inst}"
        return 0
    fi

    # The text view wants yes/no, so it builds yes/no — the same way the list
    # loop above does, rather than through a boolean and back again.
    case "${_probe}" in
    running) _running=yes ;;
    idle) _running=no ;;
    *) _running=unknown ;;
    esac
    _desc=$(aicron_manifest_description "$1")
    _sched=$(aicron_manifest_schedule "$1")
    _inst=$(aicron_report_installed_text "${_table}" "${_ok}" "$1")
    rm -f "${_table}"
    _paused=no
    aicron_state_paused "$1" && _paused=yes
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
    _tmp=$(aicron_mktemp aicron-doctor) || return 0

    # Both crontab findings come off one sorted dump, and the manifest job list
    # is read before them so "installed but not in the manifest" is a set
    # difference rather than a jq call per installed block.
    aicron_manifest_names >"${_tmp}.jobs" 2>/dev/null || : >"${_tmp}.jobs"

    if aicron_crontab_dump_to "${_tmp}.table"; then
        aicron_crontab_names_in "${_tmp}.table" | sort >"${_tmp}.all" || : >"${_tmp}.all"

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
    else
        # Not a finding about one job: nothing crontab-derived below can be
        # trusted, so say that instead of reporting every job as uninstalled.
        printf 'the crontab could not be read (%s) — installed state is unknown for every job\n' "${_AICRON_CRONTAB_ERR}"
    fi

    # (b) a manifest job whose script is not on disk.
    while IFS= read -r _n; do
        [ -n "${_n}" ] || continue
        _script=$(aicron_manifest_script "${_n}") || _script=""
        if [ -z "${_script}" ] || [ ! -f "${_script}" ]; then
            printf 'job %s: script not found: %s\n' "${_n}" "${_script:-<unset>}"
        fi
    done <"${_tmp}.jobs"

    rm -f "${_tmp}" "${_tmp}.table" "${_tmp}.all" "${_tmp}.orphan" "${_tmp}.dup" "${_tmp}.jobs"

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
    _tmp=$(aicron_mktemp aicron-findings) || {
        ux_error "could not create a temp file for the findings"
        return 1
    }
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
