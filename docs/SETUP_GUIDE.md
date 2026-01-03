# Dotfiles Setup Guide

## 📋 개요

dotfiles는 두 가지 설정 스크립트로 나뉩니다:

| 스크립트 | 목적 | 실행 시점 |
|---------|------|---------|
| `./setup.sh` | **Shell 환경 설정** (필수) | 초기 설치 시 필수 |
| `./install.sh` | **Claude/PG 보조 설정** (선택) | 초기 설치 또는 필요시 |

---

## 🚀 신규 사용자 초기화 (처음 설치)

### Step 1: 환경별 설정 (필수)
```bash
cd ~/dotfiles
./setup.sh
```

**이 스크립트가 하는 일:**

1. **shell-common/setup.sh** 실행 (환경 선택)
   ```
   Select your environment:
   1) Public PC (home environment)
   2) Internal company PC (direct connection)
   3) External company PC (VPN)
   ```
   - **1) Public PC**: 환경별 설정 제거 (집 환경)
   - **2) Internal PC**: *.local.sh 생성 + System CA Bundle 활성화
   - **3) External PC**: *.local.sh 생성 + Custom Certificate 활성화

2. `bash/setup.sh` 실행
   - `~/.bashrc` → `bash/main.bash` symlink 생성
   - `DOTFILES_BASH_DIR`, `SHELL_COMMON` 환경변수 설정
   - `~/.bash_profile` symlink (선택사항)

3. `zsh/setup.sh` 실행
   - `~/.zshrc` → `zsh/zshrc` symlink 생성
   - 완료 메시지 및 다음 단계 안내

4. `git/setup.sh` 실행
   - `~/.gitconfig` → `git/.gitconfig` symlink 생성

**결과:** 환경에 맞는 설정으로 초기화 완료

### Step 2: Claude/PostgreSQL 설정 (선택사항)
```bash
./install.sh
```

**이 스크립트가 하는 일:**
- `~/.claude/` 디렉토리 설정 (statusline-command.sh, settings.json, agents)
- PostgreSQL `pg_services.list` 설정
- 위의 symlink 재설정 (이미 생성된 경우 업데이트)

---

## ⚠️ 중요: 파일 삭제 금지

**절대 삭제하면 안 되는 파일:**
- ❌ `shell-common/setup.sh` - 환경별 설정 필수
- ❌ `bash/setup.sh` - bash 환경변수 설정 필수
- ❌ `zsh/setup.sh` - zsh 초기화 필수
- ❌ `git/setup.sh` - git config symlink 필수
- ❌ `setup.sh` - 위 파일들의 orchestrator

**이유:**
각 `setup.sh` 파일들은 **단순 symlink 생성 이상의 초기화 작업**을 수행합니다:
- bash/setup.sh: DOTFILES_BASH_DIR, SHELL_COMMON 환경변수 설정
- zsh/setup.sh: 사용자 안내 및 피드백
- git/setup.sh: UX 함수 활용한 피드백

`install.sh`만으로는 이러한 **특수 초기화**를 할 수 없습니다.

---

## 📝 각 파일의 정확한 역할

### setup.sh (루트)
```bash
#!/bin/bash
# 순서대로 각 shell의 setup.sh를 호출
./shell-common/setup.sh
./bash/setup.sh
./zsh/setup.sh
./git/setup.sh
```
- **역할**: Orchestrator (모든 shell 및 환경 setup 실행)
- **언제 실행**: 초기 설치 시 필수
- **부작용**: 없음 (하위 스크립트 호출만)

### shell-common/setup.sh
```bash
# 역할:
# 1. 사용자에게 3가지 환경 선택 요청
# 2. 환경에 맞는 *.local.sh 파일 생성/삭제
# 3. security.local.sh CA 설정 자동 구성
```
- **특수 작업**: 환경별 설정 (Public/Internal/External)
- **언제 실행**: setup.sh에서 자동 호출 (수동 호출 가능)
- **생성되는 파일**:
  - `shell-common/env/proxy.local.sh`
  - `shell-common/env/security.local.sh`
  - `shell-common/tools/external/npm.local.sh`

### bash/setup.sh
```bash
# 역할:
# 1. DOTFILES_BASH_DIR, SHELL_COMMON 환경변수 설정 ← install.sh가 못함
# 2. ~/.bashrc symlink 생성
# 3. ~/.bash_profile symlink 생성 (선택사항)
```
- **특수 작업**: 환경변수 설정 (필수!)
- **언제 실행**: setup.sh에서 자동 호출 (수동 호출 X)
- **symlink 생성**: ~/.bashrc

