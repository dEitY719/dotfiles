#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook.bats
# claude/hooks/plugin-sync.sh — install/marketplace add 병합(union) 경로 검증.
# 삭제(uninstall/marketplace remove) 경로는 plugin_sync_hook_delete.bats.
#
# #1685 이후 공용(github) 스코프가 쓰는 파일은 gitignored 오버레이
# claude/plugin/{marketplaces,plugins}.local.json 이고, tracked
# claude/plugin/{marketplaces,plugins}.json 은 upstream 등록 계약이라 훅이 읽기만
# 한다. 따라서 커밋/푸시 동작(#1072, #1125)과 커밋 제목(#1430, #1558)은 커밋을
# 남기는 유일한 스코프인 company/ 에서 검증한다.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync.sh"

setup() {
    setup_isolated_home
    MAIN_ROOT="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$MAIN_ROOT/claude/plugin"
    git -C "$MAIN_ROOT" init -q
    git -C "$MAIN_ROOT" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT" config user.name "hook-test"

    SRC="$TEST_TEMP_HOME/.claude-shared/plugins"
    mkdir -p "$SRC"
}

teardown() {
    teardown_isolated_home
}

_known_marketplaces() {
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{
  "claude-plugins-official": {"source": {"source": "github", "repo": "anthropics/claude-plugins-official"}},
  "gitkraken": {"source": {"source": "directory", "path": "/home/user/.claude/plugins/marketplaces/gitkraken"}},
  "internal-tools": {"source": {"source": "git", "url": "git@ghes.example.com:team/internal-tools.git"}}
}
JSON
}

# Simulate git/hooks/checks/main_branch_guard.sh: refuse direct commits on
# main/master unless the ALLOW_MAIN_COMMIT=1 escape hatch is set. Lets the
# isolated test repo reproduce the protected-branch condition (#1072) that
# the real CI repos never hit.
_install_protected_branch_guard() {
    mkdir -p "$1/.git/hooks"
    cat > "$1/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
[ "${ALLOW_MAIN_COMMIT:-0}" = "1" ] && exit 0
branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
case "$branch" in
    main | master) echo "BLOCKING: direct commit on protected branch" >&2; exit 1 ;;
esac
exit 0
HOOK
    chmod +x "$1/.git/hooks/pre-commit"
}

# company/ 를 자기 자신의 git 레포로 만든다 — #1685 이후 커밋을 남기는 유일한 스코프.
_company_repo() {
    mkdir -p "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" init -q
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"
}

# company/ 를 bare origin 의 클론으로 만든다 (#1125 push 검증용).
# $1 = 체크아웃할 브랜치(기본 main).
_company_clone() {
    local origin="$TEST_TEMP_HOME/company-origin.git" branch="${1:-main}"
    rm -rf "$MAIN_ROOT/claude/plugin/company"
    git init --bare --initial-branch=main "$origin" >/dev/null
    git clone -q "$origin" "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"
    (
        cd "$MAIN_ROOT/claude/plugin/company" &&
            echo seed > seed.txt && git add seed.txt &&
            git commit -q -m seed && git push -q origin main
    )
    if [ "$branch" != "main" ]; then
        (
            cd "$MAIN_ROOT/claude/plugin/company" &&
                git checkout -q -b "$branch" && git push -q -u origin "$branch"
        )
    fi
}

_installed_plugins() {
    cat > "$SRC/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "ralph-loop@claude-plugins-official": [{"scope": "user"}],
    "gitkraken-hooks@gitkraken": [{"scope": "user"}],
    "secret@internal-tools": [{"scope": "user"}],
    "visuals@visuals-skills": [{"scope": "local"}]
  }
}
JSON
}

@test "tool_name != Bash → no manifest change" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Read","tool_input":{"command":"claude plugin install foo@bar"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e 'length == 0' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure  # file shouldn't even exist yet — mkdir/write never ran
}

@test "non-matching Bash command → no manifest change" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude mcp list"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -f "$MAIN_ROOT/claude/plugin/marketplaces.json" ]
}

@test "install → public overlay gets github-sourced scope:user entries only (#1685)" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
    run jq -e 'has("gitkraken") | not' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success

    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

