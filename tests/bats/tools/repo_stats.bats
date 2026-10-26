#!/usr/bin/env bats
# tests/bats/tools/repo_stats.bats
# devx stat (repo_stats.sh, #2290): dynamic extensions in snapshot LOC,
# untracked excluded unless --include-untracked, churn section with its
# exclusion set, .mailmap-merged author ranking, --since/--until.

load '../test_helper'

setup() {
    setup_isolated_home
    REPO="$HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" config user.name Bob
    git -C "$REPO" config user.email bob@ext.io
}

teardown() {
    teardown_isolated_home
}

# _commit <name> <email> <date> <file> <n-lines>: append n lines to file and commit.
_commit() {
    local i
    for ((i = 0; i < $5; i++)); do echo "line $i" >>"$REPO/$4"; done
    git -C "$REPO" add -- "$4"
    GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" \
        GIT_COMMITTER_EMAIL="$2" GIT_AUTHOR_DATE="$3T12:00:00" \
        GIT_COMMITTER_DATE="$3T12:00:00" git -C "$REPO" commit -qm "add $4"
}

_stat() {
    run env -u DOTFILES_TEST_MODE TERM=dumb HOME="$HOME" \
        bash "${SHELL_COMMON}/tools/custom/repo_stats.sh" "$REPO" "$@"
}

_fixture() {
    _commit "Alice" "alice@team.io" 2026-01-10 app.ts 10
    _commit "Alice" "alice@team.io" 2026-01-11 README.md 50
    _commit "Alice" "alice@team.io" 2026-01-12 data.json 40
    _commit "alice" "alice@home.net" 2026-08-01 util.py 5
    _commit "Bob" "bob@ext.io" 2026-08-02 app.ts 3
}

@test "snapshot LOC collects extensions dynamically and skips json/binary" {
    _fixture
    printf '\0\1\2' >"$REPO/logo.png"
    git -C "$REPO" add logo.png && git -C "$REPO" commit -qm bin
    _stat
    assert_success
    assert_output --regexp '\.ts +│ 1 +│ 13'
    assert_output --regexp '\.py +│ 1 +│ 5'
    assert_output --regexp '\.md +│ 1 +│ 50'
    refute_output --regexp '\.json +│'
    refute_output --regexp '\.png +│'
    assert_output --regexp 'Total LOC +: 68'
}

@test "untracked files need --include-untracked" {
    _fixture
    _commit "Alice" "alice@team.io" 2026-08-03 keep.sh 1
    echo "x" >"$REPO/local.go"
    _stat
    refute_output --partial '.go'
    assert_output --partial 'untracked excluded'
    _stat --include-untracked
    assert_output --regexp '\.go +│ 1 +│ 1'
    assert_output --partial 'untracked included'
}

@test "churn excludes docs/data and prints the exclusion set" {
    _fixture
    git -C "$REPO" rm -q README.md
    GIT_AUTHOR_DATE=2026-08-04T12:00:00 GIT_COMMITTER_DATE=2026-08-04T12:00:00 \
        git -C "$REPO" commit -qm rm
    _stat
    assert_success
    assert_output --regexp 'Additions +: \+18'
    assert_output --regexp 'Deletions +: -0'
    assert_output --partial 'Excluded: *.md, *.json'
    assert_output --partial 'Churn additions = lines added by commits'
}

@test "without .mailmap aliases stay split; with it they merge" {
    _fixture
    _stat
    assert_output --regexp 'Alice +│ 3 +│ \+10 '
    assert_output --regexp 'alice +│ 1 +│ \+5 '
    printf 'Alice <alice@team.io> alice <alice@home.net>\n' >"$REPO/.mailmap"
    _stat
    assert_output --regexp 'Alice +│ 4 +│ \+15 \(83\.33%\)'
    assert_output --regexp 'Bob +│ 1 +│ \+3 \(16\.67%\)'
}

@test "--since applies to commits, churn and authors" {
    _fixture
    _stat --since 2026-07-01
    assert_success
    assert_output --regexp 'Total Commits +: 2'
    assert_output --regexp 'Additions +: \+8'
    assert_output --partial '2026-08-01 ~ 2026-08-02'
    refute_output --regexp 'Alice +│'
    _stat --until 2026-02-01
    assert_output --regexp 'Total Commits +: 3'
    assert_output --regexp 'Additions +: \+10'
}

@test "--by-author lists everyone; default folds the tail into others" {
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        _commit "Dev$i" "dev$i@x.io" 2026-03-01 "f$i.sh" 1
    done
    _stat
    assert_output --partial '(2 others)'
    _stat --by-author
    refute_output --partial 'others)'
    assert_output --regexp 'Dev12 +│'
}

@test "edge paths: deleted file, a=b name, upper-case DATA.JSON, empty repo" {
    _stat
    assert_failure 1
    assert_output --partial 'has no commits yet'
    _fixture
    _commit "Bob" "bob@ext.io" 2026-08-05 "a=b.js" 4
    _commit "Bob" "bob@ext.io" 2026-08-06 DATA.JSON 7
    rm "$REPO/util.py"
    _stat
    assert_success
    assert_output --regexp '\.js +│ 1 +│ 4'
    refute_output --regexp '\.py +│'
    assert_output --regexp 'Additions +: \+22'
}

@test "option errors exit 1" {
    _fixture
    _stat --bogus
    assert_failure 1
    assert_output --partial 'Unknown option: --bogus'
    _stat --since
    assert_failure 1
    assert_output --partial '--since requires a date'
}
