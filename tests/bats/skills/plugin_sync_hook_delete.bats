#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook_delete.bats
# claude/hooks/plugin-sync.sh — uninstall / marketplace remove 경로.
# 병합(install/add) 경로 커버리지는 plugin_sync_hook.bats.
#
# #1685: 공용 스코프에서 훅이 지우는 대상은 gitignored 오버레이
# claude/plugin/{marketplaces,plugins}.local.json 이다. tracked
# claude/plugin/{marketplaces,plugins}.json 은 upstream 등록 계약이라 손대지 않고,
# 삭제 대상이 거기 남아 있으면 stderr 힌트만 남긴다. 커밋은 company/ 만 남긴다.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync.sh"

setup() {
    setup_isolated_home
    MAIN_ROOT="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$MAIN_ROOT/claude/plugin"
    git -C "$MAIN_ROOT" init -q
    git -C "$MAIN_ROOT" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT" config user.name "hook-test"

    cat > "$MAIN_ROOT/claude/plugin/marketplaces.local.json" <<'JSON'
{"claude-plugins-official": "anthropics/claude-plugins-official", "understand-anything": "Egonex-AI/Understand-Anything"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/plugins.local.json" <<'JSON'
{"plugins": ["ralph-loop@claude-plugins-official", "understand-anything@understand-anything"]}
JSON
}

# company/ 를 자기 자신의 git 레포로 만들고 사내 매니페스트를 seed 한다 —
# #1685 이후 삭제 커밋이 남는 유일한 스코프.
_seed_company() {
    mkdir -p "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" init -q
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"
    cat > "$MAIN_ROOT/claude/plugin/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON
    git -C "$MAIN_ROOT/claude/plugin/company" add .
    git -C "$MAIN_ROOT/claude/plugin/company" commit -q -m "seed"
}

teardown() {
    teardown_isolated_home
}

@test "uninstall <plugin>@<marketplace> removes exactly that entry" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.plugins == ["understand-anything@understand-anything"]' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
    # untouched marketplace entries stay
    run jq -e 'has("claude-plugins-official")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
}

@test "uninstall <bare-plugin-name> removes the matching plugin@marketplace entry" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
}

@test "marketplace remove deletes the marketplace and cascades to its plugins" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("claude-plugins-official")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_failure
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
    # unrelated marketplace/plugin survives
    run jq -e 'has("understand-anything")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
}

@test "uninstall with no target token → no-op" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official", "understand-anything@understand-anything"]' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

@test "uninstall commits the removal locally (company scope)" {
    _seed_company
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall secret@internal-tools"}}'
    before=$(git -C "$MAIN_ROOT/claude/plugin/company" rev-parse HEAD)
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    after=$(git -C "$MAIN_ROOT/claude/plugin/company" rev-parse HEAD)
    [ "$before" != "$after" ]
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (secret@internal-tools)"
}

@test "marketplace remove commits with the removed marketplace name (#1430)" {
    _seed_company
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (internal-tools)"
}

@test "uninstall never touches the tracked registration contract (#1685)" {
    # 계약에도 같은 항목이 있는 상태 — 훅은 오버레이만 지우고 계약은 그대로 둔다.
    cat > "$MAIN_ROOT/claude/plugin/marketplaces.json" <<'JSON'
{"claude-plugins-official": "anthropics/claude-plugins-official"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/plugins.json" <<'JSON'
{"plugins": ["ralph-loop@claude-plugins-official"]}
JSON
    git -C "$MAIN_ROOT" add claude/plugin/marketplaces.json claude/plugin/plugins.json
    git -C "$MAIN_ROOT" commit -q -m "contract"
    before=$(git -C "$MAIN_ROOT" rev-parse HEAD)

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # 오버레이에서는 빠지고
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
    # 계약은 그대로 — 새 커밋도 tracked 변경도 없다
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
    [ "$before" = "$(git -C "$MAIN_ROOT" rev-parse HEAD)" ]
    run git -C "$MAIN_ROOT" status --porcelain --untracked-files=no
    assert_output ""
}

@test "uninstall of a contract entry records a tombstone instead of editing it (#1695 agy BLOCKER)" {
    cat > "$MAIN_ROOT/claude/plugin/plugins.json" <<'JSON'
{"plugins": ["ralph-loop@claude-plugins-official"]}
JSON
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    assert_output --partial "upstream 등록 계약"
    assert_output --partial "묘비"

    # 계약은 그대로, 묘비에 기록 → restore.sh 가 더 이상 설치하지 않는다.
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/removed.local.json"
    assert_success
}

@test "marketplace remove of a contract marketplace tombstones the marketplace (#1695)" {
    cat > "$MAIN_ROOT/claude/plugin/marketplaces.json" <<'JSON'
{"claude-plugins-official": "anthropics/claude-plugins-official"}
JSON
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.marketplaces == ["claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/removed.local.json"
    assert_success
}

@test "uninstall of a plugin absent from the contract writes no tombstone (#1695)" {
    # 계약에 없으면 오버레이에서 빠지는 것으로 충분하다 — 묘비는 계약 항목 전용이다.
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -f "$MAIN_ROOT/claude/plugin/removed.local.json" ]
}

@test "uninstall of a plugin absent from the contract stays silent (#1685)" {
    # 흔한 경로에서 힌트가 뜨면 사람들이 이 줄을 무시하게 된다 — 계약에 없으면 조용해야 한다.
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    refute_output --partial "upstream 등록 계약"
}

@test "marketplace remove of a contract marketplace prints the hint naming marketplaces.json (#1685)" {
    cat > "$MAIN_ROOT/claude/plugin/marketplaces.json" <<'JSON'
{"claude-plugins-official": "anthropics/claude-plugins-official"}
JSON
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    assert_output --partial "claude/plugin/marketplaces.json"
}

@test "marketplace remove also removes the matching entry from claude/plugin/company/" {
    _seed_company

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    assert_failure
    run jq -e '.plugins == []' "$MAIN_ROOT/claude/plugin/company/plugins.json"
    assert_success
}
