# Dotfiles Symbolic Link Management Skill

## 목적
dotfiles 프로젝트에서 설정 파일을 symbolic link로 관리하는 표준 패턴을 정의합니다.

## 사용 시나리오
사용자가 다음과 같이 요청할 때 이 SKILL을 적용합니다:
- "xxx.yyy 파일을 symbolic link로 관리해"
- "dotfiles로 zzz 설정 파일 관리하고 싶어"
- "aaa.conf를 symbolic link로 설정해줘"

## 설계 원칙

### 1. 파일 위치 결정
```
원본 위치:     ~/dotfiles/bash/<category>/<filename>
Symbolic link: ~/<target_dir>/<filename> -> ~/dotfiles/bash/<category>/<filename>
```

**카테고리 선택 기준:**
- `bash/claude/`: Claude Code 관련 설정
- `bash/app/`: 애플리케이션별 설정 및 관리 스크립트
- `bash/config/`: 기타 일반 설정 파일
- `bash/env/`: 환경 변수 관련 설정

### 2. Symbolic Link 생성 전략
- 원본 파일을 dotfiles 저장소로 이동
- 기존 파일은 자동 백업 (.backup 확장자)
- symbolic link 생성 및 검증

### 3. 관리 함수 추가
해당 애플리케이션의 bash 스크립트에 관리 함수를 추가합니다:
- `<app>_init`: symbolic link 초기화 함수
- `<app>_edit_<config>`: 설정 파일 편집 함수 (선택적)

### 4. 도움말 업데이트
`<app>help` 함수에 새로운 관리 함수 설명을 추가합니다.

## 구현 단계

### Step 1: 현재 상황 조사
```bash
# 대상 파일 확인
cat <target_file>
ls -la <target_file>

# 관련 bash 스크립트 확인
cat ~/dotfiles/bash/app/<app>.bash

# 카테고리 디렉토리 확인
ls -la ~/dotfiles/bash/<category>/
```

### Step 2: 파일 이동 및 Symbolic Link 생성
```bash
# 1. dotfiles로 파일 복사
cp <target_file> ~/dotfiles/bash/<category>/<filename>

# 2. 기존 파일 삭제 및 symbolic link 생성
rm <target_file>
ln -s ~/dotfiles/bash/<category>/<filename> <target_file>

# 3. 검증
ls -la <target_file>
cat <target_file>
```

### Step 3: 관리 함수 추가
`bash/app/<app>.bash` 파일에 다음 함수들을 추가:

```bash
# Symbolic link 초기화 함수
<app>_init() {
    local source="$HOME/dotfiles/bash/<category>/<filename>"
    local target="<target_file>"

    echo "🔧 Initializing <app> configuration..."

    # 디렉토리 생성
    if [[ ! -d "$(dirname "$target")" ]]; then
        echo "📁 Creating $(dirname "$target") directory..."
        mkdir -p "$(dirname "$target")"
    fi

    # Symbolic link 처리
    if [[ -L "$target" ]]; then
        echo "✅ <filename> symbolic link already exists"
    elif [[ -f "$target" ]]; then
        echo "⚠️  <filename> exists as regular file"
        echo "   Backing up to <filename>.backup..."
        mv "$target" "$target.backup"
        ln -s "$source" "$target"
        echo "✅ Created symbolic link for <filename>"
    else
        ln -s "$source" "$target"
        echo "✅ Created symbolic link for <filename>"
    fi

    echo ""
    echo "✨ <app> configuration initialization complete!"
    echo ""
    echo "📍 Symbolic link:"
    ls -la "$target"
}

# 설정 파일 편집 함수 (선택적)
<app>_edit_<config>() {
    local config_file="$HOME/dotfiles/bash/<category>/<filename>"

    if [[ ! -f "$config_file" ]]; then
        echo "❌ Config file not found: $config_file"
        return 1
    fi

    echo "📝 Editing <app> configuration..."
    echo "   File: $config_file"
    echo ""

    ${EDITOR:-vim} "$config_file"

    echo ""
    echo "✅ Configuration file edited"
    echo "   Changes will take effect immediately (symlinked)"
}
```

