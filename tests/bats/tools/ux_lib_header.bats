#!/usr/bin/env bats
# tests/bats/tools/ux_lib_header.bats
# ux_header 박스 테두리가 표시 폭(display width) 기준으로 정렬되는지 검증.
# d5a52cf0(문자 수 기준 width 계산)은 CJK/한글처럼 터미널에서 2칸을 차지하는
# 문자를 만나면 border/본문 padding이 다시 어긋난다 — 회귀 케이스.

load '../test_helper'

_run_ux_header() {
    bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        ux_header \"\$1\"
    " _ "$1"
}

_assert_box_aligned() {
    local -a lines=()
    while IFS= read -r line; do
        [ -n "$line" ] && lines+=("$line")
    done <<<"$output"

    [ "${#lines[@]}" -eq 3 ]

    local top_width mid_width bottom_width
    top_width=$(printf '%s' "${lines[0]}" | wc -L)
    mid_width=$(printf '%s' "${lines[1]}" | wc -L)
    bottom_width=$(printf '%s' "${lines[2]}" | wc -L)

    [ "$top_width" -eq "$mid_width" ]
    [ "$top_width" -eq "$bottom_width" ]
}

@test "ux_header aligns border for plain ASCII text under 60 chars" {
    run _run_ux_header "Short header"
    assert_success
    _assert_box_aligned
}

@test "ux_header aligns border for ASCII text over 60 chars (#d5a52cf0 original case)" {
    run _run_ux_header "Scanning for missing commits from 'upstream/main' in 'main'..."
    assert_success
    _assert_box_aligned
}

@test "ux_header aligns border for Korean text under 60 chars (wide-char regression)" {
    run _run_ux_header "문장을 Box 테두리로 감싸는 것"
    assert_success
    _assert_box_aligned
}

@test "ux_header aligns border for Korean text over 60 chars (wide-char regression)" {
    run _run_ux_header "문장을 Box 테두리로 감싸는 것인데 지금은 더 엉뚱하게 망가진 상태이니 다시 정확히 고쳐야 한다는 요청 사항"
    assert_success
    _assert_box_aligned
}
