# devx:pr-review-all Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PR 하나에 gemini ∥ codex ∥ `/simplify` 를 병렬 fan-out 하고 pr-reply 까지 이어주는 신규 composition 스킬 `devx:pr-review-all` 을 추가하고, `gh:issue-flow` 의 quality gate 를 이 스킬 위임으로 리팩터한다.

**Architecture:** 순수 오케스트레이션 스킬(SKILL.md + references) + 테스트 가능한 arg-parse 셸 헬퍼(`shell-common/functions/devx_pr_review_all.sh`). 병렬 리뷰는 한 턴 Agent 서브에이전트 동시 dispatch, simplify 는 동기 커밋/푸시, pr-reply 는 기본 인라인(위임 시 `--defer-reply 8`). issue-flow 는 인라인 게이트+schedule 을 단일 `Skill(devx:pr-review-all)` 호출로 대체하고, stop-guard 의 EXPECTED_CHAIN 을 lockstep 갱신한다.

**Tech Stack:** POSIX sh(셸 헬퍼), Markdown(SKILL.md/references), Python(stop-guard), bats(셸 테스트), pytest(가드 테스트), mise(lint/test).

## Global Constraints

- POSIX 호환: `[ ]`(not `[[ ]]`), `>/dev/null 2>&1`(not `&>`), `source "${SHELL_COMMON}/..."` 형식.
- 모든 출력 파일은 인터랙티브 가드로 시작 금지 대상 아님(헬퍼는 함수 정의만; 자동 소스됨).
- 이모지 금지(ai-metrics footer 예외만). 함수/파일명 snake_case, 사용자 alias dash-form.
- SKILL.md 100줄 목표 — 초과분은 references/ 로 분할.
- `--no-verify`/훅 스킵 금지. lint/test 실패는 근본 수정.
- spec: `docs/superpowers/specs/2026-07-15-devx-pr-review-all-design.md`, 추적 이슈 #1160.

---

### Task 1: arg-parse 셸 헬퍼 + bats 테스트

**Files:**
- Create: `shell-common/functions/devx_pr_review_all.sh`
- Test: `tests/bats/functions/devx_pr_review_all.bats`

**Interfaces:**
- Consumes: 없음(순수 파서).
- Produces: `devx_pr_review_all_parse "$@"` — 성공 시 `key=value` 라인 출력(`pr=`, `remote=`, `reply_mode=`, `reply_delay=`), help 요청 시 `help_requested=1`. Exit: `0` ok/help, `2` arg error. (gh_pr_review_parse 규약 미러링: `shell-common/functions/gh_pr_review.sh:23-33`.)
- reply_mode 값: `inline`(기본) | `defer` | `none`. `--no-reply` 는 `--defer-reply` 보다 우선. `reply_delay` 는 defer 일 때만 유효(기본 8, 양의 정수 아니면 exit 2).

- [ ] **Step 1: 실패 테스트 작성** (`tests/bats/functions/devx_pr_review_all.bats`)

```bash
#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all.bats
# Unit tests for devx_pr_review_all_parse (pure arg parser).
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_review_all.sh"
}

@test "pr only -> inline default, remote origin" {
    run devx_pr_review_all_parse 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr=123"* ]]
    [[ "$output" == *"remote=origin"* ]]
    [[ "$output" == *"reply_mode=inline"* ]]
}

@test "pr + remote positional" {
    run devx_pr_review_all_parse 123 upstream
    [ "$status" -eq 0 ]
    [[ "$output" == *"remote=upstream"* ]]
}

@test "--defer-reply 8 -> reply_mode=defer reply_delay=8" {
    run devx_pr_review_all_parse 123 --defer-reply 8
    [ "$status" -eq 0 ]
    [[ "$output" == *"reply_mode=defer"* ]]
    [[ "$output" == *"reply_delay=8"* ]]
}

@test "--no-reply wins over --defer-reply" {
    run devx_pr_review_all_parse 123 --defer-reply 8 --no-reply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reply_mode=none"* ]]
}

@test "missing PR -> exit 2" {
    run devx_pr_review_all_parse
    [ "$status" -eq 2 ]
}

@test "non-integer PR -> exit 2" {
    run devx_pr_review_all_parse abc
    [ "$status" -eq 2 ]
}

@test "--defer-reply non-integer -> exit 2" {
    run devx_pr_review_all_parse 123 --defer-reply x
    [ "$status" -eq 2 ]
}

@test "unknown flag -> exit 2" {
    run devx_pr_review_all_parse 123 --bogus
    [ "$status" -eq 2 ]
}

@test "help flag -> help_requested" {
    run devx_pr_review_all_parse --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"help_requested=1"* ]]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/functions/devx_pr_review_all.bats`
