# Configuration Files 와 훅

> `claude/AGENTS.md` 에서 분리 (#2151). 요약·라우팅은 [`claude/AGENTS.md`](../AGENTS.md).

```bash
# 외부 PC (옵션 1, 3) — 멀티-계정
~/.claude-personal/settings.json         = dotfiles/claude/settings.json 의 실파일 복사 (#940, symlink 아님)
~/.claude-personal/statusline-command.sh -> dotfiles/claude/statusline-command.sh
~/.claude-personal/skills/                실디렉토리 (#707) — 워크스페이스 스킬은 플러그인으로 로드, flat 링크 없음 (외부 링크만)
~/.claude-personal/docs                  -> dotfiles/claude/docs            (dir symlink, #575)
~/.claude-personal/plugins               -> ~/.claude-shared/plugins
~/.claude-personal/projects/GLOBAL/memory -> dotfiles/claude/global-memory
~/.claude-personal/CLAUDE.md             -> dotfiles/claude/CLAUDE.md       (글로벌 지침, #1115)
~/.claude-personal/keybindings.json      -> dotfiles/claude/keybindings.json (Ctrl+J -> chat:sendNow; Ctrl+Enter 는 대부분 터미널에서 LF 로 도착해 ctrl+j 에 바인딩)

# 사내 PC (옵션 2) — 단일 계정 (issue #571)
~/.claude/settings.json                  = gateway-cli setup 이 쓰는 실파일 (조직 LLM Gateway 도구 소유, 2026-08-18~)
~/.claude/statusline-command.sh          -> dotfiles/claude/statusline-command.sh
~/.claude/skills/                        실디렉토리 (#707) — 워크스페이스 스킬은 플러그인으로 로드, flat 링크 없음 (외부 링크만)
~/.claude/docs                           -> dotfiles/claude/docs            (dir symlink)
~/.claude/plugins                        -> ~/.claude-shared/plugins
~/.claude/projects/GLOBAL/memory         -> dotfiles/claude/global-memory
~/.claude/CLAUDE.md                      -> dotfiles/claude/CLAUDE.md       (글로벌 지침, #1115)
~/.claude/keybindings.json               -> dotfiles/claude/keybindings.json (Ctrl+J -> chat:sendNow; Ctrl+Enter 는 대부분 터미널에서 LF 로 도착해 ctrl+j 에 바인딩)

# 모든 환경 공통 (issue #791 — CLI 모두 entry-level 합성)
~/.codex/skills/<name>                   -> <workspace>/<repo>/skills/<name> (entry symlink, #707 → #791)
~/.config/opencode/skills/<name>         -> <workspace>/<repo>/skills/<name> (entry symlink, #791)
~/.gemini/config/skills/<name>           -> <workspace>/<repo>/skills/<name> (entry symlink, #1731 — agy, #1787)
```

`statusline-tokens.sh` (#1380) 은 계정 dir 로 링크하지 **않는다** — `statusline-command.sh` 가 자기 경로의 symlink 를 따라간 뒤 형제 파일로 source 하므로 SSOT 한 곳에만 있으면 직접 실행/symlink 경로 양쪽에서 해석된다. 없으면 세션 누적 토큰 세그먼트만 빠지고 나머지는 정상 렌더된다.

`claude/mods/cache-watch/` (#2026) — Claude Code mod(함수 훅 플러그인, 2.1.287+). 메인 스레드 `turn.step` 응답의 cache read+creation 토큰 > 0 이면 `~/.cache/claude-cache-watch/<session_id>` 에 `<lastTouchEpochSec> <ttlSec>` 한 줄을 쓴다(TTL 은 `session.start` 의 `ENABLE_PROMPT_CACHING_1H`). `statusline-command.sh` 가 이를 읽어 `⏱️ 1h` 옆에 `cache 57m` / `cache <1m` / `cache expired` 를 붙이고, 파일이 없으면 생략한다. 로드: SSOT `settings.json` 의 `env.CLAUDE_CODE_PLUGIN_DIRS`(`~/dotfiles/claude/mods/cache-watch`)가 `claude/setup.sh` 의 settings 복사로 각 계정에 배포되고, setup.sh 가 계정별로 이를 확인한다(수동 `--plugin-dir` 불필요). internal 모드는 gateway-cli 가 settings.json 을 소유해 setup 복사가 닿지 않지만, `session-start-settings-drift.sh` 가 `env.CLAUDE_CODE_PLUGIN_DIRS` 단일 키만 live 에 복구한다(#2056, 다음 세션부터 적용). 유휴 중 분 단위 갱신은 `settings.json` 의 `statusLine.refreshInterval: 60`. 검증: `claude plugin validate|test claude/mods/cache-watch`. 오래된 파일 정리는 없음(이 빌드의 `$.fs` 에 delete 부재).

기존 PC 에 남아 있는 `/etc/sudoers.d/claude-{skills,docs}-mount-*` 파일은 #575 이후로 사용처가 없다. `claude/setup.sh` 실행 시 잔존 파일이 감지되면 수동 삭제 명령을 안내한다.

`settings.json` — **tracked SSOT** (#584). 모든 모드에서 config dir 의 `settings.json` 은 symlink 가 아닌 **실파일**이다. 다만 그 실파일을 *쓰는 주체*가 모드별로 다르다:
- **외부/공용 PC (멀티 계정)** — dotfiles 소유. `_claude_ensure_settings_copy` 가 SSOT 를 그대로 복사 (#940). 재시드: `./setup.sh`.
- **사내 PC (2026-08-18~)** — **dotfiles 소유 아님**. 조직 LLM Gateway 전환 도구 `gateway-cli setup` 이 이 파일을 직접 쓴다 (`apiKeyHelper` / 자격증명 키 / `cleanupPeriodDays` / `env.*`). 종전의 "SSOT + 오버레이 jq deep-merge" (#687) 는 2026-08-18 폐지, 관련 스크립트는 #2097 에서 삭제 — 한 파일에 writer 가 둘이면 서로를 지우는 왕복이 되기 때문(실제로 gateway-cli 가 `.statusLine` 을 자기 바이너리로 덮어썼다). dotfiles 가 사내 live 파일에 남긴 지분은 둘뿐이다: 아래 `session-start-settings-drift.sh` 의 `.hooks`/`.statusLine` 자동 복구, 그리고 그 훅 **자신의 등록** 1건을 `claude/tools/register-drift-hook.sh` 가 되살리는 F-7b (#1364). 재시드는 `gateway-cli setup` / 점검은 `gateway-cli verify`.

symlink 였던 구 레이아웃은 Claude Code `/model` 이 tracked SSOT 를 write-through 로 오염시켰음 (#924 → #940). 기존 실파일의 개인 `model` 키는 setup 재실행 시 `settings.local.json` 으로 자동 이주.
`~/.claude/settings.local.json` — out-of-repo, gitignored, 개인 override 의 정식 슬롯 (#924). Claude Code 가 settings.json 과 native merge 하며 local 이 이긴다. 사내 PC 에서 gateway-cli 가 쓴 키를 개인적으로 덮고 싶을 때도 여기를 쓴다 (live `settings.json` 직접 편집 금지 — gateway-cli 재실행에 지워진다).

`~/.dotfiles-setup-mode` 가 `internal` 이면 `claude_yolo` 가 멀티-계정 해석을 우회하고 `~/.claude/` 를 강제 사용 (F-2). 잘못 migrate된 사내 PC 복구: `claude-accounts rollback` (F-3). 자세한 내용은 `docs/guide/internal-pc.md`.

`claude-accounts link [<src>] / unlink <name> / link --list` (#1847) — 3rd-party 설치기(`npx skills add`, `graphify install`)가 `CLAUDE_CONFIG_DIR` 없이 `~/.claude/skills/` 로 떨어뜨린 스킬을 `~/.claude-*/skills` (`-shared`/`-backups` 제외, 없으면 `~/.claude/skills`) 전체에 절대경로 심링크로 fan-out. 인자 없는 `link` 는 dry-run 기본(`--apply` 로 적용), `--force` 는 심링크만 교체, `unlink` 는 심링크만 제거. 워크스페이스 밖을 가리키는 링크라 `claude/setup.sh` 의 워크스페이스 링크 정리(`_claude_prune_workspace_skills`)에도 유지된다. 워크스페이스 안을 가리키는 entry 는 플러그인으로 로드되므로 fan-out 대상이 아니다 (setup 이 정리한다).

`claude/hooks/session-start-pc-context.sh` — `SessionStart` hook, `settings.json`에 등록됨. `~/.dotfiles-setup-mode` + hostname을 매 세션 시작마다 `additionalContext`로 주입해 5대 PC 혼동을 방지한다(#1052). 모드 파일이 없으면 조용히 빈 컨텍스트를 반환하고 세션 시작을 막지 않는다.

`claude/hooks/session-start-settings-drift.sh` — `SessionStart` hook, `settings.json`에 등록됨. 모든 모드에서 live `settings.json`은 SSOT의 **실파일**이라 SSOT에 훅을 추가/변경한 커밋 이후 재시드 전까지 새 훅이 발화하지 않는다(#1086). SSOT(`claude/settings.json`, 스크립트 경로 기준 상대 해석)와 live(`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`)의 **`.hooks` + `.statusLine`** 두 필드를 jq로 비교한다 — dotfiles가 "동작"으로 배포하는 필드는 이 둘뿐이고, 나머지(auth/model)는 소유자가 다르다.
- **사내 모드 (2026-08-18~)**: drift 감지 시 그 두 키만 live 파일에 in-place **자동 복구**하고 "auto-corrected — no action needed" 로 알린다. #687 재시드 머지 폐지로 사내 PC의 재시드 통로가 없어졌고, gateway-cli가 `.statusLine`을 자기 바이너리로 덮어쓰는 실제 사고가 있었기 때문. 백업은 `~/.claude-backups/settings.json.pre-drift-heal.backup` (latest-only, #919/#806). gateway-cli 소유 키(`apiKeyHelper`/자격증명 키/`cleanupPeriodDays`/`env`/`model`/`availableModels`)와 Claude Code 네이티브 키(`enabledPlugins`/`extraKnownMarketplaces`)는 **절대 건드리지 않는다**. live가 symlink거나 SSOT가 해당 키를 정의하지 않거나 patch가 실패하면 자동 복구를 포기하고 안내만 한다.
- **그 외 모드**: 종전 그대로 안내만 (`./setup.sh` 재실행 → `claude/setup.sh` 실파일 복사, #940).

자기 자신의 최초 미설치는 감지 못하지만(체크인 후 1회 재시드 필요) 이후 추가되는 모든 훅은 커버한다. best-effort, 항상 exit 0.
- **부트스트랩 데드락과 그 탈출구 (#1364)**: Claude Code 는 live `.hooks.SessionStart` 에 등록된 훅만 호출하므로, 외부 요인이 live `.hooks` 를 통째로 날리면 이 훅의 등록도 함께 사라져 훅이 **스스로를 복구할 수 없다** — 위 "자기 자신" 한계의 심각한 형태. 탈출구는 F-7b `claude/tools/register-drift-hook.sh` (internal 모드 `./setup.sh` → `claude/setup.sh` 가 호출, 수동 실행도 가능, #2097 에서 이관). 스코프 경계: 훅 커맨드는 SSOT 에서 jq 로 읽고, `.hooks.SessionStart` 에 그 1건만 append 하며, live 파일을 새로 만들거나 symlink 를 따라가지 않고, 그 외 키는 읽지도 쓰지도 않는다 — 키를 하나라도 더 얹으면 #687 왕복이 재발한다. 회귀 가드: `tests/bats/setup/register_drift_hook.bats`.

`claude/hooks/session-start-statusline-project-override.sh` — `SessionStart` hook, `settings.json`에 등록됨. Claude Code 의 settings 병합 우선순위(`settings.local.json` > 프로젝트 `settings.json` > 글로벌 `~/.claude/settings.json`)상, 프로젝트의 git-tracked `.claude/settings.json`이 자체 `.statusLine`을 정의하면 dotfiles 글로벌 statusline 을 덮어쓴다(#1236). 이를 되살릴 유일한 개인 슬롯인 `<project>/.claude/settings.local.json`은 gitignore 대상이라 fresh clone/새 worktree 마다 사라진다. 이 훅은 페이로드의 `.cwd`로 프로젝트를 식별해, 프로젝트 `settings.json`에 `.statusLine`이 있고 local 에 아직 개인 override 가 없을 때 SSOT(`claude/settings.json`, 스크립트 경로 기준 상대 해석)의 `.statusLine`을 `settings.local.json`에 seed/merge 한다(기존 키 보존). 안전장치: `git check-ignore`로 `settings.local.json`이 실제 gitignore 대상일 때만 write 하고(아니면 write 대신 .gitignore 추가 힌트만 출력해 working tree 오염 방지), 기존 `.statusLine`은 절대 덮어쓰지 않는 멱등 동작. best-effort, 항상 exit 0.

`claude/hooks/session-start-plugin-path-normalize.sh` — `SessionStart` hook, `plugin-sync-session.sh`보다 **먼저** 등록됨(#1098). 모든 계정 `plugins` 디렉터리가 `~/.claude-shared/plugins` 한 곳으로 symlink되어 SSOT를 공유하는데, Claude Code 2.1.199+는 marketplace `installLocation`을 `$CLAUDE_CONFIG_DIR/plugins/marketplaces` 기준 **문자열 prefix로만**(symlink 미해석) 검증한다. 공유 파일에 담긴 단일 표기는 다른 계정에서 "corrupted installLocation"으로 거부되므로, 이 훅이 시작 중인 계정의 `$CLAUDE_CONFIG_DIR` 표기로 `known_marketplaces.json`의 `installLocation`과 `installed_plugins.json`의 `installPath`(예방 차원)를 재작성한다(`~/.claude*/plugins/` prefix만 대상, 그 외 경로는 불변). 경로 **값**만 바꾸고 marketplace/plugin **키셋**은 건드리지 않아 `plugin-sync.sh`의 union-merge/삭제 감지에 영향을 주지 않는다. 의미 변화가 있을 때만 1회 백업 후 재작성하는 멱등 동작이라 매 세션 mtime이 안정적이다. best-effort, 항상 exit 0.

`claude/hooks/post-bash-dispatch.sh` — `PostToolUse:Bash` 단일 front-door, `settings.json`에 등록됨(#1144). Claude Code 는 매 Bash tool call 마다 등록된 훅 수만큼 프로세스를 띄우므로 `post-gh-pr-create.sh` / `plugin-sync.sh` 를 직접 등록하면 호출당 2 spawn 이 된다. 이 디스패처가 stdin 을 한 번만 파싱하고 명령어가 관련 있어 보일 때만 핸들러로 라우팅한다(핸들러는 여전히 standalone — 각자 stdin 을 재필터링). **라우팅된 경로에서만** `<entry-ms> <pre-invoke-ms> <post-exit-ms> <handler>` 한 줄을 `${XDG_STATE_HOME:-$HOME/.local/state}/claude/post-bash-dispatch-timing.log` 에 append 한다(#1258) — 대다수인 비매칭 경로는 계측 I/O 를 하지 않는다(#1144 가 없앤 호출당 오버헤드를 되살리지 않기 위함). 로그는 1000줄 초과 시 최근 500줄로 잘린다. 집계는 `claude/tools/hook-perf-report.sh`(수동 진단 도구, transcript `durationMs` + 이 stage 로그를 median/p90/p99/max 로 리포트, 목표: median < 2000ms · p99 < 5000ms). ms 변환 헬퍼 `_pbd_ms` 는 `claude/hooks/lib/pbd_ms.sh` 로 분리되어 있다 — 디스패처는 stdin 을 읽고 조기 `exit` 하는 스크립트라 source 가 불가능해, BSD `date`(`%3N` 미지원) fallback 티어를 테스트할 방법이 없었기 때문(`tests/bats/skills/pbd_ms_lib.bats`). 라이브러리는 순수 함수만 담고 top-level side effect 가 없으며, 경로는 `POST_BASH_DISPATCH_DIR`(테스트 stub 용 override)가 아니라 스크립트 자신의 실제 디렉터리로 해석한다. source 실패 시 no-op 함수로 degrade — 계측이 조용히 빠질 뿐 훅은 깨지지 않는다. best-effort, 항상 exit 0.

`claude/hooks/post-gh-pr-create.sh` — 위 디스패처가 `gh pr create` 에서 라우팅하는 핸들러. PR 카드를 "In review", `Closes #N` 로 연결된 이슈를 "In progress" 로 project board 동기화한다(#390). #813 의 auto-add race 흡수용 retry-poll 이 인라인이라 PostToolUse 가 median 7.8s / max 48.7s 를 잡아먹었으므로, #1258 부터 **foreground 에는 sync 1회만** 남기고 나머지(board 유무 probe + 2회차 이후 retry-poll + 연결 이슈 동기화)는 detach 된 백그라운드 서브프로세스로 넘긴다 — 자식이 훅의 stdout/stderr 를 잡고 있으면 Claude Code 가 파이프를 계속 기다리므로 `</dev/null >/dev/null 2>&1 & disown` 리다이렉션이 필수다. 테스트는 `POST_GH_PR_CREATE_ASYNC=0` 으로 deferred 구간을 foreground 에 고정해 호출 횟수를 결정론적으로 검증한다. board 유무 probe 가 쓰는 `_gh_project_status_normalize_repo` 호출부는 #724 가드(`command -v` → inline split)를 반드시 유지한다 — 훅과 헬퍼는 따로 배포되므로 헬퍼가 그 함수를 아직 모르는 rollout-skew 창에서 가드 없이는 `has_board` 가 조용히 false 가 되어 #813 retry-poll 이 통째로 사라진다(#1414). 그 skew 경고는 probe 안이 아니라 **헬퍼 source 직후 foreground** 에 있어야 한다 — probe 는 detach 된 tail 안이라 stderr 가 `/dev/null` 로 버려진다. best-effort, 항상 exit 0.

`claude/hooks/bash_wait_loop_guard.py` — `PreToolUse:Bash` guard, `settings.json`에 등록됨(#1521, PR #1547 리뷰로 판정 기준 교정). 이 저장소가 `PreToolUse` 이벤트를 배선하는 첫 훅이다. 자작 대기 루프 중 **종료가 구조적으로 불가능한 두 형태만** 좁게 거절한다 — 판정은 **패턴 등장 횟수가 아니라 루프 구조** 기준이다: (1) `until ! pgrep -f <TOKEN>` / `while pgrep -f <TOKEN>` 처럼 리터럴 `pgrep -f` 가 **루프의 종료 조건**으로 쓰이고 그 루프 본문에 `sleep` 이 있는 경우 — Bash 도구가 명령을 `zsh -c … eval '<command>'` 래퍼로 감싸므로 래퍼의 커맨드라인이 곧 이 명령이고, 패턴이 (pgrep 자신의 인자로서) 단 한 번만 등장해도 자기매칭이 확정된다(#1521 실측 49분). 등장 횟수 기반 판정은 초판에서 오탐(`pgrep -f ep` 같이 패턴이 `pgrep`/`-f` 자체의 부분 문자열인 일회성 호출까지 차단)과 미탐(루프 안에서 패턴이 한 번만 나오는 위험 사례를 통과) 양쪽에서 틀렸음이 PR #1547 리뷰(agy·codex)로 확인되어 폐기됐다. (2) `tasks/*.output` 을 도는 `until`/`while` + `sleep` 무한 폴링(단, 경로 참조와 `sleep` 이 **같은 루프**의 조건/본문에 구조적으로 연결된 경우만) — 서브에이전트 완료는 하네스가 자동 통지하므로 중복이다. **규칙을 넓히지 말 것**: Monitor 도구 문서가 `until grep -q "Ready in" dev.log; do sleep 0.5; done` 형태를 권장하므로 일반 폴링 루프(및 루프 밖 일회성 `pgrep -f`)는 반드시 통과해야 하고, `tests/integration/test_bash_wait_loop_guard.py` 가 그 명령을 ALLOWED 로 고정한다. 거절 사유는 문자클래스 회피(`[a]7ab…`)만 권한다 — `$$` 는 더 이상 허용 신호가 아니다: Bash 도구가 명령을 `zsh -c … eval '<command>'` 래퍼로 감싸 자기매칭이 2건(안쪽 셸 + 바깥 래퍼) 잡히므로 `| grep -vx "$$"` 는 그중 하나만 지워 루프가 여전히 끝나지 않는다(실측, #1521 pid 179954+1226029) — 루프 안에서 이 관용구를 쓴 명령도 그대로 차단한다. 출력 스키마는 Stop 훅들의 레거시 `{"decision":"block"}` 이 아니라 현행 `hookSpecificOutput.permissionDecision:"deny"` + exit 0 다. 탈출구 `BASH_WAIT_LOOP_GUARD_BYPASS=1`, 트레이스 `BASH_WAIT_LOOP_GUARD_TRACE=1`. 모든 예외에 fail-open, 항상 exit 0.

`claude/hooks/bash_stdin_repl_guard.py` — 같은 `PreToolUse:Bash` 항목의 두 번째 훅(#1815). **인자 없는 인터프리터 호출**(`python`/`python3`/`python3.X`/경로형, `node`, `ruby`, `irb`, `lua`)을 명령어 위치에서, stdin 리다이렉트(`<` `<<` `<<<`) 없이, 파이프 오른쪽이 아닐 때만 거절한다 — Bash 도구는 stdin 을 열어 두므로 EOF 가 오지 않아 영원히 대기한다(brokerdesk PR #78 실측 64분). 뒤따르는 출력 리다이렉트(`2>/dev/null`)만으로는 인자로 치지 않는다. 끝의 `&` 도 면제가 아니다: bash 는 async job 에 `/dev/null` 을 주지만 zsh 는 열린 stdin 을 그대로 물려준다(실측). 따옴표·주석·heredoc 본문은 명령으로 보지 않는다. `bun`/`deno` 는 v1 제외. **규칙을 넓히지 말 것** — 오탐 신고는 `tests/integration/test_bash_stdin_repl_guard.py` 의 ALLOWED 표에 추가하고 규칙을 좁힌다. 재작성(`updatedInput`)이 아니라 deny 인 이유: 재작성은 `permissionDecision:"allow"` 를 동반해 모든 Bash 권한 확인을 건너뛴다. 탈출구 `BASH_STDIN_REPL_GUARD_BYPASS=1`, 트레이스 `BASH_STDIN_REPL_GUARD_TRACE=1`. fail-open, 항상 exit 0.

`claude/hooks/bash_unattended_rm_allow.py` — 같은 `PreToolUse:Bash` 항목의 세 번째 훅(#2119). `sh -c`/`xargs ... sh -c`/`eval` 안의 `rm` 은 하네스가 `could not be checked` 확인 프롬프트를 띄우고, 무인 세션은 타임아웃 후 자동 거부해 명령이 실패한다. `permission_mode == bypassPermissions` 이고 모든 `rm`/`rmdir` 인자가 `/tmp/claude-<uid>/` 하위(리터럴, 또는 같은 명령에서 그 경로/`mktemp -d` 로 대입한 `$VAR`, `..` 없음)일 때만 `allow`, 아니면 무의견(`rm` 단어가 없어도 ` -c ` 스크립트 인자가 있으면 같은 프롬프트라 `allow`). 정규식 스캔이라 중첩 따옴표를 꿰뚫지만 과매칭은 allow 누락일 뿐 오허용이 아니다. **hook allow 가 이 내장 rm 안전 검사를 실제로 우회하는지는 실측 필요(미검증).** 탈출구 `BASH_UNATTENDED_RM_ALLOW_BYPASS=1`. 짝 지침: `claude/CLAUDE.md` "무인 세션 rm 규칙". fail-open.

`claude/hooks/_hook_common.py` — Stop 가드 3종(`gh_issue_flow_stop_guard.py` / `devx_autopilot_stop_guard.py` / `skill_completion_guard.py`)이 공유하는 stdlib 전용 헬퍼(`load_transcript`, `message_payload`, `line_anchored_alternation`). 훅은 settings.json 의 `${HOME}/dotfiles/...` 경로(symlink 일 수 있음)로 실행되므로 각 훅이 `sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))` 로 **실제 위치**에서 import 한다 — 계정 디렉터리에 개별 링크가 없으니 매니페스트 갱신은 불필요. import 실패 시 `sys.exit(0)` 로 fail-open. 테스트: `tests/integration/test_hook_common.py`, `test_hook_symlink_invocation.py`.
