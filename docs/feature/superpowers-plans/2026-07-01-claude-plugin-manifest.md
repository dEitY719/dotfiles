# Claude Code Plugin Manifest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `claude plugin install/uninstall`와 `claude plugin marketplace add/remove`를
dotfiles git에 자동 기록하고, 신규 PC에서 한 번의 스크립트 실행으로 그 목록을
재설치할 수 있게 한다.

**Architecture:** Claude Code `PostToolUse` hook(`claude/hooks/plugin-sync.sh`)이
`~/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json`을
scope(`user`만) · source(`github`/그 외/`directory`)로 분류해 공개
`claude/plugin/{marketplaces,plugins}.json`과 비공개 nested repo
`claude/plugin/company/{marketplaces,plugins}.json`에 병합(union) 반영하고
각각 로컬 커밋한다. `claude/plugin/restore.sh`가 신규 PC에서 그 manifest를
읽어 `claude plugin marketplace add` / `install`을 순회 실행한다.

**Tech Stack:** POSIX/bash + jq (기존 `claude/hooks/post-gh-pr-create.sh`와
동일한 hook 뼈대), bats (`tests/bats/`) 테스트, shellcheck/shfmt lint.

**Spec:** `docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md` (commits `f2a6b59d`, `e0bec411`)

## Global Constraints

- POSIX 호환 규칙은 `shell-common/`에만 적용된다 — `claude/hooks/`,
  `claude/plugin/`은 이미 `#!/usr/bin/env bash`를 쓰는 기존 파일들
  (`post-gh-pr-create.sh`)과 같은 계열이므로 bash 문법 사용 가능.
- hook은 항상 `exit 0` — 세션 흐름을 절대 막지 않는다.
- hook은 절대 `git push`하지 않는다 — 로컬 커밋까지만.
- 커밋 대상 경로는 항상 `$HOME/dotfiles` 고정 — 현재 세션의 `$DOTFILES_ROOT`나
  worktree 경로를 쓰지 않는다.
- lint: `mise run lint-sh` (shellcheck + shfmt -d) 통과 필수. 새 `.sh` 파일은
  `mise run fix-sh`로 포맷.
- 테스트: `./tests/bats/lib/bats-core/bin/bats <파일>`로 개별 실행 가능해야 함.

---

### Task 1: `claude/plugin/` 스캐폴드 + `.gitignore`

**Files:**
- Create: `claude/plugin/marketplaces.json`
- Create: `claude/plugin/plugins.json`
- Modify: `.gitignore` (기존 `/company-skills/` 블록 뒤에 추가)
- Test: `tests/bats/tools/claude_plugin_scaffold.bats`

**Interfaces:**
- Produces: `claude/plugin/marketplaces.json` — `{}` (빈 객체, `{name: "owner/repo"}` 형태로 채워질 예정)
- Produces: `claude/plugin/plugins.json` — `{"plugins": []}` (`plugin@marketplace` 문자열 배열)
- Produces: `.gitignore`에 `/claude/plugin/company/` 무시 규칙

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > tests/bats/tools/claude_plugin_scaffold.bats <<'EOF'
#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_scaffold.bats
# claude/plugin/ 스캐폴드 + .gitignore 무시 규칙 검증.

load '../test_helper'

@test "claude/plugin/marketplaces.json exists and is valid empty JSON object" {
    run jq -e 'type == "object" and length == 0' "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
    assert_success
}

