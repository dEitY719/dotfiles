#!/usr/bin/env bats
# tests/bats/functions/my_help_register.bats
# _register_help registers description + category in one call. Pins: the
# first description wins, category membership is appended once and feeds the
# reverse map, and zsh stores plain (unquoted) keys. Since #2135 every help
# file registers itself (util/help_registry.sh loads before functions/), so
# also pin: no central table in my_help.sh, every public *_help function is
# registered, and a new help file shows up without touching my_help.sh.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

REGISTER_SCRIPT='
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
    run_in_zsh 'print -rl -- ${(k)HELP_COMMAND_TO_CATEGORY} | grep -c "\"" || true'
    assert_success
    assert_output "0"
}

@test "my_help.sh holds no central registration table" {
    run grep -c "_register_help " "$DOTFILES_ROOT/shell-common/functions/my_help.sh"
    assert_output "0"
    [ -f "$DOTFILES_ROOT/shell-common/util/help_registry.sh" ]
}

# Defined public *help functions (my_help_impl is the router, not a topic)
# minus registered keys must be empty: a help file that forgets its
# `_register_help` row fails here instead of silently vanishing from my-help.
@test "bash: every public *_help function is registered" {
    run_in_bash '
        comm -23 \
            <(compgen -A function | grep "help$" | grep -v "^_" | grep -vx my_help_impl | LC_ALL=C sort) \
            <(for k in "${!HELP_DESCRIPTIONS[@]}"; do echo "$k"; done | LC_ALL=C sort) |
            sed "s/^/unregistered=/"
        echo "registered=${#HELP_DESCRIPTIONS[@]}"
    '
    assert_success
    refute_line --partial "unregistered="
    assert_line --regexp "^registered=[0-9]{2,}$"
}

@test "zsh: every public *_help function is registered" {
    run_in_zsh '
        defined=$(print -rl -- ${(k)functions} | grep "help$" | grep -v "^_" | grep -vx my_help_impl | LC_ALL=C sort)
        registered=$(print -rl -- ${(k)HELP_DESCRIPTIONS} | LC_ALL=C sort)
        comm -23 <(print -r -- "$defined") <(print -r -- "$registered") | sed "s/^/unregistered=/"
        echo "registered=${#HELP_DESCRIPTIONS}"
    '
    assert_success
    refute_line --partial "unregistered="
    assert_line --regexp "^registered=[0-9]{2,}$"
}

# A help file dropped into a copy of the tree (no my_help.sh edit) appears in
# its category page and the palette func scope.
NEW_TOPIC_FIXTURE='zzfixture_help() { ux_header "zzfixture"; }
zzfixture() { :; }
command -v _register_help >/dev/null 2>&1 || return 0
_register_help zzfixture_help "[CLI] Fixture topic" cli
_register_func zzfixture "Fixture function"
'

_with_fixture_tree() {
    local tree="$BATS_TEST_TMPDIR/tree"
    mkdir -p "$tree"
    cp -a "$DOTFILES_ROOT/bash" "$DOTFILES_ROOT/zsh" "$DOTFILES_ROOT/shell-common" "$tree/"
    printf '%s' "$NEW_TOPIC_FIXTURE" >"$tree/shell-common/functions/zzfixture_help.sh"
    export DOTFILES_ROOT="$tree" SHELL_COMMON="$tree/shell-common"
}

FIXTURE_CHECK='
    my_help_impl cli | grep -c zzfixture
    _my_help_func_registry | grep -c "^zzfixture	Fixture function$"
    echo "cat=${HELP_COMMAND_TO_CATEGORY[zzfixture]}"
'

@test "bash: a new help file self-registers without editing my_help.sh" {
    _with_fixture_tree
    run_in_bash "$FIXTURE_CHECK"
    assert_success
    assert_line --index 0 "1"
    assert_line --index 1 "1"
    assert_line "cat=cli"
}

@test "zsh: a new help file self-registers without editing my_help.sh" {
    _with_fixture_tree
    run_in_zsh "$FIXTURE_CHECK"
    assert_success
    assert_line --index 0 "1"
    assert_line --index 1 "1"
    assert_line "cat=cli"
}

# my_help.sh sourced on its own (preview helper, tests) has no loader: it loads
# the registry and replays every functions/*.sh registration row, so topics
# defined outside *_help.sh (gwt, del_file, mount) and _register_func rows stay.
@test "bash: my_help.sh sourced alone still registers every topic and func" {
    run bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1 SHELL_COMMON='$DOTFILES_ROOT/shell-common' TERM=dumb
        . '$DOTFILES_ROOT/shell-common/functions/my_help.sh' >/dev/null 2>&1
        echo \"gwt=\${HELP_COMMAND_TO_CATEGORY[gwt]-none}\"
        echo \"funcs=\$(_my_help_func_registry | wc -l)\"
    "
    assert_success
    assert_line "gwt=development"
    refute_line "funcs=0"
}

# my-help falls back to calling a same-named *function* when no <name>_help
# exists, so before issue_watcher_cron_help was registered `my-help
# issue_watcher_cron` ran a real watcher tick. Stub the tick and pin that both
# spellings now resolve to the help topic instead.
IWC_SCRIPT='
    issue_watcher_cron() { echo "TICK-RAN"; }
    my_help_impl issue-watcher-cron
    my_help_impl issue_watcher_cron
'

@test "bash: my-help issue-watcher-cron shows the help topic, never runs the tick" {
    run_in_bash "$IWC_SCRIPT"
    assert_success
    refute_output --partial "TICK-RAN"
    assert_output --partial "issue-watcher-cron-help"
}

@test "zsh: my-help issue-watcher-cron shows the help topic, never runs the tick" {
    run_in_zsh "$IWC_SCRIPT"
    assert_success
    refute_output --partial "TICK-RAN"
    assert_output --partial "issue-watcher-cron-help"
}
