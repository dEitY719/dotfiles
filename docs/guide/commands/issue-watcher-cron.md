# issue-watcher-cron

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/issue_watcher_cron.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic issue_watcher_cron --force`

## 호출

- Help 진입점: `issue-watcher-cron-help [section|--list|--all]`
- 통합 라우팅: `my-help issue_watcher_cron [section]`
- Alias: `issue-watcher-cron`, `issue-watcher-cron-help`

## 요약 (issue-watcher-cron-help)

- Usage: issue-watcher-cron-help [section|--list|--all]
- sections
    - usage: run modes (tick, --dry-run, --status)
    - files: watch list and state files
    - details: issue-watcher-cron --help  (full cycle, caps, rate-limit gate)

## 섹션

### usage

- **issue-watcher-cron** — Tick — Dispatch assigned open issues to /gh-flow:issue (cron)
- **issue-watcher-cron --dry-run** — Preview — Print what a tick would dispatch, change nothing
- **issue-watcher-cron --status** — Status — Rate-limit gate, saturation, gh search state
- **issue-watcher-cron --help** — Help — Full cycle, caps and gate rules

### files

- Watch list: ~/.agent-factory/avatars/issue-watcher/watched-repos.json (or $IW_WATCHED_REPOS)
- State dir: ${XDG_STATE_HOME:-~/.local/state}/issue-watcher/

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/issue-watcher-cron.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/issue_watcher_cron.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
