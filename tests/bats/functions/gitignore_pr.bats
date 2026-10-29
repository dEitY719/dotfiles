#!/usr/bin/env bats
# tests/bats/functions/gitignore_pr.bats
# gitignore-pr (issue #2324): a scratch repo whose origin URL is a GitHub URL
# rewritten (url.insteadOf) to a local bare repo, plus a PATH stub for `gh`
# that records its argv and prints a fake PR URL.

load '../test_helper'

GH_URL="https://github.com/test/repo.git"

setup() {
    setup_isolated_home
    unset DOTFILES_GHES_HOST
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
        GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    BARE="$TEST_TEMP_HOME/origin.git"
    REPO="$TEST_TEMP_HOME/repo"
    git init -q --bare --initial-branch=main "$BARE"
    git init -q --initial-branch=main "$REPO"
    git -C "$REPO" config url."$BARE".insteadOf "$GH_URL"
    git -C "$REPO" remote add origin "$GH_URL"
    printf 'node_modules/\n' >"$REPO/.gitignore"
    git -C "$REPO" add .gitignore
    git -C "$REPO" commit -q -m base
    git -C "$REPO" push -q -u origin main
    git -C "$REPO" remote set-head origin main
    mkdir -p "$REPO/.omo" "$REPO/.superpowers"
    touch "$REPO/.omo/x" "$REPO/.superpowers/y"

    mkdir -p "$TEST_TEMP_HOME/bin"
    cat >"$TEST_TEMP_HOME/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$HOME/gh.args"
echo "https://github.com/test/repo/pull/1"
EOF
    chmod +x "$TEST_TEMP_HOME/bin/gh"
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

_origin_gitignore() { git -C "$BARE" show "$1:.gitignore"; }

@test "no args: lists untracked entries and changes nothing" {
    run_in_bash "cd '$REPO' && gitignore_pr"
    assert_success
    assert_output --partial ".omo/"
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
}

@test "directory arg gets trailing slash, PR opened with pinned --repo" {
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_success
    assert_output --partial "https://github.com/test/repo/pull/1"
    run _origin_gitignore chore/gitignore-omo
    assert_output --partial ".omo/"
    assert_output --partial "# Agent/extra ignores"
    run cat "$HOME/gh.args"
    assert_output --partial "github.com/test/repo"
    assert_output --partial "--base
main"
    assert_output --partial "--head
chore/gitignore-omo"
    assert_output --partial "chore: ignore .omo/"
    run git -C "$REPO" symbolic-ref --short HEAD
    assert_output "main"
}

@test "feature branch: PR branch is based on origin/main and user returns" {
    git -C "$REPO" switch -q -c feat
    echo f >"$REPO/f.txt"
    git -C "$REPO" add f.txt
    git -C "$REPO" commit -q -m feat
    run_in_bash "cd '$REPO' && gitignore_pr .omo .superpowers/"
    assert_success
    run git -C "$BARE" rev-parse chore/gitignore-omo-superpowers^
    assert_output "$(git -C "$BARE" rev-parse main)"
    run git -C "$REPO" symbolic-ref --short HEAD
    assert_output "feat"
}

@test "already ignored (either spelling): no branch, no PR" {
    run_in_bash "cd '$REPO' && gitignore_pr node_modules"
    assert_success
    assert_output --partial "Already in .gitignore"
    [ ! -e "$HOME/gh.args" ]
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
}

@test "dirty tree (.gitignore modified) fails" {
    echo extra >>"$REPO/.gitignore"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_failure
    assert_output --partial "uncommitted changes"
    [ ! -e "$HOME/gh.args" ]
}

@test "existing branch fails and is left untouched" {
    git -C "$REPO" branch chore/gitignore-omo
    before="$(git -C "$REPO" rev-parse chore/gitignore-omo)"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_failure
    assert_output --partial "already exists"
    run git -C "$REPO" rev-parse chore/gitignore-omo
    assert_output "$before"
}

@test "non-GitHub origin fails" {
    git -C "$REPO" remote set-url origin "https://example.com/x/y.git"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_failure
    assert_output --partial "not a known GitHub remote"
}

@test "commit hook failure: returns to original branch and deletes chore branch" {
    mkdir -p "$TEST_TEMP_HOME/hooks"
    printf '#!/bin/sh\necho hook-says-no\nexit 1\n' >"$TEST_TEMP_HOME/hooks/pre-commit"
    chmod +x "$TEST_TEMP_HOME/hooks/pre-commit"
    git -C "$REPO" config core.hooksPath "$TEST_TEMP_HOME/hooks"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_failure
    assert_output --partial "hook-says-no"
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
    run git -C "$REPO" status --porcelain --untracked-files=no
    assert_output ""
    run git -C "$REPO" symbolic-ref --short HEAD
    assert_output "main"
}

@test "zsh: directory arg opens PR" {
    run_in_zsh "cd '$REPO' && gitignore_pr .omo"
    assert_success
    run _origin_gitignore chore/gitignore-omo
    assert_output --partial ".omo/"
}

@test "help: dash-form usage" {
    run_in_bash "gitignore_pr_help --all"
    assert_success
    assert_output --partial "gitignore-pr <pattern>"
    refute_output --partial "gitignore_pr"
}

@test "./ prefix is stripped before normalization" {
    run_in_bash "cd '$REPO' && gitignore_pr ./.omo"
    assert_success
    run _origin_gitignore chore/gitignore-omo
    assert_output --partial ".omo/"
    refute_output --partial "./.omo"
}

@test "pattern starting with # is rejected before any change" {
    run_in_bash "cd '$REPO' && gitignore_pr '#x'"
    assert_failure
    assert_output --partial "invalid pattern"
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
}

@test "detached HEAD: returns to the same commit" {
    sha="$(git -C "$REPO" rev-parse HEAD)"
    git -C "$REPO" switch -q --detach "$sha"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_success
    run git -C "$REPO" symbolic-ref -q HEAD
    assert_failure
    run git -C "$REPO" rev-parse HEAD
    assert_output "$sha"
}

@test "push failure: commit kept on chore branch, retry hint, back on main" {
    printf '#!/bin/sh\nexit 1\n' >"$BARE/hooks/pre-receive"
    chmod +x "$BARE/hooks/pre-receive"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_failure
    assert_output --partial "git push -u origin chore/gitignore-omo"
    run git -C "$REPO" show chore/gitignore-omo:.gitignore
    assert_output --partial ".omo/"
    run git -C "$REPO" symbolic-ref --short HEAD
    assert_output "main"
    [ ! -e "$HOME/gh.args" ]
}

@test "gh pr create failure: branch pushed and kept, manual hint printed" {
    printf '#!/bin/sh\necho "boom: no auth" >&2\nexit 1\n' >"$TEST_TEMP_HOME/bin/gh"
    run_in_bash "cd '$REPO' && gitignore_pr .omo"
    assert_failure
    assert_output --partial "boom: no auth"
    assert_output --partial "gh pr create --repo github.com/test/repo"
    run git -C "$BARE" rev-parse --verify -q chore/gitignore-omo
    assert_success
}
