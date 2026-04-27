# gh-pr-approve: --ai 실행 주체 선택 옵션 설계

**작성일**: 2026-04-27
**상태**: 설계 완료, 구현 대기
**관련 이슈**: #208 (`gh-flow --ai`)

## 1. 배경

현재 `gh-pr-approve` (`shell-common/functions/gh_pr_approve.sh`)는 워커에서 실행 주체를 고정한다.

- 현재 고정 실행: `claude --dangerously-skip-permissions -p "/gh-pr-approve <N>"`
- 사용자 요구: `gh-flow` #208 과 동일하게 실행 주체를 선택 가능해야 함

## 2. 목표 / 비목표

### 목표
- `gh-pr-approve --ai [claude(default)|codex|gemini]` 지원
- 기존 호출(`gh-pr-approve 42`)과 완전 호환 (기본값 `claude`)
- 병렬 워커/상태 파일/실패 격리 동작은 유지

### 비목표
- `/gh-pr-approve` 스킬 로직 변경
- 승인 정책/리뷰 판단 기준 변경
- `gh-flow` 구현 변경 (별도 #208 범위)

## 3. CLI 계약

### 3.1 사용법

```bash
gh-pr-approve <pr-number>... [--ai <agent>]
gh-pr-approve --ai <agent> <pr-number>...
gh-pr-approve -h | --help
```

- `<agent>` 허용값: `claude`, `codex`, `gemini`
- 기본값: `claude`
- `#` prefix PR 번호 허용 규칙은 기존 유지

### 3.2 실행 예시

```bash
gh-pr-approve 42                          # default: claude
gh-pr-approve 12 34 --ai codex           # codex worker 2개
gh-pr-approve --ai gemini '#56' '#78'    # gemini + #prefix
```

### 3.3 에러 UX

- `--ai` 값 누락: `missing value for --ai (expected: claude|codex|gemini)`
- 잘못된 값: `invalid --ai value: '<value>' (expected: claude|codex|gemini)`
- 미지원 옵션: `unknown option: '<arg>'`

## 4. 설계

### 4.1 파서 변경

`gh_pr_approve()`의 인자 파싱을 2단계로 분리한다.

1. 옵션 파싱: `--ai <agent>` 추출 (위치 무관)
2. 위치 인자 검증: PR 번호 목록 검증(기존 `#` strip 규칙 유지)

결과 변수:
- `_ai` (`claude` 기본)
- `_pr_args` (정규화된 숫자 목록)

### 4.2 Precondition 변경

기존의 `claude CLI not found` 하드코딩을 제거하고 선택된 `_ai` 기준으로 검사한다.

- 공통 유지: `git`, `gh`, `gwt`, main repo 체크
- AI별 검사:
  - `claude`: `_have claude`
  - `codex`: `_have codex`
  - `gemini`: `_have gemini`

### 4.3 워커 실행 분기

워커에 `_ai`를 전달하고, 승인 단계에서 실행기 헬퍼를 사용한다.

- spawn: `_gh_pr_approve_worker "$_pr" "$_ai"`
- worker: `_gh_pr_approve_run_agent "$_ai" "/gh-pr-approve $_pr"`

AI별 명령 매핑:
- `claude`: `claude --dangerously-skip-permissions -p "<prompt>"`
- `codex`: `codex exec --dangerously-bypass-approvals-and-sandbox "<prompt>"`
- `gemini`: `gemini --yolo -p "<prompt>"`

### 4.4 가시성

상태 디렉토리에 `ai` 파일 추가를 권장한다.

```
~/.local/state/gh-pr-approve/<repo>/<pr>/ai
```

로그 첫 줄에 `ai=<agent>`를 남겨 사후 분석을 단순화한다.

## 5. 테스트 계획

대상: `tests/bats/functions/gh_pr_approve.bats`

추가 케이스:
1. `--ai codex` / `--ai gemini` 파싱 성공
2. `42 --ai codex` (후행 옵션) 성공
3. `--ai` 값 누락 실패
4. `--ai unknown` 실패
5. help 출력에 `--ai` 사용법 노출

기존 케이스(정수 검증, `#` prefix, worktree guard)는 회귀 테스트로 유지.

## 6. 리스크 / 미해결

1. `codex exec`/`gemini -p`에서 slash command(`/gh-pr-approve`) 실행 결과가 `claude -p`와 완전히 동일한지 실측 필요
2. CLI별 인증/정책(예: yolo/bypass) 차이로 결과 편차 가능
3. 공통 헬퍼를 `gh_flow`까지 재사용할지(중복 제거) 범위 결정 필요

## 7. 구현 파일

- 수정: `shell-common/functions/gh_pr_approve.sh`
- 수정: `tests/bats/functions/gh_pr_approve.bats`
- 참고: `shell-common/functions/gh_flow.sh`, `shell-common/functions/gh_pr_reply.sh`
