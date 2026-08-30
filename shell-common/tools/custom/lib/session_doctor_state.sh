#!/bin/sh
# shell-common/tools/custom/lib/session_doctor_state.sh
# Per-tab state for session_doctor_cron.sh (issue #1581). Sourced by
# ../session_doctor_cron.sh.
#
# F-6 — what a tab's entry holds, and why each key is not derivable from
# anything else:
#
#   last_detected   when this tab was last seen stuck. The transcript says the
#                   turn died, never when we noticed.
#   injections      how many `/devx:restart` prompts have actually landed on
#                   this tab. Cumulative, never reset: F-7's cap is a budget
#                   per tab, and a tab id is already short-lived (herdr mints a
#                   new one whenever the tab is recreated), so the budget
#                   renews exactly when a human has intervened.
#   last_injection  when the most recent one landed.
#   capped          set once the budget is spent, so `aicron status` and a
#                   human reading the file both see why the tab stopped being
#                   helped without having to compare two numbers.
#
# Layout under <state-dir> (${XDG_STATE_HOME:-$HOME/.local/state}/session-doctor,
# the same parent aicron's own state dir sits in):
#
#   state.json    the object above, keyed by tab id under `.tabs`
#   .lock         the tick lock (NF-1) — held by the cron entrypoint
#   .state.lock   serialises the read-modify-write below
#
# The two locks are separate on purpose. The tick lock is held for the whole
# tick, including the injections it waits on; the state lock is taken and
# released around a single jq rewrite, by the parent *and* by each background
# injection that reports its own result. One lock doing both jobs would mean
# either the injections serialise (defeating the point of backgrounding them)
# or the state writes race.
#
# Note for editors: this file's basename carries underscores, so the repo's
# naming check (git/hooks/checks/naming_check.sh) flags a function defined here
# that also appears inside a double-quoted string. Every call site below
# assigns first (`_d=$(session_doctor_state_dir)`) rather than inlining it.

# F-7's budget. Overridable so an operator can widen or close it without an
# edit, and so the bats suite can exercise the boundary without three real
# injections.
: "${SESSION_DOCTOR_CAP:=3}"

# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset (a cron
# environment can be that bare), so HOME is never referenced unguarded. Same
# rule pr_merge_train_cron.sh's `_pmt_state_dir` follows.
session_doctor_state_dir() {
    printf '%s/session-doctor' \
        "${SESSION_DOCTOR_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}}"
}

session_doctor_state_file() {
    local _d
    _d=$(session_doctor_state_dir)
    printf '%s/state.json' "${_d}"
}

session_doctor_tick_lock() {
    local _d
    _d=$(session_doctor_state_dir)
    printf '%s/.lock' "${_d}"
}

session_doctor_write_lock() {
    local _d
    _d=$(session_doctor_state_dir)
    printf '%s/.state.lock' "${_d}"
}

# Create the state dir. Non-zero when the result is not writable — the caller
# then keeps scanning and skips recording, because a broken state dir must
# never stop a stuck session from being restarted. What it does cost is the
# cap: an unrecordable tick can only ever count zero injections, so the caller
# says so rather than pretending the budget is being enforced.
session_doctor_state_ensure() {
    local _d
    _d=$(session_doctor_state_dir)
    mkdir -p "${_d}" 2>/dev/null || true
    [ -d "${_d}" ] && [ -w "${_d}" ]
}

# Apply the jq arguments and program in "$@" to the state object and swap the
# result in, under the write lock.
#
# The lock covers the *whole* read-modify-write, not just the jq call. Two
# background injections finishing at once is the normal case — that is what
# concurrent injections are for — and a lock that ended before the rename
# would let the second one's `mv` land on top of a file the first had already
# replaced, dropping one of the two increments. A read that saw the old file
# and a write that lands after the new one is exactly the lost update the cap
# cannot afford.
#
# Everything about the lock is best effort: no flock binary, an unopenable
# lock file, or a holder that will not let go within the wait all degrade to
# an unlocked write. The cost is at most one miscounted injection; refusing to
# write at all would cost the cap entirely, and hanging on the lock would cost
# the tick.
session_doctor_state_apply() {
    local _f _lock
    _f=$(session_doctor_state_file)
    _lock=$(session_doctor_write_lock)

    if command -v flock >/dev/null 2>&1 && { : >>"${_lock}"; } 2>/dev/null; then
        {
            flock -w 5 8 2>/dev/null || true
            session_doctor_state_swap "${_f}" "$@"
        } 8>>"${_lock}"
        return $?
    fi
    session_doctor_state_swap "${_f}" "$@"
}

