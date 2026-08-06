# Command Interface and Help UX Guidelines

## 목표

명령어 인터페이스와 help 출력 형식을 일관되게 유지한다.
이 문서는 dotfiles 명령어 설계의 SSOT이다.

## 적용 범위

- `shell-common/functions/*.sh`의 함수형 명령어
- `*-help` 형태의 도움말 명령어
- `my-help`를 통한 topic 라우팅
- `shell-common/tools/ux_lib/UX_GUIDELINES.md`와의 상호 보완 규칙

## 표준 인터페이스

### 1) Help 진입점

- Canonical: `<topic>-help`
- 상세 조회: `<topic>-help <section>`
- 섹션 목록: `<topic>-help [--list|list]`
- 전체 상세: `<topic>-help [--all|all]`
- 통합 라우팅: `my-help [<topic>] [section|--list|--all]` (인자 생략 시 카테고리 목록 표시)
- 퍼지 검색: `my-help search` (alias `find`) — fzf 기반 finder. 인덱스는 `*_help.sh` 토픽 + 저장소 전체 alias(`bash/`, `zsh/`, `shell-common/` 의 `*.sh`/`*.bash`/`*.zsh`) 를 함께 포함한다. 토픽을 그대로 다시 노출하는 dash-form alias(`agy-help` → `agy_help`)는 중복이므로 인덱스에서 제외한다. 반대로 같은 이름이 서로 다른 정의로 두 곳에 선언된 경우(`llm-help` = `litellm_help` / `ollama_help`)는 어느 쪽이 유효한지 파일 스캔만으로 알 수 없으므로 임의로 하나를 고르지 않고 양쪽 다 각자의 위치와 함께 노출한다. alias 항목을 고르면 정의·정의 위치·주석을 출력한다. fzf 미설치·비대화형이면 카테고리 목록으로 폴백
  - alias 인덱스는 `${XDG_CACHE_HOME:-~/.cache}/dotfiles/my-help-alias-index.tsv` 에 24시간 TTL 로 캐시된다 (`MY_HELP_ALIAS_CACHE_PATH` / `MY_HELP_ALIAS_CACHE_MAX_AGE` 로 재정의 가능). 캐시가 비었거나 손상되면 자동 재생성하고, 스캔 결과가 없으면 토픽 목록만으로 폴백한다

### 2) 출력 정책

- 기본 출력(`*-help`)은 15줄 이내를 목표로 한다.
- 기본 출력은 요약 중심으로 구성한다.
- 상세 표/긴 설명은 `--all`로 분리한다.
- 기본 요약은 아래 템플릿을 기본값으로 사용한다:
  - 첫 줄: `ux_info "Usage: <topic>-help [section|--list|--all]"`
  - 섹션 루트: `ux_bullet "sections"`
  - 섹션 항목: `ux_bullet_sub "..."`
  - 금지: `ux_info "sections: ..."` 형태의 flat 나열 요약

### 3) 계층 출력 규칙

- 1단계 항목: `ux_bullet`
- 2단계 항목: `ux_bullet_sub`
- 문자열 앞 공백으로 들여쓰기하지 않는다 (`ux_bullet`, `ux_bullet_sub`가 들여쓰기와 bullet 스타일을 처리).

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

### 3) 문서 자동생성 (issue #1262)

row 함수는 화면 출력뿐 아니라 **커맨드 레퍼런스 문서의 데이터 소스** 이기도 하다.
`shell-common/tools/custom/gen_command_docs.sh` 가 `shell-common/functions/*.sh` 전체에서
`_<topic>_help_rows_<section>()` 를 찾아 실행하고, 결과를
`docs/guide/commands/<커맨드>.md` 로 렌더링한다 (`rg` 전체 텍스트 검색 대상).

- row 함수 네이밍(`_<topic>_help_rows_<section>`)을 벗어나면 그 커맨드는 문서 생성에서 **조용히 누락된다**.
- 생성 문서는 직접 편집하지 않는다. 내용을 바꾸려면 row 함수를 고치고 재생성한다.
- 소스 주석에만 있는 엣지케이스(예: fzf 피커가 Esc 에 조용히 exit 0)는 자동 추출 대상이 아니다.
  `docs/guide/commands/.notes/<커맨드>.md` 에 수기로 적으면 재생성 시 문서에 삽입된다.
- 재생성: `./shell-common/tools/custom/gen_command_docs.sh --force` (내용이 바뀐 파일만 갱신).
- **row 함수는 호스트 환경값을 출력하지 않는다.** `$SSL_CERT_FILE` 처럼 머신마다 다른 값을
  찍는 row 는 생성 문서가 재현 불가능해지고, 사내 인증서 경로 같은 값이 공개 저장소로
  새어 나간다. 그런 topic 은 `gen_command_docs.sh` 의 `GCD_DENY_TOPICS` 에 등록해
  문서 생성에서 제외한다 (현재 `ssl`, `crt`).
- 로케일 의존 출력(`sort` 정렬 순서, 멀티바이트 문자에 대한 `cut -c`)은 렌더 자식이
  `LC_ALL=C` 로 고정하므로 별도 처리 불필요.

## 네이밍 규칙 (help 함수)

- 함수명: snake_case (`git_help`, `gwt_help`)
- 내부 helper: `_` 접두사 (`_git_help_rows_stash`)
- alias: dash-form (`git-help`, `gwt-help`)

명령어 자체의 dispatcher / private sub-function 네이밍은 [`command-design-pattern.md`](./command-design-pattern.md) §1 참조.

## 멀티 커맨드 함수형 CLI

`gwt` 같은 멀티 커맨드 함수의 dispatcher 구조 자체는 [`command-design-pattern.md`](./command-design-pattern.md) §4–§7가 정의한다. 이 문서는 그 위에서 help 출력 규칙만 다룬다:

- 사용자 안내는 `gwt help [section]`을 canonical로 사용하고, `gwt-help` alias 는 backward-compat 단축형으로 동등 제공한다.
- `<alias> -h|--help|help|""` 는 canonical `<topic>-help` 와 동등한 진입점이며 두 형태 모두 테스트로 고정한다 (예: `gwt`, `gwt -h`, `gwt --help`, `gwt help`, `gwt help <section>`).

## 테스트 체크리스트

- bash/zsh 모두에서 canonical help 호출 성공
- `*-help` 기본 출력 줄 수 검증 (<= 15)
- `*-help` 기본 출력이 템플릿(Usage + `ux_bullet`/`ux_bullet_sub`)을 따르는지 검증
- `<topic>-help <section>` 출력이 `--all`의 동일 섹션 row와 일치
- `my-help <topic> [args]` 인자 전달 정상 동작

## 변경 절차

1. 인터페이스 변경 시 이 문서를 먼저 갱신
2. 해당 help 함수를 SSOT 패턴으로 수정
3. pytest 통합 테스트로 정책 고정
4. AGENTS.md는 요약 + 본 문서 링크만 유지
