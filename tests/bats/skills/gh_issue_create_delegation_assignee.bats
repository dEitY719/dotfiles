#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_delegation_assignee.bats
# Issue #1523 — AI 가 자동 생성하는 이슈는 호출자에게 자동 할당돼야 한다.
#
# issue_watcher_cron.sh 는 `gh search issues --assignee @me` 로만 후보를
# 고른다. 그래서 gh:pr-approve 의 follow-up 이슈와 devx:pr-verify-merged /
# devx:pr-verify-live 의 발견 이슈가 unassigned 로 생성되면 무인 파이프라인에
# 영원히 들어오지 못한다. 세 **호출자** 가 `--assignee @me` 를 넘기는지
# 정적으로 검증한다.
#
# NF-1: gh:issue-create 스킬 자체는 이 이슈의 범위가 아니다 — 마지막
# 회귀 가드가 그 4개 파일이 HEAD 와 바이트 동일한지 확인한다.
#
# 순수 정적 콘텐츠 검사다: 네트워크도 gh 호출도 없다.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# -- 1. gh:pr-approve follow-up issue creation --------------------------------

APPROVAL_TEMPLATES="claude/skills/gh-pr-approve/references/approval-templates.md"

@test "pr-approve: follow-up 'gh issue create' block carries --assignee @me" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/${APPROVAL_TEMPLATES}"
    [ -f "$f" ] || {
        echo "missing: $f"
        return 1
    }
    # Anchored: the assignee flag must sit inside the `gh issue create`
    # continuation block, not merely somewhere in the file.
    run grep -A 3 -F -- '--body-file "$ISSUE_BODY"' "$f"
    assert_success
    assert_output --partial '--assignee @me'
}

@test "pr-approve: Don'ts no longer forbids --assignee" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/${APPROVAL_TEMPLATES}"
    # The old prohibition grouped --assignee with --label/--milestone.
    run grep -F -- '`--label`/`--assignee`/`--milestone`' "$f"
    [ "$status" -ne 0 ] || {
        echo "Don'ts still groups --assignee into the forbidden flag list"
        return 1
    }
}

@test "pr-approve: Don'ts still forbids --label and --milestone" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/${APPROVAL_TEMPLATES}"
    run grep -F -- '`--label`/`--milestone`' "$f"
    assert_success
    assert_output --partial 'Never'
}

@test "pr-approve: Don'ts documents the --assignee @me exemption" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/${APPROVAL_TEMPLATES}"
    run grep -F -- '--assignee @me' "$f"
    assert_success
    # The exemption rationale must live next to the rule it exempts.
    run grep -c -F -- '--assignee @me' "$f"
    [ "$output" -ge 2 ]
}

# -- 2/3. delegated Skill(gh:issue-create) call sites -------------------------

@test "pr-verify-merged: Skill(gh:issue-create) delegation passes --assignee @me" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/devx-pr-verify-merged/SKILL.md"
    [ -f "$f" ] || {
        echo "missing: $f"
        return 1
    }
    run grep -F -- 'Skill(gh:issue-create' "$f"
    assert_success
    assert_output --partial '--assignee @me'
    # No bare (argument-less) delegation may survive.
    run grep -F -- 'Skill(gh:issue-create)' "$f"
    [ "$status" -ne 0 ] || {
        echo "bare Skill(gh:issue-create) still present in $f"
        return 1
    }
}

@test "pr-verify-live: findings.md section 5 delegation passes --assignee @me" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/devx-pr-verify-live/references/findings.md"
    [ -f "$f" ] || {
        echo "missing: $f"
        return 1
    }
    run grep -F -- '발견 1건마다' "$f"
    assert_success
    assert_output --partial 'Skill(gh:issue-create, "--assignee @me")'
}

# -- NF-1 regression guard ----------------------------------------------------

@test "NF-1: gh-issue-create skill files are byte-identical to HEAD" {
    local root="${_BATS_REAL_DOTFILES_ROOT}"
    local paths=(
        "claude/skills/gh-issue-create/SKILL.md"
        "claude/skills/gh-issue-create/references/options.md"
        "claude/skills/gh-issue-create/references/constraints.md"
        "claude/skills/gh-issue-create/references/create-cmd.md"
    )
    local p
    for p in "${paths[@]}"; do
        [ -f "${root}/${p}" ] || {
            echo "missing (NF-1 forbids deleting it): ${p}"
            return 1
        }
        git -C "$root" diff --quiet HEAD -- "$p" || {
            echo "NF-1 violation — ${p} differs from HEAD:"
            git -C "$root" diff HEAD -- "$p"
            return 1
        }
    done
}
