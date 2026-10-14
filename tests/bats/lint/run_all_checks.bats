#!/usr/bin/env bats
# tests/bats/lint/run_all_checks.bats
# Issue #2149 — git/hooks/checks/run_all.sh applies the pre-commit checks to
# whole files (golden rules), so a fixture must get the same verdict from
# both: pre-commit on the staged file and run_all on the committed tree.

load '../test_helper'

setup() {
    setup_isolated_home
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/git/hooks" "$REPO/git/config" "$REPO/git/global-hooks/lib" "$REPO/bash" "$REPO/claude"
    cp "${_BATS_REAL_DOTFILES_ROOT}/git/global-hooks/lib/leak_guard.sh" "$REPO/git/global-hooks/lib/"
    cp -R "${_BATS_REAL_DOTFILES_ROOT}/git/hooks/checks" "$REPO/git/hooks/"
    cp "${_BATS_REAL_DOTFILES_ROOT}/git/hooks/pre-commit" "$REPO/git/hooks/"
    cp "${_BATS_REAL_DOTFILES_ROOT}/git/config/hook-config.sh" "$REPO/git/config/"
    : >"$REPO/git/hooks/checks/baseline.txt"
    git -C "$REPO" init -q
    git -C "$REPO" symbolic-ref HEAD refs/heads/fixture
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name t
}

teardown() {
    teardown_isolated_home
}

# <path> <content>: pre-commit verdict on the staged file, then run_all's.
verdicts() {
    printf '%b' "$2" >"$REPO/$1"
    git -C "$REPO" add "$1"
    (cd "$REPO" && git/hooks/pre-commit >/dev/null 2>&1) && PRE=pass || PRE=fail
    "$REPO/git/hooks/checks/run_all.sh" "$1" >/dev/null 2>&1 && ALL=pass || ALL=fail
}

@test "emoji in bash/main.bash: pre-commit and run_all both fail" {
    verdicts bash/main.bash '#!/bin/bash\n# done \xf0\x9f\x9a\x80\n'
    [ "$PRE" = fail ]
    [ "$ALL" = fail ]
}

@test "model key in claude/settings.json: both fail" {
    verdicts claude/settings.json '{\n  "model": "opus"\n}\n'
    [ "$PRE" = fail ]
    [ "$ALL" = fail ]
}

@test "hardcoded home path, whole-file mode: both fail" {
    verdicts bash/main.bash '#!/bin/bash\nexport PATH=/home/someone/bin:$PATH\n'
    [ "$PRE" = fail ]
    [ "$ALL" = fail ]
}

@test "clean file: both pass" {
    verdicts bash/main.bash '#!/bin/bash\nexport PATH="$HOME/bin:$PATH"\n'
    [ "$PRE" = pass ]
    [ "$ALL" = pass ]
}

@test "baseline entry suppresses only its own check:path key" {
    verdicts bash/main.bash '#!/bin/bash\n# done \xf0\x9f\x9a\x80\n'
    echo 'emoji:bash/main.bash' >"$REPO/git/hooks/checks/baseline.txt"
    run "$REPO/git/hooks/checks/run_all.sh" bash/main.bash
    [ "$status" -eq 0 ]
    echo 'emoji:zsh/main.zsh' >"$REPO/git/hooks/checks/baseline.txt"
    run "$REPO/git/hooks/checks/run_all.sh" bash/main.bash
    [ "$status" -eq 1 ]
    [[ "$output" == *"emoji:bash/main.bash"* ]]
}

@test "bash-only \${BASH_*} in a #!/bin/sh util file: pre-commit warns, run_all fails" {
    mkdir -p "$REPO/shell-common/util"
    verdicts shell-common/util/x.sh '#!/bin/sh\necho "${BASH_VERSION-}"\n'
    [ "$PRE" = pass ]
    [ "$ALL" = fail ]
}

@test "stale baseline key for a judged file fails until removed" {
    verdicts bash/main.bash '#!/bin/bash\n# clean\n'
    echo 'emoji:bash/main.bash' >"$REPO/git/hooks/checks/baseline.txt"
    run "$REPO/git/hooks/checks/run_all.sh" bash/main.bash
    [ "$status" -eq 1 ]
    [[ "$output" == *"emoji:bash/main.bash  (stale"* ]]
    # A key for a file not in this run is never judged stale (chunked runs).
    run "$REPO/git/hooks/checks/run_all.sh" claude/settings.json
    [ "$status" -eq 0 ]
}

@test "missing interactive guard: pre-commit warns (passes), run_all fails" {
    mkdir -p "$REPO/shell-common/aliases"
    verdicts shell-common/aliases/nog.sh '#!/bin/sh\nalias gs="git status"\n'
    [ "$PRE" = pass ]
    [ "$ALL" = fail ]
}

@test "baseline key of a deleted file is stale in any run" {
    verdicts bash/main.bash '#!/bin/bash\n# clean\n'
    printf '# comment\n\nemoji:zsh/gone.zsh\n' >"$REPO/git/hooks/checks/baseline.txt"
    run "$REPO/git/hooks/checks/run_all.sh" bash/main.bash
    [ "$status" -eq 1 ]
    [[ "$output" == *"emoji:zsh/gone.zsh  (stale"* ]]
}
