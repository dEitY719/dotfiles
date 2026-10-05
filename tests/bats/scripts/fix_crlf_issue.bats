#!/usr/bin/env bats
# tests/bats/scripts/fix_crlf_issue.bats
# Validate scripts/maintenance/fix_crlf_issue.sh (#1972) runs to the end on a
# CRLF-damaged repo. The script does `git reset --hard`, so it only ever runs
# inside a mktemp fixture repo with a throwaway HOME -- never the real checkout.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/scripts/maintenance/fix_crlf_issue.sh"

setup() {
    setup_isolated_home
    FIXTURE="$(mktemp -d)"
    mkdir -p "$FIXTURE/repo/scripts/maintenance" \
        "$FIXTURE/repo/shell-common/tools/ux_lib" "$FIXTURE/nohooks"
    cp "$SCRIPT_UNDER_TEST" "$FIXTURE/repo/scripts/maintenance/"
    cd "$FIXTURE/repo"
    touch setup.sh
    printf 'echo a\r\necho b\r\n' >shell-common/tools/ux_lib/ux_lib.sh
    printf 'x=1\r\n' >b.bash
    printf 'echo lf\n' >c.sh
    git init -q
    git -c core.autocrlf=false add -A
    # Fixture commit only: an empty hooksPath keeps the global hooks off the
    # deliberately CRLF content.
    git -c core.hooksPath="$FIXTURE/nohooks" -c user.name=t -c user.email=t@t \
        commit -qm fixture
}

teardown() {
    cd /
    [ -n "$FIXTURE" ] && rm -rf "$FIXTURE"
    teardown_isolated_home
}

@test "fix_crlf_issue: converts CRLF files to LF and exits 0 on a fixture repo" {
    case "$(pwd -P)" in "$(cd "$FIXTURE" && pwd -P)"/*) ;; *) false ;; esac

    run bash -c 'echo y | bash scripts/maintenance/fix_crlf_issue.sh'

    [ "$status" -eq 0 ]
    [[ "$output" == *"Converted 2 files from CRLF to LF"* ]]
    [[ "$output" == *"Repair Complete"* ]]
    ! grep -q $'\r' shell-common/tools/ux_lib/ux_lib.sh b.bash c.sh
    [ "$(git config core.autocrlf)" = "false" ]
    [ "$(stat -c %a "$HOME/.config")" = "700" ]
}
