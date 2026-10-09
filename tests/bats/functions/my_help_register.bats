#!/usr/bin/env bats
# tests/bats/functions/my_help_register.bats
# _register_help registers description + category in one call. Pins: a
# module's own description wins, category membership is appended once and
# feeds the reverse map, and zsh stores plain (unquoted) keys.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

REGISTER_SCRIPT='
    _register_default_help_descriptions
    HELP_DESCRIPTIONS[zzt_help]="own"
    _register_help zzt_help "[CLI] default" cli
    _register_help zzt_help "[CLI] again" cli
    _register_help zzu_help "[CLI] uncategorized"
    echo "desc=${HELP_DESCRIPTIONS[zzt_help]}"
    echo "desc2=${HELP_DESCRIPTIONS[zzu_help]}"
    echo "count=$(printf "%s" "${HELP_CATEGORY_MEMBERS[cli]}" | tr " " "\n" | grep -cx zzt)"
    echo "last=${HELP_CATEGORY_MEMBERS[cli]##* }"
    echo "map=${HELP_COMMAND_TO_CATEGORY[zzt]}"
    echo "git=${HELP_COMMAND_TO_CATEGORY[git]}"
    echo "uncat=${HELP_COMMAND_TO_CATEGORY[zzu]-none}"
'

assert_register_output() {
    assert_success
    assert_line "desc=own"
    assert_line "desc2=[CLI] uncategorized"
    assert_line "count=1"
    assert_line "last=zzt"
    assert_line "map=cli"
    assert_line "git=development"
    assert_line "uncat=none"
}

@test "bash: _register_help sets description and category once" {
    run_in_bash "$REGISTER_SCRIPT"
    assert_register_output
}

@test "zsh: _register_help sets description and category once" {
    run_in_zsh "$REGISTER_SCRIPT"
    assert_register_output
}

@test "zsh: registry keys are stored without literal quotes" {
    run_in_zsh '_register_default_help_descriptions; print -rl -- ${(k)HELP_COMMAND_TO_CATEGORY} | grep -c "\"" || true'
    assert_success
    assert_output "0"
}
