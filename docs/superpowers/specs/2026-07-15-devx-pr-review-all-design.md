---
status: draft
date: 2026-07-15
topic: devx:pr-review-all
related_issue: 1160
supersedes: none
---

# devx:pr-review-all — Design Spec

## 1. Purpose

특정 PR 하나에 대해 **사용 가능한 모든 리뷰어를 병렬로 fan-out** 하고,
리뷰 코멘트에 대한 답변 패스까지 이어주는 단일 composition 스킬.

- 단독 실행: `/devx:pr-review-all <PR#>` — PR 을 한 번에 다각도 리뷰 + 답변.
- 재사용: `gh:issue-flow` 의 post-PR quality gate(기존 Step 2.3.1/2.3.2/2.3.3 +
  2.4)를 이 스킬 호출 하나로 대체(위임)해 로직 SSOT 화.

기존 `gh:pr-review`(단일 AI 위임, 1개 코멘트)와는 다르다 — 이 스킬은 **여러
리뷰어 + simplify + reply** 를 오케스트레이션하는 상위 composition 이다.

## 2. Interface

```
/devx:pr-review-all <PR#> [remote]
    [--defer-reply M]      # pr-reply 를 인라인 대신 devx:schedule --time M(분)로 예약
    [--no-reply]           # pr-reply 단계 자체를 건너뜀
    -h | --help | help
```

| 인자/플래그 | 설명 | 기본값 |
|---|---|---|
| `<PR#>` | 대상 PR 번호(양의 정수) | — |
| `[remote]` | git remote | `origin` |
| `--defer-reply M` | pr-reply 를 M분 뒤 예약(인라인 대신) | off(=인라인) |
| `--no-reply` | pr-reply 단계 생략 | off |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

## 3. Steps

### Step 1 — Parse args + resolve target
`<PR#>`/`remote`/플래그 파싱. `START_TS=$(date +%s)` 기록.
`--defer-reply` 와 `--no-reply` 동시 지정 시 `--no-reply` 우선(reply 생략).

### Step 2 — Pre-flight
- PR 존재 & 상태 `OPEN` & non-draft (아니면 exit 1).
- `gh auth status` 0.
- **simplify 브랜치 컨텍스트 확보**: 현재 브랜치가 PR 의 head 브랜치가 아니면
  `gh pr checkout <PR#>`. 이미 해당 브랜치(예: worktree 안 issue-flow 위임
  경로)면 skip. (근거: 아래 §5 함정 1)

### Step 3 — Parallel review gate (한 턴에 Agent 서브에이전트 동시 dispatch)
세 작업은 독립적 → **한 턴에 3개 Agent 병렬 dispatch**, 각각 soft-fail:

- **3A. gemini** — `command -v gemini` 있으면 Agent 가
  `Skill(gh:pr-review, "--ai gemini <PR#>")` 실행(리뷰 스트리밍 + PR 코멘트
  동기 게시). 없으면 SKIP.
- **3B. codex** — `command -v codex` 있으면 Agent 가
  `Skill(gh:pr-review, "--ai codex <PR#>")` 실행. 없으면 SKIP.
