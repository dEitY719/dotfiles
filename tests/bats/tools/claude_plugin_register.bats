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
    # Stub publish: log, then fail or "merge" by pushing company/ main to its origin.
    printf '#!/bin/bash\necho publish >>"%s"\n[ "${PUBLISH_RC:-0}" = 0 ] || exit "$PUBLISH_RC"\ngit -C "%s" push -q origin HEAD:main\n' \
        "$PUB_LOG" "$CO" >"$FAKE/publish-sync.sh"
    chmod +x "$FAKE/register.sh" "$FAKE/publish-sync.sh"
    git -C "$CO" init -q -b main
    printf '{\n  "corp-skills": "https://ghes.example.invalid/corp/corp-skills"\n}\n' >"$CO/marketplaces.json"
    printf '{\n  "plugins": [\n    "corp@corp-skills"\n  ]\n}\n' >"$CO/plugins.json"
    git -C "$CO" add . && git -C "$CO" commit -qm init
    git init -q --bare -b main "$TEST_TEMP_HOME/company.git"
    git -C "$CO" remote add origin "$TEST_TEMP_HOME/company.git"
    git -C "$CO" push -q origin main
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

# _co_set <mp-json> <plugins-json> — commit and publish a company/ manifest pair.
_co_set() {
    printf '%s\n' "$1" >"$CO/marketplaces.json"
    printf '%s\n' "$2" >"$CO/plugins.json"
    git -C "$CO" commit -qam set && git -C "$CO" push -q origin main
}

@test "#2455 update, 0 plugins selected: only the URL changes, unregistered plugins are named" {
    _co_set '{"git-skills":"https://ghes.example.invalid/old/git-skills.git"}' '{"plugins":["corp@corp-skills"]}'
    rm -rf "$SKILLS_DIR/git-skills"
    _ws_repo git-skills git-skills '"git","git-extra"' "$URL"
    pl_before=$(cat "$CO/plugins.json")
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "git-skills 에 등록되지 않은 plugin 2개가 있습니다 (git, git-extra) — 추가하지 않음"
    run jq -r '."git-skills"' "$CO/marketplaces.json"
    assert_output "$URL"
    assert_equal "$(cat "$CO/plugins.json")" "$pl_before"
}

@test "#2455 update, partial selection: the selection is kept, the rest only named" {
    _co_set '{"git-skills":"https://ghes.example.invalid/old/git-skills.git"}' '{"plugins":["git@git-skills"]}'
    rm -rf "$SKILLS_DIR/git-skills"
    _ws_repo git-skills git-skills '"git","git-extra"' "$URL"
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "plugin 1개가 있습니다 (git-extra)"
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["git@git-skills"]'
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "이미 등록됨"
}

@test "#2455 update: a registered plugin the repo dropped is warned about, not removed" {
    "$FAKE/register.sh" "$URL"
    jq '.plugins += ["stale@git-skills"]' "$CO/plugins.json" >"$CO/p.tmp" && mv "$CO/p.tmp" "$CO/plugins.json"
    git -C "$CO" commit -qam stale && git -C "$CO" push -q origin main
    new="https://ghes.example.invalid/team/git-skills.git"
    rm -rf "$SKILLS_DIR/git-skills"
    _ws_repo git-skills git-skills '"git"' "$new"
    run "$FAKE/register.sh" "$new"
    assert_success
    assert_output --partial "repo 에 없는 등록 plugin: stale@git-skills — 제거하지 않음"
    refute_output --partial "등록되지 않은 plugin"
    run jq -r '."git-skills"' "$CO/marketplaces.json"
    assert_output "$new"
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["corp@corp-skills","git@git-skills","stale@git-skills"]'
}

@test "#2455 new marketplace: every plugin of the repo is still added" {
    rm -rf "$SKILLS_DIR/git-skills"
    _ws_repo git-skills git-skills '"git","git-extra"' "$URL"
    run "$FAKE/register.sh" "$URL"
    assert_success
    refute_output --partial "추가하지 않음"
    run jq -c '.plugins' "$CO/plugins.json"
    assert_output '["corp@corp-skills","git-extra@git-skills","git@git-skills"]'
}

@test "#2455 update: re-registering a .git-less entry with .git leaves plugins.json alone" {
    _co_set '{"corp-skills":"https://ghes.example.invalid/corp/corp-skills"}' '{"plugins":[]}'
    _ws_repo corp-skills corp-skills '"corp","corp-x"' "https://ghes.example.invalid/corp/corp-skills"
    pl_before=$(cat "$CO/plugins.json")
    run "$FAKE/register.sh" "https://ghes.example.invalid/corp/corp-skills.git"
    assert_success
    assert_output --partial "plugin 2개가 있습니다 (corp, corp-x)"
    run jq -r '."corp-skills"' "$CO/marketplaces.json"
    assert_output "https://ghes.example.invalid/corp/corp-skills.git"
    assert_equal "$(cat "$CO/plugins.json")" "$pl_before"
}

