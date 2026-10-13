# Skills workspace (작업 사본)

- 이 폴더는 스킬 marketplace repo 들의 **작업 사본**이다. 여기 수정은 Codex / agy / OpenCode / Hermes 에는 심볼릭 링크로 즉시 반영되지만, **Claude Code 는 여기서 로드하지 않는다** — 플러그인 저장소(`plugins/cache/<mkt>/<plugin>/<version>`)에서만 로드한다.
- Claude Code 반영은 `skills-sync` (내부적으로 dotfiles 의 `claude/plugin/update-plugins.sh`) 후 세션 재시작. push 전 `.claude-plugin/plugin.json` version bump 규칙을 지킨다.
- 상세(배포 경로, 모드별 저장소 위치, "Claude 에 스킬이 안 보인다" 진단): dotfiles 의 `docs/.ssot/skills-distribution.md`.
- 이 파일은 dotfiles 의 `claude/workspace/AGENTS.md` 를 가리키는 심볼릭 링크다 (`scripts/setup-skills-ssot.sh` 관리) — dotfiles 위치는 `readlink -f CLAUDE.md` 로 확인하고 원본을 수정한다.