- **3C. /simplify** — Agent 가 built-in `/simplify` 를 **워킹트리/브랜치 diff**
  대상으로 실행(PR# 인자는 무시될 수 있음 — §5 함정 1).

**Soft-fail 규칙**: CLI 부재 / 일시 오류 / rate-limit(gh:pr-review non-zero
exit) → 해당 작업만 `[SKIP]`/`[WARN]`, 전체는 계속. gemini·codex 모두
불가여도 simplify 는 진행.

### Step 4 — Commit + push simplify 변경 (변경 있을 때만)
Step 3 의 세 Agent 를 **모두 await** 한 뒤:
- `git status --porcelain` 비어있지 않으면 →
  `git commit -m "refactor(<scope>): simplify per /simplify"` + `git push`.
  **절대 bare `git commit` 금지**(비대화형 hang 방지, `-m` 필수).
- 깨끗하면 skip.

### Step 5 — pr-reply (기본 인라인)
- 기본(플래그 없음) → **인라인** `Skill(gh:pr-reply, "<PR#>")` 를 즉시 실행.
  Step 3 을 await 했으므로 gemini/codex 코멘트 게시가 보장된 상태 → 답변 순서
  100% 보장(§4 근거).
- `--defer-reply M` → 인라인 대신 `Skill(devx:schedule, "--time M
  \"/gh-pr-reply <PR#>\"")` 로 예약.
- `--no-reply` → 생략.

### Step 6 — Report
`[OK]`/`[SKIP]`/`[WARN]` 구조화 한 줄. 예:
`[OK] PR #<N> reviewed (gemini:OK codex:SKIP simplify:committed) — reply: inline`

## 4. Ordering guarantee (왜 delay 가 필요 없나)

pr-reply 가 gemini/codex 코멘트를 확실히 보게 하는 방법은 "고정 delay" 가
아니라 **동기 게이트 + 인라인 실행**이다.

- gemini/codex 는 `gh:pr-review` **CLI** 호출 — 로컬 리뷰 후 `gh pr comment`
  로 리턴 전 **동기 게시**. Step 3 의 Agent 를 모두 await 하면 리턴 시점에
  코멘트 게시가 완료돼 있다.
- 그 직후 인라인 pr-reply → delay 불필요, 순서 결정적(deterministic).
- Caveat 1: GitHub 최종 일관성 — 같은 인증 컨텍스트 read-after-write 라 사실상
  즉시(초 단위). 위험 낮음. (버퍼가 필요해도 `devx:schedule` 은 분 단위라
  인라인이 오히려 정밀.)
- Caveat 2: 범위 한정 — 이 보장은 우리가 동기로 돌리는 **3개 CLI 리뷰**에
  대한 것. webhook 기반 비동기 GitHub App 봇 리뷰어까지 답변 대상이라면
  `--defer-reply M` 로만 커버됨(현 요구사항 범위 밖).

## 5. Known traps (구현 시 필수 반영)

1. **built-in `/simplify` 는 PR# 인자를 무시**하고 워킹트리 기준으로 동작.
   단독 호출 시 Step 2 에서 PR head 브랜치 checkout 선행 필수. 안 하면 엉뚱한
   트리에 simplify 가 적용됨.
2. **Stop-hook 가드 연동** — `gh_issue_flow_stop_guard.py` 는 issue-flow 의
   OUTER sub-skill 체인 개수(현재 5~6개)를 카운트. 게이트+schedule 을 1개
   위임 호출로 접으면 기대 체인 구성/마커 순서가 바뀐다 →
   `critical-contract.md` + `report-template.md` + `constraints.md` +
   가드의 EXPECTED_CHAIN 을 **lockstep 으로** 갱신해야 함. zero-prose 계약 유지.
3. `gh:pr-review` 가 이미 `command -v`/OPEN/draft pre-flight 함 → hard-fail
   중복 금지, 반드시 soft 로 래핑.
4. `devx:schedule` 은 **분 단위**(초 미지원). "500초" 요구는 `--defer-reply 8`
   (≈480초)로 매핑.
5. 이모지 금지, ux_lib 스타일 구조화 출력, 한국어 친화.
6. simplify 커밋+push(Step 4)는 스킬 리턴 전 **동기** 실행 → issue-flow 위임
   경로에서 이후 rebase(2.5/2.5.1) 전에 dirty tree 가 남지 않도록 보장.

## 6. gh:issue-flow refactor

- 기존 인라인 **Step 2.3.1/2.3.2/2.3.3 게이트 + Step 2.4 schedule** →
  단일 `Skill(devx:pr-review-all, "<PR_NUM> <remote> --defer-reply 8")` 로 대체.
  - gemini 리뷰가 게이트에 자연 추가됨(요구사항 핵심).
  - pr-reply 지연 5분 → **8분**으로 통일(신규 스킬 기본 위임값).
- 위임 시 `--defer-reply 8` 사용(단독 실행의 인라인과 달리, issue-flow 는
  기존 #333/#383 early-stop 가드와의 분리 동작을 유지하고 flow 턴을 짧게 둠).
- §5 함정 2 의 가드/문서 lockstep 갱신이 이 리팩터의 핵심 리스크.

## 7. Deliverables / test

- 신규: `claude/skills/devx-pr-review-all/SKILL.md` (+ `references/` 분할,
  100줄 목표).
- 수정: `gh:issue-flow` SKILL.md + `references/{quality-gate-step,
  critical-contract,report-template,constraints,help}.md` +
  `gh_issue_flow_stop_guard.py`(EXPECTED_CHAIN).
- 테스트: 기존 스킬 테스트 패턴 미러링(bats/pytest) — 파싱, soft-fail skip,
  인라인 vs defer 분기, simplify 커밋 조건.
- `mise run lint` / `mise run test` 통과.

## 8. Out of scope

- `skill_completion_guard.py` 의 boundary 정규식 버그(`\b` → `(?![\w-])`)는
  **별도 이슈**로 처리(이 세션 언블록용으로 main 워크트리에 임시 패치됨,
  현 feature 와 무관).
- approve / request-changes 결정(= `gh:pr-approve` 몫)은 이 스킬 범위 밖.
