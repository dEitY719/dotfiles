#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_restore.bats
# claude/plugin/restore.sh — dry-run 출력 및 모드별(internal/external) 분기 검증.
# 실제 claude CLI를 부르지 않도록 --dry-run만 테스트한다 (설치 부작용 없음).

load '../test_helper'

RESTORE="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/restore.sh"

setup() {
    setup_isolated_home
    PLUGDIR="$TEST_TEMP_HOME/plugdir"
    mkdir -p "$PLUGDIR"
    cp "$RESTORE" "$PLUGDIR/restore.sh"
    chmod +x "$PLUGDIR/restore.sh"

    cat > "$PLUGDIR/marketplaces.json" <<'JSON'
{"understand-anything": "Egonex-AI/Understand-Anything"}
JSON
    cat > "$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything"]}
JSON
}

teardown() {
    teardown_isolated_home
}

@test "restore.sh --dry-run lists public marketplace and plugin without installing" {
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
    assert_output --partial 'install: understand-anything@understand-anything'
}

@test "restore.sh skips company manifest on external mode" {
    echo "external" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'internal-tools'
    assert_output --partial '모드: external'
}

@test "restore.sh restores company manifest on internal mode when company/.git exists" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: internal-tools (git@ghes.example.com:team/internal-tools.git)'
    assert_output --partial 'install: secret@internal-tools'
}

@test "restore.sh prompts for manual clone on internal mode without company/.git" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial '사내 전용 레포 미설정'
}

@test "restore.sh treats an empty (not-yet-cloned) company/ on internal as inactive (#2251)" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial '사내 전용 레포 미설정'
}

@test "restore.sh --help prints usage and exits 0 without touching CLI" {
    run "$PLUGDIR/restore.sh" --help
    assert_success
    assert_output --partial 'Usage: restore.sh'
    assert_output --partial '--sync'
}

@test "restore.sh rejects an unknown flag" {
    run "$PLUGDIR/restore.sh" --bogus
    assert_failure 2
    assert_output --partial '알 수 없는 인자: --bogus'
}

@test "restore.sh --check is read-only and reports missing manifest entries" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 1
    assert_output --partial 'WARN: marketplace not installed: understand-anything'
    assert_output --partial 'WARN: plugin not installed: understand-anything@understand-anything'
}

@test "restore.sh --check reports no drift when the store matches the manifest" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo '{"understand-anything": {}}' >"$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json"
    echo '{"plugins": {"understand-anything@understand-anything": []}}' >"$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_success
    assert_output --partial 'drift 없음'
}

@test "restore.sh --check reports a tombstoned (removed.local.json) contract entry as INFO, not WARN drift" {
    # 이 PC 에서 의도적으로 설치하지 않는 계약 항목은 skills-sync 를 매번
    # "확인 필요" 로 끝내면 안 된다 — 묘비로 내리고, 숨기지 않고 INFO 로 보인다.
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo '{"marketplaces": ["understand-anything"]}' >"$PLUGDIR/removed.local.json"
    run "$PLUGDIR/restore.sh" --check
    assert_success
    refute_output --partial 'WARN:'
    assert_output --partial 'INFO: marketplace not installed on purpose (removed.local.json): understand-anything'
    assert_output --partial 'INFO: plugin not installed on purpose (removed.local.json): understand-anything@understand-anything'
    assert_output --partial 'drift 없음'
}

# --- 머신 로컬 오버레이 union (#1685) ---------------------------------------
# tracked {marketplaces,plugins}.json 은 upstream 등록 계약, *.local.json 은 이
# PC 가 설치한 것. 복원은 둘의 union 이어야 하고, --sync 는 오버레이 항목을
# 잉여로 오인해 지우면 안 된다.

@test "restore.sh --dry-run unions the machine-local overlay with the tracked contract (#1685)" {
    cat > "$PLUGDIR/marketplaces.local.json" <<'JSON'
{"caveman": "JuliusBrussee/caveman"}
JSON
    cat > "$PLUGDIR/plugins.local.json" <<'JSON'
{"plugins": ["caveman@caveman"]}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    # tracked 계약 항목
    assert_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
    assert_output --partial 'install: understand-anything@understand-anything'
    # 오버레이에만 있는 항목
    assert_output --partial 'add: caveman (JuliusBrussee/caveman)'
    assert_output --partial 'install: caveman@caveman'
}

