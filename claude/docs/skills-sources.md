# Skills 소스와 하네스 합성

> `claude/AGENTS.md` 에서 분리 (#2151). 요약·라우팅은 [`claude/AGENTS.md`](../AGENTS.md).

**dotfiles 에는 더 이상 스킬이 없다 (#1680).** 73개 스킬은 #1410 으로 15개
marketplace repo 로 분리됐고, `claude/skills/` 원본은 Phase 4 에서 삭제됐다.
등록은 `claude/plugin/{marketplaces,plugins}.json`.

**Claude Code 는 플러그인 전용이다.** Claude Code 의 스킬 SSOT 는
`claude/plugin/plugins.json` 에 선언되고 `claude/plugin/restore.sh` 가 설치하는
플러그인 하나뿐이다 (예: `gh-flow@gh-flow-skills` → `/gh-flow:issue`).
워크스페이스 스킬을 `~/.claude*/skills/` 에 flat 링크로 합성하지 **않는다** —
같은 스킬이 네임스페이스 없는 명령(`/issue`)으로 한 번 더 등록돼 중복되기
때문이다. `claude/setup.sh` 는 예전 합성이 남긴 워크스페이스 링크와
dangling 링크(워크스페이스 밖 포함, #2018)를 `_claude_prune_workspace_skills()` 로
지우고, 워크스페이스 밖을 가리키는 정상 링크(graphify, `claude-accounts link`
결과)·실디렉토리·파일은 그대로 둔다.
`skills/` 자체는 실디렉토리로 유지된다 (#707 F-8).

아래의 flat 합성은 **플러그인 기반이 아닌 나머지 하네스**(OpenCode / Codex /
agy / Hermes)에만 적용된다. 소스는 로컬에 나란히 clone 된 marketplace repo 다 —
소스 경로는 `${WORKSPACE_ROOT:-~/para/project/skills}/<repo>/skills/<skill>/SKILL.md`.

- 판별·열거 규칙 SSOT: `shell-common/functions/skill_sources.sh`
  (`_skill_workspace_root`, `_skill_workspace_dirs`) — 하네스들이 공유한다
  (Claude Code 쪽은 정리 대상 판정에만 `_skill_workspace_root` 를 쓴다).
- repo 끼리 이름이 겹치면 정렬 순서상 앞선 repo 가 이긴다 (재현 가능한 결정).
  워크스페이스 밖을 가리키는 링크(마켓플레이스 오버레이 등)는 건드리지 않는다.
- 자동 발견: repo 를 clone 하면 다음 setup 실행에서 그냥 잡힌다. `skills/` 가
  없는 repo, `SKILL.md` 가 없는 하위 디렉토리, 그리고 **linked git worktree**
  (`.git` 가 파일) 는 조용히 스킵된다 — worktree 는 `<repo>-<branch>` 가 정렬상
  앞서서 원본 clone 을 가려버리기 때문.
- repo 가 사라지면 그 repo 를 가리키던 entry 만 정리된다. 워크스페이스 밖을
  가리키는 링크(마켓플레이스 오버레이 등)는 건드리지 않는다.

### 관리 스크립트

| 도구 | 담당 스크립트 / 함수 | 트리거 |
|------|----------------------|--------|
| Claude Code (각 계정) | 플러그인 전용 — `claude/plugin/plugins.json` + `claude/plugin/restore.sh`. `shell-common/tools/integrations/claude.sh` → `_claude_account_setup_one()` + `_claude_prune_workspace_skills()` 는 예전 flat 워크스페이스 링크를 **정리만** 한다 (합성 안 함) | `./claude/setup.sh` |
| OpenCode / Gemini / agy / Hermes | `scripts/setup-skills-ssot.sh` → `link_skills_compose()` (#791, agy 는 #1731) | `./setup.sh` 또는 `./scripts/setup-skills-ssot.sh` |
| Codex | `scripts/setup-skills-ssot.sh` → `link_skills_individual_codex()` | `./setup.sh` 또는 `./scripts/setup-skills-ssot.sh` |
| 소스 열거 (#1652 / #1680) | `shell-common/functions/skill_sources.sh` + `collect_skill_sources()` (Claude Code 외 하네스) | 위와 동일 |

### 신규 스킬 추가 후 동기화

```bash
./scripts/setup-skills-ssot.sh      # Codex / OpenCode / Gemini / agy / Hermes
# 또는 한번에:
./setup.sh
```

위 CLI 는 entry-level symlink 합성이라 (#791) 새 스킬 디렉토리를 추가했을 때 위 명령으로 빠진 entry 만 추가된다. Idempotent.
Claude Code 는 해당 repo 가 `claude/plugin/plugins.json` 에 등록돼 있으면 플러그인으로 이미 로드된다 — 새 repo 는 거기에 추가하고 `claude/plugin/restore.sh` 로 설치한다.

### 연결 방식이 통일된 이유 (issue #791)

- **Codex 특수**: `.system/` (내장 skill) 디렉토리는 로컬 보존하므로 `link_skills_individual_codex` 가 따로 존재. OpenCode/Gemini 는 내장 디렉토리가 없으므로 단순한 `link_skills_compose` 로 충분.

### 절대 하지 말 것

- `~/.claude*/skills/`, `~/.gemini/config/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/` 직접 편집 금지
- 스킬은 워크스페이스 repo(`~/para/project/skills/<repo>/skills/`)에서만 생성/수정 — 합성 대상 디렉토리에서 직접 만들지 말 것
- Codex `.system/` 디렉토리 삭제 금지 (Codex 내장 스킬)
