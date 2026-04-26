# /batch - 대규모 병렬 코드 변경 오케스트레이터

**Claude Code 전용** 내장(built-in) 스킬. 플러그인/마켓플레이스가 아닌 Claude Code 바이너리에 포함되어 있어 파일시스템에 별도의 `SKILL.md`가 존재하지 않는다. `EnterPlanMode`, `ExitPlanMode`, `AskUserQuestion`, `Agent` 등 Claude Code 런타임 도구에 의존하므로 Codex 등 다른 코딩 에이전트에서는 동작하지 않는다.

대규모 기계적 변경(마이그레이션, 리팩터링, 일괄 rename 등)을 5~30개의 독립된 worktree agent로 분해하여 병렬 실행하고, 각각 PR 생성을 시도한다.

## 주의: 이 dotfiles repo에서는 동작하지 않음

이 repo는 `.gitattributes`에서 `.env` / `.secrets/**`를 git-crypt 필터에 매핑하고
로컬 git config에 `filter.git-crypt.required=true`를 두고 있다. `/batch`는 각 워커를
`Agent({ isolation: "worktree" })`로 띄우는데, harness가 `git worktree add`를 호출할 때
git-crypt 필터 우회 플래그를 주지 않으므로 모든 워커가
`fatal: .env: smudge filter git-crypt failed`로 종료된다.

**대안**:

- **Sequential 인라인 실행** — 메인 워크스페이스에서 작업을 순차 진행 (단위 수가 적을 때)
- **수동 worktree 부트스트랩** — `gwt` 또는 `ai-worktree:spawn` 스킬로 worktree를 먼저
  만들고(git-crypt 필터 우회를 자동 처리), 그 안에서
  isolation 없는 `Agent`를 디스패치
