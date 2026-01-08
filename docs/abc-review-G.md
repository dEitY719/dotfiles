# shell-common 디렉토리 구조 리팩토링 Task Plan (abc-review-G)

## 1. Executive Summary

### 목표

**shell-common** 디렉토리를 Simple, 견고하고 직관적인 구조로 리팩토링하여:

- 개발자의 반복적 실수 방지 (AGENTS.md "Common Mistakes")
- 자동 로딩 일관성 확보
- 1st-party 커맨드와 3rd-party 래퍼 명확 분리

### 설계 원칙

1. **단순한 멘탈 모델**: "자동 소싱되는 커맨드는 한 곳, 실행 스크립트는 다른 곳"
2. **소유권 분리**: 1st-party (우리 코드)와 3rd-party (외부 도구) 눈에 띄게 구분
3. **호환성 유지**: bash/zsh 양쪽 지원, 기존 로딩 순서 유지
4. **점진적 마이그레이션**: 호환성 심(symlink)으로 리스크 최소화

### 핵심 개선 사항

#### P1 (구조 개선)

- `tools/external/` → `tools/integrations/` (3rd-party 통합 의미 명확화)
- `aliases/`, `functions/`, `tools/custom/` 경계 명확화
- 파일 분류 결정 트리 추가

#### P0 (핵심 개선 - 견고한 로딩)

- **자동 소싱**: `functions/` + `integrations/` (필요시) + `aliases/`만
- **명시 실행**: `tools/custom/`은 절대 자동 소싱 금지
- bash/zsh 구분이 필요한 파일만 각 디렉토리로 이동
- AGENTS.md "Common Mistakes & Fixes" 확대 (6개 패턴 기록)

### 리팩토링 범위

- 파일 이동/이름변경: ~50개 파일
- 로딩 로직 수정: `bash/main.bash`, `zsh/main.zsh`
- 호환성 심(symlink) 설치: `tools/external → tools/integrations` (기간 한정)
  - 점진적 마이그레이션으로 리스크 최소화
  - Phase 1에서 설치, Phase 7에서 제거
- 문서화: AGENTS.md 확대, Decision Tree 추가

---

## 2. 현재 상태 분석

### 2.1 핵심 문제점

#### 문제 1: 일관성 없는 파일 명명

```bash
functions/
├── bat_help.sh           # underscore
├── cc_help.sh
├── claude_help.sh
├── git.sh
└── fzf.sh

aliases/
├── core.sh               # underscore (일관성 있음)
├── git.sh                # underscore
└── system.sh

tools/custom/
├── install_claude.sh     # underscore
├── check_proxy.sh
└── devx.sh
```

**현재**: underscore 사용 (일관성 있음)
**제안**: underscore 유지 (현재 충분히 명확)

---

#### 문제 2: devx 이중 존재 및 혼동

```bash
functions/devx.sh        # 실제 함수 정의 (자동 source)
tools/custom/devx.sh     # mytool wrapper (명시적 실행)
```

**혼동점**:

- 파일명이 동일해서 어느 것을 수정해야 하는지 불명확
- tools/custom/devx.sh의 역할이 명확하지 않음

**해결**:

```bash
functions/devx.sh            # 유지 (함수 정의)
tools/custom/devx_wrapper.sh # 이름 변경 (wrapper 표시)
```

---

#### 문제 3: tools/external 명명의 모호성

```bash
tools/external/
├── apt.sh
├── claude.sh
├── git.sh
├── npm.sh
└── docker.sh
```

**문제점**:

- "external"이 무엇을 의미하는가?
  - 외부에서 설치된 도구의 wrapper?
  - 외부 프로젝트의 코드?
  - 외부 저장소의 복사본?

**해결**:

```bash
tools/integrations/          # "통합"을 의미함
├── apt.sh                   # apt 통합
├── claude.sh                # Claude Code 통합
├── git.sh                   # Git 통합
└── docker.sh                # Docker 통합
```

---

#### 문제 4: aliases, functions, tools/custom의 관계 불명확