@test "restore.sh --dry-run restores a contract entry this PC never installed (#1685)" {
    # 오버레이가 있어도 tracked 계약 항목이 밀려나면 안 된다 — union 이지 교체가 아니다.
    cat > "$PLUGDIR/marketplaces.local.json" <<'JSON'
{"caveman": "JuliusBrussee/caveman"}
JSON
    cat > "$PLUGDIR/plugins.local.json" <<'JSON'
{"plugins": ["caveman@caveman"]}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'install: understand-anything@understand-anything'
}

@test "restore.sh: the tracked contract wins a marketplace key collision (#1695 codex BLOCKER)" {
    # 낡은 오버레이가 같은 키를 들고 있어도 upstream 이 고친 계약 URL 이 이겨야
    # 한다. 오버레이가 이기면 upstream 의 마켓플레이스 URL 정정이 조용히 무시된다.
    cat > "$PLUGDIR/marketplaces.json" <<'JSON'
{"understand-anything": "Egonex-AI/Understand-Anything"}
JSON
    cat > "$PLUGDIR/marketplaces.local.json" <<'JSON'
{"understand-anything": "stale-owner/old-repo"}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
    refute_output --partial 'stale-owner/old-repo'
}

@test "restore.sh: an overlay-only marketplace still survives the collision rule (#1695)" {
    # 우선순위 수정이 union 자체를 깨지 않았는지 — 충돌하지 않는 오버레이 키는 그대로.
    cat > "$PLUGDIR/marketplaces.local.json" <<'JSON'
{"understand-anything": "stale-owner/old-repo", "caveman": "JuliusBrussee/caveman"}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
    assert_output --partial 'add: caveman (JuliusBrussee/caveman)'
}

@test "restore.sh: a tombstoned contract plugin is NOT reinstalled (#1695 agy BLOCKER)" {
    # 계약에 남아 있는 플러그인을 이 PC 에서 uninstall 했다는 묘비가 있으면
    # restore.sh 는 다시 설치하지 않는다 — 이것이 없으면 uninstall 이 무효가 된다.
    cat > "$PLUGDIR/removed.local.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything"]}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'install: understand-anything@understand-anything'
    # 마켓플레이스는 따로 묘비를 두지 않았으므로 그대로 남는다.
    assert_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
}

@test "restore.sh: a tombstoned contract marketplace is NOT re-added (#1695)" {
    cat > "$PLUGDIR/removed.local.json" <<'JSON'
{"marketplaces": ["understand-anything"]}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
}

@test "restore.sh: a marketplace tombstone also drops that marketplace's plugins (#1695 round2 BLOCKER)" {
    # `marketplace remove` 뒤에 그 마켓플레이스의 플러그인이 union 에 남으면
    # restore.sh 가 방금 건너뛴 마켓플레이스에 설치를 시도한다.
    cat > "$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything", "keep@other-mp"]}
JSON
    cat > "$PLUGDIR/marketplaces.json" <<'JSON'
{"understand-anything": "Egonex-AI/Understand-Anything", "other-mp": "o/other"}
JSON
    cat > "$PLUGDIR/removed.local.json" <<'JSON'
{"marketplaces": ["understand-anything"]}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'add: understand-anything'
    refute_output --partial 'install: understand-anything@understand-anything'
    # 무관한 마켓플레이스와 그 플러그인은 그대로.
    assert_output --partial 'add: other-mp (o/other)'
    assert_output --partial 'install: keep@other-mp'
}