Expected: FAIL (function not found).

- [ ] **Step 3: 헬퍼 구현** (`shell-common/functions/devx_pr_review_all.sh`)

```sh
# shell-common/functions/devx_pr_review_all.sh
# Pure arg parser for the devx:pr-review-all skill. Mirrors the
# gh_pr_review_parse contract: one `key=value` line per resolved arg on
# success, errors to stderr. Exit 0 ok/help, exit 2 arg error. Runtime
# checks (PR state, gh auth, CLI presence) belong to the skill body.

devx_pr_review_all_parse() {
    pr=""
    remote="origin"
    reply_mode="inline"
    reply_delay="8"
    _no_reply=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --defer-reply)
            [ "$#" -lt 2 ] && { echo "missing value for --defer-reply" >&2; return 2; }
            reply_delay="$2"; reply_mode="defer"; shift 2 ;;
        --defer-reply=*)
            reply_delay="${1#--defer-reply=}"; reply_mode="defer"; shift ;;
        --no-reply)
            _no_reply=1; shift ;;
        -h | --help | help)
            echo "help_requested=1"; return 0 ;;
        --*)
            echo "Unknown flag: $1" >&2; return 2 ;;
        *)
            if [ -z "$pr" ]; then pr="$1"
            elif [ "$remote" = "origin" ]; then remote="$1"
            else echo "Unexpected positional arg: $1" >&2; return 2
            fi
            shift ;;
        esac
    done

    case "$pr" in
    "" ) echo "missing required arg: <PR#>" >&2; return 2 ;;
    *[!0-9]* ) echo "PR# must be a positive integer: '$pr'" >&2; return 2 ;;
    esac

    if [ "$_no_reply" -eq 1 ]; then
        reply_mode="none"
    elif [ "$reply_mode" = "defer" ]; then
        case "$reply_delay" in
        "" | *[!0-9]* ) echo "--defer-reply value must be a positive integer" >&2; return 2 ;;
        esac
    fi

    echo "pr=$pr"
    echo "remote=$remote"
    echo "reply_mode=$reply_mode"
    echo "reply_delay=$reply_delay"
    return 0
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/functions/devx_pr_review_all.bats`
Expected: PASS (9 tests).

- [ ] **Step 5: shellcheck/shfmt**

Run: `mise run lint-sh`
Expected: 통과. (필요 시 `mise run fix-sh`.)

- [ ] **Step 6: 커밋**

```bash
git add shell-common/functions/devx_pr_review_all.sh tests/bats/functions/devx_pr_review_all.bats
git commit -m "feat(devx-pr-review-all): arg-parse 헬퍼 + bats 테스트 (#1160)"
```

---

### Task 2: devx-pr-review-all SKILL.md + references

**Files:**
- Create: `claude/skills/devx-pr-review-all/SKILL.md`
- Create: `claude/skills/devx-pr-review-all/references/help.md`
- Create: `claude/skills/devx-pr-review-all/references/constraints.md`

**Interfaces:**
- Consumes: `devx_pr_review_all_parse`(Task 1), `Skill(gh:pr-review)`, built-in `/simplify`, `Skill(gh:pr-reply)`, `Skill(devx:schedule)`.
- Produces: `/devx:pr-review-all <PR#> [remote] [--defer-reply M] [--no-reply]` 스킬. issue-flow(Task 3)가 이 스킬을 위임 호출.

- [ ] **Step 1: SKILL.md 작성** (frontmatter + Role + Help + Step 1~6). 골격:

```markdown
---
name: devx:pr-review-all
description: >-
  <spec 요약 기반 — 트리거: /devx:pr-review-all, "PR 다중 리뷰어 병렬",
  "gemini codex simplify 한번에". <PR#> [remote] [--defer-reply M] [--no-reply],
  -h/--help/help. gh:pr-review(단일)와 구분되는 composition.>
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "parallel review fan-out orchestration; soft-fail gate + inline/deferred reply"
    claude: prefer
    non_claude: advisory-only
---
```