```bash
aliases/git.sh       → alias 정의
functions/git.sh     → 복잡한 함수
functions/git_help.sh → help 함수
tools/custom/init.sh → 초기화 스크립트

관계가:
- 어떻게 다른가?
- 언제 사용하는가?
- 어디에 새 파일을 추가하는가?
```

---

#### 문제 5: AGENTS.md의 "Common Mistakes & Fixes" 불완전

```bash
# 현재 기록된 실수:
# ERROR 1: Function in tools/custom/ → not auto-sourced
# ERROR 2: Sourcing utility script → global pollution

# 미기록 실수:
# ERROR 3: Hardcoded paths (~/dotfiles/... 대신 $SHELL_COMMON/...)
# ERROR 4: tools/external vs tools/custom 혼동
# ERROR 5: 관심사 혼합 (env 파일에 help 함수 정의)
# ERROR 6: BASH_SOURCE 사용 (zsh 미지원)
```

---

### 2.2 현재 구조의 강점

```bash
# ✓ 명확한 자동 로딩 메커니즘 (bash/main.bash, zsh/main.zsh)
# ✓ UX 라이브러리 우선 로드 (의존성 관리)
# ✓ tools/custom 명시적 실행 (부작용 방지)
# ✓ env/ 환경 변수만 (순수성)
# ✓ POSIX 호환성 (대부분)
```

---

## 3. 제안 대상 레이아웃 (P1 + P0)

### 3.1 디렉토리 구조

```
shell-common/
├── env/                       # 환경 변수 정의
├── functions/                 # 자동 소싱 함수 (유저 커맨드 + help)
├── aliases/                   # 단순 alias 정의
├── tools/
│   ├── integrations/          # 구 external: 3rd-party 래퍼
│   ├── custom/                # 1st-party 실행 스크립트
│   └── ux_lib/                # UX 헬퍼 (당분간 유지)
├── projects/                  # 프로젝트별 유틸리티
└── config/                    # 설정 파일
```

### 3.2 파일 분류 원칙

| 카테고리           | 위치                  | 자동 소싱 | 예시                   |
| ------------------ | --------------------- | --------- | ---------------------- |
| **Alias**          | `aliases/`            | O         | `gs='git status -sb'`  |
| **환경 변수**      | `env/`                | O         | `export PATH=...`      |
| **Help 함수**      | `functions/*_help.sh` | O         | `apt_help()`           |
| **유틸 함수**      | `functions/`          | O         | `devx()`, `gl()`       |
| **3rd-party 래퍼** | `tools/integrations/` | O         | `npm.sh`, `claude.sh`  |
| **실행 스크립트**  | `tools/custom/`       | X         | `install_*.sh`         |
| **bash/zsh 특화**  | `bash/`, `zsh/`       | 각각      | git prompt (bash only) |

---

## 4. 마이그레이션 플랜 (Phase별 체크리스트)

### Baseline: 사전 검증

#### Step 0: 현 상태 확인

```bash
cd /home/bwyoon/dotfiles
./tools/dev.sh test  # 모든 테스트 통과 확인 필수
```

---

### Phase 1: 인벤토리 분류 및 디렉토리 준비

#### 1A: 파일 분류

- `functions/`: 자동 소싱되는 함수 + help 시스템
- `tools/custom/`: 1st-party 실행 스크립트 (자동 소싱 금지)
- `tools/integrations/`: 3rd-party 래퍼 (이전 `tools/external/`)
- `devx` 중복 파일 역할 명확화

#### 1B: 디렉토리 생성

```shell
cd /home/bwyoon/dotfiles/shell-common/tools

# 새 디렉토리 생성
mkdir -p integrations

# 파일 이동
mv external/* integrations/
```

#### 1C: 호환성 심(symlink) 설치 (점진적 마이그레이션)

```bash
# tools/external 심(바로가기) 생성
# 이렇게 하면: tools/external/ → tools/integrations/ (실제 폴더)로 자동 연결됨
ln -s integrations external

# git에서 추적하지 않음
echo "external" >> .gitignore
git add -A
```

