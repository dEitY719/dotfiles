# Design: 글로벌 CLAUDE.md 신설 + Advisor/Worker 모델 역할 분담 섹션

- Issue: #1115
- Date: 2026-07-06
- Status: approved (brainstorming 세션에서 사용자 승인)

## 배경

동료가 공유한 "Advisor(메인 세션) / Worker(opus 서브에이전트) 역할 분담" 프롬프트를
CLAUDE.md에 추가하자는 제안. 이슈 원안의 대상은 repo root `CLAUDE.md`였으나,
brainstorming 중 사용자가 대상을 **글로벌 `~/.claude/CLAUDE.md`** (계정별
`$CLAUDE_CONFIG_DIR/CLAUDE.md`)로 변경했다. 특정 저장소가 아니라 모든 프로젝트
세션에 적용하려는 의도다.

현재 이 저장소는 글로벌 CLAUDE.md를 관리하지 않는다 — `claude/setup.sh`의 배포
대상(statusline, docs, plugins, global-memory, workflows, skills, settings.json)에
CLAUDE.md는 없고, 어느 계정 디렉토리에도 파일이 존재하지 않는다. 따라서 이 작업은
문서 한 줄 추가가 아니라 **새 SSOT 파일 + 배포 경로 신설**이다.

## 결정 사항 (brainstorming 합의)

| 결정 | 선택 |
|---|---|
| 도입 형태 | 슬림 섹션(~15줄) + 스코프 한정. 원문 재구성 |
| 대상 파일 | 글로벌 CLAUDE.md (repo root CLAUDE.md 아님) |
| 반복 단위 | 브리프 1건 = 완료 기준 달성까지. Worker가 TDD 루프 포함 반복을 자체 소화 |
| 위임 기준 | 구체적 휴리스틱 명시 (다중 파일·신규 기능·테스트 반복 → 위임 / 한두 파일 소규모·설정·문서 → 직접) |
| 모델 표기 | "메인 세션(Advisor)" / "opus 서브에이전트(Worker)"로 일반화. 세대명 미사용 |
| 배포 방식 | repo SSOT `claude/CLAUDE.md` + 계정별 심볼릭 링크 (statusline/docs/workflows 동일 패턴) |

## 이슈 검토 의견 5개 해소

1. **기존 skill 중복** — 섹션 마지막 줄로 관계 명시: 이 섹션은 상시 기본 자세,
   `superpowers:subagent-driven-development`는 plan 실행 시의 구체 절차.
2. **skill 직접-실행 계약 충돌** — "직접 처리" 항목에 예외 명문화: skill이 메인
   세션의 직접 실행을 명시한 단계(git/gh 명령 등)는 항상 직접 실행.
3. **TDD/디버깅 루프 오버헤드** — 브리프 1건당 다중 반복 허용. 매 반복 재위임하지
   않으며, 재위임은 Advisor 검증 실패 시에만.
4. **소규모 작업 정합성** — 위임/직접 휴리스틱을 원문의 "한두 줄"보다 현실적으로
   넓힘: 한두 파일 소규모 수정·설정·문서 변경은 직접 처리.
5. **모델 표기 일반화** — 채택. `model: "opus"` 파라미터 지정만 명시.

## 변경 내용

### 1. 새 파일: `claude/CLAUDE.md` (SSOT)

전 프로젝트 세션에 로드되므로 repo 전용 표현(ux_lib, POSIX 규칙 등)을 쓰지 않는다.

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

### 2. 배포 배선 (심볼릭 링크)

- `shell-common/tools/integrations/claude.sh` → `_claude_account_setup_one`:
  `_claude_ensure_symlink "${DOTFILES_ROOT}/claude/CLAUDE.md" "$_caso_cdir/CLAUDE.md"`
  1줄 추가 (멀티 계정 경로).
- `claude/setup.sh`:
  - SSOT 소스 변수 추가 (`CLAUDE_MD_SOURCE` 등, 기존 네이밍 관례 준수) + 존재 검사.
  - 단일 계정 분기(internal PC mode)에 `_single_account_ensure_link` 1줄 추가.
  - verify-links 목록 2곳(`for link in statusline-command.sh docs plugins
    projects/GLOBAL/memory workflows`)에 `CLAUDE.md` 추가.
- 링크 목록을 열거하는 그 밖의 위치(claude.sh 내 주석·teardown·status 함수,
  bats/셸 테스트)는 구현 계획 단계에서 `projects/GLOBAL/memory` 등으로 grep 전수
  조사 후 동일하게 갱신한다.

### 3. 문서 갱신

- `claude/AGENTS.md` Configuration Files 표에 CLAUDE.md 행 추가
  (symlink, SSOT: `claude/CLAUDE.md`, 용도: 글로벌 지침).
- repo root `CLAUDE.md`는 변경하지 않는다 — 글로벌 파일이 이 repo 세션에도
  로드되므로 중복이 된다.

## 트레이드오프 (수용됨)

`#` 메모리 단축키로 글로벌 메모리를 기록하면 심볼릭 링크를 타고 tracked SSOT가
수정되어 repo가 dirty해진다 (settings.json #924와 같은 경로). settings.json과 달리
글로벌 지침 변경은 드물고 git으로 추적되는 것이 오히려 장점이므로 심볼릭 링크를
선택한다. 문제가 되면 #940 패턴(실파일 복사 + 마이그레이션)으로 후속 전환 가능.

## 검증

- `mise run lint` — shellcheck/shfmt가 setup.sh·claude.sh 변경 검사.
- `mise run test` — 기존 bats/pytest 회귀.
- `claude/setup.sh` 실제 재실행 → `~/.claude-work/CLAUDE.md` 심볼릭 링크 생성 및
  verify-links 통과 확인. 새 Claude 세션에서 글로벌 지침 로드 확인.