본문 단계(각 단계는 spec §3 을 따른다):
1. Parse — `devx_pr_review_all_parse "$@"` 델리게이트, `START_TS` 기록.
2. Pre-flight — PR OPEN & non-draft, `gh auth`; 현재 브랜치 ≠ PR head 면 `gh pr checkout <PR#>`(이미면 skip).
3. Parallel gate — gemini ∥ codex ∥ /simplify (한 턴 Agent 동시 dispatch, 각 soft-fail; `command -v` 로 gemini/codex 가용성 판정, 없거나 non-zero exit → SKIP/WARN).
4. Commit+push — 세 Agent await 후 `git status --porcelain` 비면 skip, 아니면 `git commit -m "refactor(<scope>): simplify per /simplify"` + `git push`(bare commit 금지).
5. pr-reply — `reply_mode`: inline → `Skill(gh:pr-reply,"<PR#>")` 즉시 / defer → `Skill(devx:schedule,"--time <reply_delay> \"/gh-pr-reply <PR#>\"")` / none → 생략.
6. Report — `[OK]/[SKIP]/[WARN]` 한 줄(액션별 상태 + reply 방식).

- [ ] **Step 2: references/help.md 작성** — usage/options/examples verbatim 출력용(gh-pr-review help.md 스타일).

- [ ] **Step 3: references/constraints.md 작성** — soft-fail 규칙, bare-commit 금지, delay 는 보장 아님(인라인이 결정적), approve/request-changes 는 범위 밖(gh:pr-approve), simplify PR# 무시 함정, devx:schedule 분 단위.

- [ ] **Step 4: skill:check 통과**

Run: `Skill(skill:check)` on `claude/skills/devx-pr-review-all/SKILL.md`
Expected: 구조/UX 기준 PASS(라인 수, help 플래그, 옵션 문서, verdict 출력, next-hint). WARN/FAIL 시 수정.

- [ ] **Step 5: 라인 수 확인**

Run: `wc -l claude/skills/devx-pr-review-all/SKILL.md`
Expected: ≤ ~100. 초과 시 references 로 분할.

- [ ] **Step 6: 커밋**

```bash
git add claude/skills/devx-pr-review-all/
git commit -m "feat(devx-pr-review-all): SKILL.md + references 신규 (#1160)"
```

---

### Task 3: gh:issue-flow 위임 리팩터

**Files:**
- Modify: `claude/skills/gh-issue-flow/SKILL.md` (Step 2.3.1/2.3.2/2.3.3 + 2.4 → 단일 위임)
- Modify: `claude/skills/gh-issue-flow/references/quality-gate-step.md`
- Modify: `claude/skills/gh-issue-flow/references/critical-contract.md`
- Modify: `claude/skills/gh-issue-flow/references/report-template.md`
- Modify: `claude/skills/gh-issue-flow/references/constraints.md`
- Modify: `claude/skills/gh-issue-flow/references/help.md`

**Interfaces:**
- Consumes: `Skill(devx:pr-review-all)`(Task 2).
- Produces: Step 2.3 이 `Skill(devx:pr-review-all, "<PR_NUM> <remote> --defer-reply 8")` 하나로 게이트+schedule 수행. EXPECTED_CHAIN(Task 4)과 lockstep.

- [ ] **Step 1: SKILL.md Step 2 재작성** — 기존 6개 체인의 Step 2.3.1/2.3.2/2.3.3(quality gate) + Step 2.4(devx:schedule) 를 단일 Step 2.4 `Skill(devx:pr-review-all, "<PR_NUM> <remote> --defer-reply 8")` 로 대체. 나머지(2.1 implement, 2.2 commit, 2.3 pr, 2.5 resolve-conflict, 2.5.1 resolve-outdated, 2.6 metrics) 유지. zero-prose 계약·`--no-next-hint` 유지.

- [ ] **Step 2: quality-gate-step.md 갱신** — 인라인 게이트 절차를 devx:pr-review-all 위임 설명으로 교체(gemini 추가 명시, simplify commit-before-rebase 순서는 위임 스킬이 동기 보장함을 명기).

- [ ] **Step 3: critical-contract.md 갱신** — "6개 Skill() 사이 zero-prose" → 갱신된 체인(devx-pr-review-all 포함) 기준으로 문구 수정. 세 가드 유지 명시.

- [ ] **Step 4: report-template.md / constraints.md / help.md 갱신** — 위임 반영, pr-reply 지연 5→8분, help 의 체인 나열에서 codex∥simplify 게이트 → devx:pr-review-all(gemini∥codex∥simplify) 로 갱신.

- [ ] **Step 5: 커밋**

```bash
git add claude/skills/gh-issue-flow/
git commit -m "refactor(gh-issue-flow): quality gate 를 devx:pr-review-all 위임으로 통합 (#1160)"
```

