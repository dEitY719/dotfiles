# Git pre-commit hook: User(전역) + Project(개별) 조합 방법

## 1) 결론 (질문 1 답)
- 팀 단위로 일관된 검증을 강제하려는 목적이라면, **프로젝트 단위**(레포에 포함/문서화 가능한 방식)를 더 많이 씁니다.
  - 이유: 새로 clone한 개발자도 같은 규칙을 바로 적용할 수 있어 재현성이 높습니다.
- 반대로, 개인 취향/개인 생산성(예: 공통 포매터, 개인용 검증)을 위해 **User 단위 전역 hook**을 쓰는 사람도 많습니다.
- 다만 `git/hooks/pre-commit`처럼 **`.git/hooks`에 직접 두는 방식은 버전 관리가 안 되기 때문에** “프로젝트 표준”으로는 덜 선호되고,
  보통은 아래 중 하나로 해결합니다.
  - (권장) `core.hooksPath` + 레포 내 `.githooks/` (혹은 별도 tracked 경로) + 설치/문서화
  - (대중적) `pre-commit` 프레임워크(`.pre-commit-config.yaml`) 같은 도구 사용

## 2) 가능한가요? (질문 1의 “가능한가요” 답)
가능합니다. 핵심은 Git이 hook 디렉토리를 **하나만** 사용한다는 점(`core.hooksPath`)을 받아들이고, 그 “하나”를 **전역 wrapper hook**으로 만든 뒤,
wrapper가 레포별 hook을 찾아 실행(delegate)하도록 구성하는 것입니다.

즉,
1. 전역 `pre-commit`(공통) 실행
2. 레포 루트에서 프로젝트별 `pre-commit`이 있으면 실행
3. 둘 중 하나라도 실패(exit code != 0)하면 commit을 막음

## 3) 배경 지식 (Git hook 저장 위치 옵션)

### A. `.git/hooks/pre-commit`
- 장점: 해당 clone에서는 즉시 동작, 설정이 단순
- 단점: 기본적으로 버전 관리되지 않음(팀 공유 어려움)

### B. `core.hooksPath`
- Git이 hook을 찾는 디렉토리를 바꾸는 설정입니다.
- `git config --global core.hooksPath <dir>`로 전역 적용 가능
- 주의: 설정하면 Git은 기본 `.git/hooks`를 보지 않습니다(대신 지정한 디렉토리만 사용).

### C. `init.templateDir` (또는 `init.templatedir`)
- 새로 `git init` 할 때만 hooks 템플릿을 복사합니다.
- 이미 존재하는 레포에는 자동 적용되지 않습니다.

## 4) 추천 구성: 전역 wrapper + 레포별 hook 위임

### 4.1 전역 hooks 디렉토리 생성 및 설정
```bash
mkdir -p "$HOME/.config/git/hooks"
git config --global core.hooksPath "$HOME/.config/git/hooks"
```

### 4.2 전역 wrapper hook 만들기
아래 파일을 생성합니다: `~/.config/git/hooks/pre-commit`

```bash
#!/usr/bin/env sh
set -eu

# 1) 전역 공통 체크(원하는 내용을 여기에 추가)
# 예: 개인용 빠른 검증(가벼운 것만 권장)
# - ruff/pytest 같은 무거운 작업은 프로젝트별로 위임하는 편이 안전합니다.

# 2) 프로젝트별 pre-commit을 찾아서 실행
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo_root" ]; then
  if [ -x "$repo_root/.githooks/pre-commit" ]; then
    "$repo_root/.githooks/pre-commit"
  elif [ -x "$repo_root/git/hooks/pre-commit" ]; then
    "$repo_root/git/hooks/pre-commit"
  fi
fi
```

권한을 부여합니다.
```bash
chmod +x "$HOME/.config/git/hooks/pre-commit"
```

### 4.3 레포별 hook 추가(버전 관리 가능)
레포 루트에 `.githooks/pre-commit`을 만들고 실행 권한을 준 뒤, 레포에 커밋합니다.

```bash
mkdir -p .githooks
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# 프로젝트 전용 검사 작성
EOF
chmod +x .githooks/pre-commit
```

이 방식의 장점은 “전역 + 프로젝트별”이 동시에 가능하면서도, **프로젝트별 hook 자체는 레포에 포함**되어 팀에 공유된다는 점입니다.

## 5) 이 dotfiles 레포에서의 현재 상태와 연결
- 이 레포는 이미 `git/hooks/pre-commit`을 **tracked**로 두고, `git/setup.sh`가 `.git/hooks/pre-commit`으로 심볼릭 링크를 생성합니다.
- 위 4.2 wrapper는 `"$repo_root/git/hooks/pre-commit"`도 실행하도록 해두었기 때문에,
  전역 hooks를 도입하더라도 이 레포의 기존 hook을 계속 활용할 수 있습니다.

## 6) 자주 하는 실수/주의사항
- `core.hooksPath`를 전역으로 켠 뒤 “왜 `.git/hooks/pre-commit`이 안 돌지?”: 정상입니다. 전역 hook 디렉토리만 봅니다.
- wrapper에서 프로젝트별 hook 실행 경로를 잘못 잡아 재귀 호출: 프로젝트별 hook 경로를 전역 hook 경로와 분리해서 관리하세요.
- hook에서 너무 무거운 작업을 강제: 커밋 체감이 나빠지므로, 공통 hook은 가볍게, 무거운 건 프로젝트별/CI로 분리하는 편이 좋습니다.
