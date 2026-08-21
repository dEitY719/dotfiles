#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_tokens.bats
#
# claude/statusline-command.sh + claude/statusline-tokens.sh (#1380):
#   - the context segment is now "📜 65.7k(7%)" (was "🧮 65.7k / 7%")
#   - a session-cumulative "📥 … 💰…% 📤 …" segment is computed by scanning the
#     transcript JSONL, deduped by message.id and cached against its mtime
#   - top-level segments are grouped and joined by a DIM ┊ instead of "|"
#   - branch icon collapsed to 🌿, git status icon 📝 → 🔀
#
# The transcript scan is exercised through real fixture files rather than a
# stubbed jq: the dedup and the mtime cache are the parts that break, and both
# only exist on the real path.

load '../test_helper'

setup() {
    # Neutral $HOME: the script reads ~/.dotfiles-setup-mode, and on an
    # `internal` PC that forks a background curl to the usage API. It also
    # points XDG_CACHE_HOME at the temp home, so the token cache written by
    # these tests never touches the developer's real cache.
    setup_isolated_home
    STATUSLINE="${DOTFILES_ROOT}/claude/statusline-command.sh"
    TOKENS_LIB="${DOTFILES_ROOT}/claude/statusline-tokens.sh"
    FIXTURES="$(mktemp -d)"
}

teardown() {
    rm -rf "$FIXTURES"
    teardown_isolated_home
}

# _render / _render_plain (shared with claude_statusline_effort.bats) live in
# test_helper.bash.

# One assistant transcript line. $1=message id, then input / cache_creation /
# cache_read / output token counts.
_usage_line() {
    printf '{"type":"assistant","message":{"id":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
        "$1" "$2" "$3" "$4" "$5"
}

# A payload wired to a transcript file (and, optionally, extra JSON members).
_payload() {
    printf '{"cwd":"%s","model":{"display_name":"Opus 5"},"transcript_path":"%s","session_id":"sess-1"%s}' \
        "$FIXTURES" "$1" "${2-}"
}

# A throwaway git repo with one commit on $2 (default: main). $HOME is isolated
# so there is no user identity to inherit — hence the inline -c flags.
_mkrepo() {
    local dir="$1" branch="${2:-main}"
    mkdir -p "$dir"
    git init -q "$dir"
    git -C "$dir" checkout -q -b "$branch" 2>/dev/null
    : >"$dir/README"
    git -C "$dir" add README
    git -C "$dir" -c user.email=t@example.com -c user.name=t commit -q -m init
}

# --- F-1: context segment format ------------------------------------------

@test "statusline ctx: renders 📜 65.7k(7%) instead of 🧮 65.7k / 7%" {
    _render_plain '{"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}}'
    assert_success
    assert_output --partial '📜 65.7k(7%)'
    refute_output --partial '65.7k / 7%'
    refute_output --partial '🧮'
}

# --- F-2 / F-3 / NF-1: session-cumulative segment --------------------------

@test "statusline tokens: renders 📥 real_read 💰hit% 📤 out from the transcript" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 34567 1200000 8262102 45678 >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥 1,235k 💰87% 📤 46k'
}

@test "statusline tokens: a repeated message.id is counted once (NF-1)" {
    # One assistant turn is written once per content block, each copy carrying
    # an identical usage object — summing them would treble every number.
    local t="$FIXTURES/session.jsonl"
    {
        _usage_line msg_a 1000 2000 7000 400
        _usage_line msg_a 1000 2000 7000 400
        _usage_line msg_a 1000 2000 7000 400
        printf '{"type":"user","message":{"role":"user","content":"hi"}}\n'
    } >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    # read = 1000+2000 = 3k, hit = 7000/10000 = 70%, out = 400
    assert_output --partial '📥 3k 💰70% 📤 400'
    refute_output --partial '9k'    # 3x the read
    refute_output --partial '📤 1k' # 3x the output
}

@test "statusline tokens: distinct message.ids are summed" {
    local t="$FIXTURES/session.jsonl"
    {
        _usage_line msg_a 1000 2000 7000 200
        _usage_line msg_b 1000 2000 7000 200
    } >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    # read = 2*(3000) = 6k, hit = 14000/20000 = 70%, out = 400
    assert_output --partial '📥 6k 💰70% 📤 400'
}

