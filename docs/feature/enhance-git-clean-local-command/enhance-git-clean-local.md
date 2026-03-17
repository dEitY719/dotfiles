# git_clean_local 브랜치 보호 키워드 기능

**v2 종합** | POSIX sh (bash/zsh 호환) | 2026-03-17

| Field | Value |
|-------|-------|
| **Document ID** | enhance-git-clean-local |
| **Title** | git_clean_local 브랜치 보호 키워드 기능 |
| **Type** | Feature Requirement Scratch |
| **Status** | Draft (v2 — CX 피드백 반영) |
| **Author** | Claude |
| **Integration Sources** | enhance-git-clean-local-CX.md (Codex) |

**피드백 반영 현황:**
- [x] [CX] 매칭 규칙: prefix-only → contains로 변경 (요구사항 원문 "포함되어 있으면" 반영)
- [x] [CX] 기본 보호 키워드: `backup wip save keep` → `backup`만 (MVP 접근)
- [x] [CX] 구현 방식: regex 파이프라인 → 브랜치별 명시적 분류 (case 문)
- [x] [CX] 테스트 전략 섹션 추가
- [x] [CX] 대안 비교 섹션 추가
- [x] [CX] 롤아웃 전략 추가
- [x] [CX] UX 출력에서 보호 목록을 먼저 표시
- [x] [CX] `master` 보호 호환성 고려

---

## Executive Summary

`git_clean_local` 명령어는 현재 main과 현재 브랜치를 제외한 모든 로컬 브랜치를 삭제한다. 그러나 `backup/sso-feature`처럼 의도적으로 보존해야 하는 브랜치까지 삭제되는 문제가 있다.

본 기능은 **보호 키워드 리스트**를 도입하여, 키워드가 브랜치명에 **포함된** 브랜치를 삭제 대상에서 자동으로 제외한다. 이를 통해 사용자가 안심하고 `git_clean_local`을 실행할 수 있도록 개선한다.

이번 개선의 본질은 단순한 "삭제 제외 키워드 추가"가 아니라, **강제 삭제 명령의 안전장치와 설명 가능성 강화**이다.

## 배경 (Background)

### 현재 동작 (`shell-common/functions/git.sh:141-177`)

```bash
git_clean_local() {
    # main + 현재 브랜치만 보호
    exclude_pattern="^(main|${current_branch})$"
    # 나머지 전부 삭제
    git for-each-ref ... | grep -vE "$exclude_pattern" | xargs -r git branch -D
}
```

**문제점:**
- `backup/*`, `wip/*` 등 보존 의도가 있는 브랜치도 무조건 삭제
- 삭제 전 경고는 있으나, 브랜치 수가 많으면 놓치기 쉬움
- 실수로 삭제 시 reflog에서 복구해야 하는 번거로움
- 브랜치명에 정규식 메타문자가 포함되면 `exclude_pattern`이 의도와 다르게 동작할 수 있음
- 같은 브랜치 목록을 여러 번 계산하여 유지보수성과 출력 일관성이 떨어짐

### git 내장 기능 조사

Git 자체에는 "브랜치 이름에 키워드가 포함되면 삭제에서 제외"하는 네이티브 기능이 없다.

가까운 기능은 있지만 목적이 다르다:
- `git branch -d`: 병합된 브랜치만 안전하게 삭제 (병합 상태 기준)
- `git branch -D`: 병합 여부와 무관하게 강제 삭제
- `git branch --merged`, `--no-merged`: 병합 상태 기준 필터링
- `git worktree`: 다른 worktree에서 체크아웃 중인 브랜치 보호 (이름 기반 아님)

**결론: 함수 레벨에서 구현 필요**

### 개발자들이 많이 쓰는 보호 prefix 추천

| Prefix | 용도 | 보호 기본값 추천 |
|--------|------|-----------------|
| `backup/` | 백업 브랜치 | **기본값 (MVP)** |
| `wip/` | Work In Progress | 후속 추가 후보 |
| `keep/` | 명시적 보존 | 후속 추가 후보 |
| `archive/` | 기록 보존 | 후속 추가 후보 |