---

### Task 4: gh_issue_flow_stop_guard.py EXPECTED_CHAIN lockstep + pytest

**Files:**
- Modify: `claude/hooks/gh_issue_flow_stop_guard.py` (EXPECTED_CHAIN, STEP_LABELS, `_next_step_label`)
- Modify: `tests/integration/test_gh_issue_flow_stop_guard.py`

**Interfaces:**
- Consumes: Task 3 의 갱신된 체인.
- Produces: 가드가 `devx-pr-review-all` 을 4번째 sub-skill 로 추적(기존 `devx-schedule` 대체).

- [ ] **Step 1: 실패 테스트 갱신/추가** (`tests/integration/test_gh_issue_flow_stop_guard.py`)
  - 기존 `devx-schedule` 기대 항목을 `devx-pr-review-all` 로 바꾸는 케이스.
  - `Skill(devx:pr-review-all)` 호출 후 나머지 체인 완료 시 stop 허용되는 케이스.
  - devx-pr-review-all 미호출 시 block + 그 단계 라벨 나오는 케이스.

- [ ] **Step 2: 테스트 실패 확인**

Run: `pytest tests/integration/test_gh_issue_flow_stop_guard.py -v`
Expected: 새 케이스 FAIL.

- [ ] **Step 3: 가드 수정**
  - `EXPECTED_CHAIN`: `("devx-schedule", "devx:schedule")` → `("devx-pr-review-all", "devx:pr-review-all")`.
  - `STEP_LABELS`: 해당 항목 라벨 갱신(Step 2.4 — Skill(devx:pr-review-all)).
  - `_next_step_label`: `canonical[next_idx] == "devx-schedule"` 특수 분기를 `"devx-pr-review-all"` 로 바꾸고, 게이트 리마인더 문구를 "devx:pr-review-all 가 gemini∥codex∥simplify+commit/push 를 수행(위임)" 으로 갱신.

- [ ] **Step 4: 테스트 통과 확인**

Run: `pytest tests/integration/test_gh_issue_flow_stop_guard.py -v`
Expected: PASS 전부.

- [ ] **Step 5: 커밋**

```bash
git add claude/hooks/gh_issue_flow_stop_guard.py tests/integration/test_gh_issue_flow_stop_guard.py
git commit -m "refactor(gh-issue-flow): stop-guard EXPECTED_CHAIN 를 devx-pr-review-all 로 lockstep 갱신 (#1160)"
```

---

### Task 5: 전체 검증 (Advisor 게이트)

**Files:** 없음(검증 전용).

- [ ] **Step 1: 셸 lint**

Run: `mise run lint-sh`
Expected: 통과.

- [ ] **Step 2: Python lint**

Run: `mise run lint-py`
Expected: 통과.

- [ ] **Step 3: 전체 테스트**

Run: `mise run test`
Expected: bats + pytest + golden rules 통과.

- [ ] **Step 4: AGENTS.md 갱신 확인** — `claude/skills/` 또는 관련 모듈 루트 AGENTS.md 에 신규 스킬 반영 필요 여부 점검(있으면 갱신 후 커밋).

- [ ] **Step 5: 최종 커밋(있으면)**

```bash
git add -A && git commit -m "chore(devx-pr-review-all): 문서/AGENTS 갱신 + 전체 검증 통과 (#1160)"
```

---

## Self-Review

- **Spec coverage**: F-1~F-6, NF-1~NF-2 모두 Task 1~4 로 매핑됨(파서=T1, 스킬 본문=T2, 위임=T3, 가드=T4). Error Cases 는 T2 constraints + T1 파서 exit 2 로 커버.
- **Placeholder scan**: 셸 헬퍼/테스트는 완전 코드. SKILL.md/references 본문은 골격 + spec 참조(§3) — Worker 가 spec 을 SSOT 로 작성. 가드 변경은 정확한 심볼명(EXPECTED_CHAIN/STEP_LABELS/_next_step_label) 명시.
- **Type consistency**: 파서 출력 키(pr/remote/reply_mode/reply_delay)가 T2 Step 1·5 에서 동일하게 소비됨. EXPECTED_CHAIN 튜플 형태 `(hyphen, colon)` 유지.
- **알려진 함정**(spec §5) 반영: simplify PR# 무시→T2 Step1 pre-flight checkout, 가드 lockstep→T4, devx:schedule 분 단위→T1/T2, soft-fail→T2.
