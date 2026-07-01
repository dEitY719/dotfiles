# Claude Code Plugin Manifest — Design

Origin: [Discussion #1042](https://github.com/dEitY719/dotfiles/discussions/1042) (Understand-Anything 플러그인 설치 세션에서 파생)

## Overview

`claude plugin install` / `claude plugin marketplace add`로 설치한 Claude Code
플러그인은 지금 `~/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json`
에만 존재한다 — dotfiles git 레포와 무관한 머신 로컬 상태다. 신규 PC에서 WSL을
새로 깔고 dotfiles를 세팅해도 이 플러그인 목록은 복원되지 않고, 사용자가 그동안
뭘 설치했는지 기억해서 하나씩 재설치해야 한다.

이 기능은 두 가지를 만든다:
1. **자동 기록** — Claude Code PostToolUse hook이 `claude plugin` 설치/제거
   명령을 감지해 dotfiles git에 manifest 파일로 자동 반영·커밋한다.
2. **일괄 복원** — 신규 PC에서 `claude/plugin/restore.sh` 한 번 실행으로 그
   manifest에 있는 마켓플레이스+플러그인을 모두 재설치한다.

## Goals

- 새 PC에서 `restore.sh` 실행 한 번으로 이전에 설치했던 (scope:user) 플러그인이
  전부 재설치된다.
- 평소 `claude plugin install / uninstall / marketplace add / remove`를
  실행하는 것 외에 사용자가 추가로 신경 쓸 일이 없다 (기록은 hook이 알아서 함).
- 사외(external/public) PC와 사내(internal) PC를 구분해서, 사내 전용
  마켓플레이스가 공개 dotfiles 레포로 유출되지 않는다.

## Non-Goals

- **scope:project / scope:local 플러그인** — 특정 프로젝트 경로에 종속되므로
  새 PC 부트스트랩의 대상이 아니다. hook은 이런 설치도 감지하지만 필터링되어
  manifest에는 반영되지 않는다 (조용한 no-op).
- **source:directory 마켓플레이스** (예: `gitkraken` → 로컬 경로) — 재현
  불가능한 머신 로컬 리소스이므로 manifest에서 제외한다.
- **버전 고정(pinning)** — 항상 최신 버전을 설치한다. 특정 버전 고정은 범위 밖.
- **자동 push** — hook은 로컬 커밋까지만 하고 원격에는 올리지 않는다 (아래
  "브랜치/커밋 정책" 참조).
- **`claude plugin update`** — 버전 업데이트는 manifest에 반영하지 않는다
  (설치 목록 자체는 안 바뀌므로).

## Architecture

```
Claude Code 세션 (Bash 도구로 claude plugin ... 실행, 어느 프로젝트에서든 — hook은 전역)
        │
        ▼
  PostToolUse hook: claude/hooks/plugin-sync.sh
        │  1) tool_call이 claude plugin {install,uninstall} /
        │     claude plugin marketplace {add,remove} 패턴에 매칭되는지 확인
        │  2) ~/.claude-shared/plugins/{known_marketplaces,installed_plugins}.json
        │     을 읽어 scope:user만, source 종류별로 분류
        │       - source: "github"        → 공용 (어디서든 설치 가능)
        │       - source: 그 외(git URL 등) → 사내 전용
        │       - source: "directory"      → 제외
        │  3) install/marketplace add  → 기존 manifest에 병합(union)
        │     uninstall/marketplace remove → 명령 인자로 지정된 항목만 정확히 제거
        │  4) 공용 → $HOME/dotfiles/claude/plugin/*.json (public repo, 즉시 로컬 커밋)
        │     사내 → $HOME/dotfiles/claude/plugin/company/*.json
        │            (dotfiles 트리 안이지만 별도 private git 레포, 즉시 로컬 커밋)
        ▼
  git history (public dotfiles 레포 + claude/plugin/company/ 안의 private 레포,
               서로 완전히 다른 git — 각각 별도 커밋)

신규 PC:
  git clone dotfiles && cd dotfiles
  (internal PC라면 최초 1회만) git clone <사내 GHES private repo> claude/plugin/company
  ./claude/plugin/restore.sh   ← 수동 1회 실행
        │  공용 manifest는 항상 복원
        │  ~/.dotfiles-setup-mode == internal 이고 claude/plugin/company/ 가
        │    (위 clone으로) 준비돼 있으면 그것도 추가로 복원
        ▼
  플러그인 재설치 완료 (external: 공용만 / internal: 공용+사내전용)
```

## 파일 포맷 & 저장 위치

**공용 (public, `dotfiles/claude/plugin/`, git 커밋됨):**

```
claude/plugin/
├── marketplaces.json   # { "<marketplace-name>": "<owner>/<repo>", ... }  (source:github만)
├── plugins.json         # { "plugins": ["<plugin>@<marketplace>", ...] }   (scope:user + source:github만)
└── restore.sh
```

**사내 전용 (private, `dotfiles/claude/plugin/company/`, dotfiles 트리 안이지만
독립된 별도 git 레포):**

```
claude/plugin/company/    # 자체 .git — public dotfiles 레포와 완전히 다른 remote
├── marketplaces.json      # { "<marketplace-name>": "<repo-or-url>", ... }  (source:github가 아닌 것)
└── plugins.json            # { "plugins": [...] }
```

**왜 nested-but-separate 레포인가**: `$COMPANY_SKILLS_HOME`
(`scripts/setup-company-skills.sh`가 쓰는 사내 스킬 오버레이용 프라이빗 레포)를
재사용하려 했으나, 실제로는 어느 PC에도 설정돼 있지 않음이 확인됐다 (문서화만
되고 실사용은 안 된 인프라). 대신 이 레포는 GHES에 **새로 만드는 private
레포**이고, dotfiles 작업 트리 안 `claude/plugin/company/` 경로에 바로
clone해서 쓴다 — 경로가 dotfiles 서브디렉토리처럼 보이지만 자체 `.git`을 가진
완전히 별개의 저장소다 (submodule 아님, 그냥 나란히 존재).

- **public dotfiles의 `.gitignore`에 `/claude/plugin/company/` 추가** — 기존
  `/company-skills/` 라인과 동일한 목적(우발적 커밋 방지). public 레포 git은
  이 디렉토리 존재 자체를 추적하지 않는다.
- **최초 설정은 사용자가 수동 1회**: 사내 PC에서 GHES에 private 레포를 만들고
  `git clone <url> claude/plugin/company` 실행. 이후부터는 hook/restore.sh가
  완전 자동으로 그 레포에 커밋/복원한다 — `claude/settings.local.json`(사내
  게이트웨이 env 블록)과 같은 급의 "PC당 1회 수동 부트스트랩" 항목이다.
- hook은 `claude/plugin/company/.git`이 없으면(아직 clone 안 한 새 PC) 사내
  분류 결과가 있어도 그냥 skip한다 — 커밋할 레포 자체가 없기 때문.

> **분류 가정 (구현 시 검증 필요)**: `claude plugin marketplace add <owner>/<repo>`
> 축약형은 항상 github.com을 가리키고, GHES 등 사내 호스트는 반드시 전체 git URL
> 형태로 추가해야 한다는 가정 하에 `source.source == "github"` 를 분류 기준으로
> 삼았다. 실제 사내 마켓플레이스를 처음 추가할 때 `known_marketplaces.json`에
> 기록되는 `source.source` 값을 확인해 이 가정이 맞는지 검증한다.

## claude-help 통합

`shell-common/functions/ai_tools_help.sh`의 기존 섹션 패턴(`mcp` / `recommended`
/ `setup` / `sandbox` / `config` / `statusline` / `skills`)에 `plugin` 섹션을
추가한다.

- `_claude_help_rows_plugin()` 신설:
  - `claude plugin marketplace add/remove, install/uninstall` → 자동으로
    `claude/plugin/*.json`에 동기화됨 (hook)
  - `./claude/plugin/restore.sh` → 신규 PC에서 manifest 기반 일괄 재설치
  - `./claude/plugin/restore.sh --dry-run` → 실행 없이 계획만 출력
- `_claude_help_summary`, `_claude_help_list_sections`,
  `_claude_help_section_rows`, `_claude_help_full`에 `plugin` 섹션 등록
- `claude-help plugin`으로 상세 조회

## 동기화 hook (`claude/hooks/plugin-sync.sh`)

기존 `claude/hooks/post-gh-pr-create.sh`와 동일한 뼈대(stdin JSON → jq 파싱 →
조건 안 맞으면 조용히 `exit 0`, 항상 `exit 0`으로 세션 흐름을 막지 않음)를
따른다. `PostToolUse` / matcher `Bash`로 `claude/settings.json`에 등록 —
user-level 설정이라 모든 프로젝트/세션에서 전역으로 동작한다.

**핵심 알고리즘:**

1. `tool_name == "Bash"`이고 `tool_input.command`가
   `claude plugin (install|uninstall|marketplace (add|remove))` 패턴에
   매칭되지 않으면 즉시 `exit 0`.
2. `install` / `marketplace add`:
   - `~/.claude-shared/plugins/known_marketplaces.json` +
     `installed_plugins.json`을 다시 읽어 scope:user + source 분류(공용/사내/제외)
     상태를 계산한다.
   - **덮어쓰기가 아니라 병합(union)** — 기존 manifest 파일 내용과 방금 읽은
     로컬 상태를 합친다 (기존 키 유지 + 신규/변경 키 추가). 로컬에 없다고
     기존 항목을 지우지 않는다.
   - *왜 병합인가*: 이 manifest는 여러 PC(external/internal 각 2대, public
     2대)가 공유한다. 전체 덮어쓰기 방식이면, 예를 들어 internal PC가 아직
     어떤 공용 플러그인을 설치하지 않은 상태에서 hook이 돌 때 "로컬에 없으니
     지운다"가 되어, external PC가 이미 기록해둔 항목을 internal PC가 지워버리는
     사고가 난다. 병합 방식이면 설치는 어느 PC에서 하든 누적된다.
3. `uninstall` / `marketplace remove`:
   - 명령 인자로 지정된 대상만 정확히 파싱해 manifest에서 **그 항목만 제거**
     (전체 재계산 아님 — 다른 PC의 항목에 영향 없음).
4. 결과를 공용/사내 경로에 각각 쓰고, 각 레포(`$HOME/dotfiles`,
   `$HOME/dotfiles/claude/plugin/company`)에서 diff가 있을 때만 `git add` +
   `git commit` (메시지: `chore(claude-plugin): sync manifest`). 사내 레포는
   `claude/plugin/company/.git`이 있을 때만 시도 — 없으면(아직 clone 전) 조용히
   skip.

**브랜치/커밋 정책**: 커밋 대상은 항상 `$HOME/dotfiles` (canonical main
체크아웃) 고정 — 현재 세션의 `$DOTFILES_ROOT`나 cwd는 사용하지 않는다
(worktree에서 세션을 띄우는 게 일상적이라, 그 worktree의 브랜치가 아니라
canonical 경로를 직접 타겟해야 항상 main에 쌓인다). **push는 하지 않는다** —
이 레포의 `git/hooks/pre-push`가 `main`을 `PROTECTED_BRANCHES`로 막고 있어서
(레포 소유자 본인 포함), 자동 push를 넣으면 매번 실패하거나 그 가드를 우회해야
한다. 로컬 커밋은 되돌리기 쉽고 눈에 보이지만, push는 공유 상태라 되돌리기
번거로우므로 push 여부/시점은 사용자가 직접 결정한다.

## 복원 스크립트 (`claude/plugin/restore.sh`)

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v claude >/dev/null 2>&1 || { echo "claude CLI가 없습니다. 먼저 clinstall 하세요." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq가 필요합니다." >&2; exit 1; }

_restore_from() {
    local mp_json="$1" pl_json="$2" label="$3"
    [ -f "$mp_json" ] && [ -f "$pl_json" ] || { echo "  ($label manifest 없음 — 건너뜀)"; return 0; }
    echo "== $label marketplaces =="
    jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$mp_json" |
    while IFS=$'\t' read -r name repo; do
        echo "  add: $name ($repo)"
        [ "$DRY_RUN" = 1 ] || claude plugin marketplace add "$repo" || echo "    실패 — 계속 진행" >&2
    done
    echo "== $label plugins =="
    jq -r '.plugins[]' "$pl_json" |
    while read -r plugin; do
        echo "  install: $plugin"
        [ "$DRY_RUN" = 1 ] || claude plugin install "$plugin" || echo "    실패 — 계속 진행" >&2
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
```

- 항목 하나가 실패해도(네트워크/SSH 인증 등) 나머지는 계속 진행
- `--dry-run`으로 실제 설치 없이 계획만 확인 가능
- idempotent — 이미 설치된 항목에 다시 실행해도 `claude` CLI가 no-op/에러만
  내고 스크립트는 계속 진행
- `setup.sh` / `install.sh`에는 통합하지 않는다 — 마켓플레이스 clone은
  네트워크 작업이라 사용자가 타이밍을 보고 직접 실행하는 게 안전

## 에러 처리 · 엣지 케이스

| 상황 | 처리 |
|---|---|
| `jq` 미설치 | hook: 조용히 skip. restore.sh: 에러 메시지 후 종료 |
| `~/.claude-shared/plugins/*.json` 없음 | hook: exit 0 |
| `$HOME/dotfiles`(canonical) 없음 | hook: exit 0 |
| `claude/plugin/company/.git` 없음 (external/public PC이거나, internal인데 아직 clone 전) | 사내 분류 결과가 있어도 조용히 skip. external/public에서는 애초에 네트워크상 사내 마켓플레이스를 설치할 수 없어 발생 안 함 — internal PC는 최초 1회 clone 필요 |
| manifest 변경 없음 | `git diff --quiet` → 커밋 안 함 |
| scope:project/local 플러그인 설치 | 필터링되어 manifest에 반영 안 됨 (조용한 no-op) |
| restore.sh 중 특정 항목 실패 (SSH 키 없음 등) | 경고 출력 후 나머지 계속 진행 |

## 테스트 계획

- **hook**: 가짜 PostToolUse JSON(`claude plugin install foo@bar` 커맨드)을
  stdin으로 주입, `~/.claude-shared/plugins/*.json`을 테스트 fixture로 미리
  채워 `claude/plugin/*.json`이 병합 규칙대로 갱신되는지 검증 (실제 `claude`
  CLI/네트워크 호출 없음). 병합 케이스(기존 항목 유지)와 삭제 케이스(대상만
  제거) 둘 다 커버.
- **restore.sh**: `--dry-run`으로 실행해 출력이 manifest 내용과 일치하는지
  검증 (실제 설치 없음).

## Open Questions

- ~~`source.source == "github"` 축약형이 항상 github.com만 가리킨다는 가정 —
  실제 사내 마켓플레이스를 처음 추가할 때 검증 필요 (위 "분류 가정" 참조).~~
  **검증 완료 (2026-07-02)**: 사내 GHES에서 `claude plugin marketplace add
  https://github.samsungds.net/<owner>/<repo>.git`(전체 git URL)로 추가한
  실제 마켓플레이스의 `known_marketplaces.json` 항목은
  `source.source == "git"`로 기록됨(`"github"`도 `"directory"`도 아님) —
  가정대로 사내 전용(`mp_internal`) 분류로 정확히 떨어진다. 유출 위험 없음.
