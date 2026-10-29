#!/usr/bin/env bats
# tests/bats/integrations/postgresql_shell_options.bats
# postgresql.sh is sourced into every interactive shell, so loading it must not
# change the caller's shell options (#2332: `set -o pipefail` leaked globally).

load '../test_helper'

PG_SH='$SHELL_COMMON/tools/integrations/postgresql.sh'

# Source postgresql.sh alone and fail, printing the delta, if `set -o` changed.
SOURCE_AND_COMPARE="
    before=\$(set -o)
    . \"$PG_SH\"
    after=\$(set -o)
    if [ \"\$before\" != \"\$after\" ]; then
        printf 'before:\n%s\nafter:\n%s\n' \"\$before\" \"\$after\"
        exit 1
    fi
    type _load_services >/dev/null
"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: sourcing postgresql.sh leaves set -o unchanged and loads its functions" {
    run bash --noprofile --norc -c "$SOURCE_AND_COMPARE"
    assert_success
}

@test "zsh: sourcing postgresql.sh leaves set -o unchanged and loads its functions" {
    run zsh -f -c "$SOURCE_AND_COMPARE"
    assert_success
}

@test "bash: pipefail is off after the full dotfiles load" {
    run_in_bash 'set -o | grep -w pipefail'
    assert_success
    assert_output --regexp 'pipefail[[:space:]]+off'
}

@test "zsh: pipefail is off after the full dotfiles load" {
    run_in_zsh 'set -o | grep -w pipefail'
    assert_success
    assert_output --regexp 'pipefail[[:space:]]+off'
}

@test "bash: a pipeline reports its last stage's status after the full load" {
    run_in_bash '(false | true); printf "rc=%s\n" "$?"'
    assert_success
    assert_output --partial 'rc=0'
}
