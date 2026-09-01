#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_scaffold.bats
# claude/plugin/ 스캐폴드 + .gitignore 무시 규칙 검증.

load '../test_helper'

# 스캐폴드 시절 두 테스트는 두 파일이 *비어 있음*을 단언했다. #1638 이 첫
# 마켓플레이스를 등록한 순간부터 자기모순이 되어 계속 red 였다 — 검사하려던
# 것은 "비었다"가 아니라 "스캐폴드 모양이 맞다"이므로 형태만 고정한다.
@test "claude/plugin/marketplaces.json exists and maps names to owner/repo slugs" {
    run jq -e 'type == "object" and (to_entries | all(.value | test("^[^/]+/[^/]+$")))' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
    assert_success
}

@test "claude/plugin/plugins.json exists with a plugins array of plugin@marketplace ids" {
    run jq -e '(.plugins | type == "array") and (.plugins | all(test("^[^@]+@[^@]+$")))' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

@test ".gitignore ignores claude/plugin/company/" {
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/company/dummy.json
    assert_success
}

@test "every plugins.json entry's marketplace key exists in marketplaces.json" {
    run jq -e --slurpfile mp "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json" \
        '[.plugins[] | split("@")[1]] - ($mp[0] | keys) == []' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

# #1410 스킬 마켓플레이스 분리 — 분리 레포 등록 검증.
# 상위 테스트(참조 무결성)는 dangling 참조만 잡고 "빠짐"은 못 잡으므로,
# 레포/플러그인 이름을 여기서 명시적으로 고정한다.
# 새 phase 가 나면 아래 테이블에 한 줄만 추가한다.
@test "split-out skill marketplaces and plugins are registered (#1410)" {
    while IFS='|' read -r mp_key repo plugin; do
        run jq -er --arg k "$mp_key" '"\($k)=\(.[$k])"' \
            "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
        assert_output "${mp_key}=${repo}"

        run jq -er --arg p "${plugin}@${mp_key}" \
            '.plugins | if index($p) then "\($p) registered" else "\($p) MISSING" end' \
            "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
        assert_output "${plugin}@${mp_key} registered"
    done <<'TABLE'
packaging-skills|dEitY719/packaging-skills|packaging
harness-skills|dEitY719/harness-skills|harness
devenv-skills|dEitY719/devenv-skills|devenv
notes-skills|dEitY719/notes-skills|notes
visuals-skills|dEitY719/visuals-skills|visuals
gh-resolve-skills|dEitY719/gh-resolve-skills|gh-resolve
session-skills|dEitY719/session-skills|session
gh-verify-skills|dEitY719/gh-verify-skills|gh-verify
spec-flow-skills|dEitY719/spec-flow-skills|spec-flow
authoring-skills|dEitY719/authoring-skills|authoring
gh-setup-skills|dEitY719/gh-setup-skills|gh-setup
gh-issue-skills|dEitY719/gh-issue-skills|gh-issue
gh-pr-skills|dEitY719/gh-pr-skills|gh-pr
gh-flow-skills|dEitY719/gh-flow-skills|gh-flow
TABLE
}

@test "pkm-skills marketplace and pkm plugin are registered (#1644)" {
    run jq -e '."pkm-skills" == "dEitY719/pkm-skills"' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
    assert_success

    run jq -e '.plugins | index("pkm@pkm-skills") != null' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

# #1410 NF-1: a phase split copies its skills out, it does not move them.
# The dotfiles originals must survive until Phase 4 retires them deliberately,
# so `/write:rca`, `/gh:pr-resolve-conflict` and `/devx:session-close` keep
# working for anyone who has not installed the plugin.
#
# One row per phase — the same convention the registration table above uses,
# because this check grows the same way (#1643 was the first; #1660 and #1661
# followed). The row, not a whole hand-copied @test block, is what a new phase
# adds. When Phase 4 deletes a phase's originals, its row goes in the same
# commit: the removal stays a decision someone makes, not a side effect nobody
# notices, and the failure message names which phase broke.
@test "split-out phases left their claude/skills originals in place (#1410 NF-1)" {
    while IFS='|' read -r issue skills; do
        for skill in ${skills}; do
            [ -f "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/${skill}/SKILL.md" ] \
                || fail "claude/skills/${skill}/SKILL.md is missing (${issue}) — #1410 NF-1 says a phase split copies, never moves"
        done
    done <<'TABLE'
#1643|write-rca write-insight write-release-note write-task-history write-blog-dev-learnings
#1660|gh-pr-resolve-ci-fail gh-pr-resolve-conflict gh-pr-resolve-outdated
#1661|devx-restart devx-session-close devx-session-handoff devx-rate-limit-guard devx-resume-after-limit devx-schedule ai-worktree-spawn ai-worktree-teardown
#1659|devx-pr-review-all devx-pr-verify-live devx-pr-verify-merged devx-exception-merge-checklist gh-pr-post-merge-verify
#1657|devx-prd-to-trd devx-trd-to-issues devx-pr-to-ssot-issue devx-reverse-engineering-analysis devx-claude-to-codex
#1662|skill-create skill-check skill-refactor sh-check devx-ux-guidelines devx-command-rename
#1658|gh-label-bootstrap gh-kanban-bootstrap gh-add-ai-metrics devx-docs-bootstrap
#1676|gh-issue-read gh-issue-create gh-issue-implement gh-issue-proceed gh-discussion-create gh-discussion-convert
#1677|gh-commit gh-pr gh-pr-review gh-pr-reply gh-pr-approve gh-pr-merge gh-pr-merge-emergency gh-pr-merge-train
#1678|gh-issue-flow devx-autopilot gh-issue-relay-flow gh-relay-merge
TABLE
}

# claude-plugin-visuals 는 #1646 에서 visuals-skills 로 rename 됐다. GitHub 이
# 구 URL 을 리다이렉트해 주기 때문에 stale 참조는 조용히 살아남는다 — 그래서
# 사람이 알아채기 전에 여기서 잡는다.
#
# 범위는 "런타임에 실제로 쓰이는 것"이다: 설정 JSON, 셸 코드, 테스트 픽스처.
# 산문은 일부러 뺐다 — docs/ 의 설계 이력과 claude-plugin-* 스킬들의 예시 문자열은
# rename 전 이름을 쓰는 게 맞고, 넓은 스캔은 그것들을 전부 오탐한다.
# 이 파일 자신도 패턴을 리터럴로 들고 있어 자기 매칭을 제외한다.
@test "no live config, shell code, or test fixture points at the pre-rename claude-plugin-visuals repo (#1646)" {
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" grep -l "dEitY719/claude-plugin-visuals" -- \
        'claude/plugin/*.json' 'shell-common/**' 'bash/**' 'zsh/**' 'tests/**' \
        ':!tests/bats/tools/claude_plugin_scaffold.bats'
    assert_failure
}
