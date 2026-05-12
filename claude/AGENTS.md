# claude/ Module — Agent Context

## Purpose

Claude Code CLI 설정, 스킬, 자동화 관리.  
Dependencies: Claude Code CLI, jq, sudo

---

## Skills SSOT — 가장 자주 실수하는 부분

**`dotfiles/claude/skills/`** 가 Claude Code·Gemini·Codex 3개 도구 모두의 단일 SSOT다.

### 도구별 연결 방식

| 도구 | 경로 | 연결 방식 | 신규 스킬 자동 반영 |
|------|------|-----------|---------------------|
| **Claude Code** (각 계정) | `~/.claude-personal/skills/<name>` → `dotfiles/claude/skills/<name>` | 개별 skill symlink | ❌ setup 재실행 필요 |
| **Gemini CLI** | `~/.gemini/skills` → `dotfiles/claude/skills` | 디렉토리 symlink | ✅ 즉시 |
| **Codex** | `~/.codex/skills/<name>` → `dotfiles/claude/skills/<name>/` | 개별 skill symlink | ❌ setup 재실행 필요 |

### 관리 스크립트

| 도구 | 담당 스크립트 / 함수 | 트리거 |
|------|----------------------|--------|
| Claude Code (각 계정) | `shell-common/tools/integrations/claude.sh` → `_claude_dir_sync_one()` | `./claude/setup.sh` |
| Gemini CLI | `claude/setup.sh` → `_setup_gemini_skills_symlink()` | `./claude/setup.sh` |
| Codex | `scripts/setup-skills-ssot.sh` → `link_skills_individual_codex()` | `./setup.sh` 또는 `./scripts/setup-skills-ssot.sh` |

### 신규 스킬 추가 후 동기화

```bash
./claude/setup.sh          # Claude Code 계정 + Gemini 동기화
./scripts/setup-skills-ssot.sh  # Codex 동기화
# 또는 한번에:
./setup.sh
```

### 연결 방식이 다른 이유

- **Gemini**: 커스텀 전용 디렉토리 → 디렉토리 symlink가 가장 단순
- **Codex**: `.system/`(내장 5개) 보존 필요 → 개별 symlink로 내장/커스텀 분리
- **Claude Code**: 다중 계정별 독립 디렉토리 → 개별 symlink (`_claude_dir_sync_one`)

### 절대 하지 말 것

- `~/.claude-personal/skills/`, `~/.gemini/skills/`, `~/.codex/skills/` 직접 편집 금지
- 스킬은 반드시 SSOT인 `dotfiles/claude/skills/`에만 생성/수정
- Codex `.system/` 디렉토리 삭제 금지 (Codex 내장 스킬)

---

## Configuration Files

```bash
~/.claude-personal/settings.json         -> dotfiles/claude/settings.json
~/.claude-personal/settings.local.json   -> dotfiles/claude/settings.local.json
~/.claude-personal/statusline-command.sh -> dotfiles/claude/statusline-command.sh
~/.claude-personal/skills/<name>         -> dotfiles/claude/skills/<name>   (per-skill)
~/.claude-personal/docs/<name>           -> dotfiles/claude/docs/<name>     (per-doc)
~/.gemini/skills                         -> dotfiles/claude/skills           (dir symlink)
~/.codex/skills/<name>                   -> dotfiles/claude/skills/<name>/  (per-skill)
```

`settings.local.json` — env 블록 SSOT (e.g. `GH_PR_REPLY_AUTO_APPROVE_REPOS`).  
`settings.json` — gitignored, per-machine 설정.

---

## Known Pitfall: Agent isolation + git-crypt

`Agent({ isolation: "worktree" })` 사용 금지. `filter.git-crypt.required=true` 로 인해
`fatal: .env: smudge filter git-crypt failed` 발생.

대신: sequential dispatch (isolation 없이) 또는 `ai-worktree:spawn` 스킬 사용.  
참고: `docs/learnings/git-crypt-worktree-bootstrap.md`

---

## Skill 작성 규칙

- SSOT: `dotfiles/claude/skills/<name>/SKILL.md`
- frontmatter: `name`, `description`, `allowed-tools` 필수
- `name` 형식: `{namespace}:{action}` (e.g. `skill:check`, `gh:commit`)
- SKILL.md ≤ 100줄; 상세 내용은 `references/`로 분리 (Progressive Disclosure)
- `description:` — 단일행 또는 YAML `>-` 멀티라인 모두 허용
