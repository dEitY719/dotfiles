#!/usr/bin/env bats
# tests/bats/functions/agent_launch.bats
# shell-common/lib/agent_launch.sh (#2156): per-agent launch command strings
# and the tmux window it drives. Sourced on its own (guard-free lib), with
# tmux stubbed so nothing touches a real server.

load '../test_helper'

LIB="${BATS_TEST_DIRNAME}/../../../shell-common/lib/agent_launch.sh"

run_lib() {
    run bash --noprofile --norc -c "
        tmux() { printf 'TMUX %s\n' \"\$*\" >&2; [ \"\$1\" = new-session ] && echo 0; [ \"\$1\" = has-session ] && return 1; return 0; }
        . '${LIB}'
        $1
    "
}

@test "sourcing the lib is silent and needs no interactive guard" {
    run bash --noprofile --norc -c ". '${LIB}' && declare -f _agent_launch_cmd >/dev/null && echo ok"
    assert_success
    assert_output "ok"
}

@test "_agent_launch_cmd: claude plain / --user / --bg / prompt" {
    run_lib '_agent_launch_cmd claude; _agent_launch_cmd claude work; _agent_launch_cmd claude "" 1 ""; _agent_launch_cmd claude "" 1 "it'"'"'s x"; _agent_launch_cmd claude "" 0 "hi there"'
    assert_success
    assert_line --index 0 "claude_yolo"
    assert_line --index 1 "claude_yolo --user work"
    assert_line --index 2 "claude_yolo --bg ''"
    assert_line --index 3 "claude_yolo --bg 'it'\\''s x'"
    assert_line --index 4 "claude_yolo 'hi there'"
}

@test "_agent_launch_cmd: codex/agy/opencode ignore account and prompt" {
    run_lib '_agent_launch_cmd codex work 0 hi; _agent_launch_cmd agy; _agent_launch_cmd opencode'
    assert_success
    assert_line --index 0 "codex --dangerously-bypass-approvals-and-sandbox"
    assert_line --index 1 "agy --dangerously-skip-permissions"
    assert_line --index 2 "opencode"
}

@test "_agent_launch_cmd: launch-unsupported agent fails" {
    run_lib '_agent_launch_cmd cursor'
    assert_failure
}

@test "_ts_known_agent accepts the six agents only" {
    run_lib 'for a in claude codex agy opencode cursor copilot; do _ts_known_agent $a || echo bad $a; done; _ts_known_agent nope && echo bad nope; echo done'
    assert_output "done"
}

@test "_tmux_add_agent_window sends <agent>-yolo with --user/--bg tail" {
    run_lib '_tmux_add_agent_window sess claude /tmp work 1 "a b"'
    assert_success
    assert_output --partial "TMUX new-session -d -P -F #{window_index} -s sess -n claude -c /tmp"
    assert_output --partial "claude-yolo --user work --bg 'a b' Enter"
}

@test "_tmux_add_agent_window: non-claude agent gets no prompt tail" {
    run_lib '_tmux_add_agent_window sess codex /tmp "" 0 hi'
    assert_success
    assert_output --partial "codex-yolo Enter"
}

@test "_agent_tmux_focus attaches outside tmux, switches inside" {
    # stdout stub: switch-client's stderr is discarded by design.
    run_lib 'tmux() { echo "TMUX $*"; }; unset TMUX; _agent_tmux_focus s w; TMUX=x _agent_tmux_focus s w'
    assert_line --index 0 "TMUX attach -t s"
    assert_line --index 1 "TMUX switch-client -t s:w"
}

@test "_agent_mise_trust trusts only an existing mise.toml" {
    d="$(mktemp -d)"
    run_lib "mise() { echo \"\$*\" >> '$d/log'; }; _agent_mise_trust '$d'; [ -e '$d/log' ] && echo early; : > '$d/mise.toml'; _agent_mise_trust '$d' && cat '$d/log'"
    rm -rf "$d"
    assert_success
    assert_output "trust $d/mise.toml"
}
