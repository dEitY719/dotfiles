# OpenCode CLI Setup Guide

OpenCode는 사내에서 구동 가능한 Claude Code CLI 스타일의 코딩 에이전트입니다. 이 가이드는 dotfiles 프로젝트의 OpenCode 설치 및 설정을 설명합니다.

## 📋 목차

- [개요](#개요)
- [빠른 시작](#빠른-시작)
- [환경 선택](#환경-선택)
- [상세 설치](#상세-설치)
- [설정 파일](#설정-파일)
- [사용 방법](#사용-방법)
- [문제 해결](#문제-해결)

## 개요

### OpenCode란?

OpenCode는 다음과 같은 특징을 가진 에이전트입니다:

- **Claude Code와 유사**: Claude의 공식 CLI와 같은 사용 경험
- **사내 호스팅**: 회사 네트워크에서 안전하게 사용 가능
- **다중 LLM 지원**: 다양한 언어 모델 통합
- **상황별 구성**: Home, External, Internal 환경 지원

### 시스템 요구 사항

- **Node.js**: 16.x 이상
- **npm**: 8.x 이상 (또는 yarn, pnpm)
- **bash**: 설치 스크립트 호환성 (bash 4.0+)
- **터미널**: bash 또는 zsh 쉘

## 빠른 시작

가장 간단한 방법:

```bash
# 1. 설치 시작
install-opencode

# 2. 프롬프트에 따라 환경 선택 (1-3)
# 3. 설정이 자동으로 적용됨
# 4. 설치 완료!

# 5. 설치 확인
opencode-verify
```

## 환경 선택

OpenCode는 세 가지 환경을 지원합니다:

### 1️⃣ Home (개인 PC)

**특징:**
- 로컬 개발 환경
- SSL 검증 활성화
- OpenCode 기본 설정 사용
- 추가 설정 불필요

**설정 파일:** 선택 사항 (생성되지 않음)

**사용 시나리오:**
- 개인 노트북이나 데스크탑
- 로컬 LLM 서버 실행
- 기본 OpenCode 기능 사용

### 2️⃣ External (공개 네트워크)

**특징:**
- 회사 외부 PC
- 공개 GitHub 접근 가능
- LiteLLM을 통한 모델 접근
- 단일 모델: `gpt-oss-20b`

**설정 파일:** `~/.config/opencode/opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Provider",
      "options": {
        "baseURL": "http://ssai.samsungds.net:9090",
        "apiKey": "925f1053996f6a679f40db2251d2d622a5263731"
      },
      "models": {
        "gpt-oss-20b": {
          "name": "gpt-oss-20b"
        }
      }
    }
  }
}
```

**사용 시나리오:**
- 회사 외부 사무실
- 카페나 원격 근무지
- 공개 GitHub 저장소 접근 필요

### 3️⃣ Internal (사내 네트워크)

**특징:**
- 회사 내부 네트워크 PC
- 프록시 및 SSL 검증 비활성화
- 여러 고급 모델 접근 가능
- CA 인증서 필요할 수 있음

**설정 파일:** `~/.config/opencode/opencode.json`

**사용 가능한 모델:**
- `GLM-4.6` - Alibaba GLM 시리즈
- `gpt-oss-120b` - OpenAI 호환 대규모 모델
- `DeepSeek-V3.2` - DeepSeek 최신 모델

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Provider",
      "options": {
        "baseURL": "http://ssai.samsungds.net:9090",
        "apiKey": "925f1053996f6a679f40db2251d2d622a5263731"
      },
      "models": {
        "GLM-4.6": {
          "name": "GLM-4.6"
        },
        "gpt-oss-120b": {
          "name": "gpt-oss-120b"
        },
        "DeepSeek-V3.2": {
          "name": "DeepSeek-V3.2"
        }
      }
    }
  }
}
```

**사용 시나리오:**
- 사무실 데스크탑
- Samsung DS 사내 네트워크
- 고급 LLM 기능 활용

## 상세 설치

### 설치 방법 1: 대화형 설치 (권장)

```bash
# 환경별 설정을 자동으로 적용하는 가이드 설치
install-opencode
```

이 방법은 다음을 자동으로 수행합니다:
- 환경 선택 (Home/External/Internal)
- Node.js 및 npm 확인
- OpenCode 설치: `npm i -g opencode-ai`
- 환경별 설정 파일 자동 생성

### 설치 방법 2: 수동 설치

```bash
# OpenCode npm 패키지 직접 설치
npm i -g opencode-ai

# 설정 파일 생성 (필요시)
mkdir -p ~/.config/opencode
# ~/.config/opencode/opencode.json 파일 직접 작성
```

### 설치 과정 (대화형 설치)

| 단계 | 작업 | 명령어 |
|-----|------|--------|
| 1   | 환경 선택 | Home / External / Internal 중 선택 |
| 2   | Node.js/npm 확인 | `node -v`, `npm -v` 확인 |
| 3   | OpenCode 설치 | `npm i -g opencode-ai` |
| 4   | 설정 생성 | 환경별 `~/.config/opencode/opencode.json` 자동 생성 |
| 5   | 완료 | `opencode --version` 확인 |

### 설치 후 확인

```bash
# OpenCode 설치 확인
which opencode
opencode --version

# 커맨드를 찾을 수 없으면 셸 재로드
source ~/.bashrc  # bash
source ~/.zshrc   # zsh

# 설정 파일 확인 (External/Internal 환경만)
ls -la ~/.config/opencode/opencode.json  # 환경에 따라 있을 수도 없을 수도 있음
```

## 설정 파일

### 설정 디렉토리

```
~/.config/opencode/
├── opencode.json      # 메인 설정 파일
└── .env              # 환경 변수 (선택사항)
```

### 설정 편집

```bash
# 설정 파일 직접 편집
opencode-edit
# 또는
vim ~/.config/opencode/opencode.json

# 설정 확인
opencode-verify
```

### 설정 파일 구조

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Provider",
      "options": {
        "baseURL": "http://ssai.samsungds.net:9090",
        "apiKey": "API_KEY"
      },
      "models": {
        "model-name": {
          "name": "model-name"
        }
      }
    }
  }
}
```

## 사용 방법

### 기본 명령

```bash
# OpenCode 시작 (대화형 모드)
opencode

# 계획 모드 (권장)
openplan

# 테스트 작성 모드
opentest "Write unit tests for authentication"
```

### 유용한 명령

```bash
# 도움말 보기
opencode-help
opencode-help     # 상세 도움말

# 설정 확인
opencode-verify   # 설치 상태 및 LLM 구성 확인

# 설정 편집
opencode-edit     # 설정 파일 편집
opencfg           # 설정 편집 (단축명령)

# 버전 확인
opencode --version

# OpenCode 업그레이드
install-opencode      # 재설치를 통한 업데이트
```

### Alias 목록

| Alias | 명령 | 설명 |
|-------|------|------|
| `install-opencode` | 설치 스크립트 실행 | OpenCode 설치 및 설정 |
| `openplan` | `opencode` | 계획 모드 (대화형) |
| `opentest` | 테스트 작성 | 테스트 코드 생성 |
| `opencode-help` | 도움말 | 명령어 및 설정 도움말 |
| `opencode-verify` | 검증 | 설치 상태 확인 |
| `opencode-edit` | 편집 | 설정 파일 편집 |
| `opencfg` | 편집 | 설정 편집 (단축) |

## 문제 해결

### OpenCode를 찾을 수 없음

**증상:** `command not found: opencode`

**해결:**
```bash
# 1. 설치 확인
npm list -g opencode

# 2. 경로 재로드
source ~/.bashrc    # bash
source ~/.zshrc     # zsh

# 3. npm 경로 확인
npm config get prefix
echo $PATH | grep npm

# 4. 재설치
install-opencode
```

### 설정 파일 오류

**증상:** JSON 형식 오류

**해결:**
```bash
# 1. 설정 확인
jq . ~/.config/opencode/opencode.json

# 2. 설정 리셋
rm ~/.config/opencode/opencode.json
install-opencode
```

### LLM 연결 실패

**증상:** "LLM not responding" 오류

**해결:**
```bash
# 1. 설정 검증
opencode-verify

# 2. 네트워크 확인
curl -v http://ssai.samsungds.net:9090/health

# 3. API 키 확인
grep apiKey ~/.config/opencode/opencode.json

# 4. 방화벽/프록시 설정 확인
# - 내부 네트워크의 경우 프록시 설정 필요
# - 포트 9090 접근 가능 여부 확인
```

### 환경 변경

**시나리오:** Home에서 Internal로 변경

```bash
# 1. 설정 파일 삭제 (선택사항)
rm ~/.config/opencode/opencode.json

# 2. 재설치
install-opencode

# 3. 새 환경 선택
# (프롬프트에서 다른 번호 선택)

# 4. 검증
opencode-verify
```

### WSL 특정 이슈

**Node.js/npm: command not found**

```bash
# 1. Node.js 설치 (nvm 권장)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18

# 또는 apt를 통한 설치
sudo apt-get update
sudo apt-get install -y nodejs npm

# 2. 버전 확인
node --version
npm --version

# 3. 다시 설치
install-opencode
```

**bash: command not found**

```bash
# 1. bash 설치 (일반적으로 이미 설치됨)
sudo apt-get install -y bash

# 2. 설치 스크립트 다시 실행
bash ~/.dotfiles/shell-common/tools/custom/install_opencode.sh
```

## 팀 전파 가이드

### 설치 스크립트 공유

```bash
# 1. 설치 스크립트 경로 공유
# ~/dotfiles/shell-common/tools/custom/install_opencode.sh

# 2. 빠른 설치 명령
install-opencode

# 또는
bash ~/.dotfiles/shell-common/tools/custom/install_opencode.sh
```

### 설정 예제 공유

```bash
# 예제 파일 위치
# ~/dotfiles/shell-common/tools/integrations/opencode.*.example

# 사용자들이 자신의 환경에 맞는 예제를 복사
cp opencode.internal.example ~/.config/opencode/opencode.json
```

### 온보딩 체크리스트

- [ ] Node.js/npm 설치 확인
- [ ] OpenCode 설치 (`install-opencode`)
- [ ] 환경 선택 (Home/External/Internal)
- [ ] 설정 검증 (`opencode-verify`)
- [ ] 첫 실행 테스트 (`opencode`)
- [ ] 팀 리소스 공유

## 참고 자료

### 공식 리소스

- OpenCode 공식 문서: https://opencode.ai/
- GitHub: https://github.com/opencode-ai/opencode

### 추천 애드온

- https://ohmyopencode.com/ - OpenCode 생태계 및 플러그인

### 사내 리소스

- LiteLLM 서버: http://ssai.samsungds.net:9090
- 사내 도움말: `opencode-help`

## FAQ

### Q: 여러 환경에서 사용할 수 있나?

**A:** 예. 각 환경에서 `install-opencode`을 실행하면 환경에 맞게 자동 설정됩니다.

### Q: 설정을 변경할 수 있나?

**A:** 예. `opencode-edit`으로 JSON 설정을 수정할 수 있습니다.

### Q: 어떤 모델을 사용할 수 있나?

**A:**
- Home: OpenCode 기본값
- External: gpt-oss-20b
- Internal: GLM-4.6, gpt-oss-120b, DeepSeek-V3.2

### Q: 업그레이드는?

**A:** OpenCode 업그레이드는 npm을 통해 처리됩니다:
```bash
npm i -g opencode-ai

# 또는 대화형 설치
install-opencode
```

### Q: 완전히 제거하려면?

**A:**
```bash
npm uninstall -g opencode-ai
rm -rf ~/.config/opencode
```

## 기여 및 피드백

이 설치 가이드를 개선하려면:

1. GitHub Issue 생성
2. Pull Request 제출
3. 피드백 공유: `opencode-help`

---

**마지막 업데이트:** 2026-01-15
**작성자:** Dotfiles Team
**라이선스:** MIT
