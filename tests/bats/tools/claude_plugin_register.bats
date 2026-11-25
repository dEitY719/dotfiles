#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_register.bats
# claude/plugin/register.sh (skills-register, #2443): add / update / remove a
# non-github.com marketplace in company/{marketplaces,plugins}.json, commit it
# with the publish-sync purity subject and hand off to publish-sync.sh (stub).

load '../test_helper'

REGISTER="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/register.sh"
URL="https://ghes.example.invalid/corp/git-skills.git"

setup() {
    setup_isolated_home
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    FAKE="$TEST_TEMP_HOME/dotfiles/claude/plugin"
    CO="$FAKE/company"
    mkdir -p "$CO"
    cp "$REGISTER" "$FAKE/register.sh"
    PUB_LOG="$TEST_TEMP_HOME/publish.log"
    printf '#!/bin/bash\necho publish >>"%s"\nexit "${PUBLISH_RC:-0}"\n' "$PUB_LOG" >"$FAKE/publish-sync.sh"
    chmod +x "$FAKE/register.sh" "$FAKE/publish-sync.sh"
    git -C "$CO" init -q -b main
    printf '{\n  "corp-skills": "https://ghes.example.invalid/corp/corp-skills"\n}\n' >"$CO/marketplaces.json"
    printf '{\n  "plugins": [\n    "corp@corp-skills"\n  ]\n}\n' >"$CO/plugins.json"
    git -C "$CO" add . && git -C "$CO" commit -qm init
    export SKILLS_DIR="$TEST_TEMP_HOME/ws"
    _ws_repo git-skills git-skills '"git"' "$URL"
}

teardown() {
    teardown_isolated_home
}

# _ws_repo <folder> <marketplace> <plugin-json-names> <origin>
_ws_repo() {
    local d="$SKILLS_DIR/$1"
    mkdir -p "$d/.claude-plugin"
    printf '{"name":"%s","plugins":[%s]}\n' "$2" "$3" | jq '{name, plugins: [.plugins[] | {name: .}]}' \
        >"$d/.claude-plugin/marketplace.json"
    git -C "$d" init -q
    git -C "$d" remote add origin "$4"
}

_head_subject() { git -C "$CO" log -1 --format=%s; }

@test "add: writes both company/ files, commits with the sync subject, publishes" {
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "skills-sync --restore"
    run jq -r '."git-skills"' "$CO/marketplaces.json"
    assert_output "$URL"
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["corp@corp-skills","git@git-skills"]'
    run _head_subject
    assert_output "chore(claude-plugin): sync manifest ($URL)"
    run cat "$PUB_LOG"
    assert_output "publish"
    run git -C "$CO" status --porcelain
    assert_output ""
}

@test "idempotent: a second add reports already registered, no commit, no publish" {
    "$FAKE/register.sh" "$URL"
    : >"$PUB_LOG"
    before=$(git -C "$CO" rev-parse HEAD)
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "이미 등록됨"
    assert_equal "$(git -C "$CO" rev-parse HEAD)" "$before"
    [ ! -s "$PUB_LOG" ]
}

@test "update: a changed URL and plugin list replace the old entries" {
    "$FAKE/register.sh" "$URL"
    rm -rf "$SKILLS_DIR/git-skills"
    new="https://ghes.example.invalid/team/git-skills.git"
    _ws_repo git-skills git-skills '"git","git-extra"' "$new"
    jq '.plugins += ["stale@git-skills"]' "$CO/plugins.json" >"$CO/p.tmp" && mv "$CO/p.tmp" "$CO/plugins.json"
    run "$FAKE/register.sh" "$new"
    assert_success
    run jq -r '."git-skills"' "$CO/marketplaces.json"
    assert_output "$new"
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["corp@corp-skills","git-extra@git-skills","git@git-skills"]'
}

@test "remove: by name and by URL drop the key and every *@<mp> plugin" {
    "$FAKE/register.sh" "$URL"
    run "$FAKE/register.sh" --remove git-skills
    assert_success
    run jq -c 'keys' "$CO/marketplaces.json"
    assert_output '["corp-skills"]'
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["corp@corp-skills"]'
    run _head_subject
    assert_output "chore(claude-plugin): sync manifest (git-skills)"
    run "$FAKE/register.sh" --remove "https://ghes.example.invalid/corp/corp-skills.git"
    assert_success
    run jq -c '.' "$CO/marketplaces.json"
    assert_output '{}'
    run "$FAKE/register.sh" --remove nothing-here
    assert_success
    assert_output --partial "등록돼 있지 않음"
}

@test "unsorted plugins.json: re-registering is still a no-op; --remove cleans orphan plugins" {
    "$FAKE/register.sh" "$URL"
    jq '.plugins |= reverse' "$CO/plugins.json" >"$CO/p.tmp" && mv "$CO/p.tmp" "$CO/plugins.json"
    git -C "$CO" commit -qam unsort
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "이미 등록됨"
    jq 'del(."git-skills")' "$CO/marketplaces.json" >"$CO/m.tmp" && mv "$CO/m.tmp" "$CO/marketplaces.json"
    git -C "$CO" commit -qam orphan
    run "$FAKE/register.sh" --remove git-skills
    assert_success
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["corp@corp-skills"]'
}

@test "github.com URLs are refused (exit 2) with no write" {
    for u in "https://github.com/o/git-skills.git" "git@github.com:o/git-skills.git" \
        "ssh://git@SSH.GitHub.com:443/o/git-skills.git"; do
        run "$FAKE/register.sh" "$u"
        assert_failure 2
        assert_output --partial "upstream"
    done
    run git -C "$CO" status --porcelain
    assert_output ""
    [ ! -e "$PUB_LOG" ]
}

@test "--dry-run prints the diff and changes nothing" {
    before=$(git -C "$CO" rev-parse HEAD)
    run "$FAKE/register.sh" --dry-run "$URL"
    assert_success
    assert_output --partial '+  "git-skills": "'"$URL"'"'
    assert_output --partial '+    "git@git-skills"'
    assert_equal "$(git -C "$CO" rev-parse HEAD)" "$before"
    run git -C "$CO" status --porcelain
    assert_output ""
    [ ! -e "$PUB_LOG" ]
}

@test "a repo outside the workspace is read from a scratch clone" {
    src="$TEST_TEMP_HOME/src/far-skills"
    mkdir -p "$src/.claude-plugin"
    printf '{"name":"far-skills","plugins":[{"name":"far"}]}\n' >"$src/.claude-plugin/marketplace.json"
    git -C "$src" init -q && git -C "$src" add . && git -C "$src" commit -qm init
    export TMPDIR="$TEST_TEMP_HOME/tmp"
    mkdir -p "$TMPDIR"
    run "$FAKE/register.sh" --dry-run "file://$src"
    assert_success
    assert_output --partial '"far@far-skills"'
    run ls -A "$TMPDIR"
    assert_output ""
}

@test "no company/ repo, bare name without --remove, publish failure" {
    run "$FAKE/register.sh" git-skills
    assert_failure 2
    export PUBLISH_RC=1
    run "$FAKE/register.sh" "$URL"
    assert_failure 1
    assert_output --partial "publish-sync.sh 실패"
    rm -rf "$CO/.git"
    run "$FAKE/register.sh" "https://ghes.example.invalid/corp/x.git"
    assert_failure 1
    assert_output --partial "company/ repo 가 없습니다"
}