@test "install → tracked registration contract is never written and never committed (#1685)" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # 훅은 계약 파일을 만들지도, 고치지도 않는다 → fork 가 upstream 등록 커밋을
    # 받을 때 충돌할 tracked 변경 자체가 없다.
    [ ! -e "$MAIN_ROOT/claude/plugin/marketplaces.json" ]
    [ ! -e "$MAIN_ROOT/claude/plugin/plugins.json" ]
    # -uno: 오버레이는 실제 레포에서 gitignored 지만 이 격리 픽스처에는 .gitignore
    # 가 없다. 여기서 증명할 것은 "tracked 파일이 하나도 바뀌지 않았다" 이고,
    # 오버레이가 실제로 무시되는지는 claude_plugin_scaffold.bats 가 검증한다.
    run git -C "$MAIN_ROOT" status --porcelain --untracked-files=no
    assert_output ""
    [ "$(git -C "$MAIN_ROOT" rev-list --count --all 2>/dev/null || echo 0)" -eq 0 ]
}

@test "install → an entry the tracked contract already registers stays out of the overlay (#1685)" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    echo '{"claude-plugins-official": "anthropics/claude-plugins-official"}' \
        > "$MAIN_ROOT/claude/plugin/marketplaces.json"
    echo '{"plugins": ["ralph-loop@claude-plugins-official"]}' \
        > "$MAIN_ROOT/claude/plugin/plugins.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # 계약이 이미 담고 있으므로 오버레이 목표가 비고, 빈 오버레이 파일은
    # 애초에 만들지 않는다 (#1695 agy FOLLOW-UP). 중복 기록은 나중에 계약이
    # 바뀌었을 때 로컬이 옛 값을 되살리는 원인이 되므로 어느 쪽이든 금지다.
    [ ! -e "$MAIN_ROOT/claude/plugin/marketplaces.local.json" ]
    [ ! -e "$MAIN_ROOT/claude/plugin/plugins.local.json" ]
}

@test "install → reinstalling a tombstoned plugin cancels its tombstone (#1695)" {
    # 묘비가 남아 있으면 재설치해도 restore.sh 가 되돌린다 — add 경로가 지워야 한다.
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    cat > "$MAIN_ROOT/claude/plugin/removed.local.json" <<'JSON'
{"plugins": ["ralph-loop@claude-plugins-official", "other@claude-plugins-official"],
 "marketplaces": ["claude-plugins-official", "gone-mp"]}
JSON

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # 실제로 설치된 것만 묘비에서 빠지고, 나머지 묘비는 그대로 남는다.
    run jq -e '.plugins == ["other@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/removed.local.json"
    assert_success
    run jq -e '.marketplaces == ["gone-mp"]' \
        "$MAIN_ROOT/claude/plugin/removed.local.json"
    assert_success
}

@test "install → an EXISTING overlay is still emptied when its last local entry goes (#1695)" {
    # 위 가드는 "생성"만 막는다 — 이미 있는 파일은 비워지는 것이 정상 동작이다.
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    echo '{"claude-plugins-official": "anthropics/claude-plugins-official"}' \
        > "$MAIN_ROOT/claude/plugin/marketplaces.json"
    echo '{"plugins": ["ralph-loop@claude-plugins-official"]}' \
        > "$MAIN_ROOT/claude/plugin/plugins.json"
    echo '{"plugins": []}' > "$MAIN_ROOT/claude/plugin/plugins.local.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    [ -e "$MAIN_ROOT/claude/plugin/plugins.local.json" ]
    run jq -e '.plugins == []' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

@test "install → a no-op tombstone prune does not rewrite the file (#1695 round2 FOLLOW-UP)" {
    # 차집합 결과가 그대로면 쓰지 않는다 — no-op 재작성은 mtime 만 흔든다.
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    cat > "$MAIN_ROOT/claude/plugin/removed.local.json" <<'JSON'
{"marketplaces":["gone-mp"],"plugins":["gone@gone-mp"]}
JSON
    before=$(stat -c %Y "$MAIN_ROOT/claude/plugin/removed.local.json")
    before_body=$(cat "$MAIN_ROOT/claude/plugin/removed.local.json")

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    after=$(stat -c %Y "$MAIN_ROOT/claude/plugin/removed.local.json")
    [ "$before" = "$after" ]
    [ "$(cat "$MAIN_ROOT/claude/plugin/removed.local.json")" = "$before_body" ]
}

@test "install → directory-source and scope:local entries excluded" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("gitkraken")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_failure
    run jq -e '.plugins | any(. == "gitkraken-hooks@gitkraken")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
    run jq -e '.plugins | any(. == "visuals@visuals-skills")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
}