@test "restore.sh: a public tombstone never suppresses a same-named company entry (#1695 round2 BLOCKER)" {
    # 묘비는 스코프마다 따로다 — 두 스코프는 이름공간을 공유하지 않는다.
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"shared-name": "git@ghes.example.com:team/internal.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@shared-name"]}
JSON
    # 공용 쪽에서 같은 이름을 지웠다고 기록한다.
    cat > "$PLUGDIR/removed.local.json" <<'JSON'
{"marketplaces": ["shared-name"], "plugins": ["secret@shared-name"]}
JSON

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    # 사내 스코프는 자기 묘비만 본다 → 그대로 복원돼야 한다.
    assert_output --partial 'add: shared-name (git@ghes.example.com:team/internal.git)'
    assert_output --partial 'install: secret@shared-name'
}

@test "restore.sh: the company scope honours its OWN tombstone file (#1695 round2)" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON
    cat > "$PLUGDIR/company/removed.local.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'install: secret@internal-tools'
    assert_output --partial 'add: internal-tools (git@ghes.example.com:team/internal-tools.git)'
}

@test "restore.sh --sync prunes a tombstoned contract plugin instead of keeping it (#1695)" {
    _seed_local_state
    # SSOT 에 설치돼 있고 계약에도 있지만, 이 PC 에서 지웠다고 묘비가 말한다 →
    # keep-set 에서 빠져 prune 대상이 되어야 한다.
    cat > "$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything"]}
JSON
    cat > "$PLUGDIR/removed.local.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything"]}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    assert_output --partial 'uninstall: understand-anything@understand-anything'
}

@test "restore.sh --dry-run skips 공용 when neither tracked nor overlay manifest exists (#1685)" {
    rm -f "$PLUGDIR/marketplaces.json" "$PLUGDIR/plugins.json"
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial '(공용 manifest 없음 — 건너뜀)'
}

@test "restore.sh --dry-run runs off the overlay alone when the tracked contract is absent (#1685)" {
    rm -f "$PLUGDIR/marketplaces.json" "$PLUGDIR/plugins.json"
    cat > "$PLUGDIR/marketplaces.local.json" <<'JSON'
{"caveman": "JuliusBrussee/caveman"}
JSON
    cat > "$PLUGDIR/plugins.local.json" <<'JSON'
{"plugins": ["caveman@caveman"]}
JSON
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: caveman (JuliusBrussee/caveman)'
    assert_output --partial 'install: caveman@caveman'
    refute_output --partial '(공용 manifest 없음'
}

# --- --sync prune pass -----------------------------------------------------

# Seed a local ground-truth fixture (mirrors ~/.claude-shared/plugins) and
# point restore.sh at it via CLAUDE_SHARED_PLUGINS_DIR.
_seed_local_state() {
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{
  "understand-anything": {"source": {"source": "github", "repo": "Egonex-AI/Understand-Anything"}},
  "surplus-mp":          {"source": {"source": "github", "repo": "foo/surplus"}},
  "gitkraken":           {"source": {"source": "directory", "path": "/opt/gitkraken"}}
}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "understand-anything@understand-anything": [{"scope": "user"}],
    "surplus@surplus-mp":                       [{"scope": "user"}],
    "gk@gitkraken":                             [{"scope": "user"}],
    "projectplug@surplus-mp":                   [{"scope": "project"}]
  }
}
JSON
}

@test "restore.sh --sync --dry-run prunes surplus marketplace + plugin, keeps SSOT items" {
    _seed_local_state
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    assert_output --partial 'remove: surplus-mp'
    assert_output --partial 'uninstall: surplus@surplus-mp'
    # SSOT-present items must NOT be pruned.
    refute_output --partial 'remove: understand-anything'
    refute_output --partial 'uninstall: understand-anything@understand-anything'
}

@test "restore.sh --sync keeps entries that live only in the local overlay (#1685)" {
    _seed_local_state
    # 'surplus-mp' 는 tracked 계약엔 없지만 이 PC 의 오버레이에는 있다 →
    # keep-set 에 들어가야 하므로 prune 되면 안 된다.
    cat > "$PLUGDIR/marketplaces.local.json" <<'JSON'
{"surplus-mp": "foo/surplus"}
JSON
    cat > "$PLUGDIR/plugins.local.json" <<'JSON'
{"plugins": ["surplus@surplus-mp"]}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'remove: surplus-mp'
    refute_output --partial 'uninstall: surplus@surplus-mp'
}

