# Leak Guard 활성화 절차 (#1970)

사내 식별값(호스트, 프록시, 사번 형식 등)이 public upstream 에 들어가지 않도록
막는 opt-in 가드다. 패턴 값은 repo 에 두지 않고 각 PC 의 gitignored 로컬 파일에만
둔다. 아래 예시는 모두 가짜 값이다 — 실제 값을 이 repo 의 tracked 파일 어디에도
적지 않는다.

## 두 단계

| 단계 | 파일 | 검사 범위 | 차단 시 출력 |
|------|------|-----------|--------------|
| pre-commit | `hooks/checks/leak_pattern_check.sh` | staged 의 추가된 줄 + staged 파일 이름 (ACMR) | `file:line` 만 |
| pre-push (Layer 2) | `hooks/pre-push` | push 범위의 커밋 메시지 + 변경 파일 내용 + 변경 파일 이름 + push 대상 ref 이름 | commit + source + 줄 번호만 |

**출력 보장 (#1975, #1997)**: leak guard 가 출력하는 행에는 매칭된 텍스트가 나오지
않는다. 줄 내용은 위치(줄 번호)로만, 커밋 메시지는 줄 번호로만 표시한다. 경로(또는
ref 이름) 자체가 `LEAK_PATTERNS_ERE` 에 매칭되면 그 경로 대신 길이만 가린 표식을
출력한다 — 매칭되지 않는 경로는 평소처럼 그대로 출력한다.

- pre-commit: `<redacted path: N chars, matches LEAK_PATTERNS_ERE>  (use: git diff --cached --name-only | grep -nE "${LEAK_PATTERNS_ERE}")`,
  그 파일의 내용 매칭은 `<redacted path: N chars>:<line>`
- pre-push: `source: <redacted path: N chars, matches LEAK_PATTERNS_ERE>` +
  `lines:  (file name)`, ref 이름은 `source: <redacted ref name: N chars, ...>`

보장 범위는 leak guard 자신의 출력이다. 같은 pre-commit 의 다른 검사(shellcheck 등)나
git 자체 출력은 staged 경로를 그대로 찍을 수 있다 — 식별값을 파일 이름에 두지 않는 것이
우선이다.

두 단계 모두 같은 변수 두 개를 읽는다 (SSOT: `config/pre-push-rules.sh`, 기본값 빈
문자열 = 비활성):

- `UPSTREAM_REMOTES_ERE` — public upstream remote URL 정규식
- `LEAK_PATTERNS_ERE` — 막을 식별값 정규식 (ERE, `|` 로 연결)

활성 조건: 두 변수 모두 비어있지 않고, `SKIP_LEAK_GUARD` 가 1 이 아니고,
pre-push 는 push 대상 URL 이 / pre-commit 은 이 repo 의 remote URL 중 하나라도
`UPSTREAM_REMOTES_ERE` 와 매칭될 때. upstream remote 가 없는 체크아웃(사설 미러만)은
pre-commit 이 막지 않는다. 비활성일 때 pre-commit 은 staged diff 를 읽지도 않는다.

## 활성화 (internal / external PC 공통)

`shell-common/env/internal.local.sh` (gitignored, `env/internal.sh` 가 대화형 셸에서
source) 에 추가한다. 파일이 없으면 `internal.local.example` 을 복사해 만든다.

```sh
export UPSTREAM_REMOTES_ERE='github\.com[:/]example-owner/example-repo(\.git)?$'
export LEAK_PATTERNS_ERE='corp-internal\.example\.invalid|proxy\.example\.invalid|EMP[0-9]{5}'
```

- `internal` PC: upstream 은 pull 전용이지만, 여기서 만든 커밋이 나중에 upstream
  으로 갈 수 있으므로 pre-commit 단계가 커밋 시점에 막는다. 사내 remote 전용 커밋이
  의도적으로 식별값을 담아야 하면 그 커밋만 `SKIP_LEAK_GUARD=1` 로 우회한다.
- `external` PC: upstream 에 직접 push 하므로 두 단계 모두 활성화한다.
- `public` PC: 사내 값이 존재하지 않으면 설정하지 않아도 된다.

새 셸을 열어야 반영된다. GUI/IDE git 클라이언트는 셸 env 를 상속하지 않을 수 있다 —
그 경우 가드가 비활성이므로 터미널에서 커밋/푸시한다.

## 동작 확인 (dry run)

```sh
# 1) 변수와 upstream 매칭 확인 (값은 출력하지 않음)
printf '%s\n' "${UPSTREAM_REMOTES_ERE:+upstream set}" "${LEAK_PATTERNS_ERE:+patterns set}"
git config --get-regexp '^remote\..*\.url$' | cut -d' ' -f2- | grep -cE "$UPSTREAM_REMOTES_ERE"  # 1 이상이면 활성

# 2) pre-commit 카나리: 패턴에 걸리는 줄을 stage 하고 project hook 을 직접 실행
echo 'corp-internal.example.invalid' >leak-probe.txt   # 내 패턴에 걸리는 가짜 문자열로
git add leak-probe.txt
ALLOW_MAIN_COMMIT=1 git/hooks/pre-commit; echo "exit=$?"   # exit=1 + leak-probe.txt:1 기대
git rm -q --cached leak-probe.txt && rm leak-probe.txt

# 3) 메커니즘 회귀 테스트 (가짜 패턴 fixture)
bash git/test/test-pre-push.sh   # pre-push T-1..T-10
bash git/tests/test_hooks.sh     # pre-commit leak guard 4 케이스 포함
```

## 우회 (escape hatch)

| 변수 | 효과 |
|------|------|
| `SKIP_LEAK_GUARD=1` | 두 단계의 leak guard 만 끈다 (나머지 검사는 그대로) |
| `SKIP_PRE_PUSH=1` | pre-push 훅 전체를 끈다 |

diff 를 직접 확인한 경우에만 쓴다. 매칭 위치 확인:
`git diff --cached -U0 | grep -nE "$LEAK_PATTERNS_ERE"` (pre-commit),
`git show <commit>:<source> | grep -nE "$LEAK_PATTERNS_ERE"` (pre-push,
커밋 메시지는 `git log -1 --format=%B <commit> | grep -nE ...`).
가린 경로는 `git diff --cached --name-only | grep -nE "$LEAK_PATTERNS_ERE"` (pre-commit),
`git diff-tree --no-commit-id --name-only -r <commit> | grep -nE "$LEAK_PATTERNS_ERE"` (pre-push).