- 추적 이슈: [#153](https://github.com/dEitY719/dotfiles/issues/153)
- 상세: `docs/learnings/git-crypt-worktree-bootstrap.md`

## 동작 요약

| Phase | 이름 | 모드 | 핵심 동작 |
| ----- | ---- | ---- | --------- |
| 1 | Research and Plan | Plan Mode | Explore agent로 코드베이스 조사 후 5~30개 작업 단위로 분해, e2e 테스트 레시피 결정 |
| 2 | Spawn Workers | Execution | 작업 단위별 background agent를 worktree isolation으로 병렬 실행 |
| 3 | Track Progress | Monitoring | 상태 테이블 렌더링, 완료/실패 추적, PR 링크 수집 |

## Phase 1: Research and Plan (리서치 & 계획)

Plan Mode(`EnterPlanMode` tool)로 진입하여 다음을 수행한다.

### 1. 범위 파악

Explore agent를 **foreground**로 실행하여 변경 대상 파일, 패턴, 호출 위치를 전수 조사한다. 기존 코드 컨벤션도 파악하여 마이그레이션 일관성을 확보한다.

### 2. 독립 작업 단위 분해

작업을 5~30개 단위로 분해한다. 각 단위의 요건:

| 요건 | 설명 |
| ---- | ---- |
| 독립 구현 가능 | 격리된 git worktree에서 다른 단위와 상태 공유 없이 구현 가능 |
| 독립 병합 가능 | 다른 단위의 PR이 먼저 머지되지 않아도 단독 병합 가능 |
| 균일한 크기 | 큰 단위는 분할, 사소한 단위는 병합하여 크기를 균등하게 유지 |

단위 수 결정 기준: 파일이 적으면 5개에 가깝게, 수백 개면 30개에 가깝게 조절한다. 임의의 파일 리스트보다 **디렉토리/모듈 단위** 분할을 선호한다.

### 3. E2E 테스트 레시피 결정

워커가 자율적으로 실행할 수 있는 end-to-end 검증 방법을 결정한다. 탐색 우선순위:

1. `claude-in-chrome` skill / 브라우저 자동화 (UI 변경)
2. `tmux` / CLI-verifier skill (CLI 변경)
3. dev-server + curl 패턴 (API 변경)
4. 기존 e2e/integration 테스트 스위트

구체적인 e2e 경로를 찾지 못하면 `AskUserQuestion` tool로 사용자에게 직접 질문한다. 2~3개 옵션을 제시하며, **절대 건너뛰지 않는다** -- 워커는 사용자에게 질문할 수 없기 때문이다.

### 4. 계획 문서 작성

계획 파일에 포함되는 내용:

- 리서치 요약
- 번호 매긴 작업 단위 목록 (제목, 대상 파일/디렉토리, 변경 설명)
- e2e 테스트 레시피 (또는 "skip e2e because ..." 사유)
- 워커에게 전달할 공통 지시사항 템플릿

작성 완료 후 `ExitPlanMode`를 호출하여 사용자 승인을 요청한다.

## Phase 2: Spawn Workers (워커 생성)

사용자가 계획을 승인하면 작업 단위당 1개의 background agent를 생성한다.

### 실행 조건

- 모든 agent는 `isolation: "worktree"`, `run_in_background: true`로 실행
- **단일 메시지 블록**에서 전부 launch하여 병렬 실행
- `subagent_type: "general-purpose"` 기본 사용 (더 적합한 타입이 있으면 변경)

### 워커 프롬프트 구성

각 agent 프롬프트는 **완전히 자기 완결적(self-contained)**이어야 한다. 포함 항목:

| 항목 | 설명 |
| ---- | ---- |
| 전체 목표 | 사용자의 원본 instruction |
| 개별 작업 | 제목, 파일 목록, 변경 설명 (계획에서 그대로 복사) |
| 코드베이스 컨벤션 | Phase 1에서 발견한 스타일/패턴 규칙 |
| e2e 테스트 레시피 | 계획의 레시피 또는 skip 사유 |
| 후처리 지시사항 | 아래 Worker 지시사항 템플릿 그대로 복사 |

## Phase 3: Track Progress (진행 추적)

### 초기 상태 테이블

모든 워커 launch 직후 상태 테이블을 렌더링한다.

```
| # | Unit    | Status  | PR |
|---|---------|---------|-----|
| 1 | <title> | running | —  |
| 2 | <title> | running | —  |
```

### 완료 추적

background agent 완료 알림이 도착하면:

1. 각 agent 결과에서 `PR: <url>` 라인을 파싱
2. 상태를 `done` / `failed`로 업데이트
3. PR 링크 반영, 실패 시 간략한 사유 기록
4. 테이블 재렌더링

### 최종 보고

모든 agent 완료 시 최종 테이블과 한 줄 요약을 출력한다. 예: `"22/24 units landed as PRs"`.

## Worker 지시사항 템플릿

각 워커가 구현 완료 후 수행하는 5단계 후처리 절차:

| 단계 | 작업 | 설명 |
| ---- | ---- | ---- |
| 1 | Simplify | `/simplify` skill을 호출하여 변경사항 리뷰 및 정리 |
| 2 | Unit Test | 프로젝트 테스트 스위트 실행 (`npm test`, `pytest`, `go test` 등). 실패 시 수정 |
| 3 | E2E Test | coordinator가 제공한 e2e 레시피 실행. skip 지시가 있으면 건너뜀 |
| 4 | Commit & Push | 명확한 메시지로 commit, push, `gh pr create`로 PR 생성 시도 |
| 5 | Report | 마지막 줄에 `PR: <url>` 출력. PR 미생성 시 `PR: none — <reason>` |

## 전제 조건

| 조건 | 필수 여부 | 설명 |
| ---- | --------- | ---- |
| Git repository | 필수 | worktree isolation과 PR 생성을 위해 git repo 내에서 실행해야 함 |
| `gh` CLI | 권장 | PR 생성에 사용. 없으면 워커가 `PR: none`으로 보고 |
| Argument 제공 | 필수 | instruction 없이 호출하면 예시와 함께 안내 메시지 출력 |

## 사용 예시

```
/batch migrate from react to vue
/batch replace all uses of lodash with native equivalents
/batch add type annotations to all untyped function parameters
```

## 특징

- **사용자 전용 호출**: `disableModelInvocation: true`로 설정되어 있어 Claude가 자동으로 트리거할 수 없고, 사용자가 `/batch`로 직접 호출해야 한다.
- **Worktree Isolation**: 각 워커가 독립된 git worktree에서 실행되어 워커 간 충돌이 원천 차단된다.
- **Plan Mode 활용**: Phase 1에서 `EnterPlanMode`/`ExitPlanMode`를 사용하여 실행 전 사용자 승인을 받는 게이트를 둔다.
- **E2E 검증 강제**: e2e 테스트 경로를 찾지 못하면 사용자에게 질문하며 절대 건너뛰지 않는다. 워커는 사용자와 대화할 수 없으므로 coordinator가 사전에 확보해야 한다.
- **Self-contained 프롬프트**: 워커 프롬프트가 완전히 자기 완결적이어서 coordinator 컨텍스트 없이도 독립 실행 가능하다.
- **`/simplify` 연계**: 모든 워커가 구현 후 `/simplify` skill을 호출하여 코드 품질을 자동 검수한다.
- **실패 내성**: 일부 워커가 실패해도 나머지는 정상 진행되며, 최종 보고에서 성공/실패 비율을 한눈에 확인할 수 있다.