@test "restore.sh --sync leaves source:directory marketplaces alone" {
    _seed_local_state
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'remove: gitkraken'
    refute_output --partial 'uninstall: gk@gitkraken'
}

@test "restore.sh --sync ignores scope:project plugins" {
    _seed_local_state
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'projectplug@surplus-mp'
}

@test "restore.sh --sync respects the .local-marketplaces.json whitelist" {
    _seed_local_state
    cat > "$PLUGDIR/.local-marketplaces.json" <<'JSON'
{"marketplaces": ["surplus-mp"], "plugins": ["surplus@surplus-mp"]}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'remove: surplus-mp'
    refute_output --partial 'uninstall: surplus@surplus-mp'
}

@test "restore.sh --sync reports nothing to prune when local matches SSOT" {
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{"understand-anything": {"source": {"source": "github", "repo": "Egonex-AI/Understand-Anything"}}}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {"understand-anything@understand-anything": [{"scope": "user"}]}}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    assert_output --partial '제거할 잉여 항목 없음'
}

@test "restore.sh --sync survives a plugin whose marketplace is not in known_marketplaces.json" {
    # Regression: a plugin key whose @marketplace has no entry makes
    # $m[key] null; indexing null with .source used to abort jq mid-stream.
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{"understand-anything": {"source": {"source": "github", "repo": "Egonex-AI/Understand-Anything"}}}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {"orphan@ghostmp": [{"scope": "user"}]}}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    # ghostmp is unknown locally and not in SSOT → the plugin is still surplus,
    # and jq must not have crashed enumerating it.
    assert_output --partial 'uninstall: orphan@ghostmp'
}

# --- #1103: target config dir routing -------------------------------------

@test "restore.sh (public mode) targets ~/.claude-<default account>" {
    echo "public" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    export CLAUDE_DEFAULT_ACCOUNT="personal"
    export CLAUDE_ENABLED_ACCOUNTS="personal work"
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude-personal"
    refute_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude ="
}

@test "restore.sh --user <account> targets that account's config dir" {
    echo "public" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    export CLAUDE_DEFAULT_ACCOUNT="personal"
    export CLAUDE_ENABLED_ACCOUNTS="personal work"
    run "$PLUGDIR/restore.sh" --user work --dry-run
    assert_success
    assert_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude-work"
}

@test "restore.sh internal mode targets single-account ~/.claude" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude ="
    refute_output --partial ".claude-"
}

@test "restore.sh --all-accounts fans out over every enabled account" {
    echo "public" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    export CLAUDE_ENABLED_ACCOUNTS="personal work work1"
    run "$PLUGDIR/restore.sh" --all-accounts --dry-run
    assert_success
    assert_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude-personal"
    assert_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude-work"
    assert_output --partial "대상 config dir: $TEST_TEMP_HOME/.claude-work1"
}

@test "restore.sh --user without a value fails with exit 2" {
    run "$PLUGDIR/restore.sh" --user
    assert_failure 2
    assert_output --partial '--user 다음에 계정 이름이 필요합니다'
}

@test "restore.sh --sync keeps company plugins on internal mode with company/.git" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{"internal-tools": {"source": {"source": "git", "url": "git@ghes.example.com:team/internal-tools.git"}}}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {"secret@internal-tools": [{"scope": "user"}]}}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    # internal-tools is company SSOT → part of the keep-set → not pruned.
    refute_output --partial 'remove: internal-tools'
    refute_output --partial 'uninstall: secret@internal-tools'
}

# --- real-SSOT integration (#1643, codex FOLLOW-UP on PR #1654) ------------
#
# Every test above feeds restore.sh a synthetic manifest pair, which proves
# the parser but never the shipped `claude/plugin/{marketplaces,plugins}.json`.
# A marketplace registered in the SSOT with a slug restore.sh cannot resolve
# would pass all of them. Run the real script copy against tracked manifests
# in the isolated fixture, excluding machine-local overlays and company data.
# A registration is only "done" once restore.sh emits add + install lines.

