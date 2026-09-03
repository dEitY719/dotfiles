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

@test ".gitignore ignores the machine-local manifest overlay (#1685)" {
    # 오버레이가 추적되면 #1685 이 고친 fork 충돌이 그대로 돌아온다.
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/plugins.local.json
    assert_success
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/marketplaces.local.json
    assert_success
    # 묘비도 머신 로컬 상태다 (#1695) — 추적되면 fork 충돌이 되돌아온다.
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/removed.local.json
    assert_success
}

@test "the tracked registration contract is NOT ignored (#1685)" {
    # 반대 방향의 회귀 방지 — 계약 파일까지 무시해 버리면 등록 자체가 사라진다.
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/plugins.json
    assert_failure
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/marketplaces.json
    assert_failure
}

@test "every plugins.json entry's marketplace key exists in marketplaces.json" {
    run jq -e --slurpfile mp "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json" \
        '[.plugins[] | split("@")[1]] - ($mp[0] | keys) == []' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

# #1410 스킬 마켓플레이스 분리 — 분리 레포 등록 검증.
# 여기까지가 "등록값끼리 맞는가"의 전부다. "등록값이 원격에서 실제로 설치
# 가능한 계약인가"는 네트워크가 필요해 이 스위트에 둘 수 없다 (#1671 NF-1) —
# scripts/maintenance/check_split_skill_repos.py + split-skill-repo-audit
# 워크플로가 그쪽을 본다.
# 상위 테스트(참조 무결성)는 dangling 참조만 잡고 "빠짐"은 못 잡으므로,
# 레포/플러그인 이름을 여기서 명시적으로 고정한다.
# 새 phase 나 새 마켓플레이스(#1751 claudecode 등)가 나면 아래 테이블에
# 한 줄만 추가한다.
@test "standalone skill marketplaces and plugins are registered (#1410)" {
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
claudecode-skills|dEitY719/claudecode-skills|claudecode
TABLE
}

# A composition plugin is only runnable if the plugins owning the steps it
# delegates to are registered too. PR #1693 shipped `gh-flow` while `gh-pr`
# was still unregistered on that branch, so a plugin-only restore could load
# `/gh-flow:issue` and then fail at Step 2.2 with no `gh-pr:commit` to call
# (codex BLOCKER). A marketplace-mapping row cannot catch that — it only ever
# asserts one plugin at a time — so the dependency edges get their own table.
@test "composition plugins have every plugin they delegate to registered (#1693)" {
    while IFS='|' read -r plugin deps; do
        run jq -er --arg p "${plugin}" \
            '.plugins | map(split("@")[0]) | if index($p) then "present" else "absent" end' \
            "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
        assert_output "present"

        for dep in ${deps}; do
            run jq -er --arg d "${dep}" \
                '.plugins | map(split("@")[0]) | if index($d) then "present" else "absent" end' \
                "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
            [ "$output" = "present" ] \
                || fail "plugin '${plugin}' delegates to '${dep}', which is not in claude/plugin/plugins.json — a plugin-only restore cannot run it"
        done
    done <<'TABLE'
gh-flow|gh-issue gh-pr gh-verify gh-resolve session
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

# #1410 NF-1 said a phase split copies its skills out rather than moving
# them, so the dotfiles originals survived every phase. #1680 (Phase 4)
# retired them deliberately, in one commit, now that all 15 repos are
# published and registered above. The guard flips: the tree must be gone,
# and nothing may quietly recreate it.
@test "the dotfiles claude/skills tree is gone (#1680 Phase 4)" {
    [ ! -e "${_BATS_REAL_DOTFILES_ROOT}/claude/skills" ] \
        || fail "claude/skills/ is back — #1680 removed it; skills belong in their marketplace repo"

    run git -C "${_BATS_REAL_DOTFILES_ROOT}" ls-files -- 'claude/skills'
    assert_success
    [ -z "$output" ] || fail "claude/skills/ files are tracked again: $output"
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