@test "#2455 update: a same-name plugin elsewhere does not block a URL-only update" {
    _co_set '{"git-skills":"https://ghes.example.invalid/old/git-skills.git"}' '{"plugins":[]}'
    printf '{"plugins":["git@claude-plugins-official"]}\n' >"$FAKE/plugins.json"
    run "$FAKE/register.sh" "$URL"
    assert_success
    run jq -r '."git-skills"' "$CO/marketplaces.json"
    assert_output "$URL"
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
    git -C "$CO" commit -qam unsort && git -C "$CO" push -q origin main
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "이미 등록됨"
    jq 'del(."git-skills")' "$CO/marketplaces.json" >"$CO/m.tmp" && mv "$CO/m.tmp" "$CO/marketplaces.json"
    git -C "$CO" commit -qam orphan && git -C "$CO" push -q origin main
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

@test "re-run after a failed publish publishes the left-over commit" {
    export PUBLISH_RC=1
    run "$FAKE/register.sh" "$URL"
    assert_failure 1
    export PUBLISH_RC=0
    : >"$PUB_LOG"
    run "$FAKE/register.sh" "$URL"
    assert_success
    assert_output --partial "이미 등록됨"
    assert_output --partial "미게시"
    run cat "$PUB_LOG"
    assert_output "publish"
    run git -C "$CO" diff --quiet origin/main -- marketplaces.json plugins.json
    assert_success
}

@test "a company/ checkout behind origin/main is refused before any edit" {
    other="$TEST_TEMP_HOME/other"
    git clone -q "$TEST_TEMP_HOME/company.git" "$other"
    jq '."x-skills" = "https://ghes.example.invalid/corp/x"' "$other/marketplaces.json" >"$other/m.tmp"
    mv "$other/m.tmp" "$other/marketplaces.json"
    git -C "$other" commit -qam other && git -C "$other" push -q origin main
    run "$FAKE/register.sh" "$URL"
    assert_failure 1
    assert_output --partial "pull --rebase"
    run git -C "$CO" status --porcelain
    assert_output ""
    [ ! -e "$PUB_LOG" ]
}

@test "a marketplace.json with no plugins or a nameless plugin is refused" {
    for bad in '{"name":"git-skills"}' '{"name":"git-skills","plugins":[]}' '{"name":"git-skills","plugins":[{"x":1}]}'; do
        printf '%s\n' "$bad" >"$SKILLS_DIR/git-skills/.claude-plugin/marketplace.json"
        run "$FAKE/register.sh" "$URL"
        assert_failure 1
        assert_output --partial ".plugins"
    done
    run git -C "$CO" status --porcelain
    assert_output ""
}

@test "credentials in the URL, helper transports and option-like args are refused" {
    run "$FAKE/register.sh" "https://user:tok@ghes.example.invalid/corp/git-skills.git"
    assert_failure 2
    assert_output --partial "자격증명"
    run "$FAKE/register.sh" "ext::sh -c touch% /tmp/pwn@x:y"
    assert_failure 2
    run "$FAKE/register.sh" --remove "ext::sh -c x@h:p"
    assert_success
    assert_output --partial "등록돼 있지 않음"
}

@test "#2453: an entry stored without .git is rewritten to .git by re-running register" {
    rm -rf "$SKILLS_DIR/corp-skills"
    _ws_repo corp-skills corp-skills '"corp"' "https://ghes.example.invalid/corp/corp-skills"
    run "$FAKE/register.sh" "https://ghes.example.invalid/corp/corp-skills"
    assert_success
    assert_output --partial ".git 을 붙여 저장합니다"
    run jq -r '."corp-skills"' "$CO/marketplaces.json"
    assert_output "https://ghes.example.invalid/corp/corp-skills.git"
    run cat "$PUB_LOG"
    assert_output "publish"
    : >"$PUB_LOG"
    run "$FAKE/register.sh" "https://ghes.example.invalid/corp/corp-skills.git"
    assert_success
    assert_output --partial "이미 등록됨"
    [ ! -s "$PUB_LOG" ]
}

@test "#2453: an https URL without .git is stored with .git; ssh/scp forms stay as given" {
    rm -rf "$SKILLS_DIR/git-skills"
    _ws_repo git-skills git-skills '"git"' "https://ghes.example.invalid/corp/git-skills"
    run "$FAKE/register.sh" "https://ghes.example.invalid/corp/git-skills/"
    assert_success
    run jq -r '."git-skills"' "$CO/marketplaces.json"
    assert_output "https://ghes.example.invalid/corp/git-skills.git"
    ssh="git@ghes.example.invalid:corp/ssh-skills"
    _ws_repo ssh-skills ssh-skills '"sshp"' "$ssh"
    run "$FAKE/register.sh" "$ssh"
    assert_success
    refute_output --partial ".git 을 붙여"
    run jq -r '."ssh-skills"' "$CO/marketplaces.json"
    assert_output "$ssh"
}

@test "#2453: a plugin name already in any manifest under another marketplace is refused" {
    _ws_repo sp-dev superpowers-dev '"superpowers"' "https://ghes.example.invalid/corp/sp-dev.git"
    printf '{"plugins":["superpowers@claude-plugins-official"]}\n' >"$FAKE/plugins.json"
    run "$FAKE/register.sh" "https://ghes.example.invalid/corp/sp-dev.git"
    assert_failure 2
    assert_output --partial "superpowers@claude-plugins-official"
    assert_output --partial "skills-workspace-ignore.local.json"
    rm "$FAKE/plugins.json"
    printf '{"plugins":["superpowers@corp-other"]}\n' >"$CO/plugins.local.json"
    run "$FAKE/register.sh" --dry-run "https://ghes.example.invalid/corp/sp-dev.git"
    assert_failure 2
    assert_output --partial "superpowers@corp-other"
    run git -C "$CO" diff --quiet origin/main -- marketplaces.json plugins.json
    assert_success
    [ ! -e "$PUB_LOG" ]
}

@test "#2453: a tombstoned (removed.local.json) same-name plugin is no collision" {
    _ws_repo sp-dev superpowers-dev '"superpowers"' "https://ghes.example.invalid/corp/sp-dev.git"
    printf '{"plugins":["superpowers@claude-plugins-official"]}\n' >"$FAKE/plugins.json"
    printf '{"plugins":["superpowers@claude-plugins-official"]}\n' >"$FAKE/removed.local.json"
    run "$FAKE/register.sh" --dry-run "https://ghes.example.invalid/corp/sp-dev.git"
    assert_success
    assert_output --partial '"superpowers@superpowers-dev"'
}

@test "a copy outside \$HOME/dotfiles (worktree) is refused: publish-sync would not publish it" {
    wt="$TEST_TEMP_HOME/dotfiles-wt/claude/plugin"
    mkdir -p "$wt"
    cp "$FAKE/register.sh" "$FAKE/publish-sync.sh" "$wt/"
    run "$wt/register.sh" "$URL"
    assert_failure 2
    assert_output --partial "만 게시합니다"
    run git -C "$CO" status --porcelain
    assert_output ""
}

# --- #2446: freshness states (a)-(d); --dry-run gives the same verdict ---

# _co_ahead_origin — another PC publishes to company.git, so company/ main is behind.
_co_ahead_origin() {
    local other="$TEST_TEMP_HOME/other"
    git clone -q "$TEST_TEMP_HOME/company.git" "$other"
    jq '."x-skills" = "https://ghes.example.invalid/corp/x"' "$other/marketplaces.json" >"$other/m.tmp"
    mv "$other/m.tmp" "$other/marketplaces.json"
    git -C "$other" commit -qam other && git -C "$other" push -q origin main
}

@test "(b) behind main with uncommitted changes: names pull --rebase --autostash, which fixes it" {
    _co_ahead_origin
    printf 'local\n' >"$CO/notes.local.json"
    git -C "$CO" add notes.local.json && git -C "$CO" commit -qm notes
    printf 'edited\n' >"$CO/notes.local.json"
    for dry in "" --dry-run; do
        run "$FAKE/register.sh" $dry "$URL"
        assert_failure 1
        assert_output --partial "main 이 origin/main 보다 뒤처져"
        assert_output --partial "git -C '$CO' pull --rebase --autostash origin main"
    done
    git -C "$CO" pull -q --rebase --autostash origin main
    run "$FAKE/register.sh" --dry-run "$URL"
    assert_success
    assert_equal "$(cat "$CO/notes.local.json")" edited
}

@test "(c) stale feature branch with origin/main manifests: names the branch and switch -C" {
    git -C "$CO" switch -q -c feat/old
    printf 'x\n' >"$CO/README" && git -C "$CO" add README && git -C "$CO" commit -qm readme
    run "$FAKE/register.sh" "$URL"
    assert_failure 1
    real=$output
    assert_output --partial "'feat/old' 브랜치"
    assert_output --partial "git -C '$CO' switch -C main origin/main"
    run "$FAKE/register.sh" --dry-run "$URL"
    assert_failure 1
    assert_equal "$output" "$real"
    [ ! -e "$PUB_LOG" ]
}

@test "(d) feature branch with different manifests: warns of unpublished changes, no switch" {
    git -C "$CO" switch -q -c feat/new
    jq '."y-skills" = "https://ghes.example.invalid/corp/y"' "$CO/marketplaces.json" >"$CO/m.tmp"
    mv "$CO/m.tmp" "$CO/marketplaces.json"
    git -C "$CO" commit -qam y
    run "$FAKE/register.sh" "$URL"
    assert_failure 1
    real=$output
    assert_output --partial "'feat/new' 브랜치이고 manifest 가 origin/main 과 다릅니다"
    refute_output --partial "switch -C"
    run "$FAKE/register.sh" --dry-run "$URL"
    assert_failure 1
    assert_equal "$output" "$real"
}

@test "(a) up-to-date main: --dry-run passes the freshness check and prints the diff" {
    run "$FAKE/register.sh" --dry-run "$URL"
    assert_success
    assert_output --partial '+  "git-skills"'
}