# 새 phase 가 나면 아래 테이블에 한 줄만 추가한다 — 테스트를 더 늘리지 않는다.
@test "restore.sh --dry-run installs each split-out plugin from the real SSOT (#1410)" {
    cp "$_BATS_REAL_DOTFILES_ROOT/claude/plugin/marketplaces.json" "$PLUGDIR/marketplaces.json"
    cp "$_BATS_REAL_DOTFILES_ROOT/claude/plugin/plugins.json" "$PLUGDIR/plugins.json"
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    while IFS='|' read -r mp_key repo plugin; do
        assert_output --partial "add: ${mp_key} (${repo})"
        assert_output --partial "install: ${plugin}@${mp_key}"
    done <<'TABLE'
notes-skills|dEitY719/notes-skills|notes
authoring-skills|dEitY719/authoring-skills|authoring
gh-setup-skills|dEitY719/gh-setup-skills|gh-setup
gh-issue-skills|dEitY719/gh-issue-skills|gh-issue
gh-pr-skills|dEitY719/gh-pr-skills|gh-pr
gh-flow-skills|dEitY719/gh-flow-skills|gh-flow
TABLE
}

# --- #2344: store-aware idempotent restore (real runs against a fake claude) ---
#
# A fake `claude` on PATH logs every call to $CLAUDE_CALLS and fails the call
# whose argv contains $CLAUDE_FAIL_ON. The store is the default account's
# plugins/ dir, exactly what skills-sync points restore.sh at.

_fake_claude() {
    FAKEBIN="$TEST_TEMP_HOME/fakebin"
    mkdir -p "$FAKEBIN"
    export CLAUDE_CALLS="$TEST_TEMP_HOME/claude-calls.log"
    : >"$CLAUDE_CALLS"
    cat >"$FAKEBIN/claude" <<'SH'
#!/bin/bash
echo "$*" >>"$CLAUDE_CALLS"
case " $* " in *" ${CLAUDE_FAIL_ON:-@none@} "*) [ -z "${CLAUDE_FAIL_MSG:-}" ] || echo "$CLAUDE_FAIL_MSG" >&2; exit 1 ;; esac
exit 0
SH
    chmod +x "$FAKEBIN/claude"
    export PATH="$FAKEBIN:$PATH"
    export TMPDIR="$TEST_TEMP_HOME"
    unset CLAUDE_SHARED_PLUGINS_DIR CLAUDE_DEFAULT_ACCOUNT
    STORE="$TEST_TEMP_HOME/.claude-personal/plugins"
    mkdir -p "$STORE"
}

# _store <marketplace keys...> -- <plugin ids...>
_store() {
    local mps="{}" pls="{}" in_pl=0 k
    for k in "$@"; do
        if [ "$k" = -- ]; then in_pl=1; continue; fi
        if [ "$in_pl" = 1 ]; then
            pls=$(jq -c --arg k "$k" '.[$k] = [{"scope":"user"}]' <<<"$pls")
        else
            mps=$(jq -c --arg k "$k" '.[$k] = {"source":{"source":"github"}}' <<<"$mps")
        fi
    done
    printf '%s\n' "$mps" >"$STORE/known_marketplaces.json"
    jq -c '{plugins: .}' <<<"$pls" >"$STORE/installed_plugins.json"
}

