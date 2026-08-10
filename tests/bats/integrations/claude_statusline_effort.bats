#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_effort.bats
#
# claude/statusline-command.sh (#1302): the stdin payload carries
# `.effort.level` whenever the model supports effort levels, and the
# statusline renders it as a moon-phase glyph + the level name between the
# model and project segments.
#
# The suite also locks the NUL-delimited field reader that had to land with
# it — empty fields and separator bytes inside values both used to shift
# every later field left (rationale in the script's reader comment).

load '../test_helper'

setup() {
    # Neutral $HOME: the script reads ~/.dotfiles-setup-mode, and on an
    # `internal` PC that forks a background curl to the usage API and
    # rewrites the shared cost cache on every render.
    setup_isolated_home
    STATUSLINE="${DOTFILES_ROOT}/claude/statusline-command.sh"
}

teardown() {
    teardown_isolated_home
}

# Feed a JSON payload to the statusline and capture its rendered line.
_render() {
    run bash -c "printf '%s' '$1' | bash '${STATUSLINE}'"
}

@test "statusline effort: low renders 🌑 low" {
    _render '{"effort":{"level":"low"}}'
    assert_success
    assert_output --partial '🌑 low'
}

@test "statusline effort: medium renders 🌒 medium" {
    _render '{"effort":{"level":"medium"}}'
    assert_success
    assert_output --partial '🌒 medium'
}

@test "statusline effort: high renders 🌓 high" {
    _render '{"effort":{"level":"high"}}'
    assert_success
    assert_output --partial '🌓 high'
}

@test "statusline effort: xhigh renders 🌔 xhigh" {
    _render '{"effort":{"level":"xhigh"}}'
    assert_success
    assert_output --partial '🌔 xhigh'
}

@test "statusline effort: max renders 🌕 max" {
    _render '{"effort":{"level":"max"}}'
    assert_success
    assert_output --partial '🌕 max'
}

@test "statusline effort: absent .effort key renders no moon glyph" {
    # Models without effort support (claude-3-*, opus-4-0/4-1, sonnet-4-0/4-5)
    # omit the key entirely — the segment and its separator must both vanish.
    _render '{"model":{"display_name":"Haiku 4.5"}}'
    assert_success
    refute_output --partial '🌑'
    refute_output --partial '🌒'
    refute_output --partial '🌓'
    refute_output --partial '🌔'
    refute_output --partial '🌕'
    # The rest of the line still renders.
    assert_output --partial 'Haiku 4.5'
}

@test "statusline effort: unknown level shows raw text, no crash" {
    _render '{"effort":{"level":"ludicrous"}}'
    assert_success
    assert_output --partial 'ludicrous'
}

@test "statusline effort: effort sits between model and project segments" {
    _render '{"model":{"display_name":"Opus 5"},"effort":{"level":"xhigh"},"cwd":"/tmp"}'
    assert_success
    # Order: model name … effort … project folder.
    assert_output --regexp 'Opus 5.*🌔 xhigh.*📁'
}

@test "statusline effort: a hole in the middle does not shift later fields" {
    # Regression guard for the reader fix, with a payload that makes the shift
    # *visible*: cwd is set but model.id / display_name / usage are not, so the
    # old `@tsv` + `IFS=$'\t' read` pair collapsed the empty run and dropped
    # "max" into the model slot — rendering `🧠 max` and losing effort entirely.
    _render '{"cwd":"/tmp","effort":{"level":"max"}}'
    assert_success
    assert_output --partial '🌕 max'   # effort landed in its own slot
    refute_output --partial '🧠 max'   # and did not leak into the model slot
    assert_output --partial '📁 tmp'   # cwd still resolves
}

@test "statusline effort: model and context survive alongside effort" {
    # Every optional field populated at once — the six-field reader must keep
    # each value in its own slot.
    _render '{"model":{"display_name":"Opus 5"},"effort":{"level":"max"},"context_window":{"used_percentage":7.2,"current_usage":{"input_tokens":100,"cache_read_input_tokens":65600}}}'
    assert_success
    assert_output --partial 'Opus 5'
    assert_output --partial '🌕 max'
    assert_output --partial '65.7k / 7%'
}

# The two below lock the other half of the reader invariant: a value may
# legitimately contain the byte a previous implementation used as its field
# separator. Both payloads are decoded by jq into a real control character.

@test "statusline effort: a newline inside a value does not shift later fields" {
    # One-field-per-line reader rendered `🧠 ird` here — the tail of the path
    # landed in the model slot, effort vanished, and fmt_tokens hit stderr.
    _render '{"cwd":"/tmp/we\nird","model":{"display_name":"Opus 5"},"effort":{"level":"max"}}'
    assert_success
    assert_output --partial '🎭 Opus 5'
    assert_output --partial '🌕 max'
}

@test "statusline effort: a tab inside a value does not shift later fields" {
    # `@tsv` + `IFS=$'\t' read` rendered `🧠 unknown` here — the display name
    # split in two and every later field slid left.
    _render '{"cwd":"/tmp","model":{"display_name":"Op\tus"},"effort":{"level":"max"}}'
    assert_success
    assert_output --partial '🌕 max'
    assert_output --partial '📁 tmp'
}
