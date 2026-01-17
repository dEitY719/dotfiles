# Internal PC git-crypt 복구 가이드

**작성일**: 2026-01-17
**상태**: 긴급 복구 절차
**대상**: Internal PC (Samsung DS KORCO158847)

---

## 📍 현재 상황

| 항목 | 상태 |
|-----|------|
| External PC (SERAPH) | ✅ 정상 (git-crypt key A) |
| Internal PC (KORCO158847) | ❌ 손상 (git-crypt init으로 key B 생성) |
| git push 여부 | ✅ 미수행 (Internal에서 fetch만 함) |
| 복구 가능성 | ✅ 100% 가능 |

---

## 🚨 왜 이 문제가 발생했는가?

### Root Cause
1. **Internal PC에서 `git-crypt init` 실행**
   - 새로운 대칭키 B 생성됨
   - External PC의 키 A와 불일치 발생

2. **`.env` 자동 로딩 방어 부재**
   - `shell-common/env/dotenv.sh`가 암호화 상태를 확인 안 함
   - 암호화된 바이너리를 bash가 source 시도
   - 결과: `bash: syntax error near unexpected token ')'`

3. **git-crypt 메타데이터 혼동**
   - `.git/git-crypt` vs `.git-crypt/` 경로 헷갈림
   - 잘못된 손상 진단으로 init 재실행 권유

---

## ✅ 복구 절차 (Step-by-Step)

### 🔧 Prerequisites

```bash
# 1. External PC에서 백업 키 준비됨
# 위치: ~/.dotfiles/.secrets/.dotfiles-backup-key.txt
# 크기: 148 bytes
# 권한: 600 (읽기 전용)
```

---

### Step 1: 백업 키 받기

**옵션 A: scp를 통한 전달 (권장 - 사무실 내부망)**

```bash
# External PC (SERAPH)에서 수행됨
scp .secrets/.dotfiles-backup-key.txt \
    bwyoon@KORCO158847:/home/bwyoon/dotfiles/.secrets/

# 또는 ssh key 지정
scp -i ~/.ssh/internal_key.pem \
    .secrets/.dotfiles-backup-key.txt \
    bwyoon@KORCO158847:/home/bwyoon/dotfiles/.secrets/
```

**옵션 B: 파일 공유 (USB, 이메일 등 - 오프라인)**

```bash
# External PC에서 파일 복사
# 위치: SERAPH:/home/bwyoon/dotfiles/.secrets/.dotfiles-backup-key.txt

# Internal PC에 저장
# 위치: KORCO158847:/home/bwyoon/dotfiles/.secrets/.dotfiles-backup-key.txt
```

**옵션 C: Base64 인코딩 (제한적 환경)**

```bash
# External PC에서
base64 -w 0 .secrets/.dotfiles-backup-key.txt > key.b64
cat key.b64
# 출력된 텍스트 메모

# Internal PC에서
cat > key.b64 << 'EOF'
# 여기에 메모한 텍스트 붙여넣기
EOF

base64 -d key.b64 > .secrets/.dotfiles-backup-key.txt
chmod 600 .secrets/.dotfiles-backup-key.txt
```

---

### Step 2: Internal PC에서 손상된 메타데이터 제거

```bash
# Internal PC에서 실행
cd ~/dotfiles

# ⚠️ 중요: 새로 생성된 키 제거
rm -rf .git-crypt/

# 확인: .git-crypt 디렉토리가 없어야 함
ls -la .git-crypt/ 2>&1
# 출력: No such file or directory (정상)
```

---

### Step 3: External PC의 키로 unlock

```bash
# Internal PC에서 실행
cd ~/dotfiles

# 키 파일이 있는지 확인
ls -la .secrets/.dotfiles-backup-key.txt

# git-crypt unlock 실행
git-crypt unlock .secrets/.dotfiles-backup-key.txt

# 성공 메시지
# "Number of files successfully decrypted: 2"
```

---

### Step 4: 복구 확인

```bash
# Internal PC에서 실행

# 1. .env 파일이 평문인지 확인
head -5 .env
# ✅ 정상: # (ME) GEMINI_API_KEY: ...
# ❌ 실패: GITCRYPT... (여전히 암호화됨)

# 2. git-crypt 상태 확인
git-crypt status
# ✅ 정상: encrypted: .env

# 3. 셸 초기화 확인
source ~/.bashrc
# ✅ 에러 없이 완료

# 4. 환경변수 로드 확인
echo $GEMINI_API_KEY
# ✅ API 키가 출력됨 (또는 echo $ANTHROPIC_API_KEY)
```

---

### Step 5: 최종 검증

```bash
# Internal PC에서

# 1. git 상태 확인
git status
# ✅ nothing to commit, working tree clean

# 2. .env 커밋 히스토리 확인
git log --oneline -- .env | head -3
# External PC의 커밋과 동일해야 함:
# ed18ef5 secret: add ANTHROPIC_ADMIN_API_KEY
# dbde6f5 feat: Add automatic .env file loading to shell initialization
# 17577a5 P3: Add lazy-init helper and refactor litellm functions

# 3. git-crypt 메타데이터 확인
ls -la .git-crypt/
# ✅ 디렉토리 존재: .git-crypt/keys

# 4. External PC와 동기화 확인
git fetch origin
git status
# ✅ Your branch is up to date with 'origin/main'
```

---

## ⚠️ 주의사항

### ❌ 절대 하면 안 되는 것

