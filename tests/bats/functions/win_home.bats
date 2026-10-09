#!/usr/bin/env bats
# tests/bats/functions/win_home.bats
# shell-common/util/win_home.sh `_win_home`: the Windows profile dir as a WSL
# path, from %USERPROFILE% via wslpath. Windows and WSL user names differ per
# PC (docs/.ssot/pc-environment.md), so /mnt/c/Users/$USER and
# /mnt/c/Users/%USERNAME% are both wrong in general. cmd.exe and wslpath are
# stubbed; the stub logs every cmd.exe call so laziness/caching is checkable.

load '../test_helper'

LIB="${DOTFILES_ROOT}/shell-common/util/win_home.sh"

setup() {
    setup_isolated_home
    STUB="$HOME/stub"
    mkdir -p "$STUB" "$HOME/winprof/Documents" "$HOME/winprof/.ssh"
    # Profile dir name deliberately differs from $USER and from %USERNAME%.
    cat >"$STUB/cmd.exe" <<EOS
#!/bin/sh
echo call >>"$HOME/cmd.log"
printf 'C:\\\\Users\\\\Kim.Profile\\r\\n'
EOS
    cat >"$STUB/wslpath" <<EOS
#!/bin/sh
[ "\$1" = "-u" ] && [ "\$2" = 'C:\\Users\\Kim.Profile' ] && echo "$HOME/winprof" && exit 0
exit 1
EOS
    chmod +x "$STUB/cmd.exe" "$STUB/wslpath"
}

teardown() {
    teardown_isolated_home
}

@test "_win_home: %USERPROFILE% through wslpath, not /mnt/c/Users/\$USER" {
    run env PATH="$STUB:$PATH" bash --noprofile --norc -c ". '$LIB'; _win_home"
    assert_success
    assert_output "$HOME/winprof"
}

@test "_win_home: WIN_HOME override wins without running cmd.exe" {
    run env PATH="$STUB:$PATH" WIN_HOME=/override bash --noprofile --norc -c ". '$LIB'; _win_home"
    assert_success
    assert_output "/override"
    [ ! -e "$HOME/cmd.log" ]
}

@test "_win_home: non-WSL (no cmd.exe/wslpath) -> rc 1, no output" {
    mkdir -p "$HOME/bin"
    for c in sh bash tr; do ln -s "$(command -v "$c")" "$HOME/bin/$c"; done
    run env -i HOME="$HOME" PATH="$HOME/bin" bash --noprofile --norc -c ". '$LIB'; _win_home"
    assert_failure
    assert_output ""
}

@test "_win_home: unexpanded %USERPROFILE% (cmd.exe failure) -> rc 1" {
    printf '#!/bin/sh\necho %%USERPROFILE%%\n' >"$STUB/cmd.exe"
    run env PATH="$STUB:$PATH" bash --noprofile --norc -c ". '$LIB'; _win_home"
    assert_failure
}

@test "zsh: _win_home works when sourced under emulate -L sh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"
    run env PATH="$STUB:$PATH" zsh -f -c "f() { emulate -L sh; . '$LIB'; _win_home; }; f"
    assert_success
    assert_output "$HOME/winprof"
}

# --- cd-w* aliases (aliases/directory.sh) -------------------------------------

@test "cd-w* aliases go through _cd_win (no \$USER fallback)" {
    run_in_bash 'alias cd-wdocu cd-wdown cd-obsidian'
    assert_success
    assert_output --partial "_cd_win Documents"
    refute_output --partial 'Users/$USER'
}

@test "_cd_win: resolves lazily once, then reuses the cached profile dir" {
    run_in_bash "export PATH='$STUB':\$PATH
        [ ! -e '$HOME/cmd.log' ] || echo 'cmd.exe ran at shell start'
        _cd_win Documents && pwd
        cd /
        _cd_win .ssh && pwd
        wc -l <'$HOME/cmd.log'"
    assert_success
    assert_output "$HOME/winprof/Documents
$HOME/winprof/.ssh
1"
}

@test "zsh: _cd_win resolves the profile dir" {
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"
    run_in_zsh "export PATH='$STUB':\$PATH; _cd_win Documents && pwd"
    assert_success
    assert_output "$HOME/winprof/Documents"
}

@test "_cd_win: non-WSL -> error, rc 1" {
    run_in_bash "export PATH=/usr/bin:/bin; command -v cmd.exe >/dev/null && exit 9; _cd_win Documents"
    assert_failure
    assert_output --partial "WIN_HOME"
}

# --- check_ssh.sh uses the same helper ----------------------------------------

@test "check_ssh: Windows .ssh dir comes from %USERPROFILE%, not %USERNAME%" {
    TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
    PATH="$STUB:$PATH" run_sourced_tool_script "$TOOLS_DIR" "$TOOLS_DIR/check_ssh.sh" 'echo "$WIN_SSH_DIR"'
    assert_success
    assert_output "$HOME/winprof/.ssh"
}