# The read-modify-write itself: read <1>, apply the remaining arguments as
# jq's own, swap the result in. A file that is missing, or that stopped being
# JSON, is replaced by a fresh object rather than failing the write — the same
# call aicron_state_apply makes, for the same reason: a state file nobody can
# rewrite is a job that silently stops enforcing its own cap.
#
# Split out from the locking above so the locked and unlocked paths cannot
# drift apart, and so the temp file is created inside the lock rather than
# before it.
session_doctor_state_swap() {
    local _f _tmp _rc
    _f="$1"
    shift

    # Same directory as the target, so the closing `mv` stays a rename inside
    # one filesystem, and unguessable for the same reason every other temp name
    # in tools/custom is (see aicron_mktemp).
    _tmp=$(mktemp "${_f}.tmp.XXXXXX" 2>/dev/null) || return 1

    if [ -f "${_f}" ] && jq -e . "${_f}" >/dev/null 2>&1; then
        jq "$@" "${_f}" >"${_tmp}" 2>/dev/null
        _rc=$?
    else
        printf '%s' '{}' | jq "$@" >"${_tmp}" 2>/dev/null
        _rc=$?
    fi

    if [ "${_rc}" -ne 0 ]; then
        rm -f "${_tmp}"
        return 1
    fi
    mv "${_tmp}" "${_f}" 2>/dev/null || {
        rm -f "${_tmp}"
        return 1
    }
}

# How many `/devx:restart` prompts have landed on tab <1>. Always echoes a
# number: an absent tab, an absent file and an unreadable one are all zero,
# because "we have never helped this tab" is the honest answer to all three.
session_doctor_tab_injections() {
    local _f _v
    _f=$(session_doctor_state_file)
    [ -f "${_f}" ] || {
        printf '0'
        return 0
    }
    # shellcheck disable=SC2016  # jq program text — $t is jq's variable
    _v=$(jq -r --arg t "$1" '(.tabs[$t].injections // 0) | tostring' "${_f}" 2>/dev/null) || _v=""
    case "${_v}" in
    '' | *[!0-9]*) _v=0 ;;
    esac
    printf '%s' "${_v}"
}

# Record that tab <1> was seen stuck at <2>. Creates the entry, so every later
# write can assume the tab is present.
session_doctor_mark_detected() {
    # shellcheck disable=SC2016  # jq program text — $t/$s are jq's variables
    session_doctor_state_apply --arg t "$1" --arg s "$2" '
        .tabs = ((.tabs // {}) | .[$t] = ((.[$t] // {}) | .last_detected = $s))
    '
}

# Record that a `/devx:restart` prompt landed on tab <1> at <2>. This is the
# only place `injections` moves — an injection that herdr refused never
# reaches here, which is what leaves the retry budget intact for the next tick.
session_doctor_record_injection() {
    # shellcheck disable=SC2016  # jq program text — $t/$s are jq's variables
    session_doctor_state_apply --arg t "$1" --arg s "$2" '
        .tabs = ((.tabs // {}) | .[$t] = ((.[$t] // {})
            | .injections = ((.injections // 0) + 1)
            | .last_injection = $s))
    '
}

# Record that tab <1> was refused an injection at <2> because its budget is
# spent. Written every time it happens, not once: the pair (`capped_at`,
# `last_detected`) is what tells a human reading the file whether the tab is
# still stuck now or was stuck once, days ago.
session_doctor_mark_capped() {
    # shellcheck disable=SC2016  # jq program text — $t/$s are jq's variables
    session_doctor_state_apply --arg t "$1" --arg s "$2" '
        .tabs = ((.tabs // {}) | .[$t] = ((.[$t] // {})
            | .capped = true
            | .capped_at = $s))
    '
}
