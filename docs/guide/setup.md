# Dotfiles Setup Guide

## 📋 개요

dotfiles 설치는 `./setup.sh` 하나로 수렴합니다 — 신규 PC 든 기존 PC 든 같은 명령을 다시
실행하면 됩니다(멱등). Claude Code 설정도 `setup.sh` 가 호출하는 `claude/setup.sh` 가 맡습니다.

> `install.sh` 는 폐기되었습니다(#2131). 실행하면 안내 메시지와 함께 exit 2 로 종료합니다.
>
> 이전 `install.sh` 가 하던 일의 행방:
> - Claude Code 설정(`statusline-command.sh`, `settings.json`) → `claude/setup.sh` 가 담당
>   (`settings.json` 은 symlink 가 아닌 실파일 복사, #940/#924)
> - bash/zsh/git 링크 → `bash|zsh|git/setup.sh` 가 담당
> - `claude/*.md` → `~/.claude/agents/` 링크 → 에이전트가 아닌 파일을 등록하던 버그라 이관하지 않음
> - `~/.config/pg_services.list` 링크 → 원본 `shell-common/config/pg_services.list` 가 저장소에 없어
>   이관하지 않음. PG 서비스 목록이 필요하면 `~/.config/pg_services.list` 를 직접 만든다
>   (`shell-common/tools/integrations/postgresql.sh` 가 읽는 경로)

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
   - `~/.gitconfig` 를 실파일로 두고 최상단에 `[include] path = <dotfiles>/git/.gitconfig` 보장
     (symlink 아님 — `git config --global` 쓰기가 SSOT 를 오염시키지 않도록)

5. `claude/setup.sh` 등 나머지 단계 실행 (Claude Code 설정, gh, ssh 등)

**결과:** 환경에 맞는 설정으로 초기화 완료

### Step 1.5: npm 설정 확인

`~/.npmrc`는 `npm/npmrc.{environment}` 파일의 symlink로 자동 관리됩니다 (`setup.sh`에서 환경 선택 시 생성).

```bash
check-npm files    # symlink 상태 확인
```

---

## ⚠️ 중요: 파일 삭제 금지

**절대 삭제하면 안 되는 파일:**
- ❌ `shell-common/setup.sh` - 환경별 설정 필수
- ❌ `bash/setup.sh` - bash 환경변수 설정 필수
- ❌ `zsh/setup.sh` - zsh 초기화 필수
- ❌ `git/setup.sh` - ~/.gitconfig include 설정 필수
- ❌ `setup.sh` - 위 파일들의 orchestrator

**이유:**
각 `setup.sh` 파일들은 **단순 symlink 생성 이상의 초기화 작업**을 수행합니다:
- bash/setup.sh: DOTFILES_BASH_DIR, SHELL_COMMON 환경변수 설정
- zsh/setup.sh: 사용자 안내 및 피드백
- git/setup.sh: UX 함수 활용한 피드백

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
- **생성되는 파일/심볼릭 링크**:
  - `shell-common/env/proxy.local.sh`
  - `shell-common/env/security.local.sh`
  - `~/.npmrc` → `npm/npmrc.{environment}` (symlink)
  - `~/.config/pip/pip.conf` → `pip/pip.conf.{environment}` (symlink)
  - `~/.config/uv/uv.toml` → `uv/uv.toml.{environment}` (symlink)

### bash/setup.sh
```bash
# 역할:
# 1. DOTFILES_BASH_DIR, SHELL_COMMON 환경변수 설정
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
# 1. ~/.gitconfig 실파일 + [include] SSOT 보장 (레거시 symlink 는 실파일로 전환)
# 2. UX 함수를 이용한 피드백
```
- **특수 작업**: include 모델 유지 (로컬 커스터마이즈 보존), UX 피드백
- **언제 실행**: setup.sh에서 자동 호출 (수동 호출 X)
- **생성 파일**: ~/.gitconfig (실파일, `git/.gitconfig` 를 include)

---

## ✅ 권장 실행 순서

### 🔵 신규 사용자 (처음 설치)
```bash
cd ~/dotfiles
./setup.sh    # 전체 설정 (환경변수, symlink, Claude Code 포함)
exec bash     # 또는 exec zsh (새 shell로 진입)
```

### 🟢 기존 사용자 (업데이트)
```bash
cd ~/dotfiles
./setup.sh    # 멱등 — 다시 실행하면 최신 상태로 수렴
```

**업그레이드 노트 (#2139)**: `./setup.sh` 가 이제 `symlinks` 스텝에서
`shell-common/config/symlinks.conf` 전 항목을 자동으로 링크한다. 이전에는
`symlink-init` 을 직접 실행해야 했던 `~/.tmux.conf`, `~/.config/ghostty/config`,
`~/.local/bin/schedule-agent-prompt` 가 실파일로 있으면 첫 실행에서
`<파일>.original` 로 백업된 뒤 dotfiles 링크로 바뀐다(이후 실행은 변경 없음).
`.original` 은 latest-only 라 같은 이름의 이전 백업 파일이 있으면 교체된다.
로컬 수정이 있었다면 `.original` 에서 옮겨 담는다.

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

1. **`./setup.sh` 하나로 수렴**
   - 신규 설치와 업데이트 모두 같은 명령 (멱등)
   - `install.sh` 는 폐기됨 — 실행 시 exit 2

2. **setup.sh의 하위 파일들은 특수 초기화 수행**
   - bash/setup.sh: 환경변수 설정
   - zsh/setup.sh: 사용자 피드백
   - git/setup.sh: UX 피드백

3. **절대 setup.sh 파일들을 삭제하면 안 됨**
   - 특수 초기화 로직이 손실됨

---

## 📚 참고

- `bash/main.bash`: bash 셸 초기화
- `zsh/zshrc` & `zsh/main.zsh`: zsh 셸 초기화
- `git/.gitconfig`: git 설정 SSOT (`~/.gitconfig` 가 include)
- `shell-common/`: bash/zsh 공유 리소스 (aliases, functions, env, ux_lib)