@test "restore.sh: nothing missing -> zero claude calls, store files unchanged (#2344)" {
    _fake_claude
    _store understand-anything -- understand-anything@understand-anything
    local before
    before=$(cat "$STORE"/*.json | sha256sum)
    run "$PLUGDIR/restore.sh"
    assert_success
    [ ! -s "$CLAUDE_CALLS" ]
    assert_equal "$(cat "$STORE"/*.json | sha256sum)" "$before"
    assert_output --partial 'Marketplaces added: 0'
    assert_output --partial 'Plugins installed: 0'
    assert_output --partial 'Already present: 2'
    assert_output --partial 'Failed: 0'
}

@test "restore.sh: an empty store dir (no files) adds and installs everything (#2344 F-2)" {
    _fake_claude
    run "$PLUGDIR/restore.sh"
    assert_success
    run cat "$CLAUDE_CALLS"
    assert_output "plugin marketplace add Egonex-AI/Understand-Anything
plugin install understand-anything@understand-anything"
}

@test "restore.sh: marketplace present, plugin missing -> install only (#2344)" {
    _fake_claude
    _store understand-anything --
    run "$PLUGDIR/restore.sh"
    assert_success
    run cat "$CLAUDE_CALLS"
    assert_output "plugin install understand-anything@understand-anything"
}

@test "restore.sh: a newly added manifest plugin is the only one installed (#2344)" {
    _fake_claude
    _store understand-anything -- understand-anything@understand-anything
    cat >"$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything", "extra@understand-anything"]}
JSON
    run "$PLUGDIR/restore.sh"
    assert_success
    assert_output --partial 'Plugins installed: 1'
    run cat "$CLAUDE_CALLS"
    assert_output "plugin install extra@understand-anything"
}

@test "restore.sh: a tombstoned plugin is not installed on a real run (#2344 F-6)" {
    _fake_claude
    _store understand-anything --
    printf '{"plugins":["understand-anything@understand-anything"]}\n' >"$PLUGDIR/removed.local.json"
    run "$PLUGDIR/restore.sh"
    assert_success
    [ ! -s "$CLAUDE_CALLS" ]
}

@test "restore.sh: one failed install is counted, the rest continue, exit 1 (#2344 F-4)" {
    _fake_claude
    _store understand-anything --
    cat >"$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["bad@understand-anything", "good@understand-anything"]}
JSON
    CLAUDE_FAIL_ON=bad@understand-anything run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '실패: install bad@understand-anything'
    assert_output --partial 'Plugins installed: 1'
    assert_output --partial 'Failed: 1'
    run cat "$CLAUDE_CALLS"
    assert_line "plugin install good@understand-anything"
}

@test "restore.sh: a failed marketplace add fails its plugins without calling install (#2344)" {
    _fake_claude
    CLAUDE_FAIL_ON=Egonex-AI/Understand-Anything run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial 'Failed: 2'
    run cat "$CLAUDE_CALLS"
    assert_output "plugin marketplace add Egonex-AI/Understand-Anything"
}

# --- #2453: permanent vs transient failure classification --------------------

# _company_https <url> — internal mode with a company/ manifest holding one marketplace.
_company_https() {
    echo "internal" >"$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    printf '{"sp-dev": "%s"}\n' "$1" >"$PLUGDIR/company/marketplaces.json"
    printf '{"plugins": ["superpowers@sp-dev"]}\n' >"$PLUGDIR/company/plugins.json"
    STORE="$TEST_TEMP_HOME/.claude/plugins"
    mkdir -p "$STORE"
    _store understand-anything -- understand-anything@understand-anything
}

@test "#2453: a schema error is permanent — fix command, no re-run advice, report line" {
    _fake_claude
    _company_https "https://ghes.example.invalid/corp/sp-dev"
    export RESTORE_FAILURE_REPORT="$TEST_TEMP_HOME/report.tsv"
    CLAUDE_FAIL_ON=https://ghes.example.invalid/corp/sp-dev \
        CLAUDE_FAIL_MSG='Failed to add marketplace: Invalid marketplace schema from URL: : Invalid input' \
        run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '영구 실패: marketplace add sp-dev'
    assert_output --partial '조치: skills-register https://ghes.example.invalid/corp/sp-dev.git'
    assert_output --partial '영구 실패: install superpowers@sp-dev'
    assert_output --partial 'Failed: 2'
    refute_output --partial '다시 실행하면 남은 항목만 재시도'
    run cut -f1,2 "$RESTORE_FAILURE_REPORT"
    assert_output "$(printf 'permanent\tsp-dev\npermanent\tsuperpowers@sp-dev')"
}

@test "#2453: a permanent failure on a .git URL points at --remove" {
    _fake_claude
    _company_https "git@ghes.example.invalid:corp/sp-dev.git"
    CLAUDE_FAIL_ON=git@ghes.example.invalid:corp/sp-dev.git CLAUDE_FAIL_MSG='Marketplace not found' \
        run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '조치: skills-register --remove sp-dev'
}

@test "#2453: an install-only name collision is permanent and points at --remove, not re-register" {
    _fake_claude
    _company_https "https://ghes.example.invalid/corp/sp-dev.git"
    printf '{"understand-anything": {}, "sp-dev": {}}\n' >"$STORE/known_marketplaces.json"
    CLAUDE_FAIL_ON=superpowers@sp-dev CLAUDE_FAIL_MSG='Plugin name collision: superpowers (by an author tool)' \
        run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '영구 실패: install superpowers@sp-dev'
    assert_output --partial '조치: skills-register --remove sp-dev'
    refute_output --partial '다시 실행하면 남은 항목만 재시도'
}

@test "#2455: a plugin missing from its company/ repo points at a manual plugins.json edit, not re-register" {
    _fake_claude
    _company_https "https://ghes.example.invalid/corp/sp-dev.git"
    printf '{"understand-anything": {}, "sp-dev": {}}\n' >"$STORE/known_marketplaces.json"
    CLAUDE_FAIL_ON=superpowers@sp-dev CLAUDE_FAIL_MSG='Plugin superpowers not found in marketplace sp-dev' \
        run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '조치: claude/plugin/company/plugins.json 에서 superpowers@sp-dev 삭제'
    refute_output --partial '조치: skills-register'
}

@test "#2455: any other permanent install error points at the repo's marketplace.json, never a deletion" {
    _fake_claude
    _company_https "https://ghes.example.invalid/corp/sp-dev.git"
    printf '{"understand-anything": {}, "sp-dev": {}}\n' >"$STORE/known_marketplaces.json"
    CLAUDE_FAIL_ON=superpowers@sp-dev CLAUDE_FAIL_MSG='Invalid marketplace schema: plugins.0.source' \
        run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '조치: https://ghes.example.invalid/corp/sp-dev.git 의 .claude-plugin/marketplace.json 확인'
    refute_output --partial '삭제'
}

@test "#2453: a timeout is transient — keeps the re-run advice, no fix command" {
    _fake_claude
    _company_https "https://ghes.example.invalid/corp/sp-dev.git"
    export RESTORE_FAILURE_REPORT="$TEST_TEMP_HOME/report.tsv"
    CLAUDE_FAIL_ON=https://ghes.example.invalid/corp/sp-dev.git CLAUDE_FAIL_MSG='git clone: Connection timed out' \
        run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '다시 실행하면 남은 항목만 재시도'
    refute_output --partial '영구 실패'
    refute_output --partial '조치:'
    run cut -f1 "$RESTORE_FAILURE_REPORT"
    assert_output "$(printf 'transient\ntransient')"
}

@test "restore.sh: a corrupt installed_plugins.json fails with zero claude calls (#2344 F-2)" {
    _fake_claude
    printf '{not json' >"$STORE/installed_plugins.json"
    run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial '플러그인 저장소 파일을 읽을 수 없음'
    [ ! -s "$CLAUDE_CALLS" ]
    run "$PLUGDIR/restore.sh" --dry-run
    assert_failure 1
}

@test "restore.sh: a zero-byte or non-object store file is corrupt, not empty (#2344 F-2)" {
    _fake_claude
    : >"$STORE/known_marketplaces.json"
    run "$PLUGDIR/restore.sh"
    assert_failure 1
    [ ! -s "$CLAUDE_CALLS" ]
    printf '[]\n' >"$STORE/known_marketplaces.json"
    run "$PLUGDIR/restore.sh"
    assert_failure 1
    [ ! -s "$CLAUDE_CALLS" ]
}

@test "restore.sh: a missing plugins/ path never calls claude; skip in skills-sync, fail direct (#2344 F-11)" {
    _fake_claude
    rm -rf "$STORE"
    run "$PLUGDIR/restore.sh" --skip-without-claude
    assert_success
    assert_output --partial '플러그인 저장소 없음'
    run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial './claude/setup.sh 를 실행하세요'
    [ ! -s "$CLAUDE_CALLS" ]
    [ ! -e "$STORE" ]
}

@test "restore.sh --dry-run prints only the items a real run would execute (#2344 F-3)" {
    _fake_claude
    _store understand-anything --
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'add: understand-anything'
    assert_output --partial 'install: understand-anything@understand-anything'
    assert_output --partial 'Plugins (would install): 1'
    [ ! -s "$CLAUDE_CALLS" ]
}

@test "restore.sh without claude: error by default, skip with --skip-without-claude (#2344 F-10)" {
    mkdir -p "$TEST_TEMP_HOME/nobin"
    PATH="$TEST_TEMP_HOME/nobin:/usr/bin:/bin" run "$PLUGDIR/restore.sh"
    assert_failure 1
    assert_output --partial 'claude CLI가 없습니다'
    PATH="$TEST_TEMP_HOME/nobin:/usr/bin:/bin" run "$PLUGDIR/restore.sh" --skip-without-claude
    assert_success
    assert_output --partial '플러그인 복원 건너뜀'
}

@test "restore --check includes active company manifests and honors tombstones" {
    echo internal > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company/.git" "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo '{"private": "team/private"}' > "$PLUGDIR/company/marketplaces.json"
    echo '{"plugins": ["secret@private"]}' > "$PLUGDIR/company/plugins.json"
    echo '{"understand-anything": {}}' > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json"
    echo '{"plugins": {"understand-anything@understand-anything": []}}' > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 1
    assert_output --partial 'WARN: marketplace not installed: private'
    assert_output --partial 'WARN: plugin not installed: secret@private'
    echo '{"marketplaces": ["private"]}' > "$PLUGDIR/company/removed.local.json"
    run "$PLUGDIR/restore.sh" --check
    assert_success
    refute_output --partial 'WARN:'
}

@test "restore --check distinguishes corrupt store from missing entries" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo invalid > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 3
    assert_output --partial '플러그인 저장소 파일을 읽을 수 없음'
}

@test "restore check reports tombstones in their own scope when names overlap" {
    echo internal > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company/.git" "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    cp "$PLUGDIR/marketplaces.json" "$PLUGDIR/company/marketplaces.json"
    cp "$PLUGDIR/plugins.json" "$PLUGDIR/company/plugins.json"
    echo '{"marketplaces": ["understand-anything"]}' > "$PLUGDIR/company/removed.local.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 1
    assert_output --partial 'WARN: marketplace not installed: understand-anything'
    assert_output --partial 'INFO: marketplace not installed on purpose (removed.local.json): understand-anything'
}

@test "restore check rejects a corrupt active company manifest" {
    echo internal > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company/.git" "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo invalid > "$PLUGDIR/company/plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 3
    assert_output --partial '매니페스트 파일을 읽을 수 없음'
    refute_output --partial 'drift 없음'
}

@test "restore check rejects invalid manifest field types" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo '{"plugins": "broken"}' > "$PLUGDIR/plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 3
    assert_output --partial '매니페스트 파일을 읽을 수 없음'
}

@test "restore check rejects multiple JSON documents" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    printf '%s\n' '{"plugins":"bad"}' '{"plugins":[]}' > "$PLUGDIR/plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 3
}

@test "restore check rejects null and false plugin lists" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    for value in false null; do
        printf '{"plugins": %s}\n' "$value" > "$PLUGDIR/plugins.json"
        run "$PLUGDIR/restore.sh" --check
        assert_failure 3
    done
}

@test "restore check rejects a plugin manifest without its plugins field" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo '{}' > "$PLUGDIR/plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_failure 3
}

@test "restore check accepts an empty optional plugin overlay" {
    mkdir -p "$TEST_TEMP_HOME/shared"
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    echo '{}' > "$PLUGDIR/plugins.local.json"
    echo '{"understand-anything": {}}' > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json"
    echo '{"plugins": {"understand-anything@understand-anything": []}}' > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json"
    run "$PLUGDIR/restore.sh" --check
    assert_success
}
