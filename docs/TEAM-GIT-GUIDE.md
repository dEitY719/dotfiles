# 팀 Git Hooks 가이드

**작성일:** 2026-01-29
**대상:** SWINNOTEAM 개발자 (3명)
**목적:** Git hooks를 통한 자동화된 품질 관리 & 워크플로우 표준화

---

## 📋 목차

1. [개요](#개요)
2. [Git Hooks란?](#git-hooks란)
3. [우리 팀의 3가지 Hooks](#우리-팀의-3가지-hooks)
4. [실제 워크플로우](#실제-워크플로우)
5. [Commit 메시지 규칙](#commit-메시지-규칙)
6. [Branch 네이밍](#branch-네이밍)
7. [일반 문제와 해결](#일반-문제와-해결)
8. [FAQ](#faq)

---

## 개요

**현재 상황:**
- ✅ `commit-msg` hook: 메시지 형식 강제 (STRICT MODE)
- ✅ `pre-push` hook: main 브랜치 보호
- ✅ `prepare-commit-msg` hook: JIRA 키 자동 추출

**효과:**
```
버그 예방 ↑
work log 자동화 ↑
메시지 품질 ↑
개발 속도 ↑ (템플릿 덕분)
```

---

## Git Hooks란?

**한 문장:** Git의 특정 이벤트 전/후에 자동으로 실행되는 스크립트

```
┌─────────────────────────────────────┐
│ git add files                       │
│     ↓                               │
│ [pre-commit] ← 현재 있음 ✓           │
│     ↓                               │
│ git commit -m "message"             │
│     ↓                               │
│ [prepare-commit-msg] ← 우리 추가     │
│     ↓                               │
│ [commit-msg] ← 우리 추가 (STRICT)    │
│     ↓                               │
│ [post-commit] ← 기존 (work log)     │
│     ↓                               │
│ git push                            │
│     ↓                               │
│ [pre-push] ← 우리 추가 (main 차단)   │
│     ↓                               │
│ ✅ Push 완료                         │
└─────────────────────────────────────┘
```

---

## 우리 팀의 3가지 Hooks

### 1️⃣ commit-msg: 메시지 검증 (STRICT MODE)

**작동:**
- ✓ Conventional Commits 형식 강제
- ✓ 메시지 길이 제한 (subject < 50자)
- ✓ 금지 패턴 차단 (WIP, tmp, DEBUG 등)

**형식:**
```
<type>(<scope>): <subject>

<body (optional)>
<footer (optional)>
```

**허용 타입:**
```
feat     - 새로운 기능
fix      - 버그 수정
docs     - 문서 수정
style    - 코드 스타일 (포맷팅, 세미콜론 등)
refactor - 기능 변경 없는 코드 개선
perf     - 성능 개선
test     - 테스트 코드 추가/수정
chore    - 빌드, 의존성 업데이트
```

**예시 (좋음):**
```
feat(auth): add OAuth2 login

- Implement JWT token generation
- Add session management
- Closes SWINNOTEAM-906
```

**예시 (나쁨 - 차단됨):**
```
WIP: work in progress           ❌ 임시 메시지
tmp fix                         ❌ 랜덤 메시지
Update                          ❌ 의미 없음
fix(auth): add OAuth2 login that includes token refresh and... ❌ 너무 김 (> 50자)
```

---

### 2️⃣ prepare-commit-msg: JIRA 키 자동 추출

**작동:**
- Branch 이름에서 JIRA 키를 자동으로 추출
- 에디터 열기 전에 메시지 템플릿 미리 생성
- 사용자는 템플릿 완성만 하면 됨

**사용 예시:**

```bash
# Branch 이름
$ git checkout -b feature/SWINNOTEAM-906-add-oauth

# 커밋 시도
$ git commit

# 에디터 자동으로 열림 (이미 템플릿 생성됨!)
[SWINNOTEAM-906]
# ↑ 자동 생성

# 사용자가 추가 입력
[SWINNOTEAM-906] feat(auth): add OAuth2 login
                 ↑ 자동      ↑ 사용자 입력
```

**JIRA 키 없는 경우:**
```bash
$ git checkout -b feature/refactor-auth-module
$ git commit

# 에디터 열림 (빈 상태)
# 사용자가 직접 입력
feat(auth): refactor module
```

---

### 3️⃣ pre-push: main 브랜치 보호

**작동:**
- main, master로의 직접 push 차단
- release/* 브랜치로의 push 차단
- feature 브랜치는 push 허용

**시나리오:**

```bash
# ✓ 허용: feature 브랜치에 push
$ git push origin feature/SWINNOTEAM-906-auth
✅ Success

# ✗ 차단: main에 직접 push
$ git push origin main
🚫 Cannot push directly to protected branch: 'main'
   → Create a pull request instead
   → Merge will be done via GitHub/GitLab PR

💡 To fix this:
   1. git checkout -b feature/your-feature
   2. Make changes and commit
   3. git push origin feature/your-feature
   4. Create a pull request on GitHub
   5. Merge via pull request
```

---

## 실제 워크플로우

### 시나리오: SWINNOTEAM-906 기능 구현

```bash
# 1️⃣ Branch 생성
$ git checkout -b feature/SWINNOTEAM-906-add-oauth2

# 2️⃣ 코드 작업 (평소처럼)
$ vim src/auth.py
$ git add src/auth.py

# 3️⃣ 커밋 (여기서 자동화!)
$ git commit

# 4️⃣ prepare-commit-msg 실행
# → 에디터 열림
# → [SWINNOTEAM-906] 자동 생성
[SWINNOTEAM-906]

# 5️⃣ 메시지 완성 (빈칸만 채우기!)
[SWINNOTEAM-906] feat(auth): add OAuth2 login

- Implement JWT token generation
- Add refresh token rotation
- Update user model

# 6️⃣ 저장 & 종료 → commit-msg hook 실행
# ✓ 형식 검증 (Conventional Commits)
# ✓ 길이 검증 (< 50자)
# ✓ 금지 패턴 검증

# ✅ Commit 완료
[feature/SWINNOTEAM-906-add-oauth2 abc1234] feat(auth): add OAuth2 login

# 7️⃣ post-commit hook 실행 (자동)
# → [SWINNOTEAM-906] 감지
# → work_log.txt에 자동 기록
# [2026-01-29 14:30:00] [SWINNOTEAM-906] | feature/SWINNOTEAM-906-add-oauth2 | | abc1234

# 8️⃣ Push 준비
$ git push origin feature/SWINNOTEAM-906-add-oauth2

# 9️⃣ pre-push hook 실행
# ✓ main이 아님
# ✓ release/*가 아님
# ✅ Push 허용

# 🔟 PR 생성 & 리뷰 & Merge
# → GitHub/GitLab에서 PR 생성
# → 팀원 리뷰
# → Merge to main ✓

# ✅ 완료! 자동화된 품질 관리 끝!
```

---

## Commit 메시지 규칙

### 기본 구조

```
<type>(<scope>): <subject>    ← 1줄, 50자 이내
                              ← 빈 줄 (필수)
<body>                        ← 선택사항, 72자 이내
                              ← 빈 줄
<footer>                      ← 선택사항
```

### 좋은 예시들

**단순 메시지:**
```
feat(user): add profile page
```

**JIRA 키 포함 (자동):**
```
[SWINNOTEAM-906] feat(auth): add OAuth2 login
```

**상세 메시지:**
```
feat(api): implement webhook handler

- Add webhook endpoint at /api/webhooks
- Parse GitHub payloads
- Trigger CI on push events
- Add error logging

Closes SWINNOTEAM-906
```

**버그 수정:**
```
fix(auth): resolve null pointer in token check

- Added null check before accessing token.payload
- Added unit test for edge case
- Closes SWINNOTEAM-907
```

### 피해야 할 패턴

```
❌ WIP: feature               (Work In Progress - 금지)
❌ tmp: something             (Temporary - 금지)
❌ test                       (Random test - 금지)
❌ fix                        (너무 짧음 - 금지)
❌ Update stuff               (의미 불명확 - 금지)
❌ feat: this is a very long subject that goes over 50 chars (너무 김 - 차단)
```

---

## Branch 네이밍

### 권장 형식

```
feature/SWINNOTEAM-906-user-profile    ← JIRA 키 포함 (권장)
bugfix/SWINNOTEAM-245-login-error      ← 버그 수정
hotfix/urgent-security-fix             ← 긴급 수정 (JIRA 없을 수 있음)
refactor/simplify-auth-module          ← 리팩토링
```

### 명명 규칙

- **JIRA 키 포함:** `feature/SWINNOTEAM-906-short-description`
- **JIRA 키 없음:** `feature/refactor-auth` (간단히)
- **단어 구분:** 하이픈 사용 (underscores 금지)
- **소문자:** 항상 소문자 사용
- **한국어:** 영어 사용 (자동화 도구 호환성)

### 나쁜 예시

```
❌ Feature/SWINNOTEAM-906  (대문자 - 컨벤션 위반)
❌ feature_SWINNOTEAM_906  (언더스코어 - 대시 사용)
❌ feature/SWINNOTEAM906   (하이픈 없음 - 파싱 실패)
❌ feature/새로운기능      (한국어 - 호환성 문제)
```

---

## 일반 문제와 해결

### 문제 1: "Subject line too long" 오류

```bash
❌ 오류:
feat(auth): add OAuth2 login with JWT token refresh and session management

✅ 해결:
feat(auth): add OAuth2 login

# 상세 내용은 body에:
- Implement JWT token generation
- Add session management
```

### 문제 2: "Invalid commit type" 오류

```bash
❌ 오류:
new: add feature          (new는 허용 안 됨)

✅ 해결:
feat: add feature         (feat 사용)
```

### 문제 3: "Cannot push to main" 오류

```bash
❌ 오류:
$ git push origin main
🚫 Cannot push directly to protected branch: 'main'

✅ 해결:
1. Feature branch에서 작업: feature/SWINNOTEAM-906-xxx
2. PR 생성해서 merge
3. main은 PR을 통해서만 merge 가능
```

### 문제 4: Commit 메시지 템플릿이 안 나온다

```bash
⚠️ 원인:
- Branch name에 JIRA 키 패턴이 없음
- 또는 이미 메시지가 있는 상태

✅ 해결:
1. Branch 이름 확인: feature/SWINNOTEAM-906-xxx 형식?
2. 새로운 커밋: git commit (기존 메시지 없을 때)
3. 직접 입력: 템플릿이 없으면 직접 작성
```

### 문제 5: "This looks like a temporary commit" 오류

```bash
❌ 오류:
feat: test something      (test는 타입, 하지만 test는 임시 메시지로도 간주)

✅ 해결 1: test: 타입 사용할 때
test: add authentication tests    ← 콜론 있음 (OK)

✅ 해결 2: 실제 임시 커밋
COMMIT_MSG_WARN_ONLY=1 git commit    ← Warning만 허용
```

### 문제 6: 실수로 WIP 커밋했다

```bash
❌ 문제:
git commit -m "WIP: feature development"  ← 차단됨!

✅ 해결:
# 다시 커밋 (올바른 메시지)
git commit --amend -m "feat: add feature"

# 또는 처음부터
git reset HEAD~1
git commit -m "feat: add feature"
```

---

## FAQ

### Q1: Override는 정말 필요할까?

**A:** 거의 필요 없음. 하지만 특수한 경우:

```bash
# merge commit, amend 등에서 문제가 생기면:
COMMIT_MSG_WARN_ONLY=1 git commit

# pre-push override는 없음 (보안상 필요)
```

### Q2: JIRA 키 없는 branch에서 작업하면?

**A:** 괜찮음!

```bash
$ git checkout -b feature/refactor-auth
$ git commit

# prepare-commit-msg는 그냥 스킵
# 직접 메시지 입력하면 됨
```

### Q3: 이전 커밋들도 이 규칙을 따라야 하나?

**A:** 아니오. 이제부터만 적용

```bash
# 현재 이후의 모든 커밋만 규칙 적용
# 과거 커밋은 그대로 유지
```

### Q4: 팀원이 아직 hooks를 설정 안 했으면?

**A:** git config 설정

```bash
# 한 번만 실행:
git config core.hooksPath git/hooks

# 확인:
git config core.hooksPath
# → git/hooks
```

### Q5: CI/CD와 hooks가 충돌하면?

**A:** 보통 문제 없음

```bash
# CI는 hooks 우회 가능:
COMMIT_MSG_WARN_ONLY=1 git commit

# 하지만 우리 팀은 3명이므로
# CI 자동화는 아직 없음
```

### Q6: 규칙을 바꾸고 싶으면?

**A:** 팀 미팅 후 업데이트

```bash
# 규칙 파일 수정:
git/config/commit-msg-rules.sh
git/config/prepare-commit-msg-rules.sh
git/config/pre-push-rules.sh

# 팀원들에게 공지
```

---

## 체크리스트

### 처음 설정할 때

```
[ ] git/hooks가 설정되어 있는가?
    git config core.hooksPath
    # → git/hooks 출력되면 OK

[ ] 세 가지 hook이 모두 있는가?
    ls -la git/hooks/
    - commit-msg ✓
    - pre-push ✓
    - prepare-commit-msg ✓

[ ] 테스트 커밋을 해봤는가?
    git commit -m "test: setup verification"
    # → 에러 없이 통과하는가?
```

### 매일 사용할 때

```
[ ] Branch 이름: feature/SWINNOTEAM-XXX-description?
[ ] Commit 메시지: feat/fix/docs 등 타입으로 시작?
[ ] Subject: 50자 이내?
[ ] 금지 패턴 없음? (WIP, tmp, test 등)
[ ] Push 전 main이 아닌 브랜치인가?
```

---

## 도움말

**문제가 생겼을 때:**

```bash
# 1. 에러 메시지 읽기
# 2. 이 문서의 "일반 문제와 해결" 확인
# 3. 여전히 모르면?
#    → 팀에 물어보기
#    → 또는 이 문서의 FAQ 참고
```

**더 알아보기:**

```bash
# Hook 파일 보기:
cat git/hooks/commit-msg
cat git/hooks/pre-push
cat git/hooks/prepare-commit-msg

# 규칙 파일 보기:
cat git/config/commit-msg-rules.sh
cat git/config/pre-push-rules.sh
cat git/config/prepare-commit-msg-rules.sh

# 테스트 실행:
./git/test/test-commit-msg.sh
./git/test/test-pre-push.sh
./git/test/test-prepare-commit-msg.sh
```

---

## 마지막 팁

```
💡 Hooks는 당신을 도와주는 친구입니다!

❌ "왜 자꾸 막아?"
✅ "좋은 습관을 만드는 중"

처음엔 불편할 수 있지만,
2-3주 후면 습관처럼 자연스러워집니다.
```

---

**문서 버전:** 1.0
**마지막 수정:** 2026-01-29
**담당자:** SWINNOTEAM 개발팀
**피드백:** 이 가이드가 도움이 되지 않으면 팀에 알려주세요!
