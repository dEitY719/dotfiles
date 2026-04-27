# gh-pr-reply: --ai 실행 주체 선택 옵션 설계

**작성일**: 2026-04-27
**상태**: 설계 완료, 구현 대기
**관련 이슈**: #208 (`gh-flow --ai`)

## 1. 배경

현재 `gh-pr-reply` (`shell-common/functions/gh_pr_reply.sh`)는 워커에서 실행 주체를 고정한다.

- 현재 고정 실행: `claude --dangerously-skip-permissions -p "/gh-pr-reply <N>"`
- 사용자 요구: `gh-flow` #208 과 같은 패턴으로 `--ai` 선택 지원

`gh-pr-reply`는 승인 러너와 달리 코드 수정/commit/push를 동반할 수 있어, 실패 시 worktree 보존 정책(`failed:replying`)을 반드시 유지해야 한다.

## 2. 목표 / 비목표

### 목표
- `gh-pr-reply --ai [claude(default)|codex|gemini]` 지원
- 기존 동작(`gh-pr-reply 42`) 100% 호환
- 실패 시 teardown 생략(데이터 손실 방지) 정책 유지

### 비목표
- `/gh-pr-reply` 스킬 내부 로직 변경
- 실패 시 자동 복구 정책 변경
- `gh-pr-approve`/`gh-flow` 동시 리팩터링 (별도 이슈)

## 3. CLI 계약

### 3.1 사용법

```bash
gh-pr-reply <pr-number>... [--ai <agent>]
gh-pr-reply --ai <agent> <pr-number>...
gh-pr-reply -h | --help
```

- `<agent>` 허용값: `claude`, `codex`, `gemini`
- 기본값: `claude`
- `#` prefix PR 번호 허용 규칙은 기존 유지

### 3.2 실행 예시

```bash
gh-pr-reply 42                           # default: claude
gh-pr-reply 12 34 --ai codex            # codex worker 2개
gh-pr-reply --ai gemini '#56' '#78'     # gemini + #prefix
```

### 3.3 에러 UX

- `--ai` 값 누락: `missing value for --ai (expected: claude|codex|gemini)`
- 잘못된 값: `invalid --ai value: '<value>' (expected: claude|codex|gemini)` (실행기 선택 단계)
- 미지원 옵션: `unknown option: '<arg>'`

## 4. 설계

### 4.1 파서 변경

`gh_pr_reply()`에 옵션 파서를 추가한다.

- `_ai=claude` 기본
- `--ai <agent>` 허용 (중복 지정 시 마지막 값 사용; last-one-wins)
- 옵션 파싱 후 PR 번호 검증 수행

### 4.2 Precondition 변경

기존 `claude` 고정 체크를 `_ai_raw` 기반 실행기 선택 + CLI 검사로 변경한다.

- 공통 유지: `git`, `gh`, `gwt`, main repo 체크
- 실행기 선택:
  - `claude|codex|gemini` 외 값이면 `invalid --ai value`로 실패
- 선택된 AI별 검사:
  - `claude`: `_have claude`
  - `codex`: `_have codex`
  - `gemini`: `_have gemini`

### 4.3 워커 실행 분기

spawn → worker 호출에 `_ai` 전달 추가:

- spawn: `_gh_pr_reply_worker "$_pr" "$_ai"`
- worker: `_gh_run_ai_agent "$_ai" "/gh-pr-reply $_pr"`

AI별 명령 매핑:
- `claude`: `claude --dangerously-skip-permissions -p "<prompt>"`
- `codex`: `codex exec --dangerously-bypass-approvals-and-sandbox "<prompt>"`
- `gemini`: `gemini --yolo -p "<prompt>"`

### 4.4 실패 보존 정책 유지 (핵심)

`replying` 단계 실패 시 기존 정책을 유지한다.

- state: `failed:replying`
- teardown: 수행하지 않음
- 목적: push 전 로컬 커밋 손실 방지

AI가 달라도 이 정책은 동일해야 한다.

### 4.5 가시성

상태 디렉토리에 `ai` 파일 추가를 권장한다.

```
~/.local/state/gh-pr-reply/<repo>/<pr>/ai
```

로그 시작 줄에 `ai=<agent>`를 기록한다.

## 5. 테스트 계획

대상: `tests/bats/functions/gh_pr_reply.bats`

추가 케이스:
1. `--ai codex` / `--ai gemini` 파싱 성공
2. `42 --ai codex` (후행 옵션) 성공
3. `--ai` 값 누락 실패
4. `--ai unknown` 실패
5. help 출력에 `--ai` 사용법 노출
6. `failed:*` 자동 재개 거부 정책이 `--ai` 경로에서도 동일하게 유지되는지 확인

## 6. 리스크 / 미해결

1. `codex`/`gemini` 경로에서 `/gh-pr-reply`의 "수정→commit→push→reply" 파이프라인 안정성 실측 필요
2. CLI별 실패 코드/출력 포맷 차이로 워커 로그 판독성이 달라질 수 있음
3. 공통 헬퍼 도입 시 `gh-pr-approve`/`gh-flow`와의 공통화 경계 점검 필요

## 7. 구현 파일

- 수정: `shell-common/functions/gh_pr_reply.sh`
- 수정: `tests/bats/functions/gh_pr_reply.bats`
- 참고: `shell-common/functions/gh_pr_approve.sh`, `shell-common/functions/gh_flow.sh`