@test "install → merge preserves pre-existing overlay entries not in current local state" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    echo '{"pre-existing": "someone/else"}' > "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    echo '{"plugins": ["pre-existing-plugin@pre-existing"]}' > "$MAIN_ROOT/claude/plugin/plugins.local.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["pre-existing"] == "someone/else"' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
    run jq -e '.plugins | any(. == "pre-existing-plugin@pre-existing")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

@test "install → internal (non-github) entries go to claude/plugin/company only when that repo exists" {
    _known_marketplaces
    _installed_plugins
    _company_repo

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["internal-tools"] == "git@ghes.example.com:team/internal-tools.git"' \
        "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    assert_success
    run jq -e '.plugins == ["secret@internal-tools"]' "$MAIN_ROOT/claude/plugin/company/plugins.json"
    assert_success
    # public overlay untouched by the internal-only plugin
    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_failure

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (secret@internal-tools)"
}

@test "install → internal entries skipped entirely when company/ repo not cloned" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -d "$MAIN_ROOT/claude/plugin/company" ]
}

@test "install → GHES marketplace on a PC without company/ prints a stderr hint (not a silent skip, #1080)" {
    _known_marketplaces
    _installed_plugins
    # No company/.git → simulates an external/public PC. The internal entry
    # must NOT be stored (isolation), but the user gets a stderr hint instead
    # of the old silent skip.
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    assert_output --partial "사내 GHES 마켓플레이스 감지"
    # Still no company/ manifest written, and no leak into the public manifest.
    [ ! -d "$MAIN_ROOT/claude/plugin/company" ]
    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_failure
}

@test "marketplace add → treated the same as install (re-sync)" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace add anthropics/claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
}

@test "install → pre-existing 0-byte manifest does not break the merge (empty-file guard)" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    # 0-byte, valid-JSON-less — 오버레이도, 읽기 전용 계약도 모두 이 상태를 견뎌야 한다.
    : > "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    : > "$MAIN_ROOT/claude/plugin/plugins.local.json"
    : > "$MAIN_ROOT/claude/plugin/marketplaces.json"
    : > "$MAIN_ROOT/claude/plugin/plugins.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

@test "install → commit lands even on protected 'main' branch (#1072 escape hatch)" {
    # 커밋을 남기는 스코프는 company/ 뿐이다 (#1685).
    _known_marketplaces
    _installed_plugins
    _company_repo
    git -C "$MAIN_ROOT/claude/plugin/company" symbolic-ref HEAD refs/heads/main
    _install_protected_branch_guard "$MAIN_ROOT/claude/plugin/company"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # The manifest is actually committed — not silently blocked and left
    # unstaged as it was before the ALLOW_MAIN_COMMIT=1 fix.
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (secret@internal-tools)"
    run git -C "$MAIN_ROOT/claude/plugin/company" status --porcelain
    assert_output ""
}

@test "install → commit on protected 'main' with upstream is pushed, not left local-only (#1125)" {
    # company/ 를 bare origin 의 클론으로 만들어 `main` 이 origin/main 을 추적하게 한다
    # (#1685 이후 커밋/푸시가 일어나는 유일한 스코프). main 위의 local-only 커밋은
    # origin/main 이 움직이는 순간 갈라지므로 훅이 즉시 push 해야 한다.
    _known_marketplaces
    _installed_plugins
    _company_clone main

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # Commit landed AND was pushed: local main == origin/main, so no local-only
    # commit lingers to later diverge.
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (secret@internal-tools)"
    [ "$(git -C "$MAIN_ROOT/claude/plugin/company" rev-parse main)" \
        = "$(git -C "$MAIN_ROOT/claude/plugin/company" rev-parse origin/main)" ]
    run git -C "$MAIN_ROOT/claude/plugin/company" status --porcelain
    assert_output ""
}

