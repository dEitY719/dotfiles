# Worked Example

Given a conversation where the user fixed a bug and committed:

File: `~/para/archive/playbook/docs/task-history/2026-03-20-task-list.md`

```markdown
# Task History: 2026-03-20

---

## 14:30 | dotfiles | Fix symlink creation for pip config

### JIRA Ticket

\`\`\`text
[Title]
[dotfiles] pip config symlink 생성 오류 수정

[Description]
> 배경
- setup.sh 실행 시 ~/.config/pip/pip.conf symlink가 생성되지 않는 문제 발견
- 디렉터리 미존재가 원인

> 수행 내용
- shell-common/setup.sh에서 mkdir -p 호출 추가
- pip config symlink 생성 로직 수정
- 테스트 후 PR 생성

> 결과
- setup.sh 실행 시 pip config 정상 생성 확인
- PR #33 생성 및 머지 완료
\`\`\`

### PR

\`\`\`markdown
## Title
fix: add mkdir for pip config directory before symlink creation

## Summary
- Add `mkdir -p ~/.config/pip` before creating pip.conf symlink
- Fixes setup.sh failure on fresh installations where ~/.config/pip does not exist

## Changes
- `shell-common/setup.sh`: Added directory creation before symlink

## Test plan
- [ ] Run setup.sh on clean home directory
- [ ] Verify ~/.config/pip/pip.conf symlink exists after setup
\`\`\`
```
