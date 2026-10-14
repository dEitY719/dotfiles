# claude/ Module — Agent Context

## Purpose

Claude Code CLI 설정, 계정 라우팅, 훅, 플러그인 매니페스트 관리.
Dependencies: Claude Code CLI, jq (sudo는 #575 이후 불필요)

---

## Skills 소스 — 가장 자주 실수하는 부분

**dotfiles 에는 더 이상 스킬이 없다 (#1680).** 73개 스킬은 #1410 으로 15개
marketplace repo 로 분리됐다. 등록은 `claude/plugin/{marketplaces,plugins}.json`.

- **Claude Code 는 플러그인 전용** — `claude/plugin/restore.sh` 가 설치한 플러그인만 로드한다.
  워크스페이스 스킬을 `~/.claude*/skills/` 에 flat 링크로 합성하지 않는다(네임스페이스 없는
  중복 명령). `claude/setup.sh` 의 `_claude_prune_workspace_skills()` 는 예전 링크를 정리만 한다.
- **나머지 하네스**(Codex / OpenCode / Gemini / agy / Hermes)는 `scripts/setup-skills-ssot.sh` 가
  `${WORKSPACE_ROOT:-~/para/project/skills}/<repo>/skills/<skill>` 을 entry-level 심볼릭 링크로 합성한다.
  열거 SSOT: `shell-common/functions/skill_sources.sh`.
- **절대 하지 말 것**: 합성 대상 디렉토리(`~/.claude*/skills/`, `~/.codex/skills/` 등) 직접 편집,
  Codex `.system/` 삭제. 스킬은 워크스페이스 repo 에서만 생성/수정.

상세(관리 스크립트 표, 동기화 명령, 자동 발견 규칙): [`docs/skills-sources.md`](./docs/skills-sources.md).
배포 경로·갱신 SSOT: `docs/.ssot/skills-distribution.md`.

---

## Configuration Files

- `settings.json` — tracked SSOT 이지만 각 계정 dir 에는 **실파일 복사**(#940, symlink 아님 — `/model`
  write-through 오염 방지). 사내 PC(internal)는 `gateway-cli setup` 이 그 파일을 소유한다.
- 개인 override 슬롯: 계정 dir 의 `settings.local.json`(gitignored, native merge, local 승).
- 계정 라우팅: 외부 PC = 멀티 계정 `~/.claude-<acct>/`, 사내 PC = 단일 `~/.claude/`
  (`~/.dotfiles-setup-mode` 가 `internal` 이면 `claude_yolo` 가 강제, #571).
- symlink: `statusline-command.sh`, `docs/`, `plugins -> ~/.claude-shared/plugins`, `CLAUDE.md`(글로벌 지침),
  `keybindings.json`, `projects/GLOBAL/memory`.
- 훅(SessionStart drift 자동복구, statusline override, plugin path normalize, PostToolUse 디스패처,
  PreToolUse 가드 3종, Stop 가드 공용 헬퍼)과 `mods/cache-watch`, `claude-accounts link`.

**PreToolUse 가드(`claude/hooks/bash_*.py`)의 규칙을 넓히지 말 것** — 오탐은 `tests/integration/test_bash_*_guard.py` 의 ALLOWED 표에 추가하고 규칙을 좁힌다.

상세(계정별 경로 표, 모드별 settings 소유권, 훅별 동작·탈출구): [`docs/config-files.md`](./docs/config-files.md).

---

## Plugin Manifest (claude/plugin/)

- 동기화 두 경로: Shell CLI(`plugin-sync.sh`, PostToolUse) + slash command(`plugin-sync-session.sh`, SessionStart/Stop SSOT-diff, #1082).
- 계약/로컬 분리(#1685): tracked `{marketplaces,plugins}.json` = 등록 계약(PR 로만 변경),
  gitignored `*.local.json` = 이 PC 설치 상태. 소비자는 union, 충돌 시 계약 승. uninstall 은 `removed.local.json` 묘비.
- 사내 전용 항목은 `claude/plugin/company/`(별도 private GHES 레포).
- 신규 PC `./claude/plugin/restore.sh`, 갱신 `./claude/plugin/update-plugins.sh`, 게시 `./claude/plugin/publish-sync.sh`.
- `claude/workspace/AGENTS.md` 는 스킬 작업 폴더 루트 라우터 원본 (#2123).

상세: [`docs/plugins.md`](./docs/plugins.md).

---

## Skill 작성 규칙

- SSOT: 해당 marketplace repo 의 `skills/<name>/SKILL.md` (#1680 이후 dotfiles 밖)
- frontmatter: `name`, `description`, `allowed-tools` 필수
- `name` 형식: `{namespace}:{action}` (e.g. `skill:check`, `gh:commit`)
- SKILL.md ≤ 100줄; 상세 내용은 `references/`로 분리 (Progressive Disclosure)
- `description:` — 단일행 또는 YAML `>-` 멀티라인 모두 허용
- 실행 가능 helper 스크립트 (`.sh` 등) 는 `lib/` 에 둔다 (#699). `references/`
  는 markdown 전용 (paste-verbatim 또는 사람 읽기). 직접 호출 패턴:
  `bash <repo>/skills/<name>/lib/<script>.sh`. 첫 사례:
  `gh-kanban-bootstrap` — 이전 `scripts/` 하위 진입점을 흡수해 단일 SSOT 로 통합.
- `description:` 를 줄이거나 스킬을 리네임한 뒤에는 **트리거 정확도를 실측**한다
  (#1417). `skill:check` Check 16 은 길이만 재므로 "짧으면서 동시에 안 걸리는"
  상태를 통과시킨다. 표본 스킬은 `<repo>/skills/<name>/evals/trigger-eval.json`
  (20쿼리, should-trigger 10 / should-not 10) 을 가지며 계약은
  `after >= before - 5%p`. 옛 수동 하네스 `claude/tools/run-trigger-eval.sh` 는
  #1680 이후 실행 불가(입력이 전부 marketplace repo 로 이동)라 삭제했다 — 필요하면
  git 이력에서 꺼내 marketplace repo 로 포팅한다. 절차·격리 4종·모델 고정 근거:
  `authoring-skills` repo 의 `skills/skill-check/references/trigger-eval-procedure.md`.