@test "statusline tokens: sub-1000 value renders raw, not 0k (F-5)" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 462 0 0 462 >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥 462'
    assert_output --partial '📤 462'
    refute_output --partial '0k'
}

@test "statusline tokens: uses 📥/📤, never ↑/↓ (F-12)" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 1000 2000 7000 500 >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥'
    assert_output --partial '📤'
    refute_output --regexp '[↑↓][0-9]'
}

# --- NF-2: mtime cache ------------------------------------------------------

@test "statusline tokens: same-mtime re-render reuses the cached scan" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 1000 2000 7000 500 >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥 3k'

    # Rewrite the transcript with completely different numbers but restore the
    # original mtime: a re-scan would show 40k, the cache must still show 3k.
    touch -r "$t" "$FIXTURES/stamp"
    _usage_line msg_z 40000000 0 0 40000000 >"$t"
    touch -r "$FIXTURES/stamp" "$t"

    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥 3k'
    refute_output --partial '40,000k'
}

@test "statusline tokens: a changed mtime invalidates the cache" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 1000 2000 7000 500 >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥 3k'

    {
        _usage_line msg_a 1000 2000 7000 200
        _usage_line msg_b 1000 2000 7000 200
    } >"$t"
    # An explicit stamp, not a bare `touch`: mtime has 1-second granularity in
    # `stat %Y`, so a rewrite inside the same second would look unchanged.
    touch -t 209901010000 "$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '📥 6k'
}

@test "statusline tokens: the scan result is cached under XDG_CACHE_HOME" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 1000 2000 7000 500 >"$t"
    _render "$(_payload "$t")"
    assert_success
    [ -f "${XDG_CACHE_HOME}/dotfiles/claude-statusline/sess-1.seg" ]
}

# --- NF-3: fail soft --------------------------------------------------------

@test "statusline tokens: no transcript_path drops only the token segment" {
    _render_plain '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}}'
    assert_success
    refute_output --partial '📥'
    refute_output --partial '💰'
    assert_output --partial 'Opus 5'
    assert_output --partial '📜 65.7k(7%)'
}

@test "statusline tokens: a missing transcript file drops only the token segment" {
    _render_plain "$(_payload "$FIXTURES/does-not-exist.jsonl" ',"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}')"
    assert_success
    refute_output --partial '📥'
    assert_output --partial 'Opus 5'
    assert_output --partial '📜 65.7k(7%)'
}

@test "statusline tokens: malformed JSONL drops only the token segment" {
    local t="$FIXTURES/broken.jsonl"
    {
        _usage_line msg_a 1000 2000 7000 500
        printf '{"type":"assistant" this is not json\n'
    } >"$t"
    _render_plain "$(_payload "$t" ',"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}')"
    assert_success
    refute_output --partial '📥'
    assert_output --partial 'Opus 5'
    assert_output --partial '📜 65.7k(7%)'
}

@test "statusline tokens: no jq on PATH yields an empty segment, no crash" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 1000 2000 7000 500 >"$t"
    run bash -c ". '${TOKENS_LIB}'; PATH=/nonexistent; printf '[%s]' \"\$(_token_segment '${t}' sess-1)\""
    assert_success
    assert_output '[]'
}

@test "statusline tokens: an empty transcript yields an empty segment" {
    local t="$FIXTURES/empty.jsonl"
    : >"$t"
    run bash -c ". '${TOKENS_LIB}'; printf '[%s]' \"\$(_token_segment '${t}' sess-1)\""
    assert_success
    assert_output '[]'
}

@test "statusline tokens: statusline-tokens.sh adds no awk fork (NF-4)" {
    run grep -c 'awk' "$TOKENS_LIB"
    assert_output '0'
}

# --- F-9 / F-9a: usage group ordering and emptiness ------------------------

@test "statusline usage: token segment sits before context, space-joined" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 34567 1200000 8262102 45678 >"$t"
    _render_plain "$(_payload "$t" ',"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}')"
    assert_success
    assert_output --partial '📥 1,235k 💰87% 📤 46k 📜 65.7k(7%)'
    refute_output --partial '📤 46k ┊ 📜'
}

@test "statusline usage: token segment alone renders with no stray separator" {
    local t="$FIXTURES/session.jsonl"
    _usage_line msg_a 1000 2000 7000 400 >"$t"
    _render_plain "$(_payload "$t")"
    assert_success
    assert_output --partial '┊ 📥 3k 💰70% 📤 400'
    refute_output --partial '📜'
    refute_output --regexp '📤 400 +┊ *$'
}

