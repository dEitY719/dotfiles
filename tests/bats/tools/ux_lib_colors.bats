#!/usr/bin/env bats
# tests/bats/tools/ux_lib_colors.bats
# #2129: ux_lib fetches colors+sgr0 with one `tput -S` and spells the other
# caps as SGR literals for the xterm/screen/tmux families. Lock that the
# result stays byte-identical to the per-capability `tput` lookup it replaced,
# and that every other TERM (and a missing tput) keeps the old fallback.

load '../test_helper'

_UX_CAPS='bold|dim|sgr0|setaf 4|setaf 2|setaf 3|setaf 1|setaf 6|setaf 8'

# Print the 9 UX_* values (as od bytes) after sourcing ux_lib in <shell>.
_ux_vars() {
    # $3: PATH used only while ux_lib is sourced (od/tr still run afterwards).
    local sh="$1" term="$2" path="${3:-$PATH}"
    env -u DOTFILES_TEST_MODE -u NO_COLOR TERM="$term" DOTFILES_FORCE_INIT=1 \
        "$sh" -c '
        _p=$PATH; PATH=$2
        . "$1/shell-common/tools/ux_lib/ux_lib.sh" 2>/dev/null
        PATH=$_p
        for v in "$UX_BOLD" "$UX_DIM" "$UX_RESET" "$UX_PRIMARY" "$UX_SUCCESS" \
                 "$UX_WARNING" "$UX_ERROR" "$UX_INFO" "$UX_MUTED"; do
            printf "%s" "$v" | od -An -c | tr -s " " | tr -d "\n"; printf "|\n"
        done' _ "$_BATS_REAL_DOTFILES_ROOT" "$path"
}

# The pre-#2129 lookup: one `tput <cap>` per variable, empty on failure.
_tput_vars() {
    local term="$1" cap v
    local IFS='|'
    for cap in $_UX_CAPS; do
        IFS=' '
        # shellcheck disable=SC2086 # cap carries its own argument (setaf N)
        v=$(TERM="$term" tput $cap 2>/dev/null || echo "")
        printf "%s" "$v" | od -An -c | tr -s " " | tr -d "\n"; printf "|\n"
        IFS='|'
    done
}

@test "ux_lib colors: byte-identical to per-cap tput for every installed TERM tried (bash + zsh)" {
    command -v tput >/dev/null 2>&1 || skip "tput not installed"
    local term sh checked=0
    for term in xterm-256color xterm-16color screen-256color screen.xterm-256color \
        screen-256color-bce tmux-256color tmux screen xterm vt100 linux \
        rxvt-unicode-256color screen.rxvt screen.konsole-256color xterm-direct \
        bogus-term-2129; do
        case "$term" in
            bogus-*) ;;
            *) infocmp "$term" >/dev/null 2>&1 || continue ;;
        esac
        for sh in bash zsh; do
            command -v "$sh" >/dev/null 2>&1 || continue
            run _ux_vars "$sh" "$term"
            assert_success
            [ "$output" = "$(_tput_vars "$term")" ] ||
                fail "$sh TERM=$term: UX_* differ from per-cap tput"$'\n'"got: $output"
            checked=$((checked + 1))
        done
    done
    [ "$checked" -gt 0 ]
}

@test "ux_lib colors: no tput on PATH leaves every UX_* empty" {
    local empty
    empty=$(printf '|\n%.0s' 1 2 3 4 5 6 7 8 9)
    run _ux_vars bash xterm-256color /nonexistent-2129
    assert_success
    assert_output "$empty"
}