**보호 기본값에 넣지 않을 prefix:**
- `feature/`, `fix/`, `bugfix/`, `hotfix/`, `release/` — 이들은 일반 작업 브랜치 분류이며, 보호 기본값으로 넣으면 삭제 대상이 지나치게 줄어 명령의 효용이 사라진다.

## 목표 (Goals)

- 보호 키워드가 **포함된** 브랜치는 `git_clean_local` 실행 시 삭제되지 않아야 한다
- 보호 키워드는 함수 내 리스트 변수로 관리하여 쉽게 추가/제거 가능해야 한다
- 기존 동작(main + 현재 브랜치 보호)은 그대로 유지해야 한다
- 삭제 시 **보호된 브랜치를 먼저**, 삭제 대상을 그 다음에 표시해야 한다

## 제안 설계 (Proposed Design)

### 매칭 규칙

**`contains` 매칭** (literal 문자열 포함 여부)을 기본으로 한다.

- 요구사항 원문이 "특정 키워드가 **포함되어 있으면**"이라고 명시
- prefix-only로 구현하면 `user/backup-sso` 같은 이름은 보호되지 않음
- 시스템은 넓게 보호하고, 팀 관례는 좁고 명확하게 유지하는 방식

### 삭제 판단 로직

정규식 파이프라인 대신 **브랜치별 명시적 분류**로 전환한다:

1. 현재 브랜치면 보호
2. `main`이면 보호
3. 보호 키워드 중 하나라도 브랜치명에 literal 포함되면 보호
4. 그 외는 삭제 후보

### 구현 스케치

```bash
git_clean_local() {
    local current_branch protected_keywords branches branch
    local delete_list="" protected_list=""
    local delete_count=0 protected_count=0

    protected_keywords="backup"

    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
        ux_error "Not in a git repository or in detached HEAD state"
        return 1
    }

    branches=$(git for-each-ref --format='%(refname:short)' refs/heads)

    while IFS= read -r branch; do
        [ -n "$branch" ] || continue

        # 기본 보호: main + 현재 브랜치
        if [ "$branch" = "main" ] || [ "$branch" = "$current_branch" ]; then
            continue
        fi

        # 키워드 보호: contains 매칭
        local is_protected=false
        for keyword in $protected_keywords; do
            case "$branch" in
                *"$keyword"*)
                    protected_list="${protected_list}${branch}
"
                    protected_count=$((protected_count + 1))
                    is_protected=true
                    break
                    ;;
            esac
        done
        [ "$is_protected" = true ] && continue

        delete_list="${delete_list}${branch}
"
        delete_count=$((delete_count + 1))
    done <<EOF
$branches
EOF

    # 보호 목록 먼저 출력 → 삭제 대상 출력 → 삭제 실행
}
```

**이 방식의 장점:**
- 정규식 escaping 문제가 사라짐
- 키워드가 literal 문자열로 취급됨
- 브랜치 목록 조회를 한 번만 수행
- 보호/삭제 목록을 각각 분리하여 UX 메시지에 활용

### UX 출력

보호 목록을 **먼저** 보여준다 (파괴적 명령이므로 "무엇을 보호했는지"가 더 중요):

```
Protected branches:
  main
  backup/sso-feature

Deleting 1 local branch(es):
  fix/gcp-scan-duplicate-handling

Done! Deleted 1 branch(es). Protected 2 branch(es).
```

## 기술 요구사항 (Technical Requirements)

- POSIX sh 호환 (bash/zsh 모두 동작)
- `shell-common/functions/git.sh` 내 `git_clean_local` 함수만 수정
- 외부 의존성 없음 (case 문 기반, grep 의존 제거)
- 기존 `ux_*` 함수 (ux_header, ux_info, ux_success, ux_error) 활용
- heredoc 패턴으로 subshell 문제 방지 (프로젝트 기존 패턴 준수)

## 에러 처리 및 엣지 케이스

