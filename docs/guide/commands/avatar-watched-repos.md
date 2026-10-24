# avatar-watched-repos

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/avatar_watched_repos_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic avatar_watched_repos --force`

## 호출

- Help 진입점: `avatar-watched-repos-help [section|--list|--all]`
- 통합 라우팅: `my-help avatar_watched_repos [section]`
- Alias: `avatar-watched-repos-help`

## 요약 (avatar-watched-repos-help)

- Usage: avatar-watched-repos [--dry-run|-h|--help]
- Renders avatar/watched-repos.public.json (repo + HOME-relative rel)
    - into ~/.avatars/issue-watcher/watched-repos.json ($IW_WATCHED_REPOS)
- sections: commands, rules (avatar-watched-repos-help <section>)

## 섹션

### commands

- **avatar-watched-repos** — Render — Merge the tracked list into this PC's watch list (backup on change)
- **avatar-watched-repos --dry-run** — Preview — Print the diff only, write nothing
- **./setup.sh** — Setup — Runs the render as the optional avatar-watched-repos step

### rules

- **local-only entry** — Keep — Repos only in the local file (private repos) stay as they are
- **repo in both** — Merge — Local path wins (per-PC override); host/verify_skill come from the tracked file
- **tracked-only repo** — Add — Added as $HOME/<rel> when that directory exists, else skipped with a warning
- **same result** — Idempotent — No write, no backup; on change: watched-repos.json.bak-<ts> then write (0600)
- **broken JSON** — Abort — Either file unreadable: error, local file left untouched

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/avatar-watched-repos.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/avatar_watched_repos_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
