# Git pre-commit hook 설계 계획 (Review by Gemini)

## 1. 검토 의견 (Review of O)

`docs/abc-review-O.md`에서 제안된 **"Global Wrapper + Local Delegation"** 방식에 전적으로 동의합니다.
Git의 `core.hooksPath` 설정은 전역 Hook을 활성화하는 가장 표준적인 방법이며, 이를 통해 User 레벨의 공통 정책과 Project 레벨의 구체적인 정책을 모두 수용할 수 있습니다.

### 추가 제안 사항 (Gemini's Additions)

1.  **호환성 (Compatibility)**:
    - `core.hooksPath`를 설정하면 Git은 개별 레포지토리의 `.git/hooks`를 무시합니다.
    - 따라서, 우리가 설정할 **Global Wrapper**는 반드시 **`.git/hooks/pre-commit` (기존 표준 Hook)의 존재 여부를 확인하고 실행**해 주어야 합니다.
    - 이를 통해 `husky`, `pre-commit` 프레임워크 등을 사용하는 일반적인 오픈소스 프로젝트에서도 Hook이 정상 작동하도록 보장해야 합니다.

2.  **우선순위 (Precedence)**:
    - 한 레포지토리에 여러 형태의 Hook이 존재할 경우의 실행 순서를 정의해야 합니다.
    - 추천 순서: `팀 공유 Hook (.githooks)` > `Dotfiles 관례 (git/hooks)` > `로컬 표준 (.git/hooks)`

## 2. 구체적 설계 계획 (Concrete Design Plan)

### A. 디렉토리 구조 변경

현재 `git/` 디렉토리에 전역 Hook을 위한 폴더를 신설합니다.

```text
dotfiles/
└── git/
    ├── global-hooks/        # [신설] 전역 Hook 스크립트 모음
    │   └── pre-commit       # [신설] Global Wrapper Script
    ├── hooks/               # [기존] 이 Dotfiles 프로젝트 전용 Hook
    │   └── pre-commit
    └── setup.sh             # [수정] 설정 스크립트
```

### B. Global Wrapper Script 로직 (`git/global-hooks/pre-commit`)

이 스크립트는 모든 Git 프로젝트에서 커밋 시 실행됩니다.

```bash
#!/usr/bin/env bash
set -e

# 1. [User Level] 전역 공통 검사 (필요 시 구현)
# 예: 민감한 정보(AWS Key 등)가 커밋되는지 간단한 Grep 검사 등
# (성능을 위해 매우 가벼운 작업만 수행해야 함)

# 2. [Project Level] 로컬 Hook 위임 (Delegation)
REPO_ROOT=$(git rev-parse --show-toplevel)

# 우선순위에 따라 실행할 로컬 Hook 후보 목록
# 1) .githooks/pre-commit : 팀 차원에서 레포에 포함시킨 공유 Hook
# 2) git/hooks/pre-commit : 우리 Dotfiles 프로젝트와 같은 구조
# 3) .git/hooks/pre-commit: Husky, local 전용 등 표준 Git Hook
CANDIDATE_HOOKS=(
  ".githooks/pre-commit"
  "git/hooks/pre-commit"
  ".git/hooks/pre-commit"
)

for hook_rel_path in "${CANDIDATE_HOOKS[@]}"; do
  HOOK_PATH="$REPO_ROOT/$hook_rel_path"
  
  # 실행 권한이 있는 파일이 발견되면 실행하고 종료 (가장 높은 우선순위 하나만 실행)
  if [ -x "$HOOK_PATH" ]; then
    "$HOOK_PATH" "$@"
    exit $?
  fi
done

exit 0
```

### C. 설치 스크립트 수정 (`git/setup.sh`)

기존 심볼릭 링크 방식 대신 `core.hooksPath`를 설정하도록 변경합니다.

1.  `$HOME/.config/git/hooks` 디렉토리 생성
2.  `$DOTFILES/git/global-hooks/pre-commit` -> `$HOME/.config/git/hooks/pre-commit` 심볼릭 링크 생성
3.  Git 전역 설정 적용:
    ```bash
    git config --global core.hooksPath "$HOME/.config/git/hooks"
    ```

## 3. 구현 여부 결정 요청

위 설계대로 구현을 진행하시겠습니까?
승인하시면 다음 단계로 `git/global-hooks` 생성 및 스크립트 작성을 진행하겠습니다.
