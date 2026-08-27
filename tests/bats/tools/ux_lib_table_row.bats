#!/usr/bin/env bats
# tests/bats/tools/ux_lib_table_row.bats
# ux_table_row 의 라벨 폭 정책(#1501) 회귀 검증.
# `%-20s` 는 20자를 넘는 라벨을 자르지도 감싸지도 않아 구분자와 뒤 컬럼을
# 오른쪽으로 밀어버린다(#1481 에서 aicron 한 곳만 라벨 축약으로 땜질).
# 정책: 20자 이하 라벨은 기존 한 줄 출력을 바이트 단위로 유지하고,
# 20자를 넘는 라벨만 라벨 줄 + 이어붙임 줄로 감싸 구분자 위치를 보존한다.

load '../test_helper'

_run_ux_table_row() {
    bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        ux_table_row \"\$@\"
    " _ "$@"
}

# 첫 구분자 앞부분의 표시 폭(display width)을 돌려준다.
_sep_column() {
    local line="$1" sep="$2" prefix
    prefix="${line%%"$sep"*}"
    printf '%s' "$prefix" | wc -L
}

@test "ux_table_row: 20-char label (2-arg) renders exactly as the legacy single line" {
    run _run_ux_table_row "12345678901234567890" "twenty char label"
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    [ "$output" = "$(printf '  %-20s : %s' '12345678901234567890' 'twenty char label')" ]
}

@test "ux_table_row: short label (2-arg) renders exactly as the legacy single line" {
    run _run_ux_table_row "aicron" "Cron helper"
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    [ "$output" = "$(printf '  %-20s : %s' 'aicron' 'Cron helper')" ]
}

@test "ux_table_row: short label (3-arg) renders exactly as the legacy single line" {
    run _run_ux_table_row "aicron" "Cron helper" "see aicron --help"
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    [ "$output" = "$(printf '  %-20s │ %-30s │ %s' 'aicron' 'Cron helper' 'see aicron --help')" ]
}

@test "ux_table_row: 21-char label (2-arg) wraps onto a second line" {
    run _run_ux_table_row "123456789012345678901" "just over the limit"
    assert_success
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "  123456789012345678901" ]
    [ "${lines[1]}" = "$(printf '  %-20s : %s' '' 'just over the limit')" ]
}

@test "ux_table_row: long label (2-arg) keeps the label intact and the description whole" {
    run _run_ux_table_row "claude mcp remove <name>" "Remove a registered MCP server"
    assert_success
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "  claude mcp remove <name>" ]
    assert_output --partial "claude mcp remove <name>"
    assert_output --partial "Remove a registered MCP server"
}

@test "ux_table_row: long label (3-arg) wraps and preserves col2/col3" {
    run _run_ux_table_row "ollama-models [--docker]" "List local models" "docker exec variant"
    assert_success
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "  ollama-models [--docker]" ]
    [ "${lines[1]}" = "$(printf '  %-20s │ %-30s │ %s' '' 'List local models' 'docker exec variant')" ]
    assert_output --partial "ollama-models [--docker]"
    assert_output --partial "List local models"
    assert_output --partial "docker exec variant"
}

@test "ux_table_row: wrapped continuation separator aligns with a normal row (2-arg)" {
    run _run_ux_table_row "aicron" "Cron helper"
    assert_success
    local normal_col
    normal_col=$(_sep_column "${lines[0]}" ":")

    run _run_ux_table_row "redis-config-get <param>" "Read one redis config value"
    assert_success
    local wrapped_col
    wrapped_col=$(_sep_column "${lines[1]}" ":")

    [ "$normal_col" -eq "$wrapped_col" ]
}

@test "ux_table_row: wrapped continuation separator aligns with a normal row (3-arg)" {
    run _run_ux_table_row "aicron" "Cron helper" "extra"
    assert_success
    local normal_col
    normal_col=$(_sep_column "${lines[0]}" "│")

    run _run_ux_table_row "WSL_CHECK_CDRIVE_MIN_GB" "Free-space threshold" "default 20"
    assert_success
    local wrapped_col
    wrapped_col=$(_sep_column "${lines[1]}" "│")

    [ "$normal_col" -eq "$wrapped_col" ]
}
