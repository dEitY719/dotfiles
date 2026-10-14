#!/usr/bin/env bats
# tests/bats/lint/docs_status.bats
# Issue #2152 — scripts/lint_docs_status.sh 회귀 가드.
# (a) requirement/feature/adr 문서의 front-matter status 필수(FAIL),
# (b) approved 문서의 git 미추적 백틱 경로는 WARN(성공 종료).

load '../test_helper'

LINTER="${_BATS_REAL_DOTFILES_ROOT}/scripts/lint_docs_status.sh"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/docs/feature/foo" "$REPO/docs/adr" "$REPO/docs/.ssot" "$REPO/scripts" "$REPO/docs/archive"
    git -C "$REPO" init -q
    printf 'x\n' >"$REPO/scripts/real.sh"
    git -C "$REPO" add scripts/real.sh
}

# $1 = 경로, stdin = 내용
add_doc() {
    cat >"$REPO/$1"
    git -C "$REPO" add "$1"
}

run_linter() {
    cd "$REPO" && run sh "$LINTER"
}

@test "documents with a valid status pass" {
    printf -- '---\nstatus: draft\n---\n# a\n' | add_doc docs/feature/foo/design.md
    printf -- '---\ntitle: x\nstatus: needs-review\n---\n# b\n' | add_doc docs/adr/0001-x.md
    run_linter
    assert_success
    assert_output --partial "errors=0 warnings=0"
}

@test "feature document without status fails" {
    printf '# no front-matter\n' | add_doc docs/feature/foo/design.md
    run_linter
    assert_failure 1
    assert_output --partial "FAIL  docs/feature/foo/design.md"
}

@test "status outside the front-matter does not count" {
    printf -- '# title\n\nstatus: approved\n' | add_doc docs/feature/foo/design.md
    run_linter
    assert_failure 1
}

@test "invalid status value fails" {
    printf -- '---\nstatus: done\n---\n' | add_doc docs/adr/0001-x.md
    run_linter
    assert_failure 1
    assert_output --partial "잘못된 status 'done'"
}

@test "README.md, AGENTS.md and archive/ are out of scope" {
    printf '# r\n' | add_doc docs/feature/README.md
    printf '# a\n' | add_doc docs/adr/AGENTS.md
    printf '# old\n' | add_doc docs/archive/old.md
    run_linter
    assert_success
}

@test "approved document with a missing path warns exactly once" {
    printf -- '---\nstatus: approved\n---\nSee `scripts/real.sh`, `scripts/gone.sh:12` and `scripts/gone.sh`.\nIgnored: `other/x.md`, `scripts/*.sh`, `https://a/b`.\n' |
        add_doc docs/adr/0001-x.md
    run_linter
    assert_success
    assert_output --partial "errors=0 warnings=1"
    assert_output --partial 'warn  docs/adr/0001-x.md — stale path `scripts/gone.sh`'
}

@test "draft document with a missing path does not warn" {
    printf -- '---\nstatus: draft\n---\n`scripts/gone.sh`\n' | add_doc docs/adr/0001-x.md
    run_linter
    assert_success
    assert_output --partial "warnings=0"
}

@test "approved .ssot document is checked for stale paths" {
    printf -- '---\nstatus: approved\n---\n`scripts/gone.sh`\n' | add_doc docs/.ssot/policy.md
    run_linter
    assert_success
    assert_output --partial "warnings=1"
}
