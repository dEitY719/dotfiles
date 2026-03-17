# git_clean_local 개선 설계 제안

- 문서 ID: `enhance-git-clean-local-CX`
- 작성자: Codex
- 작성일: 2026-03-17
- 상태: Draft
- 범위: `shell-common/functions/git.sh`의 `git_clean_local`

## 1. 문제 정의

현재 `git_clean_local`은 `main`과 현재 체크아웃된 브랜치를 제외한 모든 로컬 브랜치를 `git branch -D`로 강제 삭제한다.
이 동작은 빠르지만, `backup/sso-feature`처럼 의도적으로 보존하려는 브랜치도 함께 삭제한다.

요구사항의 핵심은 다음 세 가지다.

1. 브랜치명에 특정 키워드가 포함되면 삭제 대상에서 제외한다.
2. 보호 키워드는 함수 내부의 리스트 변수로 쉽게 관리한다.
3. Git에 이미 비슷한 기능이 있는지 조사하고, 팀이 쓸 만한 prefix도 제안한다.

## 2. 현재 구현 관찰

현 구현은 아래 성격을 가진다.

- 보호 대상은 `main`과 현재 브랜치뿐이다.
- 브랜치 필터링에 정규식 기반 `grep -E`를 사용한다.
- 브랜치 목록을 세 번 조회한다.
- 삭제는 `git branch -D`로 수행한다.

이 구현에서 설계상 주의할 점이 있다.

- 이름 기반 보호 규칙이 전혀 없다.
- 현재 브랜치명이 정규식 메타문자를 포함하면 `exclude_pattern`이 의도와 다르게 동작할 수 있다.
- 같은 브랜치 목록을 여러 번 계산하므로, 유지보수성과 출력 일관성이 떨어진다.
- `-D`는 미병합 브랜치도 삭제하므로, 보호 규칙은 보수적으로 설계해야 한다.

즉, 이번 개선은 단순히 키워드 하나를 추가하는 문제가 아니라, 삭제 판단 로직을 "정규식 파이프라인"에서 "명시적 분류 로직"으로 바꾸는 것이 맞다.

## 3. Git 내 유사 기능 조사

결론부터 말하면, Git 자체에는 "브랜치 이름에 특정 키워드가 포함되면 로컬 삭제에서 제외"하는 네이티브 기능이 없다.

가까운 기능은 있지만 목적이 다르다.

- `git branch -d`: 병합된 브랜치만 안전하게 삭제한다.
- `git branch -D`: 병합 여부와 무관하게 강제 삭제한다.
- `git branch --merged`, `git branch --no-merged`: 병합 상태 기준 필터링이다.
- `git worktree`: 다른 worktree에서 체크아웃 중인 브랜치 보호에는 도움이 되지만, 이름 기반 보호는 아니다.

따라서 이번 요구사항은 Git 옵션 조합으로 해결하기보다, `git_clean_local` 함수의 삭제 후보 선정 규칙을 확장하는 편이 맞다.

참고 근거:

- Git branch docs: `-d`, `-D`, `--merged`, `--no-merged`
  - https://git-scm.com/docs/git-branch
- Git worktree docs: linked worktree에 체크아웃된 브랜치 관련 보호 동작
  - https://git-scm.com/docs/git-worktree

## 4. 설계 목표와 비목표

### 목표

- 요구사항 문구대로 "키워드 포함" 브랜치를 보호한다.
- 보호 키워드는 함수 내부 리스트 변수 하나로 관리한다.
- 기존의 `main` 및 현재 브랜치 보호는 유지한다.
- 어떤 브랜치가 보호되었는지 사용자에게 명확히 보여준다.
- bash/zsh 공용 환경에서 단순하고 읽기 쉬운 구현을 유지한다.

### 비목표

- `.gitconfig`, 환경변수, 별도 설정 파일로 보호 키워드를 외부화하지 않는다.
- 정규식 기반 고급 규칙 엔진을 만들지 않는다.
- 원격 브랜치 보호 규칙과 동기화하지 않는다.
- 이번 변경에서 CLI 옵션을 추가하지 않는다.

## 5. 권장 설계

### 5.1 매칭 규칙

내 권장안은 `prefix`가 아니라 `literal contains`를 기본 규칙으로 두는 것이다.

이유는 단순하다.