**이점**:

- 기존 코드가 `tools/external/apt.sh`를 참조해도 자동으로 `tools/integrations/apt.sh`가 열림
- Phase 1 완료 직후 테스트 즉시 통과 (기존 경로도, 새 경로도 모두 작동)
- Phase 2-4에서 천천히 모든 참조를 `integrations/`로 수정
- Phase 7에서 심을 제거해도 모든 참조가 이미 수정되어 있음 (안전함)

---

### Phase 2: 로더 수정 (자동 소싱 명시화)

#### 2A: bash/main.bash 업데이트

```bash
# 현재: for f in "${SHELL_COMMON}/tools/external/"*.sh; do
# 변경: for f in "${SHELL_COMMON}/tools/integrations/"*.sh; do

# 주의: tools/custom/ 절대 소싱 금지 (명시 실행만)
```

#### 2B: zsh/main.zsh 업데이트

```bash
# 동일하게 external/ → integrations/ 변경
```

#### 2C: 로딩 순서 명시화 (문서)

- 기존 순서 유지: UX → env → aliases → functions → integrations → projects
- 의존성 체인 명확화

---

### Phase 3: 경로 참조 업데이트

#### 3A: 하드코드 경로 수정

- 테스트 파일: `tools/external/` → `tools/integrations/`
- 헬프 출력: 경로 표기 업데이트
- `mytool.sh`: 내부 참고 경로 업데이트

#### 3B: devx 이중 존재 통합

```bash
# 현재: 이중 존재
# - functions/devx.sh (277줄): 함수 정의 + 직접 실행 로직
# - tools/custom/devx.sh (27줄): 단순 wrapper (functions/devx.sh를 실행)

# 통합 방안: functions/devx.sh만 유지 (이미 이중 역할 설계됨)

# 1. functions/mytool.sh에서 devx 함수 경로 수정
cd /home/bwyoon/dotfiles/shell-common/functions
sed -i 's|tools/custom/devx\.sh|functions/devx.sh|g' mytool.sh

# 2. tools/custom/devx.sh 삭제
rm /home/bwyoon/dotfiles/shell-common/tools/custom/devx.sh

# 3. git 추적
git add -A

# 이제 devx는 functions/devx.sh 1개 파일에서만 정의됨
# - 셸 로딩: functions/devx.sh 자동 source → devx() 함수 가능
# - 직접 실행: bash functions/devx.sh → devx__main() 실행
```

**이점**:
- ✅ 파일 1개만 유지 (wrapper 제거)
- ✅ 경로 명확화 (functions/devx.sh가 유일한 진실 공급원)
- ✅ 코드 간단화 (27줄 제거)
- ✅ 이미 functions/devx.sh는 dual-mode 설계됨 (함수 + 직접 실행)

---

### Phase 4: AGENTS.md 및 문서 강화

#### 4A: Common Mistakes & Fixes 확대

```markdown
### Common Mistakes & Fixes

**ERROR 1**: Function placed in `tools/custom/` not available after shell restart
**ERROR 2**: Utility script accidentally sourced by main.bash
**ERROR 3**: Hardcoded paths instead of environment variables
**ERROR 4**: Confusing tools/integrations vs tools/custom
**ERROR 5**: Mixing concerns in a single file
**ERROR 6**: Using bash-specific syntax in shell-common
```

#### 4B: Decision Tree 추가

```markdown
## Where to Add a New File?

1. 단순 alias? → aliases/
2. 환경 변수? → env/
3. help 함수? → functions/\*\_help.sh
4. 유틸리티 함수? → functions/
5. 3rd-party 래퍼? → tools/integrations/
6. 실행 스크립트? → tools/custom/
7. bash/zsh 특화? → bash/ or zsh/
```

#### 4C: 문서 업데이트

- `shell-common/README.md`: 디렉토리 역할 재정의
- `shell-common/AGENTS.md`: 로딩 메커니즘 명확화
- 헬프 출력: 경로 표기 통일

