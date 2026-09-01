#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_reconcile.bats
# claude/plugin/reconcile.sh — SSOT → manifest full-recompute drift 감지/복구.
# 실제 claude CLI 를 부르지 않으며, SSOT 는 CLAUDE_SHARED_PLUGINS_DIR 픽스처로 주입한다.
#
# #1685 이후 공용 스코프의 쓰기 대상은 gitignored 오버레이
# claude/plugin/{marketplaces,plugins}.local.json 이고, tracked
# claude/plugin/{marketplaces,plugins}.json 은 upstream 등록 계약이라 읽기 전용이다.
# 커밋을 남기는 스코프는 별도 private 레포인 company/ 뿐이다.

load '../test_helper'

RECONCILE="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/reconcile.sh"

setup() {
    setup_isolated_home
    # A throwaway git repo hosting the public manifest, so --apply can commit.
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO/claude/plugin"
    cp "$RECONCILE" "$REPO/claude/plugin/reconcile.sh"
    chmod +x "$REPO/claude/plugin/reconcile.sh"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name tester
    SCRIPT="$REPO/claude/plugin/reconcile.sh"

    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{
  "official":   {"source": {"source": "github", "repo": "anthropics/official"}},
  "understand": {"source": {"source": "github", "repo": "Egonex-AI/Understand"}},
  "localdir":   {"source": {"source": "directory", "path": "/opt/x"}}
}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {
  "superpowers@official":         [{"scope": "user"}],
  "understand-anything@understand": [{"scope": "user"}],
  "localthing@localdir":          [{"scope": "user"}]
}}
JSON
}

teardown() {
    teardown_isolated_home
}

# tracked 등록 계약 (#1685): 'official' 은 이 PC 에도 설치돼 있고,
# 'contract-only-mp' 는 upstream 이 등록만 해 둔 — 이 PC 에는 없는 — 항목이다.
# 후자가 유령으로 보고되지 않는 것이 이 이슈가 고치는 fork 충돌의 핵심이다.
_seed_tracked_contract() {
    cat > "$REPO/claude/plugin/marketplaces.json" <<'JSON'
{
  "official": "anthropics/official",
  "contract-only-mp": "upstream/registered-but-not-installed-here"
}
JSON
    cat > "$REPO/claude/plugin/plugins.json" <<'JSON'
{
  "plugins": [
    "superpowers@official",
    "only@contract-only-mp"
  ]
}
JSON
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm seed
}

# In-sync: 계약 + 오버레이의 union 이 SSOT 와 정확히 일치하는 상태.
_seed_in_sync_manifest() {
    _seed_tracked_contract
    cat > "$REPO/claude/plugin/marketplaces.local.json" <<'JSON'
{"understand": "Egonex-AI/Understand"}
JSON
    cat > "$REPO/claude/plugin/plugins.local.json" <<'JSON'
{"plugins": ["understand-anything@understand"]}
JSON
}

# Drifted overlay: 유령 마켓플레이스 + 유령 플러그인, 그리고 'understand' 누락.
_seed_drifted_manifest() {
    _seed_tracked_contract
    cat > "$REPO/claude/plugin/marketplaces.local.json" <<'JSON'
{"ghost-mp": "someone/ghost"}
JSON
    cat > "$REPO/claude/plugin/plugins.local.json" <<'JSON'
{"plugins": ["ghost@ghost-mp"]}
JSON
}

# internal PC + cloned company/ 레포 — 커밋을 남기는 유일한 스코프.
# 공용 SSOT 는 그대로 두고 non-github 마켓플레이스만 덧붙인다.
_activate_company() {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$REPO/claude/plugin/company"
    git -C "$REPO/claude/plugin/company" init -q
    git -C "$REPO/claude/plugin/company" config user.email t@example.com
    git -C "$REPO/claude/plugin/company" config user.name tester
}

