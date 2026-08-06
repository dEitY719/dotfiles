# work

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/work.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic work --force`

## 호출

- Help 진입점: `work-help [section|--list|--all]`
- 통합 라우팅: `my-help work [section]`
- Alias: `work-help`

## 요약 (work-help)

- Usage: work-help [section|--list|--all]
- sections
    - overview: integrated tracking & docs workflow
    - commands: work-log | make-jira | make-confluence
    - workflow: daily & weekly cycles
    - dataflow: input -> processing -> output
    - files: locations of logs, reports, tools
    - integration: git tracking & multi-PC sync
    - more: per-command help references
    - details: work-help <section>  (example: work-help commands)

## 섹션

### overview

- Integrated workflow for work tracking and documentation
- Combines: work-log (manual tracking) + make-jira (reports) + make-confluence (guides)
- All data git-tracked in dotfiles and playbook

### commands

- 1. Record Work (Manual Log Entry) work-log
- Add non-development work to weekly log
  work-log add SWINNOTEAM-903 -t coordination -c Communication -T 2.5h
  work-log list --today
- 2. Generate Weekly Report make-jira
- Create Jira-formatted weekly report from work_log.txt
  make-jira                    # Current week
  make-jira --week 2026-W05    # Specific week
  make-jira SWINNOTEAM-906     # Filter by key
- Output: playbook/docs/jira-records/YYYY-W##-report.md
- 3. Transform Docs to Confluence Guides make-confluence
- Convert markdown technical docs to Confluence format
  make-confluence docs/guide/technic/file.md                        # Auto-detect category
  make-confluence docs/analysis/file.md --category testing  # Explicit category
- Output: playbook/docs/confluence-guides/{category}/YYYY-MM-DD-{title}.md

### workflow

Daily Workflow:
  1. Work happens → git commits (auto-tracked)
  2. Manual non-dev work → work-log add
  3. Friday: make-jira → Weekly Jira report
  4. As needed: make-confluence → Technical guides
Weekly Cycle:
  Mon-Fri: Regular work + work-log entries
  Friday:  make-jira 2026-W05 → Jira report
  Anytime: make-confluence → Knowledge base

### dataflow

Work Input
  ├─ Git commits (post-commit hook → work_log.txt)
  ├─ work-log add (manual → work_log.txt)
  └─ Technical markdown (docs/guide/technic/, playbook/docs/analysis/)

Processing
  ├─ make-jira: work_log.txt → Jira reports
  └─ make-confluence: markdown → Confluence guides

Output
  ├─ playbook/docs/jira-records/ (weekly reports)
  ├─ playbook/docs/confluence-guides/ (technical guides)
  └─ All git-tracked in dotfiles (multi-PC sync via symlink)

### files

- work_log.txt: ~/work_log.txt (symlink → ~/para/archive/playbook/logs/work_log.txt)
- Jira reports: ~/para/archive/playbook/docs/jira-records/
- Confluence guides: ~/para/archive/playbook/docs/confluence-guides/
- CLI tools: ~/dotfiles/shell-common/tools/custom/make_{jira,confluence}.sh

### integration

- All commands are git-tracked:
  dotfiles:                CLI tools + alias definitions
  playbook:           Reports and guides
  Multi-PC sync:           Symlink abstraction (automatic)

### more

- For detailed help on individual commands:
  work-log help              # work-log manual
  make-jira --help           # make-jira manual (if implemented)
  make-confluence --help     # make-confluence manual (if implemented)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/work.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/work.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