---

### Phase 5: bash/zsh 특화 파일 검토 (Optional)

#### 5A: 필요시 이동

```bash
# 예: tools/integrations/git.sh (bash 전용 기능 있음)
# → bash/integrations/git.bash로 이동 (향후)

# 현재는 선택사항 (git.sh는 [ -n "$BASH" ] || return로 zsh에서 자동 스킵)
```

---

### Phase 6: 테스트 및 검증

#### 6A: Regression Test

```bash
cd /home/bwyoon/dotfiles
./tools/dev.sh test  # 모든 테스트 통과 필수
```

#### 6B: 인터랙티브 스모크 테스트

```bash
# bash 테스트
bash -i -c 'declare -f devx && devx --help'
bash -i -c 'apt-help | head -5'
bash -i -c 'alias gs'

# zsh 테스트
zsh -i -c 'declare -f devx && devx --help'
zsh -i -c 'apt-help | head -5'
zsh -i -c 'alias gs'
```

#### 6C: 검증 체크리스트

- [ ] 함수 로드됨 (devx, mytool, *_help) - 특히 `declare -f devx` 확인
- [ ] devx 함수 호출 가능: `bash -i -c 'devx --help'`
- [ ] devx 직접 실행 가능: `bash functions/devx.sh stat`
- [ ] alias 정상 (gs, ga, etc)
- [ ] 환경 변수 설정됨 (echo $PATH)
- [ ] integrations 래퍼 정상 (apt-help, git-help)
- [ ] 자동 소싱 위반 없음 (tools/custom 명시 실행만)

---

### Phase 7: 호환성 심 제거 및 최종화

#### 7A: 호환성 심(바로가기) 제거

```bash
# Phase 2-4에서 모든 참고 경로 수정 완료 후에만 실행
# (이미 모든 코드가 tools/integrations/를 사용하고 있으므로 안전함)
rm /home/bwyoon/dotfiles/shell-common/tools/external
git add -A
```

**주의**: Phase 7에 도달했다는 것은 모든 참조가 이미 `tools/integrations/`로 변경됐다는 뜻이므로 심을 제거해도 안전함

#### 7B: 최종 테스트

```bash
./tools/dev.sh test  # 재확인
```

#### 7C: git commit

```bash
# Phase별로 분리 가능 (권장: 한 PR 내 여러 commit)
# - Phase 1: 디렉토리 이동, 심 설치
# - Phase 2-4: 로더, 경로, 문서 수정
# - Phase 7: 심 제거
```

---

## 5. 위험 요소 및 완화 방안

### 위험 1: 로딩 순서 오류로 의존성 깨짐

**증상**: 셸 시작 시 함수/alias 안 로드됨
**원인**: tools/integrations 로딩 타이밍 오류
**완화**:

- Phase 2에서 로딩 순서 명시적 재확인
- Phase 6에서 regression test 반드시 실행

---

### 위험 2: devx 통합 시 함수 로드 문제

**증상**: `devx` 함수를 호출할 수 없음 (함수 미정의)
**원인**: functions/mytool.sh에서 경로 수정 누락
**완화**:

- Phase 3에서 mytool.sh의 모든 `tools/custom/devx.sh` 참조를 `functions/devx.sh`로 변경 (sed 명령으로 자동화)
- Phase 6에서 `declare -f devx` 명령으로 함수 로드 확인
- Phase 6에서 `devx --help` 명령으로 직접 실행도 확인

---

### 위험 3: git 구분 파일 (bash vs zsh) 미처리

**증상**: git 프롬프트가 bash에서만 작동
**현상태**: integrations/git.sh가 bash 조건문 있으므로 zsh에서 자동 스킵
**완화**:

- 현재 git.sh는 bash 조건문 있으므로 zsh에서 자동 스킵
- 향후 리팩토링 때 bash/integrations/로 이동 가능

---

### 위험 4: CI/CD 파이프라인 영향

