# Git Documentation

> 이 디렉토리는 dotfiles 프로젝트의 Git 관련 문서들을 모아둔 곳입니다.
>
> Hook 설정, 워크플로우, 트러블슈팅 등의 정보를 쉽게 찾을 수 있습니다.

---

## 📚 문서 목록

### 🔄 [HOOK_WORKFLOW.md](./HOOK_WORKFLOW.md)

**User-level과 Project-level Hook의 완전한 가이드**

- ✅ Hook 실행 흐름 (전체 다이어그램)
- ✅ PHASE 1: User-level Hook 상세 설명
- ✅ PHASE 2: Project-level Hook 상세 설명
- ✅ 실제 예제: bat_help.sh 수정 시 동작
- ✅ 테스트 방법 (5가지 시나리오)
- ✅ FAQ (10가지 자주 묻는 질문)

**이 문서를 읽으면**:
- Hook이 어떻게 작동하는지 명확히 이해
- 파일 수정 후 Hook 실행 순서 파악
- 문제 발생 시 디버깅 방법 습득
- 언제 어떤 체크가 실행되는지 확인

---

## 🚀 빠른 시작

### 파일 수정 후 커밋할 때

```bash
# 1. 파일 수정
vim shell-common/functions/bat_help.sh

# 2. 스테이징
git add shell-common/functions/bat_help.sh

# 3. 커밋 (Hook이 자동 실행됨)
git commit -m "Update bat_help function"

# ⬇️ 내부적으로 이 순서로 실행됨:
# PHASE 1: User-level Hook (~150ms)
#   ✓ Secrets, Conflicts, Whitespace 체크
# PHASE 2: Project-level Hook (~1-3s)
#   ✓ Shebang, Naming, UX, Anti-patterns 체크
# ✅ Commit 완료!
```

### 문제 해결

```bash
# 디버그 모드로 Hook 실행 확인
GIT_HOOKS_DEBUG=1 git commit -m "message"

# 전역 체크 스킵 (긴급상황)
GIT_HOOKS_SKIP_GLOBAL=1 git commit -m "message"

# 모든 Hook 스킵 (권장 안 함)
git commit --no-verify -m "message"
```

---

## 🎯 자주 확인하는 것들

### Q: 내 파일 수정에 어떤 Hook이 실행되나?