@test "reconcile.sh --help prints usage and exits 0" {
    run "$SCRIPT" --help
    assert_success
    assert_output --partial 'Usage: reconcile.sh'
    assert_output --partial '--apply'
}

@test "reconcile.sh rejects an unknown flag" {
    run "$SCRIPT" --bogus
    assert_failure 2
    assert_output --partial '알 수 없는 인자: --bogus'
}

@test "reconcile.sh --check on an in-sync manifest reports no drift, exit 0" {
    _seed_in_sync_manifest
    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'no drift'
}

@test "reconcile.sh defaults to --check when no flag is given" {
    _seed_in_sync_manifest
    run "$SCRIPT"
    assert_success
    assert_output --partial 'no drift'
}

@test "reconcile.sh --check on drift prints a table and exits non-zero" {
    _seed_drifted_manifest
    run "$SCRIPT" --check
    assert_failure
    assert_output --partial '+ understand'
    assert_output --partial '- ghost-mp'
    assert_output --partial '+ understand-anything@understand'
    assert_output --partial '- ghost@ghost-mp'
}

@test "reconcile.sh --apply rebuilds the overlay to match SSOT (adds + prunes ghosts)" {
    _seed_drifted_manifest
    run "$SCRIPT" --apply
    assert_success

    # Ghosts pruned; SSOT entries present; directory-source excluded; and the
    # entries the tracked contract already carries stay OUT of the overlay (#1685).
    run jq -r 'keys | join(",")' "$REPO/claude/plugin/marketplaces.local.json"
    assert_output 'understand'
    run jq -r '.plugins | join(",")' "$REPO/claude/plugin/plugins.local.json"
    assert_output 'understand-anything@understand'
}

@test "reconcile.sh --apply never rewrites the tracked registration contract (#1685)" {
    _seed_drifted_manifest
    before_mp=$(cat "$REPO/claude/plugin/marketplaces.json")
    before_pl=$(cat "$REPO/claude/plugin/plugins.json")

    run "$SCRIPT" --apply
    assert_success

    [ "$(cat "$REPO/claude/plugin/marketplaces.json")" = "$before_mp" ]
    [ "$(cat "$REPO/claude/plugin/plugins.json")" = "$before_pl" ]
    # 워킹트리도 깨끗해야 한다 — fork 가 upstream 등록 커밋을 받을 때 충돌할 것이 없다.
    run git -C "$REPO" status --porcelain -- claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_output ''
}

@test "reconcile.sh --check does not report a contract entry absent from the SSOT as a ghost (#1685)" {
    _seed_in_sync_manifest
    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'no drift'
    refute_output --partial 'contract-only-mp'
    refute_output --partial 'only@contract-only-mp'
}

@test "reconcile.sh --apply makes no public-scope commit, then --check is clean (#1685)" {
    # 오버레이는 untracked 이므로 커밋할 것이 없다 — #1685 이전의
    # "chore(claude-plugin): sync manifest" 자동 커밋이 사라진 자리다.
    _seed_drifted_manifest
    before=$(git -C "$REPO" rev-list --count HEAD)
    run "$SCRIPT" --apply
    assert_success
    after=$(git -C "$REPO" rev-list --count HEAD)
    [ "$after" -eq "$before" ]

    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'no drift'
}

