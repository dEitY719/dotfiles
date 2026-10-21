---
status: approved
---

# my-help 팔레트 v2 — 명령 메뉴 재설계 (#2263)

- 작성일: 2026-10-21
- 선행: #1740 (fzf 팔레트 v1, 설계 문서 `my-help-tui-ux.md`)
- 구현: `shell-common/functions/my_help.sh` (`_my_help_search`, `_my_help_render_rows`,
  `_my_help_palette_layout`, `_my_help_fzf_ge`, `_my_help_scope_step`, `_my_help_source_excerpt`),
  `shell-common/tools/custom/my_help_preview.sh` (카드 렌더러, `--scopes`)
- 테스트: `tests/bats/functions/my_help_palette.bats` P23–P36

Claude Code 의 `/` 메뉴, Codex CLI 의 slash popup 과 같은 문법으로 v1 팔레트를 다듬었다.
비대화형 출력(NF-4, P1/P2/P17), 읽기 전용 Enter(F-9), 5필드 레코드(P9), 폴백(P18/P22)은 v1 그대로다.

## 확정 사항

| ID | 결정 | 근거 |
|---|---|---|
| D-1 | fzf 입력은 표시열 선행 6필드 (`display<TAB>record`) + `--with-nth=1 --nth=1 --ansi` | fzf 0.44.1 에서 `--ansi --nth=6 --with-nth=6` 은 매칭 0건. 5필드 레코드는 `_my_help_search_candidates` 출력에 그대로 남는다 |
| D-2 | 스코프 전환은 부모 루프 + `--expect=tab,btab` + `change:reload` 메뉴 게이트 | 0.45 `transform` 없이 상태를 들고 다닐 수 없다. 메뉴는 라운드마다 한 번 렌더해 두고 키 입력마다 `cat` 만 돈다 |
| D-3 | 키 힌트는 하단 테두리 라벨, 스코프는 프롬프트, 카운트는 `--info=inline-right` | 0.44 에는 `--footer` 가 없다 |
| D-4 | 2-tone 색: 이름 기본색, 설명 `UX_DIM`, 태그·배지 `UX_MUTED`. fzf `--color` 는 ux_lib 인덱스(4/8)에 맞추고 ux_lib 색이 꺼지면 `--color=bw` | 출처 태그를 희미하게 처리하는 Claude Code/Codex 관례 |
| D-5 | 반응형 120/100 컬럼: ≥120 오른쪽 50%, 100–119 아래 45%, <100 숨김(`alt-p`/`?` 로 열기) | fzf 자체 `<N(...)` 대안 레이아웃은 프리뷰 창 폭 기준이라 터미널 폭을 직접 판정한다 |
| D-6 | `Tab` = 다음 스코프, `Shift-Tab` = 이전 (topic → alias → func → category → all) | #1740 D-8 의 "Tab = 셸 버퍼 주입" 예약 해제. 후속 액션 키는 `alt-enter` 계열 |
| D-7 | 기본 스코프 topic, 배지 열은 `/all` 에서만 | 단일 종류 스코프의 배지는 정보량 0 |
| D-8 | func 프리뷰·Enter 는 소스 발췌(최대 24줄, sed/bat 읽기 전용) | `definition: gwt()` 는 정보가 없다 |
| D-9 | Tier B(`--style=full`/`--ghost`/`--footer`/`--highlight-line`)는 fzf ≥ 0.63 에서만, 요구하지 않음. < 0.44 는 정적 표 + 버전 경고 | apt 기본이 0.44.1 |
| D-10 | 이슈의 Phase 1–4 를 한 PR 로 묶었다 | wave 조정자 지시(이슈 전체 범위) |
| D-11 | 동점 정렬 `--tiebreak=begin,length` | 설명열도 검색되므로 `git` 이 `hook  Git hook …` 보다 뒤로 밀리던 것을 막는다 |

## 행 규칙

| kind | 이름 열 | 설명 열 | 꼬리 태그 |
|---|---|---|---|
| topic | `-help` 제거 | `[Category]` 접두 제거 | 카테고리 레이블 |
| alias | 이름 | 정의 (40자 초과 시 `…`) | 주석, 없으면 파일 basename |
| func | 이름 | 등록 설명 | 파일 basename |
| category | 이름 | 카테고리 설명 | `N topics` |
| scope | `/alias` 등 | 스코프 설명 | 현재 스코프 레코드 기준 건수 (다른 종류는 빈칸) |

이름 열 폭 = `min(최대 이름 폭, 24)`, 초과 이름은 23자 + `…`. 정렬은 공백으로만 한다(탭스톱 금지).

## 프리뷰 카드

모든 카드: 1줄 `<kind> · <name> · <where>`, 2줄 설명, 종류별 본문, 마지막 줄 희미한 `⏎ …`.
`FZF_PREVIEW_COLUMNS` 폭으로 잘라낸다(ESC 시퀀스는 폭에서 제외). 발췌는 `relpath:line` 이
저장소 상대 경로일 때만 열고 절대경로·`..` 는 거부한다.

## 측정 (2026-10-21, fzf 0.44.1, bash)

| 항목 | 값 | 예산 |
|---|---|---|
| 라운드 준비 (후보 + 렌더 + 메뉴) topic / alias / func / category / all | 228 / 23 / 26 / 47 / 283 ms | 300 ms |
| 프리뷰 topic / alias / func / category / scope | 59 / 68 / 76 / 61 / 14 ms | 150 ms |

topic 라운드의 대부분(≈200 ms)은 v1 부터 있던 `_my_help_search_candidates topic` 비용이다.
