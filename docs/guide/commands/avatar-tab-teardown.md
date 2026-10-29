# avatar-tab-teardown

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/avatar_tab_teardown_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic avatar_tab_teardown --force`

## 호출

- Help 진입점: `avatar-tab-teardown-help [section|--list|--all]`
- 통합 라우팅: `my-help avatar_tab_teardown [section]`
- Alias: `avatar-tab-teardown-help`

## 요약 (avatar-tab-teardown-help)

- Usage: avatar-tab-teardown [--yes] [--worktree] [--force] [--repo <slug>] [--issue <N>]
- Closes finished herdr tabs of the unattended pipelines: iw (issue-watcher), mt (merge-train), mv (post-merge-verify)
    - default is a dry run: prints the candidates, closes nothing
- sections: options, rules (avatar-tab-teardown-help <section>)

## 섹션

### options

- **avatar-tab-teardown** — Dry run — List closable and skipped tabs, change nothing
- **--yes** — Close — herdr tab close every closable tab
- **--worktree** — Remove — After closing: gwt remove the iw/mv worktree when clean and pushed/merged (never mt)
- **--force** — Override — Ignore agent status and issue/PR state; gwt remove --force (current tab still skipped)
- **--repo <slug>** — Scope — Only tabs of this repo (owner/repo or repo)
- **--issue <N>** — Scope — Only tabs of issue/PR <N> (excludes mt)

### rules

- **ownership** — Agent name — iw-<repo>-issue-<N> / mt-<repo> / mv-<repo>-pr-<N>; label or mv scratch cwd as fallback
- **hand-made tab** — Never — issue-<N> / pr-<N> labels alone are not candidates
- **all kinds** — Idle — No agent in the tab is working or blocked
- **iw** — Closed — Issue <N> is CLOSED on GitHub (lookup failure: WARN, not closed)
- **mv** — Merged — PR <N> is MERGED
- **mt** — Idle only — The next merge-train tick recreates the tab
- **current tab** — Skip — The tab this command runs in is never closed
- **repo** — Watch list — Slug resolved via avatar-watched-repos list; mt falls back to its checkout's origin

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/avatar-tab-teardown.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/avatar_tab_teardown_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