```bash
# ❌ 절대 금지: 다시 초기화 (더 망침!)
git-crypt init

# ❌ 절대 금지: .git-crypt 직접 수정
rm -rf .git-crypt/keys/...  # (전체 제거만 가능)

# ❌ 절대 금지: 암호화 키를 평문으로 commit
git add .secrets/.dotfiles-backup-key.txt --no-skip-worktree
# (.gitattributes가 자동 암호화하므로 직접 추가 불필요)
```

### ✅ 복구 후 보안 조치

```bash
# 복구 완료 후 실행

# 1. 임시 백업 키 파일 정리 (필요 시)
rm -f /tmp/dotfiles-crypt-key.txt

# 2. .secrets/ 디렉토리 권한 확인
chmod 700 .secrets/
chmod 600 .secrets/.dotfiles-backup-key.txt

# 3. 키 파일이 git에서 암호화되었는지 확인
git-crypt status | grep dotfiles-backup-key
# ✅ encrypted: .secrets/.dotfiles-backup-key.txt
```

---

## 🔍 문제 해결 (Troubleshooting)

### Q1: "git-crypt unlock 실패: no GPG secret key available"

**원인**: symmetric key (대칭키)로 unlock하려는데 GPG 키 요청

**해결**:
```bash
# 대칭키 파일 경로가 맞는지 확인
ls -l .secrets/.dotfiles-backup-key.txt

# 파일이 손상되지 않았는지 확인 (크기 확인)
wc -c .secrets/.dotfiles-backup-key.txt
# ✅ 148 바이트여야 함

# 다시 unlock 시도
git-crypt unlock .secrets/.dotfiles-backup-key.txt
```

### Q2: ".env가 여전히 암호화되어 있음"

**원인**: unlock이 완료되지 않았거나 .git-crypt 메타데이터 문제

**해결**:
```bash
# 진단
git-crypt status

# 만약 아직 locked 상태라면:
# 1. 디렉토리 제거 후 다시 unlock
rm -rf .git-crypt/
git-crypt unlock .secrets/.dotfiles-backup-key.txt

# 2. 또는 git에서 다시 checkout
git checkout HEAD -- .env
```

### Q3: "source ~/.bashrc 후 syntax error 반복"

**원인**: .env 파일이 여전히 암호화된 바이너리 상태

**해결**:
```bash
# 확인
cat .env | head -c 20
# GITCRYPT...로 시작하면 아직 암호화됨

# Step 2-3 재진행
rm -rf .git-crypt/
git-crypt unlock .secrets/.dotfiles-backup-key.txt

# 또는 임시 우회 (복구 전까지만)
echo 'export SKIP_ENV_LOAD=1' >> ~/.bashrc.local
source ~/.bashrc
```

### Q4: "scp 전달 실패: permission denied"

**원인**: 네트워크 연결 또는 SSH 인증 문제

**해결**:
```bash
# 1. 네트워크 연결 확인
ping KORCO158847

# 2. SSH 연결 테스트
ssh bwyoon@KORCO158847 echo "OK"

# 3. 파일 공유 (USB) 방법으로 변경
# 또는 이메일로 Base64 전송 (옵션 C)
```

---

## 📋 Internal PC 체크리스트

복구 진행도 추적:

- [ ] **Step 1**: 백업 키 파일 받기 완료
  - [ ] 파일 위치: `.secrets/.dotfiles-backup-key.txt`
  - [ ] 파일 크기: 148 바이트
  - [ ] 파일 권한: 600

- [ ] **Step 2**: `.git-crypt/` 디렉토리 제거 완료
  - [ ] 확인: `ls -la .git-crypt/` → 없음

- [ ] **Step 3**: git-crypt unlock 성공
  - [ ] 출력: "Number of files successfully decrypted: 2"

- [ ] **Step 4**: 평문 .env 확인
  - [ ] `head -5 .env` → API 키 보임
  - [ ] `source ~/.bashrc` → 에러 없음
  - [ ] `echo $GEMINI_API_KEY` → 값 출력됨

- [ ] **Step 5**: 최종 검증 완료
  - [ ] `git status` → clean
  - [ ] `git log --oneline -- .env` → 3개 commit 보임
  - [ ] `git-crypt status` → encrypted 파일 표시
  - [ ] `git fetch origin` → up to date

- [ ] **보안**: 임시 파일 정리
  - [ ] 불필요한 키 파일 삭제
  - [ ] 권한 설정 확인

---

## 🎯 예상 소요 시간

| 단계 | 시간 | 비고 |
|------|------|------|
| Step 1 (키 전달) | 5~10분 | 네트워크 환경에 따라 변동 |
| Step 2-3 (메타데이터 제거 & unlock) | 2분 | 매우 빠름 |
| Step 4-5 (검증) | 3분 | 모든 확인 포함 |
| **총계** | **~15분** | 문제 없으면 10분 이내 |

---

## 📞 문제 해결 후 보고

복구 완료 후:

```bash
# Internal PC에서 최종 확인 후 아래 실행
git log -1 --oneline -- .env
git-crypt status
git status

# 출력 결과를 External PC에 보고
# (작업 완료 확인용)
```

---

## 참고 자료

- [git-crypt 공식 문서](https://github.com/AGWA/git-crypt)
- [문제 분석 리뷰](./abc-review-CX.md) - 원인 분석 및 개선 사항
- [환경 로더 수정사항](../shell-common/env/dotenv.sh) - 방어 로직 추가됨
- [git-crypt 헬퍼 수정사항](../shell-common/tools/integrations/git_crypt.sh) - 경로 수정

---

**최종 작성**: 2026-01-17
**상태**: ✅ 복구 절차 확정, 안전성 보장
**담당자**: 
- External PC (SERAPH): 키 관리 및 전달
- Internal PC (KORCO158847): 복구 실행 및 검증