**증상**: GitHub Actions 테스트 실패
**원인**: 환경 변수 로드 순서 변경
**완화**:

- Phase 6에서 ./tools/dev.sh test 반드시 통과
- CI/CD 테스트도 재실행 (Phase 6과 동일)

---

## 6. 예상 결과

### 리팩토링 후 디렉토리 구조

```
shell-common/
├── AGENTS.md                  (확대: Common Mistakes & Fixes, Decision Tree)
├── README.md                  (업데이트: 구조 설명)
├── env/                       (유지)
├── functions/                 (유지)
├── aliases/                   (유지)
├── tools/
│   ├── integrations/          (external → 이름변경)
│   ├── custom/
│   │   ├── devx_wrapper.sh    (devx.sh → 이름변경)
│   │   └── ... (나머지 유지)
│   └── ux_lib/                (유지)
├── projects/                  (유지)
└── config/                    (유지)
```

### 로딩 메커니즘 개선

**Before**:

```
- shell-common/tools/external/ 명명 불명확
- devx.sh 이중 존재로 혼동
- AGENTS.md 실수 패턴 불완전
- 개발자가 실수하기 쉬운 구조
```

**After**:

```
- tools/integrations/ 명명 명확 ("3rd-party 통합")
- devx.sh vs devx_wrapper.sh 역할 구분 명확
- AGENTS.md 실수 패턴 완전 (ERROR 1-6)
- Decision Tree로 새 파일 추가 위치 명확
- Simple, 직관적, 견고한 구조
```

---

## 7. 검토 체크리스트 (동료 승인용)

리팩토링 진행 전 다음을 검토해주세요:

- [ ] P1 개선 사항 (tools 구조, 명명) 동의?
- [ ] P0 핵심 개선 (로딩 구조, AGENTS.md) 동의?
- [ ] 마이그레이션 절차 (Phase 1-7) 검토 완료?
- [ ] 위험 요소 (위험 1-4) 충분히 완화되었나?
- [ ] Regression Test 전략 (./tools/dev.sh test) 동의?
- [ ] 호환성 심 설치 방식 동의?
- [ ] 문서화 계획 충분한가?

---

## 8. 참고: 현재 로딩 메커니즘

### bash/main.bash 로딩 순서

```
1. UX 라이브러리 (ux_lib.sh)
2. shell-common/env/*.sh
3. shell-common/aliases/*.sh
4. shell-common/functions/*.sh
5. shell-common/tools/external/*.sh  ← integrations/로 변경
6. shell-common/projects/*.sh
7. bash/env/*.bash
8. bash/ 자동 검색
```

### zsh/main.zsh 로딩 순서

```
1. UX 라이브러리 (ux_lib.sh)
2. shell-common/env/*.sh
3. zsh/env/*.zsh
4. shell-common/aliases/*.sh
5. shell-common/functions/*.sh
6. shell-common/tools/external/*.sh  ← integrations/로 변경
7. shell-common/projects/*.sh
8. zsh/util/*.zsh
9. zsh apps (자동 검색)
```

---

## Appendix: abc-review-CX 피드백 반영

동료 4명의 검토 의견:

- ✅ 단순한 멘탈 모델 명확화 (자동 소싱 vs 명시 실행)
- ✅ 호환성 심(symlink)을 통한 점진적 마이그레이션 제안
- ✅ "열린 결정" 문서화 (ux/ 신설, integrations 자동 소싱 여부 등)
- ✅ 리스크/대응 섹션 강화
- ✅ 8단계 마이그레이션 플랜 → Phase별 체크리스트로 전환
- ✅ 1st-party vs 3rd-party 소유권 분리 강조
- ✅ bash/zsh 호환성 보장 프로토콜

---

## Next Steps

1. **동료 검토**: 이 Task Plan을 검토해주세요 (위 체크리스트 참고)
2. **승인 후**: Phase 1-7 순서대로 리팩토링 시작
3. **각 Phase 후**: Regression Test (`./tools/dev.sh test`) 실행
4. **최종**: git commit + PR 작성