@test "claude/plugin/plugins.json exists with empty plugins array" {
    run jq -e '.plugins == []' "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

@test ".gitignore ignores claude/plugin/company/" {
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/company/dummy.json
    assert_success
}
EOF
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_scaffold.bats`
Expected: 3개 테스트 모두 FAIL (`claude/plugin/` 디렉토리 자체가 없음)

- [ ] **Step 3: 스캐폴드 생성**

```bash
mkdir -p claude/plugin
printf '{}\n' > claude/plugin/marketplaces.json
printf '{"plugins": []}\n' > claude/plugin/plugins.json
```

`.gitignore`의 기존 `/company-skills/` 블록 뒤에 추가:

```gitignore

# Claude Code plugin manifest — 사내 전용 분류는 별도 private nested repo로
# 관리한다 (docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md).
# public 레포는 이 경로의 존재 자체를 추적하지 않는다.
/claude/plugin/company/
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_scaffold.bats`
Expected: 3개 테스트 모두 PASS

- [ ] **Step 5: 커밋**

```bash
git add claude/plugin/marketplaces.json claude/plugin/plugins.json .gitignore \
    tests/bats/tools/claude_plugin_scaffold.bats
git commit -m "feat(claude-plugin): scaffold manifest files + gitignore company overlay"
```

---

### Task 2: `claude/plugin/restore.sh`

**Files:**
- Create: `claude/plugin/restore.sh`
- Test: `tests/bats/tools/claude_plugin_restore.bats`

**Interfaces:**
- Consumes: `claude/plugin/marketplaces.json` (`{name: repo}`), `claude/plugin/plugins.json` (`{"plugins": [...]}`) from Task 1; same shape at `claude/plugin/company/` when present
- Produces: stdout log lines `add: <name> (<repo>)` / `install: <plugin>`; with `--dry-run` no external commands are run

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
mkdir -p tests/bats/tools
cat > tests/bats/tools/claude_plugin_restore.bats <<'EOF'
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
EOF
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_restore.bats`
Expected: 4개 테스트 모두 FAIL (`claude/plugin/restore.sh: No such file or directory`)

- [ ] **Step 3: 구현**

```bash
cat > claude/plugin/restore.sh <<'EOF'
#!/usr/bin/env bash
# claude/plugin/restore.sh
#
# Reinstall Claude Code plugins/marketplaces from the dotfiles manifest.
# Public manifest (claude/plugin/{marketplaces,plugins}.json) is always
# restored. The private company/ nested repo is restored only when
# ~/.dotfiles-setup-mode == internal AND claude/plugin/company/.git exists
# (cloned there manually once — see the design doc).
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v jq >/dev/null 2>&1 || { echo "jq가 필요합니다." >&2; exit 1; }
# --dry-run only prints the plan — don't require the claude CLI for that,
# so this also works as a preview before clinstall, and so CI (which has
# no claude binary) can exercise --dry-run in tests without it.
if [ "$DRY_RUN" -eq 0 ]; then
    command -v claude >/dev/null 2>&1 || { echo "claude CLI가 없습니다. 먼저 clinstall 하세요." >&2; exit 1; }
fi

_restore_from() {
    local mp_json="$1" pl_json="$2" label="$3"
    if [ ! -f "$mp_json" ] || [ ! -f "$pl_json" ]; then
        echo "  (${label} manifest 없음 — 건너뜀)"
        return 0
    fi
    echo "== ${label} marketplaces =="
    jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$mp_json" |
        while IFS=$'\t' read -r name repo; do
            echo "  add: ${name} (${repo})"
            if [ "$DRY_RUN" -eq 0 ]; then
                claude plugin marketplace add "$repo" || echo "    실패 — 계속 진행" >&2
            fi
        done
    echo "== ${label} plugins =="
    jq -r '.plugins[]' "$pl_json" |
        while read -r plugin; do
            echo "  install: ${plugin}"
            if [ "$DRY_RUN" -eq 0 ]; then
                claude plugin install "$plugin" || echo "    실패 — 계속 진행" >&2
            fi
        done
}

_restore_from "$SCRIPT_DIR/marketplaces.json" "$SCRIPT_DIR/plugins.json" "공용"

MODE=$(cat "$HOME/.dotfiles-setup-mode" 2>/dev/null || echo "")
if [ "$MODE" = "internal" ]; then
    PRIV="$SCRIPT_DIR/company"
    if [ -d "$PRIV/.git" ]; then
        _restore_from "$PRIV/marketplaces.json" "$PRIV/plugins.json" "사내 전용"
    else
        echo "(사내 전용 레포 미설정 — 먼저 실행: git clone <GHES private repo url> $PRIV)"
    fi
else
    echo "(모드: ${MODE:-미설정} — 사내 전용 manifest는 internal에서만 복원)"
fi

echo "완료. 새 Claude Code 세션을 시작해 스킬이 로드됐는지 확인하세요."
EOF
chmod +x claude/plugin/restore.sh
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_restore.bats`
Expected: 4개 테스트 모두 PASS

- [ ] **Step 5: lint + 커밋**

```bash
shellcheck claude/plugin/restore.sh
shfmt -d claude/plugin/restore.sh
git add claude/plugin/restore.sh tests/bats/tools/claude_plugin_restore.bats
git commit -m "feat(claude-plugin): add restore.sh (mode-aware manifest restore)"
```

---

### Task 3: `claude/hooks/plugin-sync.sh` — 병합(union) 동기화 (install / marketplace add)

**Files:**
- Create: `claude/hooks/plugin-sync.sh`
- Test: `tests/bats/skills/plugin_sync_hook.bats`

**Interfaces:**
- Consumes: stdin PostToolUse JSON `{"tool_name": "...", "tool_input": {"command": "..."}}`;
  `$HOME/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json`
- Produces: `$HOME/dotfiles/claude/plugin/{marketplaces,plugins}.json` (병합),
  `$HOME/dotfiles/claude/plugin/company/{marketplaces,plugins}.json` (해당
  레포가 존재할 때만), 각각 로컬 git 커밋

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
mkdir -p tests/bats/skills
cat > tests/bats/skills/plugin_sync_hook.bats <<'EOF'
#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook.bats
# claude/hooks/plugin-sync.sh — install/marketplace add 병합(union) 경로 검증.
# 삭제(uninstall/marketplace remove) 경로는 plugin_sync_hook_delete.bats.

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

_installed_plugins() {
    cat > "$SRC/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "ralph-loop@claude-plugins-official": [{"scope": "user"}],
    "gitkraken-hooks@gitkraken": [{"scope": "user"}],
    "secret@internal-tools": [{"scope": "user"}],
    "visuals@claude-plugin-visuals": [{"scope": "local"}]
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

@test "install → public manifest gets github-sourced scope:user entries only" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
    run jq -e '.["gitkraken"] // empty | length == 0' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success

    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success

    # committed locally
    run git -C "$MAIN_ROOT" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
}

@test "install → directory-source and scope:local entries excluded" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("gitkraken")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure
    run jq -e '.plugins | any(. == "gitkraken-hooks@gitkraken")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
    run jq -e '.plugins | any(. == "visuals@claude-plugin-visuals")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
}

