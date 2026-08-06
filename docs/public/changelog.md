# Changelog

사용자 관점의 의미 있는 변경 기록. 포맷: `## YYYY-MM-DD` 헤더 아래 `- 변경: **요약**`.

## 2026-08-06
- 변경: **`PostToolUse:Bash` 훅 지연 제거 — `gh pr create` 후 project board retry-poll(최대 6회 x 2s sleep + GraphQL 왕복)과 연결 이슈 동기화를 백그라운드로 분리. foreground 는 sync 1회만 수행하므로 훅이 즉시 반환한다 (median 7.8s / max 48.7s → 즉시) (#1258)**
- 변경: **훅 구간별 타이밍 계측 추가 — 라우팅된 호출만 `~/.local/state/claude/post-bash-dispatch-timing.log` 에 기록하고, `claude/tools/hook-perf-report.sh` 로 median/p90/p99/max 와 목표치(median < 2000ms · p99 < 5000ms) PASS/FAIL 을 집계한다 (#1258)**

## 2026-07-30
- 변경: **statusline 시간 표시 `HH:MM:SS`로 축약 + fcitx 한글/영어 입력기 상태 표시 (#1251)**
- 변경: **`CLAUDE_STATUSLINE_SKIP_FCITX=1` 환경변수 추가 — Windows Terminal/VS Code Remote-WSL처럼 X11 클라이언트가 아닌 콘솔에서는 fcitx 상태를 원천적으로 못 읽으므로 매 프롬프트 fcitx-remote 호출을 건너뜀 (개인 PC는 `~/.zshrc.local`에서 설정)**
- 변경: **`claude-skills-marketplace search`(alias `find`)에 fzf 퍼지 피커 추가 — fzf 미설치·비대화형이면 기존 jq substring 검색으로 폴백**

## 2026-07-29
- 변경: **`my-help search` (alias `find`) 추가 — fzf 퍼지 topic 검색, fzf 미설치·비대화형이면 카테고리 목록 폴백 (#1246)**

## 2026-07-24
- 변경: **changelog 신설 — 일일/주간 보고 허브(my-share) 수집 대상**
- 변경: **`herdr-help install` 섹션 추가 — 사외 표준 설치 + 사내 프록시 우회 설치 안내 (#1239)**
