# claude/ Module — Agent Context

## Purpose

Claude Code CLI 설정, 스킬, 자동화 관리.  
Dependencies: Claude Code CLI, jq (sudo는 #575 이후 불필요)

---

## Skills SSOT — 가장 자주 실수하는 부분

**`dotfiles/claude/skills/`** 가 Claude Code·Gemini·Codex 3개 도구 모두의 단일 SSOT다.

### 도구별 연결 방식

| 도구 | 경로 | 연결 방식 | 신규 스킬 자동 반영 |
|------|------|-----------|---------------------|
| **Claude Code** (모든 모드) | `~/.claude*/skills` → `dotfiles/claude/skills` | 디렉토리 symlink (#575) | ✅ 즉시 |
| **Gemini CLI** | `~/.gemini/skills` → `dotfiles/claude/skills` | 디렉토리 symlink | ✅ 즉시 |
| **Codex** | `~/.codex/skills/<name>` → `dotfiles/claude/skills/<name>/` | 개별 skill symlink | ❌ setup 재실행 필요 |

### 관리 스크립트

| 도구 | 담당 스크립트 / 함수 | 트리거 |
|------|----------------------|--------|
| Claude Code (각 계정) | `shell-common/tools/integrations/claude.sh` → `_claude_account_setup_one()` | `./claude/setup.sh` |
| Gemini CLI | `claude/setup.sh` → `_setup_gemini_skills_symlink()` | `./claude/setup.sh` |
| Codex | `scripts/setup-skills-ssot.sh` → `link_skills_individual_codex()` | `./setup.sh` 또는 `./scripts/setup-skills-ssot.sh` |

### 신규 스킬 추가 후 동기화

```bash
./claude/setup.sh          # Claude Code 계정 + Gemini 동기화
./scripts/setup-skills-ssot.sh  # Codex 동기화
# 또는 한번에:
./setup.sh
```

Claude Code 의 skills/ 는 디렉토리 symlink 라 SSOT 에 새 스킬 디렉토리만 추가하면 setup 재실행 없이 즉시 보인다 (#575).

### 연결 방식이 다른 이유

- **Gemini**: 커스텀 전용 디렉토리 → 디렉토리 symlink가 가장 단순
- **Codex**: `.system/`(내장 5개) 보존 필요 → 개별 symlink로 내장/커스텀 분리
- **Claude Code**: 옵션 1·2·3 모두 디렉토리 symlink. `_claude_account_setup_one` 한 곳에서 처리하며, 이전의 bind-mount (#287) 와 per-skill symlink (#342) 는 #575 에서 제거됨.

### 절대 하지 말 것

- `~/.claude*/skills/`, `~/.gemini/skills/`, `~/.codex/skills/` 직접 편집 금지
- 스킬은 반드시 SSOT인 `dotfiles/claude/skills/`에만 생성/수정
- Codex `.system/` 디렉토리 삭제 금지 (Codex 내장 스킬)

---

## Configuration Files

```bash
# 외부 PC (옵션 1, 3) — 멀티-계정
~/.claude-personal/settings.json         -> dotfiles/claude/settings.json
~/.claude-personal/statusline-command.sh -> dotfiles/claude/statusline-command.sh
~/.claude-personal/skills                -> dotfiles/claude/skills          (dir symlink, #575)
~/.claude-personal/docs                  -> dotfiles/claude/docs            (dir symlink, #575)
~/.claude-personal/plugins               -> ~/.claude-shared/plugins
~/.claude-personal/projects/GLOBAL/memory -> dotfiles/claude/global-memory

# 사내 PC (옵션 2) — 단일 계정 (issue #571)
~/.claude/settings.json                  -> dotfiles/claude/settings.json
~/.claude/statusline-command.sh          -> dotfiles/claude/statusline-command.sh
~/.claude/skills                         -> dotfiles/claude/skills          (dir symlink)
~/.claude/docs                           -> dotfiles/claude/docs            (dir symlink)
~/.claude/plugins                        -> ~/.claude-shared/plugins
~/.claude/projects/GLOBAL/memory         -> dotfiles/claude/global-memory

# 모든 환경 공통
~/.gemini/skills                         -> dotfiles/claude/skills          (dir symlink)
~/.codex/skills/<name>                   -> dotfiles/claude/skills/<name>/  (per-skill)
```

기존 PC 에 남아 있는 `/etc/sudoers.d/claude-{skills,docs}-mount-*` 파일은 #575 이후로 사용처가 없다. `claude/setup.sh` 실행 시 잔존 파일이 감지되면 수동 삭제 명령을 안내한다.

`settings.json` — **tracked SSOT** (#584). 동일한 파일이 Home/External/Internal 모두에서 `~/.claude/settings.json` 으로 심볼릭링크됨.
`~/.claude/settings.local.json` — out-of-repo, gitignored, Internal PC 1회 손수 작성. 사번 헤더 / 사내 `ANTHROPIC_*` 가 들어가며 Claude Code 가 settings.json 과 native merge. `claude/setup.sh` 가 Internal 모드 종료 직전 copy-paste heredoc 안내 출력 (#584).

`~/.dotfiles-setup-mode` 가 `internal` 이면 `claude_yolo` 가 멀티-계정 해석을 우회하고 `~/.claude/` 를 강제 사용 (F-2). 잘못 migrate된 사내 PC 복구: `claude-accounts rollback` (F-3). 자세한 내용은 `docs/guide/internal-pc.md`.

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