@test "statusline usage: context alone renders with no stray separator" {
    _render_plain '{"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}}'
    assert_success
    assert_output --partial '┊ 📜 65.7k(7%)'
    refute_output --partial '┊  📜'
}

@test "statusline usage: both halves absent drops the whole group" {
    # Model group must butt straight against the location group.
    _render_plain '{"model":{"display_name":"Haiku 4.5"}}'
    assert_success
    assert_output --partial 'Haiku 4.5 ┊ 📁'
    refute_output --partial '┊ ┊'
    refute_output --regexp '┊ *$'
}

# --- F-10 / F-11: separator and grouping ------------------------------------

@test "statusline layout: top-level separator is a DIM ┊, not |" {
    local esc
    esc=$(printf '\033')
    _render '{"model":{"display_name":"Opus 5"}}'
    assert_success
    assert_output --partial "${esc}[2m┊${esc}[0m"
    refute_output --partial ' | '
}

@test "statusline layout: account tag and time are one group" {
    local esc
    esc=$(printf '\033')
    run bash -c "printf '%s' '{}' | CLAUDE_CONFIG_DIR='${HOME}/.claude-work1' bash '${STATUSLINE}' | sed 's/${esc}\[[0-9;]*m//g'"
    assert_success
    # No separator between the tag and the clock.
    assert_output --regexp '👤 W1 [^┊]*[0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "statusline layout: model and effort are one group" {
    _render_plain '{"model":{"display_name":"Opus 5"},"effort":{"level":"high"}}'
    assert_success
    assert_output --partial '🎭 Opus 5 🌓 high'
    refute_output --partial 'Opus 5 ┊ 🌓'
}

# --- F-7 / F-8: git and branch icons ---------------------------------------

@test "statusline git: dirty repo renders 🔀, never 📝" {
    local repo="$FIXTURES/repo"
    _mkrepo "$repo" main
    : >"$repo/untracked"
    _render_plain "{\"cwd\":\"$repo\"}"
    assert_success
    assert_output --partial '🔀 ●1'
    refute_output --partial '📝'
}

@test "statusline git: ahead count still renders ↑N" {
    local src="$FIXTURES/src" work="$FIXTURES/work"
    _mkrepo "$src" main
    git clone -q "$src" "$work"
    : >"$work/second"
    git -C "$work" add second
    git -C "$work" -c user.email=t@example.com -c user.name=t commit -q -m second
    _render_plain "{\"cwd\":\"$work\"}"
    assert_success
    assert_output --partial '↑1'
}

@test "statusline branch: main renders 🌿, not 🌳" {
    local repo="$FIXTURES/repo"
    _mkrepo "$repo" main
    _render_plain "{\"cwd\":\"$repo\"}"
    assert_success
    assert_output --partial '(🌿 main)'
    refute_output --partial '🌳'
    refute_output --partial '👑'
}

@test "statusline branch: feat/ and pr/ branches render 🌿 too" {
    local repo="$FIXTURES/repo"
    _mkrepo "$repo" feat/statusline
    _render_plain "{\"cwd\":\"$repo\"}"
    assert_success
    assert_output --partial '(🌿 feat/statusline)'
    refute_output --partial '✨'

    git -C "$repo" checkout -q -b pr/9
    _render_plain "{\"cwd\":\"$repo\"}"
    assert_success
    assert_output --partial '(🌿 pr/9)'
    refute_output --partial '⬆️'
}

@test "statusline branch: master renders 🌿, not 👑" {
    local repo="$FIXTURES/repo"
    _mkrepo "$repo" master
    _render_plain "{\"cwd\":\"$repo\"}"
    assert_success
    assert_output --partial '(🌿 master)'
    refute_output --partial '👑'
}

@test "statusline branch: non-repo still renders ⚠️ and missing dir ❓ (F-8b)" {
    local plain="$FIXTURES/plain"
    mkdir -p "$plain"
    _render_plain "{\"cwd\":\"$plain\"}"
    assert_success
    assert_output --partial '⚠️ no-git'

    _render_plain "{\"cwd\":\"$FIXTURES/nope\"}"
    assert_success
    assert_output --partial '❓ no-dir'
}
