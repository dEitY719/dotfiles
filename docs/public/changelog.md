# Changelog

사용자 관점의 의미 있는 변경 기록. 포맷: `## YYYY-MM-DD` 헤더 아래 `- 변경: **요약**`.

## 2026-08-06
- 변경: **`PostToolUse:Bash` 훅 지연 제거 — `gh pr create` 후 project board retry-poll(최대 6회 x 2s sleep + GraphQL 왕복)과 연결 이슈 동기화를 백그라운드로 분리. foreground 는 sync 1회만 수행하므로 훅이 재시도 예산을 기다리지 않고 반환한다 (median 7.8s / max 48.7s → sync 1회 왕복) (#1258)**
- 변경: **훅 구간별 타이밍 계측 추가 — 라우팅된 호출만 `~/.local/state/claude/post-bash-dispatch-timing.log` 에 기록하고, `claude/tools/hook-perf-report.sh` 로 median/p90/p99/max 와 목표치(median < 2000ms · p99 < 5000ms) PASS/FAIL 을 집계한다 (#1258)**
- 변경: **커맨드별 마크다운 레퍼런스 자동생성 — `shell-common/tools/custom/gen_command_docs.sh` 가 `_<topic>_help_rows_<section>()` row 함수를 실행해 `docs/guide/commands/<커맨드>.md` 57개를 생성. `rg "<키워드>" docs/guide/commands/` 로 커맨드 동작 전체 텍스트 검색 (#1262)**
- 변경: **호스트 환경값(`$SSL_CERT_FILE` 등)을 출력하는 `ssl`/`crt` topic 은 문서 생성에서 제외 — 머신마다 값이 달라 재현 불가능하고 사내 인증서 경로가 공개 저장소로 새어 나간다. 해당 값은 `ssl-help`/`crt-help` 로 직접 확인 (#1262)**
- 변경: **소스 주석에만 있던 엣지케이스를 `docs/guide/commands/.notes/<커맨드>.md` 에 수기 보강하면 재생성 시 문서에 삽입 — 첫 대상은 `csm find` 의 fzf 피커/Esc 무음 종료 동작**
- 변경: **`my-help search`(alias `find`) 인덱스를 `*_help.sh` 토픽에서 저장소 전체 alias까지 확장 — alias 이름으로 바로 찾고, 고르면 정의·정의 위치·주석을 표시. 토픽을 그대로 다시 노출하는 dash-form alias(`agy-help` → `agy_help`)는 중복 제거하되, 서로 다른 정의를 가진 동명 alias(`llm-help`)는 양쪽 다 노출한다 (#1261)**
- 변경: **alias 인덱스는 `${XDG_CACHE_HOME:-~/.cache}/dotfiles/my-help-alias-index.tsv`에 24시간 TTL로 캐시 — `MY_HELP_ALIAS_CACHE_PATH` / `MY_HELP_ALIAS_CACHE_MAX_AGE`로 재정의 가능하며, 캐시가 비었거나 손상되면 자동 재생성**
- 변경: **gh-issue-flow Stop 훅이 `Bash` heredoc/`printf` 로 출력된 Step 3 종료 리포트도 인식 — 기존에는 assistant text 블록만 스캔해 리포트가 tool_use `input.command` 와 `tool_result` 에만 남으면 플로우가 영원히 종료되지 않았다. 템플릿 자리표시자(`<N>`/`<i>`) 대신 실제 숫자를 요구하는 엄격한 정규식을 쓰고 `Bash` 만 스캔한다(`Write`/`Edit` 입력은 SKILL.md 편집 시 진짜 템플릿 텍스트를 담으므로 제외) (#1270)**
- 변경: **오래된 flow boundary 자동 만료 — 종료 리포트 없이 끝난 플로우의 boundary 가 세션 내내 남아 무관한 턴까지 계속 차단하던 문제 수정. boundary 이후 사용자 프롬프트가 3회 쌓이면 fail-open 한다. `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS` 로 조정하고 `0` 이면 만료 비활성화. tool_result·skill 확장·`<system-reminder>` 전용 메시지는 사용자 프롬프트로 세지 않는다 (#1270)**
- 변경: **Step 3 리포트는 반드시 plain assistant text 로 출력하도록 SKILL.md·report-template.md 에 명시 — `Bash` 경로는 어디까지나 폴백 (#1270)**
- 변경: **flow boundary 만료 카운터가 훅 자체 피드백을 사용자 턴으로 오인하던 문제 수정 — 실제 2489-entry 트랜스크립트에서 "새 사용자 프롬프트" 102건 중 실제 사람 입력은 4건뿐이었고, 나머지는 훅이 되돌려받은 `Stop hook feedback:` 62건과 백그라운드 서브에이전트 완료 알림 `<task-notification>` 40건이었다. 그 결과 1/6 단계에서 가드가 스스로 꺼졌다(`devx:pr-review-all` 이 백그라운드 에이전트 3개를 띄우므로 상시 재현). 이제 트랜스크립트 엔트리의 `isMeta` 플래그와 harness 주입 마커를 걸러내고, 반대로 사람이 쓴 텍스트가 `tool_result` 와 같은 턴에 실려 온 경우는 정상적으로 사용자 턴으로 센다 (#1270)**
- 변경: **`Bash` 폴백 종료 채널을 command + `tool_result` 쌍 매칭으로 좁힘 — 기존에는 `Bash` 명령 문자열에 종료 마커가 들어 있기만 하면 플로우를 종료로 판정해, `cat <<'EOF' > /tmp/report.txt` 처럼 파일로 리다이렉트하거나 셸 주석에 마커가 있는 경우에도 리포트를 실제로 출력한 것으로 오인했다. 이제 tool_use 의 `input.command` 와 같은 `id` 를 가진 `tool_result` 가 **둘 다** 엄격 정규식에 매치할 때만 종료로 본다(리다이렉트는 stdout 이 없어 쌍이 성립하지 않음). SKILL.md 를 읽어 `tool_result` 에만 템플릿이 실리는 #608 경로는 명령 쪽(`Read`/`cat`)이 숫자 형식을 만족할 수 없어 여전히 차단된다 — 쌍 조건은 양쪽 각각보다 엄격하다 (#1270 / PR #1272 리뷰)**
- 변경: **`/devx:pr-verify-live` 스킬 신설 — 머지 직후(또는 PR 브랜치에서) 이미 떠 있는 dev 앱에 붙어 PR 이 실제로 동작하는지 확인하고 발견을 대상 프로젝트 레포 이슈로 등록한다. base URL·API origin 을 하드코딩 없이 발견하고, 서빙 중인 체크아웃이 대상 커밋(`mergeCommit.oid`)을 포함하는지 확인한 뒤에만 측정한다 (#1271)**
- 변경: **`devx:pr-verify-live` 의 검증 전 단언 3종 — 서빙 체크아웃 · 로케일/뷰포트 전환 적용 · 대상 요소 비가림. 하나라도 실패하면 측정하지 않고 정지한다. "화면은 멀쩡히 뜨는데 검증이 무효" 인 실패를 여섯 번의 실행에서 반복 관측한 결과 (#1271)**
- 변경: **`devx:pr-verify-live` 는 이슈 등록 전에 자기 반증 3가설(하네스 오류 · 데이터 상태 · 의도된 동작)을 세워 위양성을 걷어낸다. 근거 게이트는 "수치" 가 아니라 "기계 판독 가능한 단언" 이라 i18n·상태·어포던스 결함도 등록 가능하다. 이슈 본문·라벨·메트릭은 `gh:issue-create` 가 SSOT (#1271)**
- 변경: **devx-autopilot Stop 훅에도 오래된 boundary 자동 만료 이식 — 종료 리포트 없이 중단된 Stage-B 실행의 boundary 가 세션 내내 남아 무관한 턴까지 계속 차단하던 문제 수정(gh-issue-flow 는 #1270 에서 이미 해결). boundary 이후 진짜 사용자 프롬프트가 3회 쌓이면 fail-open 하며 `DEVX_AUTOPILOT_STOP_GUARD_MAX_USER_TURNS` 로 조정하고 `0` 이면 만료 비활성화. 엔트리의 `isMeta` 플래그, 훅 자신의 `devx-autopilot incomplete:` 재주입, `<task-notification>` 등 harness 주입, skill 확장, `<system-reminder>` 전용·tool_result 전용 메시지는 사용자 프롬프트로 세지 않는다 (#1275)**
- 변경: **macOS/BSD 이식성 수정 — 타이밍 테스트가 GNU 전용 `date +%s%N` 대신 bash 내장 `SECONDS` 를 쓰도록 바꿔 BSD `date` 에서 테스트가 중단되지 않는다. ms 변환 헬퍼는 `claude/hooks/lib/pbd_ms.sh`(디스패처와 같은 디렉터리에 함께 배포되어야 하는 신규 파일) 로 분리해 BSD `date` fallback 경로에 테스트 커버리지를 붙였다 (#1258 리뷰 후속)**

## 2026-07-30
- 변경: **statusline 시간 표시 `HH:MM:SS`로 축약 + fcitx 한글/영어 입력기 상태 표시 (#1251)**
- 변경: **`CLAUDE_STATUSLINE_SKIP_FCITX=1` 환경변수 추가 — Windows Terminal/VS Code Remote-WSL처럼 X11 클라이언트가 아닌 콘솔에서는 fcitx 상태를 원천적으로 못 읽으므로 매 프롬프트 fcitx-remote 호출을 건너뜀 (개인 PC는 `~/.zshrc.local`에서 설정)**
- 변경: **`claude-skills-marketplace search`(alias `find`)에 fzf 퍼지 피커 추가 — fzf 미설치·비대화형이면 기존 jq substring 검색으로 폴백**

## 2026-07-29
- 변경: **`my-help search` (alias `find`) 추가 — fzf 퍼지 topic 검색, fzf 미설치·비대화형이면 카테고리 목록 폴백 (#1246)**

## 2026-07-24
- 변경: **changelog 신설 — 일일/주간 보고 허브(my-share) 수집 대상**
- 변경: **`herdr-help install` 섹션 추가 — 사외 표준 설치 + 사내 프록시 우회 설치 안내 (#1239)**
