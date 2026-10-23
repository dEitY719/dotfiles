# avatar-issue-watcher

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/avatar_issue_watcher.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic avatar_issue_watcher --force`

## 호출

- Help 진입점: `avatar-issue-watcher-help [section|--list|--all]`
- 통합 라우팅: `my-help avatar_issue_watcher [section]`
- Alias: `avatar-issue-watcher`, `avatar-issue-watcher-help`

## 요약 (avatar-issue-watcher-help)

- Usage: avatar-issue-watcher-help [section|--list|--all]
- sections
    - commands: run modes (tick, --dry-run, --status, watch)
    - examples: manual runs, watch list, periodic runs (aicron/crontab)
- Full cycle, caps, gate, watch list and state paths: avatar-issue-watcher --help

## 섹션

### commands

- **avatar-issue-watcher** — Tick — Dispatch assigned open issues to /gh-flow:wave (cron)
- **avatar-issue-watcher --dry-run** — Preview — Print what a tick would dispatch, change nothing
- **avatar-issue-watcher --status** — Status — Rate-limit gate, saturation, gh search state
- **avatar-issue-watcher watch list** — Watch — Show the watch list file and its entries
- **avatar-issue-watcher watch add [owner/repo]** — Watch — Add/update an entry (--path P, --host H; default: cwd repo)
- **avatar-issue-watcher watch remove [owner/repo]** — Watch — Drop an entry (default: cwd repo)
- **avatar-issue-watcher --help** — Help — Full cycle, caps and gate rules

### examples

- **avatar-issue-watcher --dry-run** — Manual — Preview one tick without dispatching
- **avatar-issue-watcher --status** — Manual — Show gate, saturation and search state
- **cd ~/dotfiles && avatar-issue-watcher** — Manual — cwd mode: tick only this repo
- **avatar-issue-watcher --cwd ~/dotfiles** — Manual — Same tick, started from any directory
- **avatar-issue-watcher watch list** — Watch — Show the watch list
- **cd ~/dotfiles && avatar-issue-watcher watch add** — Watch — Add the cwd repo
- **avatar-issue-watcher watch add dEitY719/gh-verify-skills --path ~/para/project/skills** — Watch — Add a repo with its checkout path
- **avatar-issue-watcher watch remove dEitY719/equinest** — Watch — Drop a repo
- **aicron add avatar-issue-watcher --schedule '*/4 * * * *'** — Periodic — Install the shipped aicron job
- **aicron status avatar-issue-watcher --json | jq .last_exit** — Periodic — Exit code of the last run
- **aicron run avatar-issue-watcher --dry-run** — Periodic — Run the job once by hand
- **crontab: */4 * * * * avatar-issue-watcher --cwd ~ >> ~/.local/state/avatar-issue-watcher/cron.log 2>&1** — Periodic — Plain crontab line
- Note: inside a git repo without --cwd it runs in cwd mode (that repo only, no watch list)
- Note: from cron, pass --cwd or start in $HOME so the watch list is used

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/avatar-issue-watcher.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/avatar_issue_watcher.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