@test "install → merge preserves pre-existing manifest entries not in current local state" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    echo '{"pre-existing": "someone/else"}' > "$MAIN_ROOT/claude/plugin/marketplaces.json"
    echo '{"plugins": ["pre-existing-plugin@pre-existing"]}' > "$MAIN_ROOT/claude/plugin/plugins.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["pre-existing"] == "someone/else"' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
    run jq -e '.plugins | any(. == "pre-existing-plugin@pre-existing")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
}

@test "install → internal (non-github) entries go to claude/plugin/company only when that repo exists" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" init -q
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["internal-tools"] == "git@ghes.example.com:team/internal-tools.git"' \
        "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    assert_success
    run jq -e '.plugins == ["secret@internal-tools"]' "$MAIN_ROOT/claude/plugin/company/plugins.json"
    assert_success
    # public manifest untouched by the internal-only plugin
    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
}

@test "install → internal entries skipped entirely when company/ repo not cloned" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -d "$MAIN_ROOT/claude/plugin/company" ]
}

@test "marketplace add → treated the same as install (re-sync)" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace add anthropics/claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
}

@test "no-op re-run does not create an empty commit" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    bash -c "printf '%s' '$payload' | '$HOOK'"
    before=$(git -C "$MAIN_ROOT" rev-parse HEAD)

    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    after=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    [ "$before" = "$after" ]
}
EOF
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/skills/plugin_sync_hook.bats`
Expected: 모든 테스트 FAIL (`claude/hooks/plugin-sync.sh: No such file or directory`)

- [ ] **Step 3: 구현 (install / marketplace add 경로만)**

```bash
cat > claude/hooks/plugin-sync.sh <<'EOF'
#!/usr/bin/env bash
# claude/hooks/plugin-sync.sh
#
# Claude Code PostToolUse hook for `claude plugin ...` commands. Keeps
# claude/plugin/{marketplaces,plugins}.json (public, github-sourced,
# scope:user) and claude/plugin/company/{marketplaces,plugins}.json
# (private nested repo, non-github sourced) merged with the ground truth
# in ~/.claude-shared/plugins/ so claude/plugin/restore.sh can rebuild a
# fresh PC's plugin set.
#
# See docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md
#
# Always exits 0 — best-effort, never blocks the session.
set -u

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""') || exit 0
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""') || exit 0

