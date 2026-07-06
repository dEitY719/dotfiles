# 글로벌 CLAUDE.md Advisor/Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** repo가 관리하는 글로벌 Claude 지침 SSOT(`claude/CLAUDE.md`, Advisor/Worker 역할 분담 섹션)를 신설하고, 계정별 `$CLAUDE_CONFIG_DIR/CLAUDE.md` 심볼릭 링크로 배포한다 (#1115).

**Architecture:** statusline/docs/workflows와 동일한 SSOT+symlink 패턴. 멀티 계정은 `_claude_account_setup_one`(shell-common/tools/integrations/claude.sh), 단일 계정(internal)은 `claude/setup.sh` 분기가 링크를 만들고, `claude_accounts_repair`가 워크트리 오염 복구를 담당한다. Spec: `docs/superpowers/specs/2026-07-06-global-claude-md-advisor-worker-design.md`.

**Tech Stack:** POSIX shell (bash/zsh 겸용 소싱), bats-core 테스트, mise task runner.

## Global Constraints

- 이모지 금지 (repo 전역 규칙, ai-metrics footer 제외).
- `shell-common/tools/integrations/claude.sh`는 POSIX 호환 유지: `[ ]` 사용, `>/dev/null 2>&1`, 함수 로컬은 `_caso_`/`_car_` 같은 prefix 변수 관례.
- 출력은 ux_lib 함수(`ux_info`, `ux_warning` 등)만 사용 — raw `echo`/`printf` 금지.
- lint/test 실패 시 root cause 수정 — `--no-verify` 금지.
- 커밋 메시지는 semantic commit + 본문 끝 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- bats 실행 전제: `git submodule update --init tests/bats/lib/bats-core tests/bats/lib/bats-assert tests/bats/lib/bats-support` (이 워크트리에는 이미 완료됨).
- **알려진 베이스라인 실패**: `claude_accounts.bats`의 "claude/setup.sh creates ~/.claude-personal/ structure" 등 setup.sh 통합 테스트는 현재도 실패한다 — `setup_isolated_dotfiles_root`가 `claude/workflows`를 스테이징하지 않아 `workflows 디렉토리 없음`으로 종료. Task 4에서 함께 수정한다.
- **이 워크트리에서 실 배포 검증 금지**: `claude/setup.sh`를 실제 HOME에 대고 실행하지 않는다 — 워크트리 경로 오염(#589)을 만든다. 실 배포는 머지 후 메인 체크아웃에서 `./setup.sh` 재실행으로 수행 (Task 5의 후속 안내 참조).

---

### Task 1: SSOT 파일 `claude/CLAUDE.md` 생성

**Files:**
- Create: `claude/CLAUDE.md`

**Interfaces:**
- Consumes: 없음
- Produces: `${DOTFILES_ROOT}/claude/CLAUDE.md` — Task 2~4의 심볼릭 링크 소스 경로. 파일명·경로는 정확히 이것이어야 한다.

- [ ] **Step 1: 파일 작성**

`claude/CLAUDE.md`를 아래 내용 그대로 생성한다 (spec 승인 원문 — 임의 수정 금지):

```markdown
# Global Instructions

## 모델 역할 분담: Advisor / Worker

메인 세션(Advisor)은 판단에 집중하고, 열린 구현 작업(open-ended implementation)은
opus 서브에이전트(Worker)에게 Agent 도구(model: "opus")로 위임한다.

**위임 대상** — 여러 파일에 걸친 수정, 새 기능/모듈 구현, 테스트 반복이 필요한 구현.
서로 독립적인 작업은 병렬로 위임한다.

**직접 처리** — 한두 파일의 소규모 수정, 설정/문서 변경 등 위임 오버헤드가 작업보다 큰 일.
skill이 메인 세션의 직접 실행을 명시한 단계(git/gh 명령 등)는 항상 직접 실행한다.

**브리프 기준** — Worker가 재탐색하지 않도록 이미 파악한 컨텍스트를 담는다: 파일 경로,
프로젝트 컨벤션, 알려진 함정, 완료 기준(통과해야 할 테스트). 브리프 1건 = 완료 기준
달성까지 — Worker는 테스트 작성→구현→통과 반복(TDD 루프 포함)을 브리프 안에서 자체 소화한다.

**검증** — Worker의 완료 보고를 그대로 믿지 않는다. Advisor가 diff 확인과 테스트 실행으로
직접 검증한 뒤 승인하고, 실패 시 수정 브리프로 재위임한다(직접 수정은 사소한 마무리만).

계획 문서 기반 다중 작업 실행 시에는 superpowers:subagent-driven-development가 이 원칙의
구체 절차다.
```

- [ ] **Step 2: 검증 — 존재 + 이모지 금지 규칙**

Run: `[ -f claude/CLAUDE.md ] && echo OK`
Expected: `OK`

Run: `grep -P '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' claude/CLAUDE.md; echo "exit=$?"`
Expected: 매치 없음, `exit=1`

- [ ] **Step 3: Commit**

```bash
git add claude/CLAUDE.md
git commit -m "feat(claude): 글로벌 CLAUDE.md SSOT 신설 — Advisor/Worker 역할 분담 (#1115)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: 멀티 계정 배선 — `_claude_account_setup_one`

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh:902-928` (`_claude_account_setup_one`)
- Test: `tests/bats/integrations/claude_accounts.bats:218-243` (기존 test "bash: _claude_account_setup_one creates directory-level symlinks (issue #575 → #707)")

**Interfaces:**
- Consumes: Task 1의 `${DOTFILES_ROOT}/claude/CLAUDE.md`, 기존 `_claude_ensure_symlink <source> <target>` 헬퍼 (같은 파일에 정의됨)
- Produces: `$_caso_cdir/CLAUDE.md` 심볼릭 링크 — Task 4의 setup.sh verify 목록이 이 링크의 존재를 전제한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/bats/integrations/claude_accounts.bats`의 해당 테스트에서
`[ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]` 줄(현재 line 232) 바로 아래에 추가:

```bash
    # CLAUDE.md is a directory-entry symlink to the global-instructions SSOT (#1115).
    [ -L "$HOME/.claude-personal/CLAUDE.md" ]
    [ "$(readlink "$HOME/.claude-personal/CLAUDE.md")" = "${DOTFILES_ROOT}/claude/CLAUDE.md" ]
```

(이 테스트는 real DOTFILES_ROOT로 도는 테스트라 Task 1에서 만든 SSOT 파일이 그대로 보인다.)

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts.bats -f "_claude_account_setup_one creates"`
Expected: FAIL — `[ -L "$HOME/.claude-personal/CLAUDE.md" ]`에서 실패

- [ ] **Step 3: 구현**

`shell-common/tools/integrations/claude.sh`의 `_claude_account_setup_one` 안,
`_claude_ensure_symlink "${DOTFILES_ROOT}/claude/workflows"` 줄 바로 아래에 추가:

```bash
    # Global instructions (Advisor/Worker) — SSOT symlink, all projects (#1115).
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/CLAUDE.md"              "$_caso_cdir/CLAUDE.md"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts.bats -f "_claude_account_setup_one creates"`
Expected: PASS (1 test, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "feat(claude): 계정별 CLAUDE.md 심볼릭 링크 배선 — 멀티 계정 (#1115)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: 진단·복구 커버리지 — `claude_accounts_status` + `claude_accounts_repair`

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh:1011` (status 링크 루프), `:1340-1356` (repair scope 주석), `:1468-1474` (repair heredoc 페어 목록)
- Test: `tests/bats/integrations/claude_accounts.bats` (status 회귀 테스트 1건 신규, workflows #707 테스트 바로 아래), `tests/bats/integrations/claude_accounts_repair.bats` (setup() line 22-29 + 신규 @test)

**Interfaces:**
- Consumes: Task 2까지의 레이아웃 (`CLAUDE.md`가 well-known symlink 셋의 일원; `claude_accounts_init`은 내부적으로 `_claude_account_setup_one`을 호출하므로 Task 2 이후 CLAUDE.md 링크를 만든다)
- Produces: `claude-accounts status`가 CLAUDE.md 링크 상태를 보고하고, `claude-accounts repair`가 워크트리 오염된 `CLAUDE.md` 링크를 canonical로 재바인딩

참고: `claude_accounts_migrate`의 legacy symlink 해제 목록(line ~1157)은 docs/workflows도 포함하지 않는 기존 관례라 CLAUDE.md도 추가하지 않는다 — 이동된 canonical 링크는 무해하며 후속 setup이 멱등 보정한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/bats/integrations/claude_accounts.bats`의
`@test "bash: claude_accounts_status reports workflows symlink (#707 regression)"` 블록 바로 아래에 신규 테스트 추가:

```bash
@test "bash: claude_accounts_status reports CLAUDE.md symlink (#1115)" {
    # The status loop enumerates the well-known link set by hand; a new
    # link name must be added here or breakage never surfaces at
    # diagnosis time (same failure mode as the #707 workflows omission).
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs" "${DOTFILES_ROOT}/claude/workflows"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_init && CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_status'
    assert_success
    assert_output --partial "CLAUDE.md: symlink ✓"
}
```

이어서 `tests/bats/integrations/claude_accounts_repair.bats`의 `setup()`에서
`ln -s "$FAKE_WT/claude/global-memory" "$PERSONAL/projects/GLOBAL/memory"` 줄 아래에 추가:

```bash
    ln -s "$FAKE_WT/claude/CLAUDE.md"              "$PERSONAL/CLAUDE.md"
```

그리고 `@test "claude_accounts_repair: rebinds nested projects/GLOBAL/memory"` 블록 바로 아래에 신규 테스트 추가:

```bash
@test "claude_accounts_repair: rebinds dangling CLAUDE.md (global instructions, #1115)" {
    run_in_bash 'claude_accounts_repair >/dev/null 2>&1; readlink "$HOME/.claude-personal/CLAUDE.md"'
    assert_success
    assert_output "$DOTFILES_ROOT/claude/CLAUDE.md"
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts_repair.bats -f "CLAUDE.md"`
Expected: FAIL — readlink가 `$FAKE_WT/claude/CLAUDE.md` (fake 경로)를 그대로 출력

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts.bats -f "status reports CLAUDE.md"`
Expected: FAIL — status 출력에 `CLAUDE.md:` 줄이 없음

- [ ] **Step 3: 구현**

`shell-common/tools/integrations/claude.sh`의 `claude_accounts_status` 링크 루프(line ~1011)를:

```bash
        for _cas_link in settings.json settings.local.json statusline-command.sh plugins projects/GLOBAL/memory skills docs workflows CLAUDE.md; do
```

로 변경(목록 끝에 `CLAUDE.md` 추가)하고, 같은 파일의 `claude_accounts_repair` 내부 heredoc(line ~1468)에서
`projects/GLOBAL/memory|${_car_claude_src}/global-memory` 줄 아래(EOF 위)에 추가:

```
CLAUDE.md|${_car_claude_src}/CLAUDE.md
```

같은 함수 상단의 scope 주석(line ~1350)도 실제 heredoc과 일치하도록 갱신
(현행 주석은 workflows도 누락하고 있다 — 함께 바로잡는다):

```bash
# Scope: only touches symlinks whose name matches the well-known set
# created by `_claude_account_setup_one`:
#   settings.json, statusline-command.sh, skills, docs, workflows,
#   projects/GLOBAL/memory, CLAUDE.md
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts_repair.bats`
Expected: 전체 PASS (기존 repair 테스트 포함 회귀 없음)

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts.bats -f "status reports"`
Expected: 전체 PASS (workflows #707 회귀 테스트 포함)

- [ ] **Step 5: Commit**

```bash
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats tests/bats/integrations/claude_accounts_repair.bats
git commit -m "feat(claude): status/repair 진단 경로에 CLAUDE.md 링크 커버리지 추가 (#1115)

repair scope 주석의 workflows 누락도 함께 바로잡음.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `claude/setup.sh` 단일 계정 배선 + verify 목록 + 테스트 헬퍼 수정

**Files:**
- Modify: `claude/setup.sh` (header 주석 ~line 9-15, 변수 ~56-70, 소스 검증 ~514-520, 단일 계정 링크 ~645-653, verify 목록 line 662 및 727)
- Modify: `tests/bats/test_helper.bash:69-97` (`setup_isolated_dotfiles_root`)
- Test: `tests/bats/integrations/claude_accounts.bats:795-822` (기존 setup.sh 통합 테스트 2건)

**Interfaces:**
- Consumes: Task 1의 `claude/CLAUDE.md`, Task 2의 `_claude_account_setup_one` (멀티 계정 루프가 호출), 기존 `_single_account_ensure_link <source> <target>` 헬퍼
- Produces: internal(단일 계정) 모드의 `~/.claude/CLAUDE.md` 심볼릭 링크 + 모든 모드 verify 게이트

- [ ] **Step 1: 테스트 헬퍼의 기존 결함 수정 (베이스라인 복구)**

`tests/bats/test_helper.bash`의 `setup_isolated_dotfiles_root()`에서

```bash
    mkdir -p "$iso_root/claude/skills" "$iso_root/claude/docs" "$iso_root/claude/global-memory"
```

를 다음으로 교체 (workflows 스테이징 누락이 현행 setup.sh 통합 테스트를 깨뜨리고 있다):

```bash
    mkdir -p "$iso_root/claude/skills" "$iso_root/claude/docs" "$iso_root/claude/global-memory" \
        "$iso_root/claude/workflows"
    cp "$real_root/claude/CLAUDE.md" "$iso_root/claude/CLAUDE.md"
```

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/bats/integrations/claude_accounts.bats`에서:

(a) `@test "bash: claude/setup.sh creates ~/.claude-personal/ structure"`의
`[ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]` 줄 아래에 추가:

```bash
    [ -L "$HOME/.claude-personal/CLAUDE.md" ]
```

(b) `@test "bash: claude/setup.sh respects Internal-PC mode via .dotfiles-setup-mode"`의
`[ -L "$HOME/.claude/statusline-command.sh" ]` 줄 아래에 추가:

```bash
    [ -L "$HOME/.claude/CLAUDE.md" ]
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts.bats -f "claude/setup.sh"`
Expected: "Internal-PC mode" 테스트 FAIL — 단일 계정 분기에 CLAUDE.md 링크가 아직 없음.
"creates ~/.claude-personal/ structure" 테스트는 Step 1 헬퍼 수정 + Task 2 배선 덕에 PASS할 수 있음 — 그것은 정상.

- [ ] **Step 4: `claude/setup.sh` 구현**

(a) Home 위치 변수 — `HOME_WORKFLOWS="${HOME_CLAUDE}/workflows"` 줄 아래에 추가:

```bash
HOME_CLAUDE_MD="${HOME_CLAUDE}/CLAUDE.md"
```

(b) 소스 변수 — `CLAUDE_WORKFLOWS_SOURCE="${CLAUDE_DOTFILES}/workflows"` 줄 아래에 추가:

```bash
CLAUDE_MD_SOURCE="${CLAUDE_DOTFILES}/CLAUDE.md"
```

(c) 소스 검증 블록 — `[ -d "$CLAUDE_WORKFLOWS_SOURCE" ] || ...` 줄 아래에 추가:

```bash
[ -f "$CLAUDE_MD_SOURCE" ]            || log_error_and_exit "CLAUDE.md 없음: $CLAUDE_MD_SOURCE"
```

(d) 단일 계정(internal) 분기 — `_single_account_ensure_link "$CLAUDE_WORKFLOWS_SOURCE" "$HOME_WORKFLOWS"` 줄 아래에 추가:

```bash
    _single_account_ensure_link "$CLAUDE_MD_SOURCE"                     "$HOME_CLAUDE_MD"
```

(e) verify-links 목록 2곳 (단일 계정 line ~662, 멀티 계정 line ~727) — 둘 다:

```bash
    for link in statusline-command.sh docs plugins projects/GLOBAL/memory workflows CLAUDE.md; do
```

(f) 파일 header 주석의 SPECIAL INITIALIZATION 목록 — 5번 아래에 삽입, 기존 6번(Verifies)을 7번으로:

```bash
#   6. Creates ~/.claude/CLAUDE.md symlink (global instructions, #1115)
#   7. Verifies ~/.claude directory structure
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/integrations/claude_accounts.bats -f "claude/setup.sh"`
Expected: 전체 PASS ("creates structure", "Internal-PC mode", "idempotent" 포함)

- [ ] **Step 6: shell lint**

Run: `mise run lint-sh`
Expected: shellcheck + shfmt diff 통과 (수정 파일 포함, 실패 시 root cause 수정)

- [ ] **Step 7: Commit**

```bash
git add claude/setup.sh tests/bats/test_helper.bash tests/bats/integrations/claude_accounts.bats
git commit -m "feat(claude): setup.sh 단일 계정 CLAUDE.md 배선 + verify 목록 갱신 (#1115)

setup_isolated_dotfiles_root의 workflows 스테이징 누락(기존 통합 테스트
베이스라인 실패)도 함께 수정.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 문서 갱신 + 전체 검증

**Files:**
- Modify: `claude/AGENTS.md` (Configuration Files 블록, line ~59-79)

**Interfaces:**
- Consumes: Task 1~4의 최종 레이아웃
- Produces: 없음 (문서)

- [ ] **Step 1: `claude/AGENTS.md` Configuration Files 갱신**

외부 PC 블록의 `~/.claude-personal/projects/GLOBAL/memory` 줄 아래에 추가:

```
~/.claude-personal/CLAUDE.md             -> dotfiles/claude/CLAUDE.md       (글로벌 지침, #1115)
```

사내 PC 블록의 `~/.claude/projects/GLOBAL/memory` 줄 아래에 추가:

```
~/.claude/CLAUDE.md                      -> dotfiles/claude/CLAUDE.md       (글로벌 지침, #1115)
```

- [ ] **Step 2: 전체 lint**

Run: `mise run lint`
Expected: ruff + mypy + shellcheck + shfmt 모두 통과

- [ ] **Step 3: 전체 테스트**

Run: `mise run test`
Expected: bats + pytest + golden rules 통과. (이 플랜 이전부터 실패하던 케이스가 남아 있으면 Task 4 Step 1과 무관한지 확인 후 보고 — 새 실패는 root cause 수정.)

- [ ] **Step 4: Commit**

```bash
git add claude/AGENTS.md
git commit -m "docs(claude): AGENTS.md에 CLAUDE.md 글로벌 지침 링크 문서화 (#1115)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 실 배포 후속 안내 (실행 아님 — 보고에 포함)**

이 워크트리에서는 `claude/setup.sh`를 실행하지 않는다 (#589 워크트리 오염).
머지 후 메인 체크아웃(`~/dotfiles` 등)에서:

```bash
./setup.sh
ls -la ~/.claude-work/CLAUDE.md   # -> dotfiles/claude/CLAUDE.md 확인
```

새 Claude 세션에서 글로벌 지침이 로드되는지 확인한다.
