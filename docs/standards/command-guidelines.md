# Command Interface and Help UX Guidelines

## 목표

명령어 인터페이스와 help 출력 형식을 일관되게 유지한다.
이 문서는 dotfiles 명령어 설계의 SSOT이다.

## 적용 범위

- `shell-common/functions/*.sh`의 함수형 명령어
- `*-help` 형태의 도움말 명령어
- `my-help`를 통한 topic 라우팅

## 표준 인터페이스

### 1) Help 진입점

- Canonical: `<topic>-help`
- 상세 조회: `<topic>-help <section>`
- 섹션 목록: `<topic>-help --list`
- 전체 상세: `<topic>-help --all`
- 통합 라우팅: `my-help <topic> [section|--list|--all]`

### 2) 출력 정책

- 기본 출력(`*-help`)은 15줄 이내를 목표로 한다.
- 기본 출력은 요약 중심으로 구성한다.
- 상세 표/긴 설명은 `--all`로 분리한다.

### 3) 계층 출력 규칙

- 1단계 항목: `ux_bullet`
- 2단계 항목: `ux_bullet_sub`
- 문자열 앞 공백으로 들여쓰기하지 않는다.

## SSOT 원칙

### 1) 섹션 데이터 단일화

- `--all`과 `<section>`은 같은 row 함수(데이터 소스)를 재사용해야 한다.
- 권장 패턴:
  - `_topic_help_rows_<section>()` : 섹션 row 정의
  - `_topic_help_full()` : 섹션 renderer 조립
  - `_topic_help_section_rows()` : 단일 섹션 row 출력

### 2) 표시와 데이터 분리

- row 데이터 정의와 화면 조립 로직을 분리한다.
- 섹션 추가 시 row 함수만 추가하고 renderer에 조립한다.

## 네이밍 규칙

- 함수명: snake_case (`git_help`, `gwt_help`)
- 내부 helper: `_` 접두사 (`_git_help_rows_stash`)
- alias: dash-form (`git-help`, `gwt-help`)

## 멀티 커맨드 함수형 CLI 규칙

- `gwt` 같은 멀티 커맨드 함수도 help 표준은 동일하게 적용한다.
- 사용자 안내는 `gwt-help [section]`을 canonical로 사용한다.
- 구형 help 진입점 유지 여부는 명시적으로 결정하고 테스트로 고정한다.

## 테스트 체크리스트

- bash/zsh 모두에서 canonical help 호출 성공
- `*-help` 기본 출력 줄 수 검증 (<= 15)
- `<topic>-help <section>` 출력이 `--all`의 동일 섹션 row와 일치
- `my-help <topic> [args]` 인자 전달 정상 동작

## 변경 절차

1. 인터페이스 변경 시 이 문서를 먼저 갱신
2. 해당 help 함수를 SSOT 패턴으로 수정
3. pytest 통합 테스트로 정책 고정
4. AGENTS.md는 요약 + 본 문서 링크만 유지
