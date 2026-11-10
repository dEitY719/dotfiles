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

@test "internal mode + github.com origin: refused before fetch or branch (#96)" {
    git -C "$REPO" update-ref -d refs/remotes/origin/HEAD
    git -C "$REPO" update-ref -d refs/remotes/origin/main
    run_in_bash "cd '$REPO' && export DOTFILES_SETUP_MODE=internal && gitignore_pr .omo"
    assert_failure
    assert_output --partial "push to github.com"
    assert_output --partial ".git/info/exclude"
    run git -C "$REPO" show-ref --verify -q refs/remotes/origin/main
    assert_failure
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
    [ ! -e "$HOME/gh.args" ]
}

@test "internal mode + GHES origin: not refused (#96)" {
    ghes_url="https://ghes.example.com/test/repo.git"
    git -C "$REPO" config url."$BARE".insteadOf "$ghes_url"
    git -C "$REPO" remote set-url origin "$ghes_url"
    run_in_bash "cd '$REPO' && export DOTFILES_SETUP_MODE=internal DOTFILES_GHES_HOST=ghes.example.com && gitignore_pr .omo"
    assert_success
    run cat "$HOME/gh.args"
    assert_output --partial "ghes.example.com/test/repo"
}

@test "internal mode push failure toward github.com: no retry hint (#96)" {
    printf '#!/bin/sh\nexit 1\n' >"$BARE/hooks/pre-receive"
    chmod +x "$BARE/hooks/pre-receive"
    git -C "$REPO" switch -q -c chore/gitignore-omo origin/main
    run_in_bash "cd '$REPO' && export DOTFILES_SETUP_MODE=internal && _gitignore_pr_commit_push_pr '$REPO' main chore/gitignore-omo github.com/test/repo .omo/ 'chore: ignore .omo/'"
    assert_failure
    assert_output --partial "external PC"
    refute_output --partial "Retry: git push"
}

@test "internal mode + github.com pushurl (subdomain, mixed case) behind a GHES origin: refused (#96)" {
    ghes_url="https://ghes.example.com/test/repo.git"
    git -C "$REPO" config --unset url."$BARE".insteadOf
    git -C "$REPO" config url."$BARE".insteadOf "$ghes_url"
    git -C "$REPO" remote set-url origin "$ghes_url"
    git -C "$REPO" remote set-url --push origin "ssh://git@SSH.GitHub.com:443/test/repo.git"
    # GIT_SSH_COMMAND=false: should the guard regress, the push still never leaves the host.
    run_in_bash "cd '$REPO' && export GIT_SSH_COMMAND=false DOTFILES_SETUP_MODE=internal DOTFILES_GHES_HOST=ghes.example.com && gitignore_pr .omo"
    assert_failure
    assert_output --partial "push to github.com"
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
}

@test "internal mode + second github.com pushurl: refused before branching" {
    ghes_url="https://ghes.example.com/test/repo.git"
    git -C "$REPO" remote set-url origin "$ghes_url"
    git -C "$REPO" remote set-url --add --push origin "$ghes_url"
    git -C "$REPO" remote set-url --add --push origin "ssh://git@SSH.GitHub.com:443/test/repo.git"
    run_in_bash "cd '$REPO' && export GIT_SSH_COMMAND=false DOTFILES_SETUP_MODE=internal DOTFILES_GHES_HOST=ghes.example.com && gitignore_pr .omo"
    assert_failure
    assert_output --partial "push to github.com"
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
}

@test "internal mode + scp-style github.com pushurl without user: refused" {
    git -C "$REPO" remote set-url origin "https://ghes.example.com/test/repo.git"
    git -C "$REPO" remote set-url --push origin "github.com:test/repo.git"
    run_in_bash "cd '$REPO' && export GIT_SSH_COMMAND=false DOTFILES_SETUP_MODE=internal DOTFILES_GHES_HOST=ghes.example.com && gitignore_pr .omo"
    assert_failure
    assert_output --partial "push to github.com"
    run git -C "$REPO" branch --list 'chore/*'
    assert_output ""
}
