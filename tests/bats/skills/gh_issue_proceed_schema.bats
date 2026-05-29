#!/usr/bin/env bats
# tests/bats/skills/gh_issue_proceed_schema.bats
# Verify the strict 8-section schema validator documented in
#   claude/skills/gh-issue-proceed/references/protocol-schema.md
# Source-of-truth fixture: _fixtures/gh_issue_proceed_schema.sh
#
# Five variants from design §8 / acceptance criteria:
#   1. all-OK     → PASS
#   2. missing    → FAIL (Missing required sections)
#   3. empty      → FAIL (Empty required sections)
#   4. H3-nested  → PASS (validator matches H2-H6)
#   5. KO-aliases → PASS (Korean heading aliases)

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh"
}

teardown() {
    teardown_isolated_home
    unset FAKE_BODY
}

# ---------- Variant 1: all-OK ----------

@test "schema: complete 8-section body (H2, EN) → PASS" {
    FAKE_BODY=$(cat <<'EOF'
## Goal
Verify the CLI end-to-end so that every documented command returns success.

## Preconditions
The repo is cloned and the binary is built; network access to the API is available.

## Execution Protocol
1. Run `app --help` and confirm a usage block prints without any error here.
2. Run `app list 1 10` and confirm ten rows of output appear correctly here.

## Decision Rules
- PASS: continue to the next step in the protocol as normal without action.
- FAIL-CLI: file_issue: cli-bug and then continue with the remaining steps.

## Deliverables
A short verification report plus one filed follow-up issue per failing command.

## Done Criteria
- [ ] every documented command was executed at least once during the run
- [ ] a report comment summarizing pass and fail counts was posted

## Out of Scope
Performance benchmarking and load testing are explicitly not part of this task.

## Safety
Read-only verification only. Abort on any destructive command encountered here.
EOF
)
    run gh_proceed_validate_schema 81
    assert_success
    assert_output --partial 'schema OK'
}

# ---------- Variant 2: missing section ----------

@test "schema: body missing the Safety section → FAIL (missing)" {
    FAKE_BODY=$(cat <<'EOF'
## Goal
Verify the CLI end-to-end so that every documented command returns success.

## Preconditions
The repo is cloned and the binary is built; network access to the API is available.

## Execution Protocol
1. Run `app --help` and confirm a usage block prints without any error here.

## Decision Rules
- PASS: continue to the next step in the protocol as normal without action.

## Deliverables
A short verification report plus one filed follow-up issue per failing command.

## Done Criteria
- [ ] every documented command was executed at least once during the run

## Out of Scope
Performance benchmarking and load testing are explicitly not part of this task.
EOF
)
    run gh_proceed_validate_schema 81
    assert_failure
    assert_output --partial 'Missing required sections'
    assert_output --partial 'safety'
}

# ---------- Variant 3: empty section ----------

@test "schema: Goal heading present but content < 50 chars → FAIL (empty)" {
    FAKE_BODY=$(cat <<'EOF'
## Goal
- ok

## Preconditions
The repo is cloned and the binary is built; network access to the API is available.

## Execution Protocol
1. Run `app --help` and confirm a usage block prints without any error here.

## Decision Rules
- PASS: continue to the next step in the protocol as normal without action.

## Deliverables
A short verification report plus one filed follow-up issue per failing command.

## Done Criteria
- [ ] every documented command was executed at least once during the run

## Out of Scope
Performance benchmarking and load testing are explicitly not part of this task.

## Safety
Read-only verification only. Abort on any destructive command encountered here.
EOF
)
    run gh_proceed_validate_schema 81
    assert_failure
    assert_output --partial 'Empty required sections'
    assert_output --partial 'goal'
}

# ---------- Variant 4: H3-nested headings ----------

@test "schema: same body with H3 (###) headings → PASS" {
    FAKE_BODY=$(cat <<'EOF'
### Goal
Verify the CLI end-to-end so that every documented command returns success.

### Preconditions
The repo is cloned and the binary is built; network access to the API is available.

### Execution Protocol
1. Run `app --help` and confirm a usage block prints without any error here.
2. Run `app list 1 10` and confirm ten rows of output appear correctly here.

### Decision Rules
- PASS: continue to the next step in the protocol as normal without action.

### Deliverables
A short verification report plus one filed follow-up issue per failing command.

### Done Criteria
- [ ] every documented command was executed at least once during the run

### Out of Scope
Performance benchmarking and load testing are explicitly not part of this task.

### Safety
Read-only verification only. Abort on any destructive command encountered here.
EOF
)
    run gh_proceed_validate_schema 81
    assert_success
    assert_output --partial 'schema OK'
}

# ---------- Variant 5: Korean aliases ----------

@test "schema: Korean heading aliases → PASS" {
    FAKE_BODY=$(cat <<'EOF'
## 목표
모든 문서화된 명령을 직접 실행하여 정상적으로 종료되는지 처음부터 끝까지 빠짐없이 검증한다 end to end verification.

## 사전 조건
저장소가 클론되어 있고 바이너리가 빌드되어 있으며 API 네트워크 접근이 가능하다 here.

## 실행 절차
1. `app --help` 를 실행하여 사용법 블록이 오류 없이 출력되는지 확인한다 step one.
2. `app list 1 10` 를 실행하여 열 개의 행이 정상 출력되는지 확인한다 step two.

## 결정 규칙
- PASS: 다음 단계로 계속 진행한다 continue without any extra action taken here.

## 산출물
짧은 검증 리포트와 실패한 명령마다 하나씩 등록한 후속 이슈를 제출한다 deliverable.

## 종료 조건
- [ ] 모든 문서화된 명령이 최소 한 번 이상 실행되었다 executed at least once

## 범위 밖
성능 벤치마크와 부하 테스트 그리고 보안 감사는 이 작업의 범위에 전혀 포함되지 않는다 strictly out of scope here.

## 안전 규칙
읽기 전용 검증만 수행한다. 파괴적 명령을 만나면 즉시 중단한다 abort on danger.
EOF
)
    run gh_proceed_validate_schema 81
    assert_success
    assert_output --partial 'schema OK'
}
