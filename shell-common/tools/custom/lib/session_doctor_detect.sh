#!/bin/sh
# shell-common/tools/custom/lib/session_doctor_detect.sh
# Stuck-session detection for session_doctor_cron.sh (issue #1581). Sourced by
# ../session_doctor_cron.sh.
#
# F-3/F-4 — the question this file answers, for one herdr pane:
#
#   "did this tab's last assistant turn die mid-stream on an API error,
#    rather than finish?"
#
# The answer comes from the pane's own Claude Code transcript, because
# `agent_status` cannot distinguish the two: a session that finished its turn
# and a session whose turn was cut off by a 529 both report `idle`, forever.
#
# AC-3 makes zero false positives a hard requirement, and that is what shapes
# every rule below:
#
#   * Only the last event whose `.type` is `assistant` is inspected. A
#     transcript is full of the *words* "API Error" that are not errors — a
#     `task-notification` relaying a failed subagent, a user asking about the
#     error, an assistant turn that discusses one. Those are `user` and
#     `queue-operation` events, or normal assistant turns, and none of them is
#     the last assistant event of a session that died mid-stream.
#   * That event must carry a structural marker, not just matching prose:
#     `isApiErrorMessage: true`, or `message.model == "<synthetic>"` together
#     with the text signature. Claude Code mints the cut-off turn as a
#     synthetic assistant message; a real turn is neither synthetic nor
#     flagged, so an assistant that merely *writes* "API Error: ..." in its
#     own prose can never be mistaken for one. Two markers rather than one
#     because either alone would be a single point of failure across Claude
#     Code versions.
#
# Everything that cannot be established reads as "not stuck", never as
# "stuck": no transcript, no readable event, no jq — all return non-zero. The
# bias is deliberate and asymmetric, because a false negative costs one more
# cron period and a false positive types into a session that was fine.

# How many trailing lines of a transcript are searched for the last assistant
# event. A session whose turn just died has that event at (or within a handful
# of lines of) the end, so this is generous; what it buys is that a 40 MB
# transcript is not re-parsed every minute, for every tab. A window that finds
# no assistant event reads as "not stuck" — the false-negative side, as above.
: "${SESSION_DOCTOR_TAIL_LINES:=400}"

# The text half of the F-4 signature. Kept as one ERE so the three phrases the
# issue names stay in one place; `test` below applies it case-insensitively.
: "${SESSION_DOCTOR_ERROR_ERE:=API Error|Connection lost|response may be incomplete}"

# Claude Code's project-directory name for the working directory <1>: every
# character that is not a letter or a digit becomes a dash. Verified against
# live directories — `/home/u/dotfiles-issue-1581-1` becomes
# `-home-u-dotfiles-issue-1581-1`, and `/home/u/.config/herdr` becomes
# `-home-u--config-herdr` (the dot and the slash each produce their own dash,
# which is why the doubled dash is correct and not a bug).
session_doctor_cwd_slug() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'
}

# The most recently modified session transcript for working directory <1>,
# across every Claude Code account directory (`~/.claude`, `~/.claude-work1`,
# … — this repo runs multi-account, so one slug can exist under several).
# Non-zero when there is none.
#
# Only `*.jsonl` directly under the slug directory is considered. A subagent's
# transcript lives one level deeper, under `<session-uuid>/subagents/`, and is
# deliberately out of scope: a subagent dying on an API error is reported back
# to its parent as a task notification, and the parent session is the one that
# would have to be restarted.
session_doctor_transcript() {
    local _slug _newest
    [ -n "${HOME:-}" ] || return 1
    _slug=$(session_doctor_cwd_slug "$1")
    [ -n "${_slug}" ] || return 1

    # `ls -t` rather than `find -printf`/`stat`: the two platforms this repo
    # targets disagree about both of those, and these filenames are session
    # UUIDs — no spaces, no newlines, nothing for the usual `ls` parsing
    # objection to bite on. Same reasoning aicron_run_rollover uses for
    # preferring `wc -c` over `stat`.
    # shellcheck disable=SC2012
    _newest=$(ls -1t "${HOME}"/.claude*/projects/"${_slug}"/*.jsonl 2>/dev/null | head -n 1)
    [ -n "${_newest}" ] || return 1
    [ -f "${_newest}" ] || return 1
    printf '%s' "${_newest}"
}

# The last `assistant` event of transcript <1>, as one JSON line. Echoes
# nothing when the tail window holds none.
#
# `jq -R` with `fromjson?` rather than a plain JSON-stream read: the tail
# window almost always starts mid-line, and one unparseable line must skip
# itself rather than abort the whole read.
session_doctor_last_assistant_event() {
    local _f
    _f="$1"
    [ -f "${_f}" ] || return 1
    tail -n "${SESSION_DOCTOR_TAIL_LINES}" "${_f}" 2>/dev/null |
        jq -c -R 'fromjson? | select(.type == "assistant")' 2>/dev/null |
        tail -n 1
}

# Non-zero unless the assistant event on stdin is the cut-off turn described
# in this file's header. `jq -e` is what makes a `false` verdict an exit code.
session_doctor_event_is_api_error() {
    jq -e --arg re "${SESSION_DOCTOR_ERROR_ERE}" '
        def texts:
            (.message.content) as $c
            | if ($c | type) == "string" then $c
              elif ($c | type) == "array" then
                  [ $c[]? | select(type == "object" and .type == "text") | (.text // "") ]
                  | join(" ")
              else "" end;
        (.isApiErrorMessage == true)
        or (((.message.model // "") == "<synthetic>") and (texts | test($re; "i")))
    ' >/dev/null 2>&1
}

# The whole question, for working directory <1>: zero when its newest
# transcript ends on a turn that died mid-stream. Every unknown is non-zero
# (see the header's bias note).
session_doctor_cwd_is_stuck() {
    local _transcript _event
    _transcript=$(session_doctor_transcript "$1") || return 1
    _event=$(session_doctor_last_assistant_event "${_transcript}") || return 1
    [ -n "${_event}" ] || return 1
    printf '%s' "${_event}" | session_doctor_event_is_api_error
}
