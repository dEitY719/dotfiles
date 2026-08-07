# Changelog

사용자 관점의 의미 있는 변경 기록. 포맷: `## YYYY-MM-DD` 헤더 아래 `- 변경: **요약**`.

## 2026-08-07
- 변경: **`bash/main.bash`(`~/.bashrc` SSOT)에 `~/.bashrc.local` source 훅 추가, `bash/setup.sh`에 idempotent seed 로직 추가 — zsh의 `~/.zshrc.local` 격리 패턴(#737)을 bash에도 대칭 도입. gateway-migration 등 외부 installer/훅 스크립트가 `~/.bashrc`에 하드코딩 절대경로를 직접 append해 SSOT를 오염시키는 사고를 막는다. 실제 차단은 기존 pre-commit 하드코딩 home-path 가드(#1142)가 커밋 시점에 잡아내고, `~/.bashrc.local`은 그 걸린 줄을 옮겨 담는 착지 지점 역할 — zsh 쪽과 동일한 이단계 메커니즘 (#1290)**
- 변경: **zsh 에서 `my-help find`(fzf) 가 대부분의 명령어를 2줄씩 중복 표시하던 버그 수정 — dash-form 헬퍼(`git-help` 등)를 zsh 전용 진짜 함수로 새로 정의하던 `_help_std_define_zsh_dash_function` 을 제거하고, bash 와 동일하게 alias 로만 등록한다. zsh 는 alias 를 파싱 시점에 확장하므로 비대화형 호출(`zsh -c`, `setopt no_aliases`)에서 dash-form 이 안 보일 수 있어, `command_not_found_handler` 를 `*-help` → 언더스코어 헬퍼 매핑으로 일반화해 안전망으로 둔다(실함수일 때만 디스패치하며, 동명의 실행 파일이 PATH 에 있으면 그쪽이 항상 우선한다) (#1287)**
- 변경: **`devx:pr-verify-live` 가 검증 리포트를 대상 PR 에 코멘트로 게시 — Step 8 결과가 `[OK]`/`[WARN]` 이면 그 리포트 블록을 그대로 PR 코멘트로 남긴다(Step 9). `[FAIL]` 은 검증 전 단언이 막은 환경 문제이므로 게시하지 않고 로컬 출력으로만 끝낸다. 게시 경로는 `gh_pr_review.sh` 의 `_gh_pr_review_post_comment` 재사용이라 soft-fail 계약(게시 실패는 경고, 스킬 정지 아님)이 그대로 유지되고, 헬퍼는 레포 표준 폴백 블록(#644 NF-1 + #724)으로 감싸 부른다. 매 실행이 새 코멘트를 덧붙이는 append-only 동작 — 재검증 이력이 덮이지 않는다. 끄려면 새 플래그 `--no-comment`(파서 출력 `post_comment=0`); `--dry-run`/`--no-issue` 는 이슈 생성만 게이트하므로 코멘트 게시와 서로 독립이다 (#1288)**

## 2026-08-06
- 변경: **Stop 가드 두 개(`gh_issue_flow_stop_guard.py` / `devx_autopilot_stop_guard.py`)의 harness 마커 판정을 부분 문자열에서 줄머리 고정(`(?m)^`) 으로 교체 — 사람이 `"Stop hook feedback:"` 이나 `<task-notification>` 을 문장 안에 인용하기만 해도 그 턴 전체가 fresh user prompt 집계에서 빠져 stale boundary 가 만료되지 않던 문제 수정. 마커 문자열 SSOT 인 `_SKILL_EXPANSION_MARKERS` / `_HARNESS_INJECTION_MARKERS` 튜플에서 `re.escape` 로 정규식을 파생하며, 두 훅에 동일한 구조로 적용해 #1275 식 구조 드리프트를 막는다. 단 `is already loaded above` 는 예외 — 실제 주입문이 `Skill <name> is already loaded above; instructions unchanged. Arguments: …` 형태라 리터럴이 줄머리에 오지 않으므로, `_SKILL_EXPANSION_SHAPES` 의 `^Skill\s+\S+\s+is already loaded above` 정규식 조각으로 실제 문장 구조를 매칭한다(그대로 리터럴로 두면 이 한 마커에 대해 #1270 의 over-count 가 되살아난다) (#1281)**
- 변경: **`gh:pr-review` 의 임시파일 3종(`PROMPT_FILE`/`AI_OUT`/`BODY_FILE`) 할당을 `_gh_pr_review_mktemp_safe <template>` 하나로 통일 — `mktemp` 실패 시 쓰던 예측 가능한 `$$` 폴백 경로를 `set -C`(noclobber, O_CREAT\|O_EXCL) 서브셸로 배타 생성하고, 그 자리에 파일이나 심볼릭 링크가 이미 있으면 링크를 따라 덮어쓰지 않고 즉시 실패한다. 세 호출 지점 모두 실패를 검사해 `gh_pr_review` 를 중단하므로(빈 경로로 진행하지 않음), `/tmp` 가 쓰기 불가·쿼터 초과일 때 로컬 공격자가 PID 를 예측해 심링크를 심어 임의 파일을 덮어쓰던 경로가 닫힌다 (#1283)**
- 변경: **`gh:pr-review` 의 `PROMPT_FILE` 경로를 레인별로 분리 — `_gh_pr_review_mktemp_prompt <ai> <PR#>`(`mktemp "/tmp/gh-pr-review-prompt.<ai>.<PR#>.XXXXXX"`) 가 SSOT. `devx:pr-review-all` 이 agy·codex 레인을 같은 턴에 병렬로 띄울 때 두 레인이 고정된 프롬프트 파일 이름을 공유해 서로 덮어쓰면 두 CLI 가 동일한 바이트를 리뷰하고도 `agy:OK codex:OK` 로 조용히 통과하던 위양성을 차단한다. SKILL.md Step 4 는 프롬프트 작성과 Step 5 디스패치를 같은 Bash 호출 안에서 수행하도록 명시(Bash 툴은 호출마다 새 서브프로세스라 `$PROMPT_FILE` 이 다음 호출로 이어지지 않는다) (#1276)**
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
- 변경: **`Bash` 폴백 종료 채널이 리포트 *전체 형태* 를 요구하도록 추가로 좁힘 — `grep "gh:issue-flow complete (#1270)" some.log` 는 명령 문자열에 숫자 형식 마커가 있고 grep 이 그 줄을 그대로 stdout 으로 되돌려주므로 쌍 매칭 두 조건을 모두 만족했다. 즉 진행 중인 flow 와 같은 이슈 번호를 로그에서 검색하기만 해도 플로우가 조기 종료될 수 있었다. 이제 짝지어진 `tool_result` 가 마커뿐 아니라 리포트 필드 줄(`PR URL:` 성공형 / `Resume after fix:` 실패형)까지 담아야 종료로 본다 — 한 줄짜리 grep 출력으로는 재현되지 않는 구조다. 명령 쪽 조건은 그대로 두어 heredoc 리포트는 계속 인식되며, `tool_result.content` 가 텍스트 블록 리스트로 쪼개져 오는 경우를 위해 매칭 전 블록을 합친다. 필드 이름이 report-template.md 에서 바뀌면 훅이 조용히 무력화되지 않도록 드리프트 테스트를 함께 추가했다 (#1274)**
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