- 요구사항 원문이 "특정 키워드가 포함되어 있으면"이라고 명시한다.
- 예시도 `backup`이라는 키워드 자체를 말한다.
- prefix-only로 구현하면 `user/backup-sso` 같은 이름은 보호되지 않아 요구사항 해석이 더 좁아진다.

다만 팀 운영 권장안은 별도로 둔다.

- 기능 구현의 매칭 규칙: `contains`
- 팀 브랜치 네이밍 권장안: `backup/...` 같은 명시적 prefix

즉, 시스템은 넓게 보호하고, 팀 관례는 좁고 명확하게 유지하는 방식이다.

### 5.2 보호 키워드 관리 방식

함수 내부에 다음과 같은 리스트 변수를 둔다.

```bash
local protected_keywords="backup"
```

특징은 다음과 같다.

- MVP 기본값은 `backup` 하나만 둔다.
- 추가는 문자열에 토큰을 붙이는 방식으로 끝나야 한다.
- 기본값을 과하게 늘리지 않는다.

기본값을 `backup`만 두는 이유:

- 요구사항에서 명시적으로 요청한 값이다.
- `wip`, `keep`, `archive`까지 기본 포함하면 예상보다 삭제가 덜 되어 명령의 효용이 떨어질 수 있다.
- 보호 규칙은 과도한 자동화보다, 명시적 opt-in이 더 안전하다.

### 5.3 삭제 판단 로직

삭제 여부는 브랜치별 분류 함수 수준으로 단순화하는 것이 좋다.

판단 순서는 아래와 같다.

1. 현재 브랜치면 보호
2. `main`이면 보호
3. 향후 호환성 차원에서 `master` 보호는 선택 사항
4. 보호 키워드 중 하나라도 브랜치명에 literal 포함되면 보호
5. 그 외는 삭제 후보

여기서 핵심은 정규식 조합을 버리고, 브랜치 하나씩 명시적으로 판정하는 것이다.

### 5.4 구현 스케치

아래는 문서 수준의 스케치다.

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

        if [ "$branch" = "main" ] || [ "$branch" = "$current_branch" ]; then
            protected_list="${protected_list}${branch}
"
            protected_count=$((protected_count + 1))
            continue
        fi

        for keyword in $protected_keywords; do
            case "$branch" in
                *"$keyword"*)
                    protected_list="${protected_list}${branch}
"
                    protected_count=$((protected_count + 1))
                    continue 2
                    ;;
            esac
        done

        delete_list="${delete_list}${branch}
"
        delete_count=$((delete_count + 1))
    done <<EOF
$branches
EOF

    # protected_list / delete_list 출력 후 delete_list만 삭제
}
```

이 스케치의 장점은 다음과 같다.

- 정규식 escaping 문제가 사라진다.
- 키워드가 literal 문자열로 취급된다.
- 목록 조회를 한 번만 수행한다.
- 보호 목록과 삭제 목록을 각각 UX 메시지로 분리해 보여주기 쉽다.

## 6. UX 동작 제안

이 명령은 파괴적이므로, "무엇을 지웠는지"보다 "무엇을 보호했는지"를 먼저 보여주는 것이 낫다.

권장 출력 순서:

1. 보호된 브랜치 목록
2. 삭제 대상 브랜치 목록
3. 삭제 실행 결과

예시:

```text
Protected branches:
  main
  backup/sso-feature

Deleting 1 local branch(es):
  fix/gcp-scan-duplicate-handling

