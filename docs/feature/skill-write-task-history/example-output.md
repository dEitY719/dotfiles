# Example Output: /write-task-history

아래는 오늘(2026-03-20) dotfiles 프로젝트에서 작업한 내용을 예시로 한 출력입니다.
JIRA/PR 각각 코드블럭으로 감싸서 복사/붙여넣기가 용이한 형태.

## 저장될 파일

`~/para/archive/playbook/docs/task-history/2026-03-20-task-list.md`

---

아래부터가 실제 파일에 작성되는 내용입니다:

---

## Task History: 2026-03-20

---

### 13:50 | dotfiles | rm -rf ~ 홈 디렉터리 복구 및 git-crypt 키 백업

#### JIRA Ticket

```text
[Title]
[dotfiles] rm -rf ~ 사고 복구 및 git-crypt 대칭키 백업 체계 구축

[Description]
▶ 배경
◇ 홈 디렉터리에 리터럴 "~" 디렉터리가 존재하여 삭제 시도
◇ rm -rf ~ (따옴표 없이) 실행으로 홈 디렉터리 전체 삭제됨
◇ bash/zsh 셸 설정, SSH 키, GPG 키, oh-my-zsh 등 전부 삭제

▶ 수행 내용
◇ dotfiles setup.sh 실행하여 셸 환경 복구 (bash, zsh, git, npm, pip 등 symlink 재생성)
◇ oh-my-zsh + powerlevel10k + zsh-autosuggestions 재설치
◇ pyenv + pyenv-virtualenv 재설치
◇ git-crypt 대칭키 export 및 Obsidian 로컬 백업
◇ GPG 키 복구 시도 (비밀번호 불일치로 실패, 대칭키로 대체)
◇ fasd, uv 재설치
◇ gh auth login 재인증
◇ 리터럴 ~ 디렉터리를 git 추적에서 제거
◇ .gitignore에 .claude/ 패턴 추가

▶ 결과
◇ 셸 환경 전체 정상 복구 (bash, zsh 모두 동작 확인)
◇ git-crypt 대칭키 Obsidian 로컬 백업 완료 (SHA256 해시 포함)
◇ 재해 복구 가이드 문서 작성: docs/todo/disaster-recovery-rm-rf-home.md
◇ PR #32 생성 및 머지 완료

▶ 비고
◇ SSH 키가 새로 생성됨 (사내 서버 사용 시 공개키 재등록 필요)
◇ GPG 비밀키는 분실 상태 (git-crypt 대칭키로 기능 대체)
```

#### PR

```markdown
## Title

fix: remove accidental literal ~ directory and update .gitignore

## 📋 Summary

- Remove `~/.oh-my-zsh/custom/plugins/zsh-autosuggestions` submodule that was accidentally committed when `git clone` was run with quoted `"~"` path
- Update `.gitignore`: replace `.claude/scheduled_tasks.lock` with broader `.claude/` pattern to ignore all project-local Claude Code settings

## 📝 Changes

- `~/.oh-my-zsh/custom/plugins/zsh-autosuggestions`: git 추적에서 제거 (리터럴 ~ 디렉터리 정리)
- `.gitignore`: `.claude/scheduled_tasks.lock` -> `.claude/` 패턴 변경

## ✅ Test plan

- [x] `git status` shows clean working tree
- [x] `ls ~/dotfiles/` no longer contains literal `~` directory
- [x] `.claude/` directory no longer appears in untracked files
```
