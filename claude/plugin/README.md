# claude/plugin/ — 플러그인·스킬 관리 코드의 위치별 역할

marketplace / plugin / skill 디렉토리를 다루는 코드는 네 곳에 나뉘어 있다. 데이터 SSOT 는
이 디렉토리의 두 파일 `marketplaces.json` · `plugins.json` 하나로 일관되고(로컬 설치 상태는
gitignored `*.local.json`), 아래 표는 **코드가 어디에 사는가** 를 고정한다 (#2147).
배포 경로·갱신 절차는 [`docs/.ssot/skills-distribution.md`](../../docs/.ssot/skills-distribution.md),
매니페스트 계약은 [`claude/docs/plugins.md`](../docs/plugins.md) 를 본다.

## 호출 그래프

```
scripts/update-skills.sh                          (skills-sync 5단계 진입점)
 ├─ claude/plugin/git-clone-skills.sh ── marketplaces.json, functions/gh_host.sh
 ├─ claude/plugin/git-pull-skills.sh
 ├─ claude/setup.sh ── tools/custom/lib/claude_accounts_skills.sh (_claude_prune_workspace_skills)
 ├─ claude/plugin/update-plugins.sh ── marketplaces.json, plugins.json
 └─ scripts/setup-skills-ssot.sh ── functions/skill_sources.sh ── 워크스페이스 clone
claude/plugin/restore.sh ── functions/claude_plugin_manifest.sh   (독립: 신규 PC 설치)
claude/plugin/reconcile.sh ── functions/claude_plugin_manifest.sh, plugin_sync_title.sh   (독립: drift 점검)
claude/hooks/plugin-sync-session.sh -> plugin-sync.sh ── claude_plugin_manifest.sh, plugin_sync_title.sh
claude/plugin/publish-sync.sh                     (독립: 게시)
functions/marketplace.sh, claude_plugins_core.sh, claude_plugin_list.sh   (대화형 UI, plugin/*.sh 미참조)
claude-accounts link/unlink ── tools/custom/lib/claude_accounts_skills.sh ── functions/skill_sources.sh
```

## 역할표

| 위치 | 역할 | 포함 |
|------|------|------|
| `claude/plugin/*.sh` | 실행 단위 — 한 가지 일을 끝까지 | clone · pull · update · reconcile · restore · publish |
| `shell-common/functions/claude_plugin_manifest.sh`, `skill_sources.sh` | 데이터 접근 — SSOT 파일·워크스페이스를 읽기만 | 매니페스트 union, 스킬 소스 열거, 워크스페이스 소속 판정 |
| `scripts/update-skills.sh`, `scripts/setup-skills-ssot.sh` | 사용자 / setup 진입점 | skills-sync 오케스트레이션, 비-Claude 하네스 합성 |
| `shell-common/functions/marketplace.sh`, `claude_plugins_*.sh`, `claude_plugin_list.sh` | 대화형 UI | 목록·검색·설치 메뉴, help |
| `claude/hooks/plugin-sync*.sh` | 세션 훅 | PostToolUse / SessionStart·Stop SSOT-diff 동기화 |
| `shell-common/tools/custom/lib/claude_accounts_skills.sh` | Claude Code 계정 skills/ 디렉토리 | 실디렉토리 정규화, 예전 flat 링크 정리, `claude-accounts link/unlink` |

훅 경로(`plugin-sync.sh`)는 `claude/settings.json` 에 하드코딩돼 있어 옮기지 않는다 (#584).

## 스킬 디렉토리: 하네스별 정책은 다르고 판정 규칙은 하나

- **판정 규칙(SSOT)** — "이 링크가 워크스페이스를 가리키나" 는 `skill_sources.sh` 의
  `_skill_under_workspace` 한 곳뿐이다. `setup-skills-ssot.sh` 의 `skill_source_is_managed`
  와 계정 lib(prune / `link --list` / `link` fan-out 제외)가 모두 이것을 호출한다.
- **정책은 의도적으로 다르다** — Codex / OpenCode / agy 는 워크스페이스 스킬을 **합성**하고
  관리 대상 dir-symlink 만 마이그레이션한다(`link_skills_compose`). Claude Code 계정은
  플러그인으로만 로드하므로 워크스페이스 링크를 **정리만** 하고(`_claude_prune_workspace_skills`,
  #2018 dangling 정리 포함) dir-symlink 는 무엇을 가리키든 실디렉토리로 바꾼다
  (`_claude_prepare_skills_dir`). 정리 개수는 `CLAUDE_WS_SKILLS_PRUNED` 로 같은 셸의
  `claude/setup.sh` 요약에 누적되므로, 이 두 함수는 별도 프로세스가 아니라 source 되는 lib 에 있다.

## 새 기능은 어디에

1. 플러그인 설치·갱신·게시처럼 한 번 실행하고 끝나는 작업 → `claude/plugin/<verb>.sh`
2. `plugins.json` / 워크스페이스를 읽는 판정·열거 → `shell-common/functions/` 의 데이터 접근 파일
3. 여러 단계를 묶어 사용자가 한 번에 부르는 것 → `scripts/update-skills.sh` 의 단계 추가
4. 사람이 메뉴로 고르는 것 → `functions/marketplace.sh` 계열 UI
5. 세션 시작·도구 실행에 자동으로 붙는 것 → `claude/hooks/plugin-sync*.sh` (settings.json 경로 불변)