- 보호 키워드 리스트가 비어있는 경우 → 기존 동작과 동일하게 작동
- 모든 브랜치가 보호 대상인 경우 → "No local branches to delete" 메시지 출력
- 현재 브랜치가 보호 키워드에 해당하는 경우 → 이중 보호 — 문제 없음
- detached HEAD 상태 → 에러 출력 후 종료
- 키워드에 정규식 특수문자가 포함된 경우 → case 문 literal 매칭이므로 안전

## 대안 비교

| 대안 | 장점 | 단점 | 판단 |
|------|------|------|------|
| **A: prefix-only** (`^backup/`) | 규칙 명확, 오탐 적음 | 요구사항보다 좁음 | 팀 표준으로는 좋으나 구현으로는 부적합 |
| **B: regex 기반** (`backup\|wip`) | 표현력 높음 | escaping 비용, 현재 취약점 확장 | 과설계 |
| **C: 외부 설정 파일** | 사용자별 커스텀 | 범위 초과, 초기화 순서 관리 비용 | 후속 확장 항목 |
| **D: contains + case 문 (채택)** | 안전, 읽기 쉬움, 요구사항 충족 | prefix보다 넓은 매칭 | 최적 |

## 범위 및 제약 (Scope & Constraints)

### In Scope
- `protected_keywords` 리스트 변수 도입 (기본값: `backup`)
- contains 기반 매칭으로 브랜치 보호
- 보호된 브랜치 안내 출력 (보호 목록 먼저)
- 브랜치별 명시적 분류 로직으로 전환
- 기존 테스트/동작 호환성 유지

### Out of Scope
- 설정 파일 기반 키워드 관리 (향후 확장 가능)
- 정규식 기반 복잡한 매칭 패턴
- 대화형 확인 (y/n) 프롬프트 추가
- CLI 옵션 추가
- 원격 브랜치 보호 규칙 동기화

## 테스트 전략

### 최소 검증 시나리오

1. `main`, 현재 브랜치, `backup/foo`, `fix/bar`가 있을 때 → `backup/foo` 보호, `fix/bar` 삭제
2. 보호 키워드가 비어 있으면 → 기존 동작과 동일
3. 삭제 대상이 없으면 → "No local branches to delete" 출력
4. detached HEAD에서 → 에러 출력 후 종료
5. bash와 zsh에서 동일하게 동작

### 수동 검증

```bash
git checkout -b backup/sso-feature
git checkout -b fix/gcp-scan-duplicate-handling
git checkout main
git-clean-local
# 기대: backup/sso-feature 보호, fix/gcp-scan-duplicate-handling 삭제
```

## 롤아웃 전략

1. `protected_keywords="backup"`만 추가
2. 보호 목록 출력 기능 포함
3. 팀이 1-2주 사용 후 `wip`, `keep`, `archive` 추가 여부 결정

보호 키워드를 과하게 늘리면 정리 명령이 무력화될 수 있으므로, 실제 사용 데이터 기반으로 점진적 확장한다.

## 성공 지표 (Success Criteria)

| 지표 | 목표값 |
|------|--------|
| `backup` 포함 브랜치 보호 | 삭제되지 않음 |
| 기존 동작 유지 | main + current 브랜치 보호 |
| 키워드 추가 용이성 | 리스트에 단어 추가만으로 완료 |
| bash/zsh 호환 | 두 셸 모두 정상 동작 |
| 정규식 escaping 문제 | 제거됨 (case 문 사용) |

## 미결 사항 (Open Questions)

- [x] ~~키워드 매칭을 prefix만 할 것인지, contains도 지원할 것인지?~~ → **contains 채택** (요구사항 원문 반영)
- [x] ~~기본 보호 키워드를 어떤 것들로 설정할 것인지?~~ → **`backup`만 (MVP)**
- [ ] 향후 `.gitconfig`나 환경변수로 키워드를 외부 설정할 필요가 있는지?
- [ ] `master` 브랜치도 기본 보호 대상에 포함할 것인지?
