#!/bin/sh
# shell-common/tools/custom/lib/aicron_manifest.sh
# Manifest reader for aicron (issue #1472). Sourced by ../aicron.sh.
#
# The manifest is data, never code. Every value that reaches a job's
# environment or argv is substituted with jq's `gsub`, so `$HOME` (and
# `${HOME}`) expand and nothing else does — there is deliberately no `eval`
# anywhere in this file. Adding one would turn a JSON file that lives in the
# repo into a code-execution path for whoever can edit it.
#
# Only the reads live here. Where the state file, the lock and the log go is
# aicron_state.sh's business, and installing a schedule is aicron_crontab.sh's.

# Absolute path of the manifest. AICRON_MANIFEST overrides it — the bats suite
# and anyone testing a candidate manifest depend on that override.
aicron_manifest_file() {
    printf '%s' "${AICRON_MANIFEST:-${DOTFILES_ROOT:-}/shell-common/tools/custom/cron-jobs.json}"
}

# Non-zero (with a message) when the manifest is missing or not valid JSON.
aicron_manifest_check() {
    local _m
    _m=$(aicron_manifest_file)
    if [ ! -f "${_m}" ]; then
        ux_error "manifest not found: ${_m}"
        return 1
    fi
    if ! jq -e . "${_m}" >/dev/null 2>&1; then
        ux_error "manifest is not valid JSON: ${_m}"
        return 1
    fi
    return 0
}

# Every job name, in manifest order, one per line.
aicron_manifest_names() {
    local _m
    _m=$(aicron_manifest_file)
    jq -r '.jobs[]?.name // empty' "${_m}" 2>/dev/null
}

# True when <1> names a job in the manifest.
aicron_manifest_has() {
    local _m _c
    _m=$(aicron_manifest_file)
    _c=$(jq -r --arg n "$1" '[.jobs[]? | select(.name == $n)] | length' "${_m}" 2>/dev/null)
    [ "${_c:-0}" -gt 0 ]
}

# The one substitution the manifest gets, defined once so the "$HOME and
# nothing else expands, and never through eval" rule has a single home. Every
# jq program below prepends it and is handed $h.
# shellcheck disable=SC2016  # jq program text — $h is jq's variable, not the shell's
_AICRON_JQ_EXPAND='def expand: gsub("\\$\\{HOME\\}"; $h) | gsub("\\$HOME"; $h);'

# Raw read of one field: <1> = job, <2> = a jq expression applied to the job
# object (e.g. `.schedule // ""`, or `.log | expand`).
aicron_manifest_get() {
    local _m
    _m=$(aicron_manifest_file)
    jq -r --arg n "$1" --arg h "${HOME:-}" \
        "${_AICRON_JQ_EXPAND} .jobs[]? | select(.name == \$n) | $2" "${_m}" 2>/dev/null
}

aicron_manifest_schedule() {
    aicron_manifest_get "$1" '.schedule // ""'
}

aicron_manifest_description() {
    aicron_manifest_get "$1" '.description // ""'
}

# The job's script, resolved to an absolute path. A manifest path is relative
# to DOTFILES_ROOT (so the same manifest works on every checkout); an absolute
# path is taken as-is.
aicron_manifest_script() {
    local _s
    _s=$(aicron_manifest_get "$1" '.script // ""')
    [ -n "${_s}" ] || return 1
    case "${_s}" in
    /*) printf '%s' "${_s}" ;;
    *) printf '%s/%s' "${DOTFILES_ROOT:-}" "${_s}" ;;
    esac
}

# The job's `log` override, already $HOME-expanded, or nothing when the job
# does not set one (the caller then falls back to the default log path).
aicron_manifest_log() {
    aicron_manifest_get "$1" '(.log // "") | tostring | expand'
}

# `defaults.env` overridden by the job's own `env`, as KEY=VALUE lines with
# $HOME expanded. Consumed by aicron_run.sh, which hands the lines straight to
# `env` rather than sourcing them.
# Not routed through aicron_manifest_get: this one reads .defaults at the
# document root, outside the job object that helper selects.
aicron_manifest_env() {
    local _m
    _m=$(aicron_manifest_file)
    jq -r --arg n "$1" --arg h "${HOME:-}" "${_AICRON_JQ_EXPAND}"'
        ((.defaults.env // {}) + ((.jobs[]? | select(.name == $n) | .env) // {}))
        | to_entries[]
        | "\(.key)=\(.value | tostring | expand)"
    ' "${_m}" 2>/dev/null
}

# The job's argv, one argument per line, $HOME expanded the same way the env
# values are. `--cwd $HOME/dotfiles` in the shipped manifest is why: the cron
# tick starts in $HOME with no repo under it, and hard-coding one user's home
# would make the version-controlled manifest machine-specific.
aicron_manifest_args() {
    aicron_manifest_get "$1" '(.args // []) | .[] | tostring | expand'
}