**A**: [HOOK_WORKFLOW.md](./HOOK_WORKFLOW.md#2-hook-실행-흐름) 참고

- **User-level Hook** (항상 먼저)
  - Secrets 감지
  - Conflicts 감지
  - Trailing whitespace
  - Debug code
  - Large files
  - Email identity

- **Project-level Hook** (그 다음)
  - Shebang 검사
  - Function naming
  - UX library 사용
  - Anti-patterns

### Q: 왜 커밋이 안 되나?

**A**: [HOOK_WORKFLOW.md#7-faq](./HOOK_WORKFLOW.md#7-faq) 참고

가능한 원인:
- [ ] Trailing whitespace (라인 끝 공백)
- [ ] Conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
- [ ] Secret/Key 패턴 감지
- [ ] Function naming (dash-case 사용?)
- [ ] Alias/Function 이름 충돌

디버그 모드로 확인:
```bash
GIT_HOOKS_DEBUG=1 git commit -m "message"
```

### Q: hook을 무시하고 싶으면?

**A**: [HOOK_WORKFLOW.md#q2-hook을-무시하고-강제로-커밋하려면](./HOOK_WORKFLOW.md#q2-hook을-무시하고-강제로-커밋하려면) 참고

```bash
# 방법 1: 전역 체크만 스킵
GIT_HOOKS_SKIP_GLOBAL=1 git commit -m "message"

# 방법 2: 모든 Hook 스킵 (권장 안 함)
git commit --no-verify -m "message"
```

---

## 📖 상세 섹션별 가이드

### 🔐 초기 설정

| 토픽 | 위치 | 내용 |
|------|------|------|
| SSH 설정 | [SSH_SETUP_GUIDE.md](./SSH_SETUP_GUIDE.md) | Enterprise GitHub SSH 인증 완전 가이드 |

### 🔍 Hook 동작 이해하기

| 토픽 | 위치 | 내용 |
|------|------|------|
| 전체 흐름도 | [HOOK_WORKFLOW.md#2-hook-실행-흐름](./HOOK_WORKFLOW.md#2-hook-실행-흐름) | 시각적 다이어그램 |
| User-level 상세 | [HOOK_WORKFLOW.md#3-phase-1-user-level-hook](./HOOK_WORKFLOW.md#3-phase-1-user-level-hook) | 6가지 검사 상세 설명 |
| Project-level 상세 | [HOOK_WORKFLOW.md#4-phase-2-project-level-hook](./HOOK_WORKFLOW.md#4-phase-2-project-level-hook) | 6가지 검사 상세 설명 |

### 📋 실제 사용 예제

| 시나리오 | 위치 | 내용 |
|---------|------|------|
| 파일 수정 후 커밋 | [HOOK_WORKFLOW.md#5-실제-예제-bat_helpsh-수정](./HOOK_WORKFLOW.md#5-실제-예제-bat_helpsh-수정) | bat_help.sh 수정 시 Hook 동작 |
| 디버그 모드 | [HOOK_WORKFLOW.md#-테스트-1-디버그-모드로-hook-실행-확인](./HOOK_WORKFLOW.md#-테스트-1-디버그-모드로-hook-실행-확인) | 상세 로그 보기 |
| 오류 발생 | [HOOK_WORKFLOW.md#-테스트-3-실제-오류-발생시키기](./HOOK_WORKFLOW.md#-테스트-3-실제-오류-발생시키기) | Trailing whitespace 예제 |
| 공백 파일명 | [HOOK_WORKFLOW.md#-테스트-4-공백-있는-파일명](./HOOK_WORKFLOW.md#-테스트-4-공백-있는-파일명) | NUL-safe 처리 확인 |

### ❓ 문제 해결

| 질문 | 위치 | 해답 |
|------|------|------|
| Hook이 실행 안 됨 | [HOOK_WORKFLOW.md#q1-hook이-실행되지-않는-경우](./HOOK_WORKFLOW.md#q1-hook이-실행되지-않는-경우) | 설치 확인 |
| Hook 무시하기 | [HOOK_WORKFLOW.md#q2-hook을-무시하고-강제로-커밋하려면](./HOOK_WORKFLOW.md#q2-hook을-무시하고-강제로-커밋하려면) | --no-verify 사용 |
| 오류 메시지 이해 | [HOOK_WORKFLOW.md#q3-hook-에러-메시지가-이해가-안-갈-때](./HOOK_WORKFLOW.md#q3-hook-에러-메시지가-이해가-안-갈-때) | 디버그 모드 사용 |
| Trailing space 자동 제거 | [HOOK_WORKFLOW.md#q4-trailing-whitespace를-자동으로-제거할-수-있나](./HOOK_WORKFLOW.md#q4-trailing-whitespace를-자동으로-제거할-수-있나) | 스크립트 제공 |
| 다른 프로젝트 Hook 추가 | [HOOK_WORKFLOW.md#q5-다른-프로젝트에도-project-level-hook을-추가할-수-있나](./HOOK_WORKFLOW.md#q5-다른-프로젝트에도-project-level-hook을-추가할-수-있나) | .githooks 생성 |

---

## 🛠️ 관련 파일

### 구현 파일

```
git/global-hooks/pre-commit      # User-level Hook 구현
git/hooks/pre-commit             # Project-level Hook 구현
git/setup.sh                      # Hook 설치 스크립트
```

### 설정 파일

```
~/.config/git/hooks/pre-commit   # User-level Hook (설치 후)
.git/config                      # Git 설정
```

### 관련 문서

```
docs/abc-review-code-quality-improvements.md  # 코드 품질 개선
docs/abc-review-G.md                         # Gemini 리뷰
docs/abc-review-CX.md                        # CX 리뷰
```

---

## 💡 팁

### Alias로 빠르게 접근

```bash
# ~/.bashrc 또는 ~/.zshrc에 추가
alias git-doc='cat /home/bwyoon/dotfiles/git/doc/HOOK_WORKFLOW.md | less'

# 사용
git-doc
```

### 자주 사용하는 명령어

```bash
# 디버그 모드
alias git-commit-debug='GIT_HOOKS_DEBUG=1 git commit'

# 전역 체크 스킵
alias git-commit-skip='GIT_HOOKS_SKIP_GLOBAL=1 git commit'

# 모든 Hook 스킵 (권장 안 함)
alias git-commit-force='git commit --no-verify'
```

---

## 🔗 관련 링크

- [git/hooks/pre-commit](../hooks/pre-commit) - Project-level Hook 코드
- [git/global-hooks/pre-commit](../global-hooks/pre-commit) - User-level Hook 코드
- [git/setup.sh](../setup.sh) - Hook 설치 스크립트

---

## 📝 문서 버전

| 버전 | 날짜 | 변경사항 |
|------|------|---------|
| 1.0 | 2026-01-20 | 초기 문서 작성 |

---

## 🤝 피드백

이 문서가 도움이 되었나요? 개선할 점이 있으면 알려주세요!

- 명확하지 않은 부분
- 빠진 예제
- 추가했으면 하는 내용

---

**마지막 수정**: 2026-01-20