### zsh/setup.sh
```bash
# 역할:
# 1. ~/.zshrc symlink 생성
# 2. ~/.p10k.zsh symlink 생성 (Powerlevel10k 설정)
# 3. 완료 메시지 + 다음 단계 안내 (사용자 피드백)
```
- **특수 작업**: 사용자 안내, p10k 설정 관리
- **언제 실행**: setup.sh에서 자동 호출 (수동 호출 X)
- **symlink 생성**: ~/.zshrc, ~/.p10k.zsh

### git/setup.sh
```bash
# 역할:
# 1. ~/.gitconfig symlink 생성
# 2. UX 함수를 이용한 피드백
```
- **특수 작업**: UX 피드백
- **언제 실행**: setup.sh에서 자동 호출 (수동 호출 X)
- **symlink 생성**: ~/.gitconfig

### install.sh
```bash
# 역할:
# 1. Claude 설정 (statusline-command.sh, settings.json, agents)
# 2. PostgreSQL 설정 (pg_services.list)
# 3. Bash/Zsh/Git symlink 재설정 (setup.sh와 중복)
```
- **특수 작업**: Claude, PG 설정
- **언제 실행**:
  - 초기 설치 시 (setup.sh 후)
  - Claude 설정 필요시 아무 때나
- **symlink 생성**: ~/.bashrc, ~/.zshrc, ~/.gitconfig (setup.sh와 동일)

---

## ✅ 권장 실행 순서

### 🔵 신규 사용자 (처음 설치)
```bash
cd ~/dotfiles
./setup.sh    # Step 1: Shell 설정 (필수) ← 환경변수 설정 포함
./install.sh  # Step 2: Claude/PG 설정 (선택)
exec bash     # 또는 exec zsh (새 shell로 진입)
```

### 🟢 기존 사용자 (업데이트)
```bash
cd ~/dotfiles
./install.sh  # Claude/PG 설정만 업데이트
```

### 🟡 특정 shell만 재설정
```bash
# Bash만 재설정
./bash/setup.sh

# Zsh만 재설정
./zsh/setup.sh

# Git만 재설정
./git/setup.sh
```

---

## 🔍 Troubleshooting

### ❌ "ux_header: command not found" 오류
**원인**: ux_lib.sh가 로드되지 않음

**해결**:
1. zsh/zshrc 98번 줄 확인: `$SHELL_COMMON/tools/ux_lib/ux_lib.sh` 경로 확인
2. bash/main.bash에서 ux_lib.sh 로드 확인

### ❌ ~/.bashrc 또는 ~/.zshrc 심볼릭 링크 깨짐
**원인**: setup.sh를 실행하지 않았거나, symlink가 잘못 설정됨

**해결**:
```bash
./setup.sh  # 다시 실행
```

### ❌ 새 shell에서 alias/function이 로드되지 않음
**원인**: 기존 ~/.bashrc 또는 ~/.zshrc 파일이 존재하거나, setup.sh를 실행하지 않음

**해결**:
```bash
./setup.sh  # setup.sh가 symlink를 생성하면서 기존 파일을 백업함
```

---

## 📌 핵심 원칙

1. **setup.sh와 install.sh는 보완 관계**
   - setup.sh: Shell 환경 설정 (필수)
   - install.sh: Claude/PG 추가 설정 (선택)

2. **setup.sh의 하위 파일들은 특수 초기화 수행**
   - bash/setup.sh: 환경변수 설정
   - zsh/setup.sh: 사용자 피드백
   - git/setup.sh: UX 피드백

3. **install.sh는 symlink 재설정만 가능**
   - bash/zsh 환경변수 설정 안 함
   - 따라서 초기 설치 시에는 setup.sh 필수

4. **절대 setup.sh 파일들을 삭제하면 안 됨**
   - 특수 초기화 로직이 손실됨
   - install.sh로 복구 불가능

---

## 📚 참고

- `bash/main.bash`: bash 셸 초기화
- `zsh/zshrc` & `zsh/main.zsh`: zsh 셸 초기화
- `git/.gitconfig`: git 설정
- `shell-common/`: bash/zsh 공유 리소스 (aliases, functions, env, ux_lib)
