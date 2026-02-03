# Post-Commit Hook 설정 가이드

> 모든 프로젝트에서 work_log.txt에 자동으로 커밋 기록을 남기고,
> playbook 저장소에 자동으로 동기화하는 post-commit hook 완전 가이드

---

## 📖 목차

1. [개념 이해](#1-개념-이해)
2. [Quick Start](#2-quick-start)
3. [상세 설정](#3-상세-설정)
4. [실제 예제: litellm 프로젝트](#4-실제-예제-litellm-프로젝트)
5. [FAQ](#5-faq)
6. [문제 해결](#6-문제-해결)

---

## 1. 개념 이해

### 1.1 Post-Commit Hook이란?

```
Git Commit 발생
    ↓
    ├─ Pre-commit Hook (커밋 전 검사)
    ├─ Commit 생성
    │
    └─ Post-commit Hook ← 우리가 설정하는 부분
          │
          └─ work_log.txt 자동 기록
             └─ playbook 자동 동기화
```

**특징:**
- 커밋이 이미 완료된 후에 실행
- 커밋 중단 불가능 (실패해도 커밋은 이미 되어 있음)
- 각 저장소마다 독립적으로 작동

### 1.2 각 저장소의 범위

```
~/dotfiles/.git/hooks/post-commit
    ↓ (dotfiles에서만 실행)
    └─ work_log.txt 기록 + playbook 자동 커밋

~/para/project/litellm/.git/hooks/post-commit
    ↓ (litellm에서만 실행)
    └─ work_log.txt 기록 (playbook 자동 커밋 없음)

~/para/project/other-project/.git/hooks/post-commit
    ↓ (other-project에서만 실행)
    └─ work_log.txt 기록
```

### 1.3 작동 흐름

```
개발자가 프로젝트에서 commit 실행
│
├─ Commit 생성됨
│
└─ Post-commit Hook 자동 실행
     │
     ├─ Step 1: 커밋 정보 추출
     │   ├─ commit hash
     │   ├─ commit message
     │   ├─ timestamp
     │   └─ 패턴 분석 (type, category, jira key)
     │
     ├─ Step 2: work_log.txt에 기록
     │   └─ [YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | hours | hash
     │
     └─ Step 3: Target 저장소 자동 커밋 (dotfiles의 경우만)
           └─ playbook 저장소에 자동 커밋
```

---

## 2. Quick Start

### 최소한의 3단계

```bash
# Step 1: Hook 설치 스크립트 실행
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/litellm

# Step 2: 확인
ls -la ~/para/project/litellm/.git/hooks/post-commit

# Step 3: 테스트 커밋
cd ~/para/project/litellm
git commit --allow-empty -m "test: verify post-commit hook"

# Step 4: work_log.txt 확인
tail ~/work_log.txt
```

**기대 결과:**
```
[2026-02-03 12:30:00] [LITELLM-AUTO] | test | other | -h | abc123def
```

---

## 3. 상세 설정

### 3.1 사전 조건

```bash
# 1. Hook 저장소 확인
ls -la ~/dotfiles/git/hooks/
  ✓ post-commit.generic     (모든 프로젝트용 템플릿)
  ✓ install-hooks.sh        (설치 스크립트)

# 2. Target 저장소 확인 (work_log.txt가 있는 곳)
ls -la ~/para/archive/playbook/logs/
  ✓ work_log.txt            (실제 파일)

# 3. 프로젝트 git 저장소 확인
cd ~/para/project/your-project
git rev-parse --git-dir
  ✓ .git 또는 <path-to-.git>
```

### 3.2 설치 옵션

#### Option A: 설치 스크립트 (권장)

```bash
# 절대 경로로 실행
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/litellm

# 상대 경로로 실행 (현재 디렉토리가 litellm인 경우)
~/dotfiles/git/hooks/install-hooks.sh .

# 기존 hook 덮어쓰기
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/litellm --force
```

**내부 동작:**
```bash
# 스크립트가 다음을 자동으로 함:
mkdir -p ~/para/project/litellm/.git/hooks
ln -s ~/dotfiles/git/hooks/post-commit.generic \
      ~/para/project/litellm/.git/hooks/post-commit
chmod +x ~/para/project/litellm/.git/hooks/post-commit
```

#### Option B: 수동 설치

```bash
cd ~/para/project/litellm

# 1. 기존 파일 백업 (있으면)
[ -f .git/hooks/post-commit ] && mv .git/hooks/post-commit .git/hooks/post-commit.bak

# 2. Symlink 생성
ln -s ~/dotfiles/git/hooks/post-commit.generic .git/hooks/post-commit

# 3. 권한 설정
chmod +x .git/hooks/post-commit

# 4. 확인
ls -la .git/hooks/post-commit
```

#### Option C: 파일 복사

```bash
cd ~/para/project/litellm

# 1. 파일 복사
cp ~/dotfiles/git/hooks/post-commit.generic .git/hooks/post-commit

# 2. 권한 설정
chmod +x .git/hooks/post-commit
```

### 3.3 환경 변수 커스터마이징 (고급)

```bash
# 기본값 (litellm에서는 이것으로 충분)
WORK_LOG_DIR=${HOME}/para/archive/playbook/logs        # 기록할 위치
AUTO_COMMIT_REPO=${HOME}/para/archive/playbook         # 자동 커밋 대상 (dotfiles만)

# 커스터마이징 예제 (다른 프로젝트인 경우)
# ~/.bashrc 또는 git 설정에 추가:

# 예: 다른 work_log 위치 사용
export WORK_LOG_DIR="${HOME}/my/custom/path/logs"

# 예: 자동 커밋 비활성화
export AUTO_COMMIT_REPO=""
```

---

## 4. 실제 예제: litellm 프로젝트

### 4.1 사전 확인

```bash
# litellm 프로젝트 확인
ls -la ~/para/project/litellm/
  ✓ .git 디렉토리 있나? (git 저장소인가?)
  ✓ .git/config 있나?

# 작동 확인
cd ~/para/project/litellm
git status
  ✓ "On branch ..." 출력되나?
```

### 4.2 단계별 설치

#### Step 1: Hook 설치

```bash
# 절대 경로로 설치 (어디서든 실행 가능)
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/litellm

# 출력 예:
# Installing hooks to: /home/bwyoon/para/project/litellm/.git/hooks
#
# ✓ Created symlink:
#   Target: /home/bwyoon/para/project/litellm/.git/hooks/post-commit
#   Source: /home/bwyoon/dotfiles/git/hooks/post-commit.generic
#
# Installation complete!
```

#### Step 2: 설치 확인

```bash
# Symlink 확인
ls -la ~/para/project/litellm/.git/hooks/post-commit

# 출력 예:
# lrwxrwxrwx 1 user group 51 Feb  3 12:30 post-commit -> /home/bwyoon/dotfiles/git/hooks/post-commit.generic

# Symlink 대상 확인
readlink ~/para/project/litellm/.git/hooks/post-commit

# 출력 예:
# /home/bwyoon/dotfiles/git/hooks/post-commit.generic

# 실행 권한 확인
test -x ~/para/project/litellm/.git/hooks/post-commit && echo "✓ Executable" || echo "✗ Not executable"
```

#### Step 3: 테스트 커밋 #1 - 빈 커밋

```bash
cd ~/para/project/litellm

# 빈 커밋으로 hook 테스트
git commit --allow-empty -m "test: verify post-commit hook installation"

# 출력 예:
# [main abc1234] test: verify post-commit hook installation
#  0 files changed
```

#### Step 4: work_log.txt 확인

```bash
# work_log.txt에 기록되었는지 확인
tail -5 ~/work_log.txt

# 출력 예:
# [2026-02-03 10:00:00] [DOTFILES-AUTO] | fix | Infrastructure | 1h | 18b3da7
# [2026-02-03 10:15:00] [DOTFILES-AUTO] | feat |  | -h | 39d4624
# [2026-02-03 12:30:00] [LITELLM-AUTO] | test | other | -h | abc1234  ← 우리가 만든 커밋
```

**기록 형식 설명:**

```
[2026-02-03 12:30:00]      ← 타임스탬프
[LITELLM-AUTO]             ← JIRA Key (프로젝트명-AUTO)
| test                     ← Type (commit message 첫 단어)
| other                    ← Category (없으면 "other")
| -h                       ← TimeSpent (일반적으로 "-h")
| abc1234                  ← Commit hash
```

#### Step 5: 실제 개발 작업으로 테스트

```bash
cd ~/para/project/litellm

# 실제 파일 수정
echo "feature X" >> README.md

# 스테이징
git add README.md

# 실제 커밋 (commit message에 type과 category 포함)
git commit -m "feat(llm): add new feature X

This is a description of the feature.

Category: Feature Development"

# 결과 확인
tail -3 ~/work_log.txt

# 출력 예:
# [2026-02-03 12:35:00] [LITELLM-AUTO] | test | other | -h | abc1234
# [2026-02-03 12:36:00] [LITELLM-AUTO] | feat | Feature Development | -h | def5678
```

#### Step 6: playbook 동기화 확인 (dotfiles의 경우만)

```bash
# dotfiles에서 commit하면 playbook도 자동 커밋됨
cd ~/dotfiles

# 어떤 파일이든 수정
echo "test" >> README.md
git add README.md
git commit -m "docs: update README"

# playbook 자동 커밋 확인
cd ~/para/archive/playbook
git log --oneline -3

# 출력 예:
# xyz9999 chore(work-log): auto updated by def5678
# abc8888 docs: add work log system documentation
# ...
```

### 4.3 고급 사용: 커밋 메시지 패턴

Hook이 인식하는 패턴:

```bash
# ✓ Type 자동 인식 (첫 단어)
git commit -m "feat: add feature"          → type: "feat"
git commit -m "fix(api): fix bug"          → type: "fix"
git commit -m "docs: update doc"           → type: "docs"

# ✓ Category 인식 (Category: 키워드)
git commit -m "feat: add feature

Category: Feature Development"             → category: "Feature Development"

# ✓ JIRA Key 인식
git commit -m "feat: add feature [PROJ-123]"  → jira_key: "PROJ-123"

# ✓ TimeSpent 인식 (있으면)
git commit -m "feat: add feature
TimeSpent: 2h"                            → time: "2" hours

# 만약 명시적 JIRA Key가 없으면
git commit -m "feat: add feature"          → jira_key: "LITELLM-AUTO" (자동)
```

---

## 5. FAQ

### Q1: Hook이 자동으로 실행되지 않아요

**A:** 다음을 확인해보세요:

```bash
# 1. Symlink가 제대로 되어있나?
ls -la ~/para/project/litellm/.git/hooks/post-commit

# 2. 원본 파일이 있나?
ls -la ~/dotfiles/git/hooks/post-commit.generic

# 3. 권한이 있나?
test -x ~/para/project/litellm/.git/hooks/post-commit && echo "OK" || echo "NO"

# 4. 디버그: Hook 수동 실행
cd ~/para/project/litellm
bash .git/hooks/post-commit
tail ~/work_log.txt
```

### Q2: work_log.txt에 기록이 안 됨

**A:** 경로를 확인하세요:

```bash
# 1. work_log.txt가 있나?
ls -la ~/work_log.txt

# 2. Symlink로 가리키는 곳이 있나?
readlink ~/work_log.txt

# 3. 실제 파일이 있나?
ls -la ~/para/archive/playbook/logs/work_log.txt

# 4. 권한이 있나?
touch ~/work_log.txt && echo "OK" || echo "NO"
```

### Q3: JIRA Key가 "AUTO"가 되는데, 원하는 Key를 사용하려면?

**A:** 커밋 메시지에 명시하세요:

```bash
# 명시적 JIRA Key
git commit -m "feat: add feature [LITELLM-100]"
  → work_log.txt: [LITELLM-100]

# 또는 환경변수 설정
export JIRA_KEY_DEFAULT="LITELLM-100"
git commit -m "feat: add feature"
  → work_log.txt: [LITELLM-100]
```

### Q4: 다른 저장소에도 설치하려면?

**A:** 같은 명령어 반복:

```bash
# Project A
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/project-a

# Project B
~/dotfiles/git/hooks/install-hooks.sh ~/workspace/project-b

# 확인
for dir in ~/para/project/* ~/workspace/*; do
    if [ -d "$dir/.git" ]; then
        echo "$dir: $([ -L $dir/.git/hooks/post-commit ] && echo 'Installed' || echo 'Not installed')"
    fi
done
```

### Q5: Hook을 제거하려면?

**A:** Symlink 삭제:

```bash
rm ~/para/project/litellm/.git/hooks/post-commit

# 확인
ls -la ~/para/project/litellm/.git/hooks/post-commit
  # No such file or directory (정상)
```

---

## 6. 문제 해결

### 문제: "Permission denied" 오류

```bash
# 원인: 실행 권한 없음
chmod +x ~/dotfiles/git/hooks/post-commit.generic

# 또는 다시 설치
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/litellm --force
```

### 문제: Hook이 느리게 실행됨

```bash
# 이유: Auto-commit 작업 때문 (dotfiles의 경우)
# 무시하세요 - 정상입니다

# 속도 확인
time bash ~/.git/hooks/post-commit
```

### 문제: playbook 저장소가 변경되었어요

```bash
# 원인: dotfiles의 post-commit이 auto-commit했음
cd ~/para/archive/playbook
git log --oneline -3

# work_log.txt 변경 확인
git diff HEAD~1 HEAD -- logs/work_log.txt
```

### 문제: 너무 많은 커밋이 생기네요

```bash
# 각 commit마다 playbook에 commit이 생김 (dotfiles의 경우)
# 이것은 정상입니다 - design으로 의도된 것입니다

# 관리하려면:
cd ~/para/archive/playbook

# 최근 work-log 커밋들만 보기
git log --oneline | grep "auto updated" | head -10
```

---

## 📋 체크리스트

설치 완료 확인:

```bash
# [ ] 1. Hook 설치 완료
~/dotfiles/git/hooks/install-hooks.sh ~/para/project/litellm

# [ ] 2. Symlink 확인
ls -la ~/para/project/litellm/.git/hooks/post-commit

# [ ] 3. work_log.txt 경로 확인
ls -la ~/work_log.txt

# [ ] 4. 실제 파일 확인
ls -la ~/para/archive/playbook/logs/work_log.txt

# [ ] 5. 테스트 커밋
cd ~/para/project/litellm
git commit --allow-empty -m "test: verify post-commit"

# [ ] 6. work_log.txt 기록 확인
tail ~/work_log.txt | grep litellm

# [ ] 7. 문서 읽기 완료 ✓
```

---

## 🔗 관련 파일

- `~/dotfiles/git/hooks/post-commit.generic` - Hook 원본
- `~/dotfiles/git/hooks/install-hooks.sh` - 설치 스크립트
- `~/dotfiles/git/hooks/post-commit` - dotfiles 전용 (playbook auto-commit 포함)
- `~/para/archive/playbook/logs/work_log.txt` - 작업 로그 저장소
- `~/para/archive/playbook/docs/worklog-templates/WORKLOG-SYSTEM.md` - 시스템 문서

---

## 📝 변경 기록

| 버전 | 날짜 | 내용 |
|------|------|------|
| 1.0 | 2026-02-03 | 초기 문서 작성, litellm 예제 추가 |

---

**마지막 수정:** 2026-02-03