# Target extraction assumes the plugin/marketplace name is the token
# immediately following the subcommand (the common case: no flags before
# the positional arg). Flags placed before the target are not handled.
action=""
target=""
if printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+marketplace[[:space:]]+add'; then
    action="add"
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+marketplace[[:space:]]+(remove|rm)'; then
    action="marketplace_remove"
    target=$(printf '%s' "$cmd" |
        grep -oE 'marketplace[[:space:]]+(remove|rm)[[:space:]]+[^[:space:]]+' |
        awk '{print $NF}')
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+install'; then
    action="add"
elif printf '%s' "$cmd" | grep -qE 'claude[[:space:]]+plugin[[:space:]]+(uninstall|remove)'; then
    action="uninstall"
    target=$(printf '%s' "$cmd" |
        grep -oE '(uninstall|remove)[[:space:]]+[^[:space:]]+' |
        awk '{print $NF}')
else
    exit 0
fi

MAIN_ROOT="$HOME/dotfiles"
[ -d "$MAIN_ROOT/.git" ] || exit 0

SRC="$HOME/.claude-shared/plugins"
MP_SRC="$SRC/known_marketplaces.json"
PL_SRC="$SRC/installed_plugins.json"

PUB_DIR="$MAIN_ROOT/claude/plugin"
PRIV_DIR="$PUB_DIR/company"

# Stage + commit only if there is an actual diff (works for brand-new
# untracked files too, since `git diff --cached` compares the *staged*
# tree against HEAD — plain `git diff` would miss never-added files).
_commit_if_changed() {
    local repo_dir="$1" msg="$2"
    shift 2
    git -C "$repo_dir" add "$@" 2>/dev/null || return 0
    git -C "$repo_dir" diff --cached --quiet -- "$@" 2>/dev/null && return 0
    git -C "$repo_dir" commit -m "$msg" --quiet 2>/dev/null || true
}

