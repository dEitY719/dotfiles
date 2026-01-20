# VS Code 설정 동기화

회사(Internal PC)와 외부(External PC) 간 VS Code 설정을 수동으로 동기화하는 간단한 시스템입니다.

## 📋 파일 구조

```
.vscode/
├── base.json          # VS Code 설정 파일 (Git에서 추적)
├── sync-push.sh       # Push: base.json → VS Code 설정
├── sync-pull.sh       # Pull: VS Code 설정 → base.json
└── README.md          # 이 파일
```

## 🔄 동기화 방법

### 1️⃣ PUSH: base.json을 VS Code에 복사

새로 클론한 PC에서, 또는 dotfiles의 설정을 VS Code에 적용하려면:

```bash
./.vscode/sync-push.sh
```

**수행 작업:**
- ✅ `base.json` → VS Code 설정 디렉토리에 복사
- ✅ 기존 설정 자동 백업 생성
- ✅ VS Code 재시작 필요

---

### 2️⃣ PULL: VS Code 설정을 base.json에 복사

VS Code에서 설정을 변경한 후, dotfiles에 저장하려면:

```bash
./.vscode/sync-pull.sh
```

**수행 작업:**
- ✅ VS Code 설정 → `base.json` 복사
- ✅ 기존 `base.json` 자동 백업 생성
- ✅ 복사된 내용을 JSON 형식으로 출력

---

## 📝 사용 워크플로우

### 시나리오 1: 외부 PC에서 회사 PC로 설정 동기화

#### 외부 PC에서:
```bash
# 1. VS Code 설정을 base.json에 저장
./.vscode/sync-pull.sh

# 2. 확인 후 Git에 커밋
git add .vscode/base.json
git commit -m "chore: update VS Code settings"
git push
```

#### 회사 PC에서:
```bash
# 1. 최신 코드 가져오기
git pull

# 2. base.json을 VS Code에 적용
./.vscode/sync-push.sh

# 3. VS Code 재시작
```

---

### 시나리오 2: 회사 PC에서 외부 PC로 설정 동기화

#### 회사 PC에서:
```bash
# 1. VS Code 설정을 base.json에 저장
./.vscode/sync-pull.sh

# 2. 확인 후 Git에 커밋
git add .vscode/base.json
git commit -m "chore: update VS Code settings from company PC"
git push
```

#### 외부 PC에서:
```bash
# 1. 최신 코드 가져오기
git pull

# 2. base.json을 VS Code에 적용
./.vscode/sync-push.sh

# 3. VS Code 재시작
```

---

## 🖥️ 플랫폼별 경로

### Windows (회사 PC)
- VS Code 설정: `$APPDATA\Code\User\settings.json`
  - 예: `C:\Users\bwyoon\AppData\Roaming\Code\User\settings.json`

### Linux/macOS
- Linux: `~/.config/Code/User/settings.json`
- macOS: `~/Library/Application Support/Code/User/settings.json`

> 스크립트가 자동으로 OS를 감지하여 올바른 경로를 사용합니다.

---

## 💾 백업 파일

동기화할 때마다 자동으로 백업이 생성됩니다:

```bash
# PULL 실행 시
.vscode/base.json.backup.20250120_143022

# PUSH 실행 시
$APPDATA\Code\User\settings.json.backup.20250120_143022
```

필요하면 언제든 백업에서 복구할 수 있습니다.

---

## ⚠️ 주의사항

### 1. 민감한 정보는 저장하지 마세요
다음 항목은 `base.json`에 포함하면 안 됩니다:
- 개인 토큰, API 키
- 절대 경로
- 로컬 환경 경로

### 2. 충돌 주의
여러 PC에서 동시에 수정하면 마지막 PULL/PUSH가 이전 변경사항을 덮어씁니다:
```
❌ Bad: 외부 PC와 회사 PC에서 동시에 수정 후 PULL/PUSH
✅ Good: 한쪽에서 수정 → PULL/PUSH → 다른 쪽에서 받기
```

### 3. VS Code 재시작 필수
PUSH 후 설정을 적용하려면 VS Code를 완전히 종료했다가 다시 실행하세요.

---

## 🔧 명령어 참고

```bash
# 현재 base.json 내용 확인
cat .vscode/base.json | python3 -m json.tool

# 동기화 스크립트 실행 권한 확인
ls -l .vscode/sync-*.sh

# 백업 파일 목록 확인
ls -la .vscode/base.json.backup.*
ls -la "$APPDATA/Code/User/settings.json.backup.*"  # Windows
```

---

## 📞 문제 해결

### Q: 스크립트가 실행되지 않습니다
```bash
chmod +x .vscode/sync-push.sh .vscode/sync-pull.sh
```

### Q: "VS Code 설정 디렉토리를 찾을 수 없습니다" 오류
- 해당 PC에서 VS Code를 한 번 실행한 후 다시 시도하세요
- 경로가 올바른지 수동 확인:
  - Windows: `C:\Users\<username>\AppData\Roaming\Code\User\`
  - Linux: `~/.config/Code/User/`

### Q: Git 커밋 전에 변경사항을 확인하고 싶습니다
```bash
# PULL 후 내용 확인
./.vscode/sync-pull.sh

# 백업과 비교
diff .vscode/base.json.backup.* .vscode/base.json
```

### Q: 실수로 잘못된 설정을 저장했습니다
```bash
# 백업에서 복구
cp .vscode/base.json.backup.20250120_143022 .vscode/base.json

# 또는 VS Code 설정에서 복구
cp "$APPDATA/Code/User/settings.json.backup.DATE_TIME" "$APPDATA/Code/User/settings.json"
```

---

## 🚀 빠른 시작

```bash
# 1. 현재 VS Code 설정을 base.json으로 저장 (처음 한 번)
./.vscode/sync-pull.sh

# 2. Git에 커밋
git add .vscode/base.json
git commit -m "initial: add VS Code settings"

# 3. 다른 PC에서 가져온 후
git pull

# 4. VS Code에 적용
./.vscode/sync-push.sh
```

---

**마지막 업데이트:** 2025-01-20
