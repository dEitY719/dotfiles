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

# The transcript of Claude Code session <1>, across every Claude Code account
# directory (`~/.claude`, `~/.claude-work1`, … — this repo runs multi-account,
# so the session could be filed under any of them). Non-zero when there is none.
#
# Keyed on the session id, never on the pane's working directory, because the
# working directory cannot answer the question the moment two panes share one —
# two Claude Code sessions open in the same repo with no worktree between them
# is an ordinary day here, not an exotic case. Claude Code mints one session
# (and so one `<uuid>.jsonl`) per pane, so a same-cwd pair leaves two files in
# one project directory and "the newest of them" attributes one pane's dead
# turn to the other pane, which is the false positive AC-3 forbids (PR #1609
# codex review).
#
# `herdr agent list` reports that id as `agent_session.value`, and it is the
# transcript's own basename. Verified against a live server: every `claude`
# pane's value named an existing `<uuid>.jsonl`, and the one `codex` pane's
# value named none — so a non-Claude agent falls out here as "no transcript"
# rather than being handed some Claude session that happened to share its cwd.
#
# The project directory is globbed rather than derived from the pane's cwd for
# the same reason the cwd is not the key: the id is unique on its own, so
# adding the cwd could only ever *lose* a session (a pane whose herdr `cwd` and
# the directory Claude Code actually filed it under disagree), never sharpen
# the match.
#
# Only `*.jsonl` directly under a project directory is considered. A subagent's
# transcript lives one level deeper, under `<session-uuid>/subagents/`, and is
# deliberately out of scope: a subagent dying on an API error is reported back
# to its parent as a task notification, and the parent session is the one that
# would have to be restarted.
session_doctor_transcript() {
    local _id _newest
    [ -n "${HOME:-}" ] || return 1
    _id="$1"

    # A session id is a UUID, and this one is spliced straight into a glob.
    # Anything carrying a slash or a glob metacharacter is not a session id and
    # must not be allowed to widen the pattern.
    case "${_id}" in
    '' | *[!A-Za-z0-9-]*) return 1 ;;
    esac

    # `ls -t` rather than `find -printf`/`stat`: the two platforms this repo
    # targets disagree about both of those, and these filenames are session
    # UUIDs — no spaces, no newlines, nothing for the usual `ls` parsing
    # objection to bite on. Same reasoning aicron_run_rollover uses for
    # preferring `wc -c` over `stat`. The newest wins only in the case that is
    # left after the id has done its work: the same session id filed under two
    # account directories.
    # shellcheck disable=SC2012
    _newest=$(ls -1t "${HOME}"/.claude*/projects/*/"${_id}".jsonl 2>/dev/null | head -n 1)
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

# The whole question, for Claude Code session <1>: zero when that session's
# transcript ends on a turn that died mid-stream. Every unknown is non-zero
# (see the header's bias note) — a pane herdr reports no session id for lands
# here as an empty argument and reads as "not stuck", which is the same answer
# a pane with no transcript already gets.
session_doctor_session_is_stuck() {
    local _transcript _event
    _transcript=$(session_doctor_transcript "$1") || return 1
    _event=$(session_doctor_last_assistant_event "${_transcript}") || return 1
    [ -n "${_event}" ] || return 1
    printf '%s' "${_event}" | session_doctor_event_is_api_error
}