if [ "$action" = "add" ]; then
    [ -f "$MP_SRC" ] && [ -f "$PL_SRC" ] || exit 0

    mp_common=$(jq -c '
        [to_entries[] | select(.value.source.source == "github")]
        | map({(.key): .value.source.repo}) | add // {}
    ' "$MP_SRC") || exit 0
    mp_internal=$(jq -c '
        [to_entries[] | select(.value.source.source != "github" and .value.source.source != "directory")]
        | map({(.key): (.value.source.repo // .value.source.url // .value.source.path)}) | add // {}
    ' "$MP_SRC") || exit 0

    plugins_common=$(jq -c --argjson mp "$mp_common" '
        [(.plugins // {}) | to_entries[]
            | select(.value[]?.scope == "user")
            | .key
            | select($mp[(. | split("@") | last)] != null)
        ] | unique
    ' "$PL_SRC") || exit 0
    plugins_internal=$(jq -c --argjson mp "$mp_internal" '
        [(.plugins // {}) | to_entries[]
            | select(.value[]?.scope == "user")
            | .key
            | select($mp[(. | split("@") | last)] != null)
        ] | unique
    ' "$PL_SRC") || exit 0

    mkdir -p "$PUB_DIR"
    jq -n --argjson old "$(cat "$PUB_DIR/marketplaces.json" 2>/dev/null || echo '{}')" \
        --argjson new "$mp_common" '$old * $new' \
        >"$PUB_DIR/marketplaces.json.tmp" &&
        mv "$PUB_DIR/marketplaces.json.tmp" "$PUB_DIR/marketplaces.json"
    jq -n --argjson old "$(cat "$PUB_DIR/plugins.json" 2>/dev/null || echo '{"plugins":[]}')" \
        --argjson new "$plugins_common" \
        '{plugins: (($old.plugins // []) + $new | unique | sort)}' \
        >"$PUB_DIR/plugins.json.tmp" &&
        mv "$PUB_DIR/plugins.json.tmp" "$PUB_DIR/plugins.json"
    _commit_if_changed "$MAIN_ROOT" "chore(claude-plugin): sync manifest" \
        claude/plugin/marketplaces.json claude/plugin/plugins.json

    if [ -d "$PRIV_DIR/.git" ] && [ "$mp_internal" != "{}" ]; then
        jq -n --argjson old "$(cat "$PRIV_DIR/marketplaces.json" 2>/dev/null || echo '{}')" \
            --argjson new "$mp_internal" '$old * $new' \
            >"$PRIV_DIR/marketplaces.json.tmp" &&
            mv "$PRIV_DIR/marketplaces.json.tmp" "$PRIV_DIR/marketplaces.json"
        jq -n --argjson old "$(cat "$PRIV_DIR/plugins.json" 2>/dev/null || echo '{"plugins":[]}')" \
            --argjson new "$plugins_internal" \
            '{plugins: (($old.plugins // []) + $new | unique | sort)}' \
            >"$PRIV_DIR/plugins.json.tmp" &&
            mv "$PRIV_DIR/plugins.json.tmp" "$PRIV_DIR/plugins.json"
        _commit_if_changed "$PRIV_DIR" "chore(claude-plugin): sync manifest" \
            marketplaces.json plugins.json
    fi
fi

exit 0
EOF
chmod +x claude/hooks/plugin-sync.sh
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/skills/plugin_sync_hook.bats`
Expected: 모든 테스트 PASS (uninstall/marketplace remove 관련 테스트는 아직
없음 — Task 4에서 추가)

- [ ] **Step 5: lint + 커밋**

```bash
shellcheck claude/hooks/plugin-sync.sh
shfmt -d claude/hooks/plugin-sync.sh
git add claude/hooks/plugin-sync.sh tests/bats/skills/plugin_sync_hook.bats
git commit -m "feat(claude-plugin): add plugin-sync hook (install/marketplace-add merge path)"
```

---

### Task 4: `plugin-sync.sh` — 삭제(uninstall / marketplace remove) 경로

**Files:**
- Modify: `claude/hooks/plugin-sync.sh`
- Test: `tests/bats/skills/plugin_sync_hook_delete.bats`

**Interfaces:**
- Consumes: 동일 stdin JSON, 이번엔 `uninstall <plugin>[@<marketplace>]` /
  `marketplace remove <name>` 커맨드
- Produces: 대상 항목만 제거된 `claude/plugin/{,company/}{marketplaces,plugins}.json`

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > tests/bats/skills/plugin_sync_hook_delete.bats <<'EOF'
#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook_delete.bats
# claude/hooks/plugin-sync.sh — uninstall / marketplace remove 경로.
# 병합(install/add) 경로 커버리지는 plugin_sync_hook.bats.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync.sh"

setup() {
    setup_isolated_home
    MAIN_ROOT="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$MAIN_ROOT/claude/plugin"
    git -C "$MAIN_ROOT" init -q
    git -C "$MAIN_ROOT" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT" config user.name "hook-test"

    cat > "$MAIN_ROOT/claude/plugin/marketplaces.json" <<'JSON'
{"claude-plugins-official": "anthropics/claude-plugins-official", "understand-anything": "Egonex-AI/Understand-Anything"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/plugins.json" <<'JSON'
{"plugins": ["ralph-loop@claude-plugins-official", "understand-anything@understand-anything"]}
JSON
    git -C "$MAIN_ROOT" add claude/plugin
    git -C "$MAIN_ROOT" commit -q -m "seed"
}

teardown() {
    teardown_isolated_home
}

@test "uninstall <plugin>@<marketplace> removes exactly that entry" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.plugins == ["understand-anything@understand-anything"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
    # untouched marketplace entries stay
    run jq -e 'has("claude-plugins-official")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
}

@test "uninstall <bare-plugin-name> removes the matching plugin@marketplace entry" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
}

@test "marketplace remove deletes the marketplace and cascades to its plugins" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("claude-plugins-official")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
    # unrelated marketplace/plugin survives
    run jq -e 'has("understand-anything")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
}

@test "uninstall with no target token → no-op" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official", "understand-anything@understand-anything"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
}

@test "uninstall commits the removal locally" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    before=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    after=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    [ "$before" != "$after" ]
    run git -C "$MAIN_ROOT" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
}

@test "marketplace remove also removes the matching entry from claude/plugin/company/" {
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

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    assert_failure
    run jq -e '.plugins == []' "$MAIN_ROOT/claude/plugin/company/plugins.json"
    assert_success
}
EOF
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/skills/plugin_sync_hook_delete.bats`
Expected: 모든 테스트 FAIL (hook에 삭제 분기가 아직 없어 `action` else 분기가 비어 있음)

- [ ] **Step 3: 구현 — `plugin-sync.sh`의 `if [ "$action" = "add" ]; then ... fi` 블록
      바로 뒤, `exit 0` 앞에 삽입**

```bash
if [ "$action" = "uninstall" ] || [ "$action" = "marketplace_remove" ]; then
    [ -n "$target" ] || exit 0
    for dir in "$PUB_DIR" "$PRIV_DIR"; do
        [ -f "$dir/marketplaces.json" ] || [ -f "$dir/plugins.json" ] || continue

        if [ "$action" = "marketplace_remove" ]; then
            if [ -f "$dir/marketplaces.json" ]; then
                jq --arg t "$target" 'del(.[$t])' "$dir/marketplaces.json" \
                    >"$dir/marketplaces.json.tmp" 2>/dev/null &&
                    mv "$dir/marketplaces.json.tmp" "$dir/marketplaces.json"
            fi
            if [ -f "$dir/plugins.json" ]; then
                jq --arg t "$target" \
                    '{plugins: [.plugins[] | select((. | split("@") | last) != $t)]}' \
                    "$dir/plugins.json" >"$dir/plugins.json.tmp" 2>/dev/null &&
                    mv "$dir/plugins.json.tmp" "$dir/plugins.json"
            fi
        else
            if [ -f "$dir/plugins.json" ]; then
                jq --arg t "$target" \
                    '{plugins: [.plugins[] | select(. != $t and (startswith($t + "@") | not))]}' \
                    "$dir/plugins.json" >"$dir/plugins.json.tmp" 2>/dev/null &&
                    mv "$dir/plugins.json.tmp" "$dir/plugins.json"
            fi
        fi
    done

    _commit_if_changed "$MAIN_ROOT" "chore(claude-plugin): sync manifest" \
        claude/plugin/marketplaces.json claude/plugin/plugins.json
    if [ -d "$PRIV_DIR/.git" ]; then
        _commit_if_changed "$PRIV_DIR" "chore(claude-plugin): sync manifest" \
            marketplaces.json plugins.json
    fi
fi
```

- [ ] **Step 4: 테스트 통과 확인 (Task 3 회귀 포함)**

Run:
```bash
./tests/bats/lib/bats-core/bin/bats tests/bats/skills/plugin_sync_hook.bats \
    tests/bats/skills/plugin_sync_hook_delete.bats
```
Expected: 모든 테스트 PASS

- [ ] **Step 5: lint + 커밋**

```bash
shellcheck claude/hooks/plugin-sync.sh
shfmt -d claude/hooks/plugin-sync.sh
git add claude/hooks/plugin-sync.sh tests/bats/skills/plugin_sync_hook_delete.bats
git commit -m "feat(claude-plugin): add plugin-sync hook uninstall/marketplace-remove path"
```

---

### Task 5: hook을 `claude/settings.json`에 등록

**Files:**
- Modify: `claude/settings.json`
- Test: `tests/bats/skills/plugin_sync_hook_registration.bats`

**Interfaces:**
- Produces: `.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[]`
  배열에 `claude/hooks/plugin-sync.sh` 항목 추가 (기존
  `post-gh-pr-create.sh` 항목은 유지)

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > tests/bats/skills/plugin_sync_hook_registration.bats <<'EOF'
#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook_registration.bats
# claude/settings.json에 plugin-sync.sh가 PostToolUse/Bash로 등록됐는지,
# 기존 post-gh-pr-create.sh 등록이 안 깨졌는지 확인.

load '../test_helper'

SETTINGS="${_BATS_REAL_DOTFILES_ROOT}/claude/settings.json"

@test "settings.json is valid JSON" {
    run jq -e '.' "$SETTINGS"
    assert_success
}

@test "PostToolUse/Bash includes plugin-sync.sh" {
    run jq -e '
        .hooks.PostToolUse[]
        | select(.matcher == "Bash")
        | .hooks[]
        | select(.command | endswith("claude/hooks/plugin-sync.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "PostToolUse/Bash still includes post-gh-pr-create.sh" {
    run jq -e '
        .hooks.PostToolUse[]
        | select(.matcher == "Bash")
        | .hooks[]
        | select(.command | endswith("claude/hooks/post-gh-pr-create.sh"))
    ' "$SETTINGS"
    assert_success
}
EOF
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/skills/plugin_sync_hook_registration.bats`
Expected: "PostToolUse/Bash includes plugin-sync.sh" FAIL

- [ ] **Step 3: `claude/settings.json` 수정**

기존:
```json
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/dotfiles/claude/hooks/post-gh-pr-create.sh"
          }
        ]
      }
    ]
```

변경 후:
```json
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/dotfiles/claude/hooks/post-gh-pr-create.sh"
          },
          {
            "type": "command",
            "command": "${HOME}/dotfiles/claude/hooks/plugin-sync.sh"
          }
        ]
      }
    ]
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/skills/plugin_sync_hook_registration.bats`
Expected: 3개 테스트 모두 PASS

- [ ] **Step 5: 커밋**

```bash
git add claude/settings.json tests/bats/skills/plugin_sync_hook_registration.bats
git commit -m "feat(claude-plugin): register plugin-sync hook in settings.json"
```

---

### Task 6: `claude-help plugin` 섹션 + `claude/AGENTS.md` 갱신

**Files:**
- Modify: `shell-common/functions/ai_tools_help.sh`
- Modify: `claude/AGENTS.md`
- Test: `tests/bats/functions/claude_help_plugin.bats`

**Interfaces:**
- Produces: `claude_help plugin` (alias `claude-help plugin`)이 아래 내용을 출력
- Consumes: 없음 (순수 텍스트 출력 함수)

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > tests/bats/functions/claude_help_plugin.bats <<'EOF'
#!/usr/bin/env bats
# tests/bats/functions/claude_help_plugin.bats
# claude_help의 신규 `plugin` 섹션 검증.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

_run_claude_help() {
    bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/ai_tools_help.sh'
        claude_help $1
    "
}

@test "claude-help --list includes plugin section" {
    run _run_claude_help --list
    assert_success
    assert_output --partial 'plugin'
}

@test "claude-help summary mentions plugin section" {
    run _run_claude_help ""
    assert_success
    assert_output --partial 'plugin'
}

@test "claude-help plugin shows restore.sh usage" {
    run _run_claude_help plugin
    assert_success
    assert_output --partial 'claude/plugin/restore.sh'
    assert_output --partial 'claude plugin marketplace add/remove'
}

@test "claude-help --all renders the plugin section" {
    run _run_claude_help --all
    assert_success
    assert_output --partial 'claude/plugin/restore.sh'
}
EOF
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/functions/claude_help_plugin.bats`
Expected: "claude-help plugin shows restore.sh usage" 및 `--all` 테스트 FAIL
(`Unknown claude-help section: plugin`)

- [ ] **Step 3: `shell-common/functions/ai_tools_help.sh` 수정**

`_claude_help_rows_skills()` 정의 바로 뒤에 추가:

```bash
_claude_help_rows_plugin() {
    ux_table_row "claude plugin marketplace add/remove, install/uninstall" "자동으로 claude/plugin/*.json에 동기화됨 (hook)" ""
    ux_table_row "./claude/plugin/restore.sh" "신규 PC에서 manifest 기반 일괄 재설치" ""
    ux_table_row "./claude/plugin/restore.sh --dry-run" "실행 없이 계획만 출력" ""
}
```

`_claude_help_summary()`의 `skills` bullet 뒤에 한 줄 추가:
```bash
    ux_bullet_sub "plugin: claude plugin sync + restore.sh"
```

`_claude_help_list_sections()`의 `skills` bullet 뒤에 한 줄 추가:
```bash
    ux_bullet_sub "plugin"
```

`_claude_help_section_rows()`의 `skills)` case 뒤에 추가:
```bash
        plugin|plugins)
            _claude_help_rows_plugin
            ;;
```

`_claude_help_full()`의 마지막 `_claude_help_render_section` 호출 뒤에 추가:
```bash
    _claude_help_render_section "Plugin Manifest Sync" _claude_help_rows_plugin
```

`claude/AGENTS.md`의 "## Configuration Files" 섹션 뒤에 새 섹션 추가:

```markdown
## Plugin Manifest (claude/plugin/)

`claude plugin install/uninstall`, `claude plugin marketplace add/remove`는
`claude/hooks/plugin-sync.sh` (PostToolUse hook)가 자동 감지해
`claude/plugin/{marketplaces,plugins}.json`(공용, scope:user +
source:github만)에 병합 반영하고 로컬 커밋한다. 사내 전용
(non-github source) 항목은 `claude/plugin/company/`(dotfiles 트리 안이지만
자체 `.git`을 가진 별도 private GHES 레포, `.gitignore`로 public 레포
추적 제외)로 간다 — internal PC에서 최초 1회 `git clone <url>
claude/plugin/company` 필요.

신규 PC: `./claude/plugin/restore.sh` (mode-aware, `--dry-run` 지원).
자세한 설계: `docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md`.
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/functions/claude_help_plugin.bats`
Expected: 4개 테스트 모두 PASS

- [ ] **Step 5: 커밋**

```bash
git add shell-common/functions/ai_tools_help.sh claude/AGENTS.md \
    tests/bats/functions/claude_help_plugin.bats
git commit -m "docs(claude-plugin): add claude-help plugin section + AGENTS.md entry"
```

---

### Task 7: 전체 lint/test 통과 확인 + 수동 스모크 테스트

**Files:** 없음 (검증 전용)

- [ ] **Step 1: 전체 lint**

Run: `mise run lint`
Expected: `ruff` / `mypy` / `shellcheck` / `shfmt -d` 모두 통과 (신규 `.sh` 파일 포함)

- [ ] **Step 2: 전체 테스트**

Run: `mise run test`
Expected: 기존 bats/pytest/golden-rule 스위트 + 이번에 추가한 6개 `.bats`
파일 전부 PASS

- [ ] **Step 3: 실제 세션에서 수동 확인 (자동화 불가 — 실제 `claude` CLI 호출)**

```bash
# 1) 이미 설치돼 있던 아무 플러그인이나 다시 install 실행 (idempotent) —
#    hook이 실제로 걸리는지 확인
claude plugin install understand-anything@understand-anything

# 2) 매니페스트가 채워졌는지 확인
cat claude/plugin/marketplaces.json
cat claude/plugin/plugins.json
git log -1 --format=%s   # "chore(claude-plugin): sync manifest" 기대

# 3) restore.sh dry-run으로 왕복 확인
./claude/plugin/restore.sh --dry-run

# 4) claude-help 확인
claude-help plugin
```

Expected: 실제 설치된 scope:user + source:github 플러그인들이 두 파일에
반영되고, dry-run 출력이 그 내용과 일치하며, `claude-help plugin`이
사용법을 보여준다.

- [ ] **Step 4: 최종 커밋 (수동 확인 중 발견된 수정사항이 있다면)**

수동 확인에서 코드 변경이 필요했다면 해당 파일만 골라 커밋. 변경이 없었다면
이 태스크는 커밋 없이 종료.

---

## Post-Plan: 이슈 등록

이 계획은 `docs/feature/superpowers-plans/2026-07-01-claude-plugin-manifest.md`로
커밋된 뒤, `gh:issue-create` (또는 동등 절차)로 GitHub 이슈를 생성해 이슈
기반으로 구현을 진행한다. 이슈 본문은 이 계획 파일과
`docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md`
(design spec)을 함께 링크한다.
