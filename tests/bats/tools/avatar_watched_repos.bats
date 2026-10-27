#!/usr/bin/env bats
# tests/bats/tools/avatar_watched_repos.bats
# avatar_watched_repos.sh (#2285): render avatar/watched-repos.public.json into
# the watch list avatar_issue_watcher.sh reads. The merge rules themselves are
# pinned by tests/py/test_issue_watcher_watched_repos.py; this suite covers the
# shell entrypoint end to end against the real tracked file.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/avatar_watched_repos.sh"
TRACKED="${DOTFILES_ROOT}/avatar/watched-repos.public.json"

setup() {
    setup_isolated_home
    export IW_WATCHED_REPOS="${HOME}/.avatars/issue-watcher/watched-repos.json"
    mkdir -p "${HOME}/dotfiles" "${HOME}/para/project/equinest"
}

teardown() {
    teardown_isolated_home
}

_backups() {
    find "${HOME}/.avatars/issue-watcher" -name 'watched-repos.json.bak-*' | wc -l | tr -d ' '
}

@test "avatar_watched_repos: empty PC renders only repos whose checkout exists" {
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "watch list written"
    assert_output --partial "skip dEitY719/gh-pr-skills"
    run jq -r '.[] | "\(.repo) \(.path)"' "$IW_WATCHED_REPOS"
    assert_output "dEitY719/dotfiles ${HOME}/dotfiles
dEitY719/equinest ${HOME}/para/project/equinest"
    [ "$(stat -c %a "$IW_WATCHED_REPOS")" = 600 ]
    [ "$(stat -c %a "${HOME}/.avatars/issue-watcher")" = 700 ]
    [ "$(_backups)" = 0 ]
}

@test "avatar_watched_repos: local-only entry and path override survive a render" {
    mkdir -p "${HOME}/.avatars/issue-watcher"
    printf '%s\n' '[{"repo":"me/private","path":"/srv/private"},{"repo":"dEitY719/dotfiles","path":"/opt/dots","host":"github.com"}]' >"$IW_WATCHED_REPOS"
    chmod 600 "$IW_WATCHED_REPOS"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "backup:"
    run jq -r '.[] | "\(.repo) \(.path) \(.post_merge_verify // "-") \(.post_merge_verify_skill // "-")"' "$IW_WATCHED_REPOS"
    assert_line --index 0 "me/private /srv/private - -"
    assert_line --index 1 "dEitY719/dotfiles /opt/dots true gh-verify:merged"
    [ "$(_backups)" = 1 ]
}

@test "avatar_watched_repos: old verify_skill is migrated and the watcher still reads the file" {
    mkdir -p "${HOME}/.avatars/issue-watcher"
    printf '%s\n' '[{"repo":"me/live","path":"/srv/live","verify_skill":"gh-verify:live"},{"repo":"me/odd","path":"/srv/odd","verify_skill":"bogus"},{"repo":"dEitY719/dotfiles","path":"/opt/dots","verify_skill":"gh-verify:live"}]' >"$IW_WATCHED_REPOS"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "me/odd: verify_skill 'bogus'"
    run jq -c '.[] | [.repo, .post_merge_verify, .post_merge_verify_skill, .verify_skill]' "$IW_WATCHED_REPOS"
    assert_line --index 0 '["me/live",true,"gh-verify:live",null]'
    assert_line --index 1 '["me/odd",null,null,"bogus"]'
    assert_line --index 2 '["dEitY719/dotfiles",true,"gh-verify:merged",null]'
    run bash "$SCRIPT"
    assert_output --partial "already up to date"
    run bash "${DOTFILES_ROOT}/shell-common/tools/custom/avatar_issue_watcher.sh" watch list
    assert_success
    assert_output --partial "me/live"
}

@test "avatar_watched_repos: second run changes neither the file nor the backups" {
    run bash "$SCRIPT"
    assert_success
    before="$(cat "$IW_WATCHED_REPOS")"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "already up to date"
    [ "$(cat "$IW_WATCHED_REPOS")" = "$before" ]
    [ "$(_backups)" = 0 ]
}

@test "avatar_watched_repos: --dry-run prints the diff and writes nothing" {
    run bash "$SCRIPT" --dry-run
    assert_success
    assert_output --partial '+    "repo": "dEitY719/dotfiles",'
    assert_output --partial "would change"
    [ ! -e "$IW_WATCHED_REPOS" ]
}

@test "avatar_watched_repos: broken target JSON aborts and leaves it untouched" {
    mkdir -p "${HOME}/.avatars/issue-watcher"
    printf '[{' >"$IW_WATCHED_REPOS"
    run bash "$SCRIPT"
    assert_failure
    assert_output --partial "left untouched"
    [ "$(cat "$IW_WATCHED_REPOS")" = "[{" ]
    [ "$(_backups)" = 0 ]
}

@test "avatar_watched_repos: the watcher parses the rendered file" {
    run bash "$SCRIPT"
    assert_success
    run bash "${DOTFILES_ROOT}/shell-common/tools/custom/avatar_issue_watcher.sh" watch list
    assert_success
    assert_output --partial "dEitY719/dotfiles"
    assert_output --partial "${HOME}/para/project/equinest"
}

@test "avatar_watched_repos: tracked file has no absolute path, user name or internal domain" {
    # Only public github.com hosts: an internal GHES host would leak a domain.
    run jq -e 'length > 0 and all(.[];
        (.rel | startswith("/") | not) and (.rel | contains("..") | not)
        and ((.host // "github.com") == "github.com") and (has("path") | not))' "$TRACKED"
    assert_success
    run grep -nE '/home/|/Users/|[A-Za-z]:\\' "$TRACKED"
    assert_failure
    # Match the user name only as a whole JSON value or path segment, so a
    # short name like `dev` does not trip on `dev-team-404`.
    u="$(id -un)"
    run grep -nF -e "\"$u\"" -e "/$u/" -e "\"$u/" -e "/$u\"" "$TRACKED"
    assert_failure
    # Same patterns the pre-push leak guard uses, when this PC defines them.
    if [ -n "${LEAK_PATTERNS_ERE-}" ]; then
        run grep -nE "$LEAK_PATTERNS_ERE" "$TRACKED"
        assert_failure
    fi
}

@test "avatar_watched_repos: -h prints help without touching the watch list" {
    run bash "$SCRIPT" -h
    assert_success
    assert_output --partial "avatar-watched-repos"
    [ ! -e "$IW_WATCHED_REPOS" ]
}