### Step 4: 도움말 업데이트
`<app>help` 함수에 새로운 섹션 추가:

```bash
${bold}${blue}[Configuration Management]${reset}

  ${green}<app>_init${reset}         : <app> 설정 파일 symbolic link 초기화
                        (dotfiles/bash/<category>/<filename> ↔ <target_file>)
  ${green}<app>_edit_<config>${reset} : <filename> 파일 편집
```

### Step 5: Git 관리
```bash
# .gitignore 확인 및 수정 (필요시)
grep "<filename>" .gitignore

# 파일 추가
git add bash/<category>/<filename>
git add bash/app/<app>.bash
git add .gitignore  # (수정한 경우)

# Commit
git commit -m "feat: manage <filename> via dotfiles with symbolic link"
```

## 실제 예제: Claude Code settings.json

### 적용 결과
```
원본 위치:     ~/dotfiles/bash/claude/settings.json
Symbolic link: ~/.claude/settings.json -> ~/dotfiles/bash/claude/settings.json
관리 스크립트:  ~/dotfiles/bash/app/claude.bash
```

### 추가된 함수
- `claude_init`: Claude Code 설정 파일 symbolic link 초기화
  - settings.json 및 statusline-command.sh 관리
  - 자동 백업 기능
- `claude_edit_settings`: settings.json 편집 함수

### 사용법
```bash
# 초기 설정 또는 재설정
claude_init

# 설정 파일 편집
claude_edit_settings

# 도움말 확인
claudehelp
```

## 체크리스트

### 설계 단계
- [ ] 대상 파일 식별 및 내용 확인
- [ ] 적절한 카테고리 디렉토리 선택
- [ ] 관리 스크립트 파일 결정 (bash/app/<app>.bash)
- [ ] Symbolic link 경로 설계

### 구현 단계
- [ ] 파일을 dotfiles로 복사
- [ ] Symbolic link 생성 및 검증
- [ ] `<app>_init` 함수 구현
- [ ] `<app>_edit_<config>` 함수 구현 (선택적)
- [ ] `<app>help` 함수 업데이트

### 테스트 단계
- [ ] Symbolic link 작동 확인 (ls -la, cat)
- [ ] `<app>_init` 함수 테스트
- [ ] `<app>_edit_<config>` 함수 테스트 (선택적)
- [ ] 도움말 출력 확인

### Git 관리
- [ ] .gitignore 확인 및 수정 (필요시)
- [ ] 변경된 파일 git add
- [ ] Commit 메시지 작성 및 커밋
- [ ] (선택적) Push

## 주의사항

### 파일 권한
- 민감한 정보가 포함된 파일은 .gitignore에 추가
- 필요시 git-crypt 사용 고려

### 카테고리 선택
- 애플리케이션별 관리가 필요한 경우: `bash/app/<app>/`
- 단순 설정 파일: `bash/config/`
- 환경 변수: `bash/env/`

### 다중 파일 관리
- 한 애플리케이션에 여러 설정 파일이 있는 경우, `<app>_init` 함수 내에서 모두 처리
- 예: claude_init은 settings.json과 statusline-command.sh를 모두 관리

### 함수 명명 규칙
- 초기화: `<app>_init`
- 편집: `<app>_edit_<config>`
- 도움말: `<app>help`

## 확장 가능성

### Template 파일 관리
민감한 정보가 포함된 경우:
```bash
# Template 파일 생성
cp config.json config.json.template
git add config.json.template

# .gitignore에 실제 파일 추가
echo "bash/<category>/config.json" >> .gitignore

# init 함수에서 template 복사 로직 추가
if [[ ! -f "$source" ]] && [[ -f "$source.template" ]]; then
    cp "$source.template" "$source"
fi
```

### 다중 환경 지원
```bash
# 환경별 설정 파일
config.local.json    # .gitignore
config.dev.json      # git 관리
config.prod.json     # git 관리

# init 함수에서 환경 선택
<app>_init() {
    local env="${1:-local}"
    local source="$HOME/dotfiles/bash/<category>/config.$env.json"
    # ...
}
```