@test "reconcile.sh --apply truncates a commit title with more than 4 changed entries (#1430)" {
    # 커밋을 남기는 스코프는 company/ 뿐이므로(#1685) 제목 포맷도 거기서 검증한다.
    _activate_company
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{
  "mp-keep":   {"source": {"source": "git", "url": "git@ghes.example.com:org/keep.git"}},
  "mp-add-1":  {"source": {"source": "git", "url": "git@ghes.example.com:org/add1.git"}},
  "mp-add-2":  {"source": {"source": "git", "url": "git@ghes.example.com:org/add2.git"}},
  "mp-add-3":  {"source": {"source": "git", "url": "git@ghes.example.com:org/add3.git"}}
}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {"kept-plugin@mp-keep": [{"scope": "user"}]}}
JSON
    cat > "$REPO/claude/plugin/company/marketplaces.json" <<'JSON'
{"mp-keep": "git@ghes.example.com:org/keep.git", "mp-remove-1": "org/gone1", "mp-remove-2": "org/gone2"}
JSON
    cat > "$REPO/claude/plugin/company/plugins.json" <<'JSON'
{"plugins": ["kept-plugin@mp-keep"]}
JSON
    git -C "$REPO/claude/plugin/company" add -A
    git -C "$REPO/claude/plugin/company" commit -qm seed

    run "$SCRIPT" --apply
    assert_success
    run git -C "$REPO/claude/plugin/company" log -1 --pretty=%s
    assert_output 'chore(claude-plugin): sync manifest (+mp-add-1 +mp-add-2 +mp-add-3 외 2개)'
}

@test "reconcile.sh --apply makes no commit when already in sync" {
    _seed_in_sync_manifest
    before=$(git -C "$REPO" rev-list --count HEAD)
    run "$SCRIPT" --apply
    assert_success
    after=$(git -C "$REPO" rev-list --count HEAD)
    [ "$after" -eq "$before" ]
}

@test "reconcile.sh errors clearly when the SSOT file is missing" {
    rm -f "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json"
    run "$SCRIPT" --check
    assert_failure 1
    assert_output --partial 'SSOT 파일이 없습니다'
    assert_output --partial 'installed_plugins.json'
}

@test "reconcile.sh skips company/ on a non-internal PC" {
    echo "external" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    _seed_in_sync_manifest
    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'company/ 건너뜀'
    refute_output --partial 'company/marketplaces.json'
}

@test "reconcile.sh --apply fails clearly when the plugin_sync_title.sh helper cannot be sourced (#1558 codex review)" {
    # A half-installed / mid-upgrade checkout: shell-common/functions/plugin_sync_title.sh
    # is unreachable, so _plugin_sync_title never gets defined. --apply must refuse loudly
    # (empty-subject commits are worse than no commit) rather than silently degrading.
    # 제목 헬퍼는 커밋을 남기는 company/ 스코프에서만 필요하다 (#1685).
    # company/ 는 부모 `git add -A` 가 빈 중첩 레포에 걸리지 않도록 seed 뒤에 만든다.
    _seed_drifted_manifest
    _activate_company
    before=$(git -C "$REPO/claude/plugin/company" rev-list --count HEAD 2>/dev/null || echo 0)

    SHELL_COMMON="$TEST_TEMP_HOME/no-such-shell-common" run "$SCRIPT" --apply
    assert_failure 1
    assert_output --partial 'plugin_sync_title.sh 를 불러오지 못했습니다'

    after=$(git -C "$REPO/claude/plugin/company" rev-list --count HEAD 2>/dev/null || echo 0)
    [ "$after" -eq "$before" ]
}

@test "reconcile.sh --apply does not need the title helper on a public-only PC (#1685)" {
    # 공용 스코프는 커밋을 만들지 않으므로 헬퍼가 없어도 오버레이 갱신은 성공해야 한다.
    _seed_drifted_manifest
    SHELL_COMMON="$TEST_TEMP_HOME/no-such-shell-common" run "$SCRIPT" --apply
    assert_success
    run jq -r 'keys | join(",")' "$REPO/claude/plugin/marketplaces.local.json"
    assert_output 'understand'
}

@test "reconcile.sh --check still works when the plugin_sync_title.sh helper cannot be sourced (half-installed tree)" {
    # --check never builds a commit title, so it must not depend on the helper at all —
    # only --apply's missing-helper guard should fire.
    _seed_drifted_manifest
    SHELL_COMMON="$TEST_TEMP_HOME/no-such-shell-common" run "$SCRIPT" --check
    assert_failure
    assert_output --partial '+ understand'
    refute_output --partial 'plugin_sync_title.sh 를 불러오지 못했습니다'
}
