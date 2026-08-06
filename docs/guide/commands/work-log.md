# work-log

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/work_log_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic work_log --force`

## 호출

- Help 진입점: `work-log-help [section|--list|--all]`
- 통합 라우팅: `my-help work_log [section]`
- Alias: `work-log-help`

## 요약 (work-log-help)

- Usage: work-log-help [section|--list|--all]
- sections
    - overview: manual work log for non-dev work
    - usage: work-log add | list | help
    - add: interactive & argument modes
    - list: list options & filters
    - format: output entry format
    - types: coordination | assessment | approval | meeting
    - categories: Testing | Infrastructure | Documentation | ...
    - tasks: common task templates
    - details: work-log-help <section>

## 섹션

### overview

- Manual work log recording tool for non-development work
- Companion to post-commit hook for development work
- All entries are appended to ~/work_log.txt

### usage

- work-log add [JIRA-KEY] [OPTIONS]  - Add a work log entry
- work-log list [OPTIONS]            - List recent entries
- work-log help                      - Show this help

### add

- Interactive Mode:
1. work-log add
- System will prompt for Jira key, type, category, and time
- Argument Mode:
1. work-log add JIRA-KEY --type TYPE --category CATEGORY --time TIME
- Short options:
- -t, --type TYPE          (coordination|assessment|approval|meeting)
- -c, --category CATEGORY  (Testing|Infrastructure|Documentation|Communication|Training|Other)
- -T, --time TIME          (numeric: 2.5 or 2.5h)
- Example Coordination meeting on testing strategy
  work-log add SWINNOTEAM-903 -t coordination -c Communication -T 2.5h

### list

1. work-log list              - Show last 10 entries
2. work-log list --count 20  - Show last 20 entries
3. work-log list --today     - Show today's entries

### format

- [YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | time | manual
- └─ Category: CategoryName

### types

- coordination  - Team coordination, meetings, planning
- assessment    - Code/design reviews, evaluations
- approval      - Approval requests, sign-offs
- meeting       - Official meetings, presentations

### categories

- Testing, Infrastructure, Documentation, Performance, Security
- Communication, Coordination, Training, Other

### tasks

- Daily standup:  work-log add [PROJ-XXX] -t meeting -c Communication -T 0.5h
- Code review:    work-log add [PROJ-XXX] -t assessment -c Communication -T 1.5h
- Team planning:  work-log add [ADMIN-001] -t coordination -c Coordination -T 2h
- All entries stored in: ~/work_log.txt (symlink → dotfiles)
- Git tracking: Automatically versioned in dotfiles/shell-common/data/
- Use these entries for weekly reports and time tracking

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/work-log.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/work_log_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