@test "install → commit on a feature branch is NOT auto-pushed (#1125 scope guard)" {
    _known_marketplaces
    _installed_plugins
    _company_clone feat/x

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # Committed locally on the feature branch. feat/x HAS an upstream, so the
    # early @{u} return cannot mask a broken branch filter — the only reason
    # origin/feat/x stays at seed is the main/master-only scope guard.
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (secret@internal-tools)"
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s origin/feat/x
    assert_output "seed"
}

@test "install → internal reserved sentinel (session-hook bulk resync) names the keys it actually changed (#1430, #1558)" {
    # The sentinel is a bulk SSOT re-sync, not a single install, so the
    # placeholder name must never reach the title (#1430). Titling it bare
    # left `git log --oneline` unable to tell one bulk sync from another
    # (#1558) — now it lists the changed keys the way reconcile.sh does.
    _known_marketplaces
    _installed_plugins
    _company_repo
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install __slash_command_sync__"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (+internal-tools +secret@internal-tools)"
}

@test "install → bulk resync title lists only what this run changed, never the merge-preserved entries (#1558)" {
    # The add path MERGES (union) — it never deletes. A title computed
    # against the raw SSOT target would claim "-pre-existing" for an entry
    # the commit deliberately keeps, so the keys are diffed against the
    # merged value that is actually written.
    _known_marketplaces
    _installed_plugins
    _company_repo
    echo '{"pre-existing": "someone/else"}' > "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    echo '{"plugins": ["pre-existing-plugin@pre-existing"]}' > "$MAIN_ROOT/claude/plugin/company/plugins.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install __slash_command_sync__"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (+internal-tools +secret@internal-tools)"
    refute_output --partial "-pre-existing"
}

@test "install → bulk resync title truncates past 4 changed keys like reconcile.sh (#1558)" {
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{
  "internal-tools": {"source": {"source": "git", "url": "git@ghes.example.com:team/internal-tools.git"}}
}
JSON
    cat > "$SRC/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "aa@internal-tools": [{"scope": "user"}],
    "bb@internal-tools": [{"scope": "user"}],
    "cc@internal-tools": [{"scope": "user"}],
    "dd@internal-tools": [{"scope": "user"}],
    "ee@internal-tools": [{"scope": "user"}]
  }
}
JSON
    _company_repo

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install __slash_command_sync__"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # 6 changed keys (1 marketplace + 5 plugins) → first 3 + "외 3개".
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (+internal-tools +aa@internal-tools +bb@internal-tools 외 3개)"
}

@test "install → bulk resync titles company/ from the private manifest, never from the public overlay (#1558)" {
    _known_marketplaces
    _installed_plugins
    _company_repo

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install __slash_command_sync__"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # 공용 오버레이가 같은 실행에서 github 항목을 받아도 company/ 제목에는
    # 사내 키만 들어가야 한다.
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (+internal-tools +secret@internal-tools)"
    refute_output --partial "claude-plugins-official"
}

@test "install → bulk resync falls back to the bare subject when the title helper is unavailable (#1558)" {
    # Stale install / missing shell-common: the hook is best-effort and must
    # still commit under the bare subject rather than dying on an undefined
    # _build_sync_title (which would leave the manifest uncommitted).
    _known_marketplaces
    _installed_plugins
    _company_repo
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install __slash_command_sync__"}}'
    run bash -c "printf '%s' '$payload' | SHELL_COMMON='$TEST_TEMP_HOME/no-such-dir' '$HOOK'"
    assert_success

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
    run git -C "$MAIN_ROOT/claude/plugin/company" status --porcelain
    assert_output ""
}

@test "no-op re-run does not create an empty commit" {
    _known_marketplaces
    _installed_plugins
    _company_repo
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    bash -c "printf '%s' '$payload' | '$HOOK'"
    before=$(git -C "$MAIN_ROOT/claude/plugin/company" rev-parse HEAD)

    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    after=$(git -C "$MAIN_ROOT/claude/plugin/company" rev-parse HEAD)
    [ "$before" = "$after" ]
}

@test "no-op re-run leaves the public overlay byte-identical and the tree clean (#1685)" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    bash -c "printf '%s' '$payload' | '$HOOK'"
    before=$(cat "$MAIN_ROOT/claude/plugin/plugins.local.json")

    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ "$(cat "$MAIN_ROOT/claude/plugin/plugins.local.json")" = "$before" ]
    run git -C "$MAIN_ROOT" status --porcelain --untracked-files=no
    assert_output ""
}
