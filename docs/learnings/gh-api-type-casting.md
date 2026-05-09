# `gh api graphql`의 `-f` vs `-F` 타입 캐스팅 함정

## Context

PR·이슈 추적: 이슈 [#384](https://github.com/dEitY719/dotfiles/issues/384)
검토 노트, 이슈 [#395](https://github.com/dEitY719/dotfiles/issues/395) 구현.

`shell-common/functions/gh_project_status.sh`의 projectV2 mutation에서
`updateProjectV2ItemFieldValue` 호출이 GraphQL `422` 로 silent fail 한
사례에서 출발. 호출부 변수 매핑(`-f` vs `-F`)이 query의 `String!`/`ID!`/`Int!`
타입과 맞지 않아도 `gh api`가 stderr에 한 줄 찍고 종료하는데, 보통 helper
들은 `2>/dev/null` 로 stderr를 버려 caller가 실패를 인지하지 못한다.

## Pattern

`gh api graphql` 변수 바인딩은 두 종류:

| Flag | 동작 | GraphQL 타입 |
|---|---|---|
| `-f name=value` | **raw String**으로 전달 | `String!`, `ID!` |
| `-F name=value` | **type inference** — 순수 숫자면 자동 `Int` 캐스팅 | `Int!` |

함정:

```sh
# WRONG — -F 가 "12345" 를 Int 로 캐스팅 → ID! 에 Int 전달 → 422
gh api graphql -f query='mutation($id: ID!) {...}' -F id="12345"

# WRONG — -f 가 "42" 를 String 으로 전달 → Int! 에 String → 422
gh api graphql -f query='query($num: Int!) {...}' -f num="42"
```

## Code

호출부에 **`# Variables: $x Type!, ...` 주석**을 붙이는 것이 1차 방어선.
리뷰어/미래의 본인이 `-f`/`-F` 가 query 의 타입과 맞는지 한눈에 검증 가능.

```sh
# Variables: $owner String!, $repo String!, $number Int!, $target String!
gh api graphql \
    -f query='
      query($owner: String!, $repo: String!, $number: Int!, $target: String!) {
        repository(owner: $owner, name: $repo) {
          issue(number: $number) { ... }
        }
      }' \
    -f owner="$_owner" \
    -f repo="$_repo" \
    -F number="$_num" \
    -f target="$_target"
```

`$VAR` 가 number 인지 string 인지는 lint 시점에 알 수 없으므로 사람이 의도를
**주석으로 박아두는** 것이 가장 안전한 회귀 가드.

## When to use

- 모든 `gh api graphql` 호출 — `mutation`, `query` 어느 쪽이든.
- `gh api repos/...` 같은 REST 엔드포인트는 해당 없음 (REST는 path/JSON
  body 기반이라 GraphQL 타입 시스템과 무관).
- pre-commit `git/hooks/checks/gh_api_type_check.sh`가 위 컨벤션 부재를
  warning 수준으로 잡아낸다 (false-positive 위험으로 block 안 함).

## Related

- 코드: `shell-common/functions/gh_project_status.sh`,
  `shell-common/functions/gh_audit_builtin_workflows.sh`
- 회귀 가드: `tests/bats/lint/gh_api_type_mapping.bats`
- pre-commit 훅: `git/hooks/checks/gh_api_type_check.sh`
- 이슈: [#384](https://github.com/dEitY719/dotfiles/issues/384) (검토 노트),
  [#395](https://github.com/dEitY719/dotfiles/issues/395) (구현)
