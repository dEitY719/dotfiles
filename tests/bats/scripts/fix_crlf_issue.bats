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

@test "fix_crlf_issue: reports 10 leftover CR files as remaining, not clean (#1988)" {
    case "$(pwd -P)" in "$(cd "$FIXTURE" && pwd -P)"/*) ;; *) false ;; esac
    # A bare CR mid-line survives the `s/\r$//` conversion, so these 10 files
    # are still flagged by the verification step.
    for i in 1 2 3 4 5 6 7 8 9 10; do printf 'a\rb\n' >"mid$i.sh"; done
    git -c core.autocrlf=false add -A
    git -c core.hooksPath="$FIXTURE/nohooks" -c user.name=t -c user.email=t@t \
        commit -qm mid

    run bash -c 'echo y | bash scripts/maintenance/fix_crlf_issue.sh'

    [ "$status" -eq 0 ]
    [[ "$output" == *"10 files still have CRLF endings"* ]]
    [[ "$output" != *"No CRLF found"* ]]
}

@test "fix_crlf_issue: clean run reports no CRLF and no hardcoded home path (#1988)" {
    case "$(pwd -P)" in "$(cd "$FIXTURE" && pwd -P)"/*) ;; *) false ;; esac

    run bash -c 'echo y | bash scripts/maintenance/fix_crlf_issue.sh'

    [ "$status" -eq 0 ]
    [[ "$output" == *"No CRLF found"* ]]
    [[ "$output" == *"file $FIXTURE/repo/shell-common/aliases/core.sh"* ]] ||
        [[ "$output" == *"file $(cd "$FIXTURE/repo" && pwd -P)/shell-common/aliases/core.sh"* ]]
}
