# claude/ Module — Agent Context

## Purpose

Claude Code CLI 설정, 스킬, 자동화 관리.  
Dependencies: Claude Code CLI, jq (sudo는 #575 이후 불필요)

---

## Skills SSOT — 가장 자주 실수하는 부분

**`dotfiles/claude/skills/`** 가 Claude Code·Gemini·Codex 3개 도구 모두의 단일 SSOT다.

### 도구별 연결 방식 (issue #791 — 4 CLI 모두 entry-level 합성으로 통일)

| 도구 | 경로 | 연결 방식 | 신규 스킬 자동 반영 |
|------|------|-----------|---------------------|
| **Claude Code** (모든 모드) | `~/.claude*/skills/<name>` → `dotfiles/claude/skills/<name>` | entry-level symlink (#707, F-8) | ❌ setup 재실행 필요 |
| **Codex** | `~/.codex/skills/<name>` → `dotfiles/claude/skills/<name>` | entry-level symlink (#707 → #791) + `.system` 로컬 보존 | ❌ setup 재실행 필요 |
| **OpenCode** | `~/.config/opencode/skills/<name>` → `dotfiles/claude/skills/<name>` | entry-level symlink (#791) | ❌ setup 재실행 필요 |
| **Gemini CLI** | `~/.gemini/skills/<name>` → `dotfiles/claude/skills/<name>` | entry-level symlink (#791) | ❌ setup 재실행 필요 |

`~/.claude*/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/`, `~/.gemini/skills/` 는 모두 **실제 디렉토리** 이며 child entry 만 `dotfiles/claude/skills/<name>` 로 가는 symlink. 이 4-way 일관성이 외부에서 추가된 symlink (마켓플레이스 `npx skills add`, 수동 링크 등) 를 모든 CLI 의 같은 디렉토리에 추가 entry 로 layer 할 여지를 만든다. SSOT 위치 자체는 변하지 않음.

### 관리 스크립트

| 도구 | 담당 스크립트 / 함수 | 트리거 |
|------|----------------------|--------|
| Claude Code (각 계정) | `shell-common/tools/integrations/claude.sh` → `_claude_account_setup_one()` + `_claude_compose_skills_dir()` (#707, F-8) | `./claude/setup.sh` |
| OpenCode / Gemini | `scripts/setup-skills-ssot.sh` → `link_skills_compose()` (#791) | `./setup.sh` 또는 `./scripts/setup-skills-ssot.sh` |
| Codex | `scripts/setup-skills-ssot.sh` → `link_skills_individual_codex()` | `./setup.sh` 또는 `./scripts/setup-skills-ssot.sh` |

### 신규 스킬 추가 후 동기화

```bash
./claude/setup.sh                   # Claude Code 계정
./scripts/setup-skills-ssot.sh      # Codex / OpenCode / Gemini
# 또는 한번에:
./setup.sh
```

4 CLI 모두 entry-level symlink 합성이라 (#707, F-8 + #791) 새 스킬 디렉토리를 추가했을 때 위 명령으로 빠진 entry 만 추가된다. Idempotent.

### 연결 방식이 통일된 이유 (issue #791)

- **Codex 특수**: `.system/` (내장 skill) 디렉토리는 로컬 보존하므로 `link_skills_individual_codex` 가 따로 존재. OpenCode/Gemini 는 내장 디렉토리가 없으므로 단순한 `link_skills_compose` 로 충분.

### 절대 하지 말 것

- `~/.claude*/skills/`, `~/.gemini/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/` 직접 편집 금지
- 스킬은 반드시 SSOT인 `dotfiles/claude/skills/`에만 생성/수정
- Codex `.system/` 디렉토리 삭제 금지 (Codex 내장 스킬)

---

## Configuration Files

```bash
# 외부 PC (옵션 1, 3) — 멀티-계정
~/.claude-personal/settings.json         = dotfiles/claude/settings.json 의 실파일 복사 (#940, symlink 아님)
~/.claude-personal/statusline-command.sh -> dotfiles/claude/statusline-command.sh
~/.claude-personal/skills/<name>         -> dotfiles/claude/skills/<name>   (entry symlink, #707)
~/.claude-personal/docs                  -> dotfiles/claude/docs            (dir symlink, #575)
~/.claude-personal/plugins               -> ~/.claude-shared/plugins
~/.claude-personal/projects/GLOBAL/memory -> dotfiles/claude/global-memory
~/.claude-personal/CLAUDE.md             -> dotfiles/claude/CLAUDE.md       (글로벌 지침, #1115)

# 사내 PC (옵션 2) — 단일 계정 (issue #571)
~/.claude/settings.json                  = aws/setup.sh 가 SSOT + Bedrock 오버레이를 merge 한 실파일 (#687)
~/.claude/statusline-command.sh          -> dotfiles/claude/statusline-command.sh
~/.claude/skills/<name>                  -> dotfiles/claude/skills/<name>   (entry symlink, #707)
~/.claude/docs                           -> dotfiles/claude/docs            (dir symlink)
~/.claude/plugins                        -> ~/.claude-shared/plugins
~/.claude/projects/GLOBAL/memory         -> dotfiles/claude/global-memory
~/.claude/CLAUDE.md                      -> dotfiles/claude/CLAUDE.md       (글로벌 지침, #1115)

# 모든 환경 공통 (issue #791 — 4 CLI 모두 entry-level 합성)
~/.codex/skills/<name>                   -> dotfiles/claude/skills/<name>   (entry symlink, #707 → #791)
~/.config/opencode/skills/<name>         -> dotfiles/claude/skills/<name>   (entry symlink, #791)
~/.gemini/skills/<name>                  -> dotfiles/claude/skills/<name>   (entry symlink, #791)
```

기존 PC 에 남아 있는 `/etc/sudoers.d/claude-{skills,docs}-mount-*` 파일은 #575 이후로 사용처가 없다. `claude/setup.sh` 실행 시 잔존 파일이 감지되면 수동 삭제 명령을 안내한다.

`settings.json` — **tracked SSOT** (#584). 모든 모드에서 config dir 의 `settings.json` 은 SSOT 의 **실파일 복사**다 — 멀티 계정은 `_claude_ensure_settings_copy` (#940), Internal 은 `aws/setup.sh` merge (#687). symlink 였던 구 레이아웃은 Claude Code `/model` 이 tracked SSOT 를 write-through 로 오염시켰음 (#924 → #940). 기존 실파일의 개인 `model` 키는 setup 재실행 시 `settings.local.json` 으로 자동 이주.
`~/.claude/settings.local.json` — out-of-repo, gitignored, Internal PC 1회 손수 작성. 사번 헤더 / 사내 `ANTHROPIC_*` 가 들어가며 Claude Code 가 settings.json 과 native merge. `claude/setup.sh` 가 Internal 모드 종료 직전 copy-paste heredoc 안내 출력 (#584).

`~/.dotfiles-setup-mode` 가 `internal` 이면 `claude_yolo` 가 멀티-계정 해석을 우회하고 `~/.claude/` 를 강제 사용 (F-2). 잘못 migrate된 사내 PC 복구: `claude-accounts rollback` (F-3). 자세한 내용은 `docs/guide/internal-pc.md`.

`claude/hooks/session-start-pc-context.sh` — `SessionStart` hook, `settings.json`에 등록됨. `~/.dotfiles-setup-mode` + hostname을 매 세션 시작마다 `additionalContext`로 주입해 5대 PC 혼동을 방지한다(#1052). 모드 파일이 없으면 조용히 빈 컨텍스트를 반환하고 세션 시작을 막지 않는다.

`claude/hooks/session-start-settings-drift.sh` — `SessionStart` hook, `settings.json`에 등록됨. 모든 모드에서 live `settings.json`은 SSOT의 **실파일**이라 SSOT에 훅을 추가/변경한 커밋 이후 `./setup.sh`(internal: `./aws/setup.sh`) 재실행 전까지 새 훅이 발화하지 않는다(#1086). 이 훅은 SSOT(`claude/settings.json`, 스크립트 경로 기준 상대 해석)와 live(`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`)의 `.hooks` 필드만 jq로 비교해 drift 감지 시 stderr + `additionalContext`로 재시드를 안내한다. Bedrock 오버레이는 `.hooks`를 건드리지 않아 오탐이 없다. 자기 자신의 최초 미설치는 감지 못하지만(체크인 후 1회 재시드 필요) 이후 추가되는 모든 훅은 커버한다. best-effort, 항상 exit 0.

`claude/hooks/session-start-statusline-project-override.sh` — `SessionStart` hook, `settings.json`에 등록됨. Claude Code 의 settings 병합 우선순위(`settings.local.json` > 프로젝트 `settings.json` > 글로벌 `~/.claude/settings.json`)상, 프로젝트의 git-tracked `.claude/settings.json`이 자체 `.statusLine`을 정의하면 dotfiles 글로벌 statusline 을 덮어쓴다(#1236). 이를 되살릴 유일한 개인 슬롯인 `<project>/.claude/settings.local.json`은 gitignore 대상이라 fresh clone/새 worktree 마다 사라진다. 이 훅은 페이로드의 `.cwd`로 프로젝트를 식별해, 프로젝트 `settings.json`에 `.statusLine`이 있고 local 에 아직 개인 override 가 없을 때 SSOT(`claude/settings.json`, 스크립트 경로 기준 상대 해석)의 `.statusLine`을 `settings.local.json`에 seed/merge 한다(기존 키 보존). 안전장치: `git check-ignore`로 `settings.local.json`이 실제 gitignore 대상일 때만 write 하고(아니면 write 대신 .gitignore 추가 힌트만 출력해 working tree 오염 방지), 기존 `.statusLine`은 절대 덮어쓰지 않는 멱등 동작. best-effort, 항상 exit 0.

`claude/hooks/session-start-plugin-path-normalize.sh` — `SessionStart` hook, `plugin-sync-session.sh`보다 **먼저** 등록됨(#1098). 모든 계정 `plugins` 디렉터리가 `~/.claude-shared/plugins` 한 곳으로 symlink되어 SSOT를 공유하는데, Claude Code 2.1.199+는 marketplace `installLocation`을 `$CLAUDE_CONFIG_DIR/plugins/marketplaces` 기준 **문자열 prefix로만**(symlink 미해석) 검증한다. 공유 파일에 담긴 단일 표기는 다른 계정에서 "corrupted installLocation"으로 거부되므로, 이 훅이 시작 중인 계정의 `$CLAUDE_CONFIG_DIR` 표기로 `known_marketplaces.json`의 `installLocation`과 `installed_plugins.json`의 `installPath`(예방 차원)를 재작성한다(`~/.claude*/plugins/` prefix만 대상, 그 외 경로는 불변). 경로 **값**만 바꾸고 marketplace/plugin **키셋**은 건드리지 않아 `plugin-sync.sh`의 union-merge/삭제 감지에 영향을 주지 않는다. 의미 변화가 있을 때만 1회 백업 후 재작성하는 멱등 동작이라 매 세션 mtime이 안정적이다. best-effort, 항상 exit 0.

---

## Plugin Manifest (claude/plugin/)

플러그인 변경은 **두 진입 경로** 모두에서 동기화된다:

1. **Shell CLI** (`claude plugin install/uninstall`, `claude plugin
   marketplace add/remove`) — `claude/hooks/plugin-sync.sh` (PostToolUse+Bash
   hook)가 명령어 문자열을 정규식으로 감지.
2. **내장 slash command** (`/plugin install|uninstall`, `/plugin marketplace
   add|remove`) — Claude Code UI 파이프라인을 통과해 Bash tool call 을 만들지
   않으므로 PostToolUse hook 이 안 잡힌다. `claude/hooks/plugin-sync-session.sh`
   (SessionStart+Stop hook)가 SSOT (`~/.claude-shared/plugins/{known_marketplaces,
   installed_plugins}.json`) 해시를 세션 시작 시 stash 하고, 매 Stop 마다 diff 해
   변화가 있으면 `plugin-sync.sh` 의 add/uninstall 분기를 재실행한다 — 진입 경로
   무관 (add + remove 대칭 처리, #1082). Claude Code 2.1.x 는 slash command 전용
   hook event 를 노출하지 않아 이 SSOT-diff 방식을 택했다.

두 경로 모두 `claude/plugin/{marketplaces,plugins}.json`(공용, scope:user +
source:github만)에 병합 반영하고 로컬 커밋한다. 사내 전용
(non-github source) 항목은 `claude/plugin/company/`(dotfiles 트리 안이지만
자체 `.git`을 가진 별도 private GHES 레포, `.gitignore`로 public 레포
추적 제외)로 간다 — internal PC에서 최초 1회 `git clone <url>
claude/plugin/company` 필요.

external/public PC에서 사내 GHES 마켓플레이스가 우연히 감지되면(company/
레포 미clone) hook은 격리 정책상 저장하지 않고 stderr 힌트만 남긴다 — 조용한
skip이 아니다 (#1080).

신규 PC: `./claude/plugin/restore.sh` (mode-aware, `--dry-run` 지원). 대상
config dir 은 setup-mode 로 라우팅된다 (#1103) — internal → `~/.claude`,
그 외 → `~/.claude-<account>` (기본 `$CLAUDE_DEFAULT_ACCOUNT`). 특정 계정은
`--user <account>`, 전체 계정은 `--all-accounts`.

두 레포 모두 "PR을 통해서만 변경 가능" 규칙이 걸려 있어 hook의 로컬 커밋이
origin에 직접 push되지 않는다 — `./claude/plugin/publish-sync.sh`
(`--dry-run` 지원)를 수동 실행하면 쌓인 변경분을 브랜치+PR+admin-merge로
게시한다. internal PC는 github.com이 pull-only라 public 단계를 자동으로
건너뛴다 (company/ GHES 단계만 게시, #1080). 자세한 설계: `docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md`,
`docs/feature/superpowers-specs/2026-07-02-plugin-manifest-batch-publish-design.md`.

---

## Skill 작성 규칙

- SSOT: `dotfiles/claude/skills/<name>/SKILL.md`
- frontmatter: `name`, `description`, `allowed-tools` 필수
- `name` 형식: `{namespace}:{action}` (e.g. `skill:check`, `gh:commit`)
- SKILL.md ≤ 100줄; 상세 내용은 `references/`로 분리 (Progressive Disclosure)
- `description:` — 단일행 또는 YAML `>-` 멀티라인 모두 허용
- 실행 가능 helper 스크립트 (`.sh` 등) 는 `lib/` 에 둔다 (#699). `references/`
  는 markdown 전용 (paste-verbatim 또는 사람 읽기). 직접 호출 패턴:
  `bash claude/skills/<name>/lib/<script>.sh`. 첫 사례:
  `gh-kanban-bootstrap` — 이전 `scripts/` 하위 진입점을 흡수해 단일 SSOT 로 통합.