Done! Deleted 1 branch(es). Protected 2 branch(es).
```

이 메시지 구조가 좋은 이유는 다음과 같다.

- 사용자는 명령 실행 직후 보호 규칙이 실제로 먹혔는지 확인할 수 있다.
- "왜 안 지워졌지?"와 "왜 지워졌지?" 둘 다 설명 가능하다.
- 이후 키워드 리스트를 수정할 때 피드백 루프가 빠르다.

## 7. Prefix 추천

보호 키워드의 기본값은 `backup` 하나만 권장한다.
다만 팀 규칙으로는 아래 prefix를 후보로 둘 수 있다.

- `backup/`: 임시 백업 브랜치. 가장 적합하다.
- `wip/`: 아직 정리되지 않은 장기 작업.
- `keep/`: 명시적으로 보존하고 싶은 브랜치.
- `archive/`: 기록 보존 목적의 브랜치.

반대로 아래 prefix들은 "보호 기본값"으로 추천하지 않는다.

- `feature/`
- `fix/`
- `bugfix/`
- `hotfix/`
- `release/`

이 prefix들은 일반 작업 브랜치 분류에는 유용하지만, 로컬 정리 명령의 보호 규칙으로 넣으면 삭제 대상이 지나치게 줄어든다.

참고로 업계에서 자주 보이는 분류 prefix는 `feature`, `bugfix`, `hotfix`, `release`다. Atlassian도 Bitbucket branching model에서 이 네 가지를 기본 branch type으로 소개한다. 다만 이것은 "브랜치 분류 표준"이지 "삭제 제외 표준"은 아니다.

참고 근거:

- Atlassian Bitbucket branching model
  - https://www.atlassian.com/blog/bitbucket/introducing-bitbucket-cloud-branching-model-support

## 8. 대안 비교

### 대안 A: prefix-only 보호

예: `^backup/`만 보호

장점:

- 규칙이 명확하다.
- 오탐이 적다.

단점:

- 요구사항의 "포함"보다 좁다.
- 기존 브랜치 네이밍을 바꾸지 않으면 보호가 안 된다.

판단:

- 팀 표준으로는 좋지만, 이번 요구사항의 1차 구현으로는 부적합하다.

### 대안 B: regex 기반 보호 리스트

예: `backup|wip|archive`

장점:

- 표현력이 높다.

단점:

- escaping 비용이 커진다.
- 현재 구현의 취약점을 그대로 확장할 가능성이 높다.
- Bash/Zsh 공용 함수에서 읽기 어려워진다.

판단:

- 지금 시점에서는 과설계다.

### 대안 C: 외부 설정 파일 또는 환경변수

장점:

- 사용자별 커스터마이징이 쉽다.

단점:

- 요구사항보다 범위가 커진다.
- 문서화와 초기화 순서 관리 비용이 생긴다.

판단:

- 후속 확장 항목으로 미룬다.

## 9. 테스트 전략

최소 검증 시나리오는 아래면 충분하다.

1. `main`, 현재 브랜치, `backup/foo`, `fix/bar`가 있을 때 `backup/foo`만 보호되고 `fix/bar`는 삭제된다.
2. 보호 키워드가 비어 있으면 기존 동작과 동일하다.
3. 삭제 대상이 하나도 없으면 "No local branches to delete"가 출력된다.
4. detached HEAD에서는 에러를 출력하고 종료한다.
5. bash와 zsh에서 동일하게 동작한다.

권장 수동 검증:

```bash
git checkout -b backup/sso-feature
git checkout -b fix/gcp-scan-duplicate-handling
git checkout main
git-clean-local
```

기대 결과:

- `backup/sso-feature`는 남아 있어야 한다.
- 현재 브랜치와 `main`은 당연히 남아 있어야 한다.
- `fix/gcp-scan-duplicate-handling`는 삭제되어야 한다.

## 10. 롤아웃 제안

이번 변경은 기능 자체보다 "삭제 규칙의 가시성"이 중요하다.
따라서 롤아웃은 작게 가는 편이 맞다.

1. `protected_keywords="backup"`만 추가한다.
2. 보호 목록을 출력한다.
3. 팀이 1~2주 사용한 뒤 `wip`, `keep`, `archive` 추가 여부를 결정한다.

이 접근이 좋은 이유는, 실제 팀 브랜치 이름 데이터 없이 보호 키워드를 많이 넣으면 정리 명령이 사실상 무력화될 수 있기 때문이다.

## 11. 최종 제안

내 권장안은 다음과 같다.

- 요구사항 해석은 `contains`로 맞춘다.
- 구현은 regex 조합이 아니라 브랜치별 명시 판정으로 바꾼다.
- 기본 보호 키워드는 `backup` 하나만 둔다.
- `feature`, `fix`, `bugfix`, `hotfix`, `release`는 보호 기본값으로 넣지 않는다.
- UX 출력에서 보호 목록을 먼저 보여준다.

한 줄로 요약하면, 이번 개선은 "삭제 제외 키워드 추가"보다 "강제 삭제 명령의 안전장치와 설명 가능성 강화"로 보는 것이 맞다.
