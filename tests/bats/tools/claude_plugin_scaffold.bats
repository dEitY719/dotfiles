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

# #1410 NF-1: a Phase-1 split copies its skills out, it does not move them.
# The dotfiles originals must survive until Phase 4 retires them deliberately,
# so `/write:rca` keeps working for anyone who has not installed the plugin.
# When Phase 4 does delete them, this test is the thing that must be removed
# in the same commit — that is the point: the removal becomes a decision
# someone makes, not a side effect nobody notices.
@test "notes-skills split left the claude/skills/write-* originals in place (#1643)" {
    for skill in rca insight release-note task-history blog-dev-learnings; do
        [ -f "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/write-${skill}/SKILL.md" ] \
            || fail "claude/skills/write-${skill}/SKILL.md is missing — #1410 NF-1 says Phase 1 copies, never moves"
    done
}

# claude-plugin-visuals 는 #1646 에서 visuals-skills 로 rename 됐다. GitHub 이
# 구 URL 을 리다이렉트해 주기 때문에 stale 참조는 조용히 살아남는다 — 그래서
# 사람이 알아채기 전에 여기서 잡는다.
@test "no tracked file still points at the pre-rename claude-plugin-visuals repo (#1646)" {
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" grep -l "github.com/dEitY719/claude-plugin-visuals" -- \
        'claude/plugin/*.json' 'shell-common/**' 'bash/**' 'zsh/**'
    assert_failure
}
